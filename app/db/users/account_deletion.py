"""Self-serve account deletion lifecycle: request -> grace window -> Tier-1
purge (anonymize in place) -> Tier-2 purge (hard-delete, much later).

profiles/users/auth.users are never row-deleted during Tier-1: they are the
ON DELETE CASCADE parent of the match/chat/report graph
(20260604180435_initial.sql, 20260605122617_auth_moderation.sql), so
deleting them early would destroy the counterparty's shared match/chat
history and the trust & safety audit trail along with it. Tier 1 instead
nulls out PII in place, leaving every cascade-linked child row (matches,
chat_conversations, user_reports, ...) with full referential integrity.
Tier 2, much later (see hard_purge_long_tail_accounts), is what finally
removes the row for good.

See 20260801000000_account_deletion_lifecycle.sql,
20260801010000_deleted_account_blocklist.sql,
20260801020000_chat_conversations_deletion_close_reason.sql, and
20260801030000_account_history_archive.sql for the schema this operates on.
"""

import logging
import secrets
import time
from datetime import datetime, timedelta
from typing import Any, cast

import sentry_sdk
from postgrest.exceptions import APIError

from app.core.config import settings
from app.core.infra.cache import invalidate_user_status_cache
from app.core.security.crypto import encrypt_to_hex
from app.db.chat import (
    delete_user_chat_media,
    reopen_conversations_for_reactivation,
)
from app.db.client import (
    DatabaseAccessError,
    normalize_uuid,
    supabase_client,
    utcnow,
)

logger = logging.getLogger(__name__)

# Encrypted/PII profile columns nulled at Tier-1 anonymization. Deliberately
# excludes structural/preference columns that are NOT NULL, CHECK-constrained,
# or not meaningfully identifying on their own (age, campus_year,
# search_bucket, the three *_target_buckets arrays, dating_for, role_type).
#
# Compliance & Architectural Note (GDPR Recital 26 / DPDP §2(k)):
# `age` is intentionally stored unencrypted in plaintext to support high-throughput
# database-level B-tree indexed range queries (.gte("age", min).lte("age", max))
# during Stage 1 discovery candidate filtering. Retaining coarse demographic `age`
# without direct identifying PII (name, profile_pic, bio, campus branch) during
# Tier-1 anonymization preserves aggregate statistical telemetry without
# individual re-identification risk.
_PROFILE_PII_COLUMNS = (
    "campus_branch",
    "campus_name",
    "display_gender",
    "display_sexuality",
    "pronouns",
    "bio",
    "hometown",
    "current_place",
    "partner_values",
    "children_plans",
    "religious_beliefs",
    "lifestyle",
    "drinking",
    "smoking",
    "role_at",
    "looking_for",
    "activities",
    "causes_supported",
    "top_artists",
    "artist_affinity",
    "tech_skills",
    "languages",
    "ai_vibe_tags",
    "pets",
    "interests",
    "sub_interests",
    "value_dimensions",
    "normal_pics",
    "profile_pic",
    "music_taste_synced_at",
)
_PROFILE_BLIND_INDEX_COLUMNS = (
    "campus_branch_blind_index",
)
_ANONYMIZED_NAME = "Deleted User"

# Tables holding only this user's own data, with no retention purpose once
# the account can never log in again - hard-deleted at Tier-1 purge time.
# All share a `user_id` column (some FK profiles(id), some FK users(id), but
# both ids are the same UUID, since profiles/users are 1:1 siblings keyed
# off auth.users(id) - see app/db/client.py's authorization-model comment).
#
# Retention Schedule Note (F-13 / terms_consent_log):
# `terms_consent_log` is an append-only audit trail containing pseudonymous
# consent events (category, granted, terms_version, created_at) without direct
# PII. It is retained between Tier 1 and Tier 2 as proof of consent under
# GDPR/DPDP legal compliance standards, and is automatically cascade-purged at
# Tier-2 when auth.users / public.users is deleted via `terms_consent_log_user_id_fkey`
# ON DELETE CASCADE.
_NO_RETENTION_TABLES = (
    "chat_identity_keys",
    "chat_signed_prekeys",
    "chat_one_time_prekeys",
    "spotify_connections",
    "spotify_playlists",
    "profile_pseudonym_map",  # cascades away vector_profiles too
    "user_devices",
    "safety_contacts",
    "safety_sessions",
    "profile_name_change_log",
    "profile_age_change_log",
)

_MEDIA_BUCKET = "user_media"
_FEEDBACK_BUCKET = "feedback_attachments"
_CHAT_MEDIA_BUCKET = "chat_media"

# safety_alerts/safety_evidence are deliberately NOT purged here - they're
# on a separate, longer legal-hold timer anchored to purged_at (set below),
# not to deletion request time. See purge_safety_data_for_purged_accounts
# and purge_expired_safety_evidence in app/db/safety.py.


# ---------------------------------------------------------------------------
# Blocklist flagging
# ---------------------------------------------------------------------------


def _reason_code_for_flag(
    user_row: dict[str, Any],
    has_unresolved_report: bool,
) -> str | None:
    """Reason code for flag.

        Args:
            user_row: Input user row parameter.
            has_unresolved_report: Input has unresolved report parameter.

        Returns:
            str | None: Response payload or result."""
    moderation_status = str(user_row.get("moderation_status") or "clear")
    if moderation_status == "banned":
        return "banned"
    if moderation_status == "restricted":
        return "restricted"
    if bool(user_row.get("is_suspended", False)):
        return "suspended"
    if has_unresolved_report:
        return "unresolved_report"
    return None


def compute_deletion_flag_reason(user_id: str) -> str | None:
    """Determines whether this account should be blocklist-flagged if
    deleted right now: banned/restricted/suspended, or has an unresolved
    report against it. The caller freezes this into
    users.deletion_flagged_reason_code at request time so a status change
    during the grace window can't silently change the outcome.
    """
    try:
        user_res = (
            supabase_client.table("users")
            .select("moderation_status, is_suspended")
            .eq("id", user_id)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch user for deletion flag", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to fetch user") from e

    rows = cast(list[Any], user_res.data or [])
    user_row = (
        cast(dict[str, Any], rows[0]) if rows and isinstance(rows[0], dict) else {}
    )

    try:
        report_res = (
            supabase_client.table("user_reports")
            .select("id")
            .eq("target_id", user_id)
            .in_("review_status", ["pending", "reviewed"])
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch reports for deletion flag", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to fetch reports") from e

    return _reason_code_for_flag(user_row, bool(report_res.data))


def is_phone_blocklisted(blind_index: str) -> bool:
    """Used by the phone-claim path (app/db/users.py::set_verified_mobile)
    before a number can be verified onto an account.
    """
    if not blind_index:
        return False
    try:
        res = (
            supabase_client.table("deleted_account_blocklist")
            .select("id, cooldown_expires_at")
            .eq("phone_blind_index", blind_index)
            .gt("cooldown_expires_at", utcnow().isoformat())
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to check phone blocklist")
        raise DatabaseAccessError("Failed to check phone blocklist") from e

    rows = cast(list[Any], getattr(res, "data", None) or [])
    if rows and isinstance(rows[0], dict):
        first_row = cast(dict[str, Any], rows[0])
        cooldown_expires_at = first_row.get("cooldown_expires_at")
        masked_blind_index = (
            f"{blind_index[:6]}...{blind_index[-6:]}"
            if len(blind_index) >= 12
            else "***"
        )
        logger.warning(
            "Phone registration/claim blocked by deleted account blocklist hit",
            extra={
                "masked_phone_hash": masked_blind_index,
                "cooldown_expires_at": cooldown_expires_at,
            },
        )
        return True
    return False


# ---------------------------------------------------------------------------
# Tier 1: request / cancel / purge
# ---------------------------------------------------------------------------


def fetch_deletion_status(user_id: str) -> dict[str, Any] | None:
    """Executes fetch deletion status operation.

        Args:
            user_id: Unique UUID string of the authenticated user.

        Returns:
            dict[str, Any] | None: Response payload or result."""
    try:
        res = (
            supabase_client.table("users")
            .select("deletion_requested_at, scheduled_purge_at")
            .eq("id", user_id)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to fetch deletion status", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to fetch deletion status") from e
    rows = cast(list[Any], res.data or [])
    if not rows or not isinstance(rows[0], dict):
        return None
    return cast(dict[str, Any], rows[0])


def _close_all_conversations(user_id: str) -> None:
    """Bulk closes all active conversations across all tabs in a single database query.

    Args:
        user_id: Unique UUID string of the authenticated user.
    """
    user_id = normalize_uuid(user_id)
    now = utcnow()
    try:
        # nosec: user_id validated via normalize_uuid
        supabase_client.table("chat_conversations").update(
            {"closed_at": now.isoformat(), "closed_reason": "account_deletion"},
        ).or_(
            f"user_a_id.eq.{user_id},user_b_id.eq.{user_id}",
        ).is_("closed_at", "null").execute()
    except APIError as e:
        logger.exception(
            "Failed to bulk close all conversations for user", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to bulk close all conversations") from e


def _best_effort_deletion_cleanup(user_id: str, access_token: str | None) -> None:
    try:
        supabase_client.table("user_devices").update(
            {"is_active": False},
        ).eq("user_id", user_id).execute()
    except APIError as e:
        sentry_sdk.capture_exception(e)
        logger.exception(
            "Failed to deactivate devices for deletion", extra={"user_id": user_id},
        )

    try:
        supabase_client.table("safety_sessions").update(
            {"status": "ended"},
        ).eq("user_id", user_id).eq("status", "active").execute()
    except APIError as e:
        sentry_sdk.capture_exception(e)
        logger.exception(
            "Failed to end active safety sessions on deletion request",
            extra={"user_id": user_id},
        )

    try:
        supabase_client.table("discovery_session_items").delete().eq(
            "candidate_id", user_id,
        ).execute()
    except APIError as e:
        sentry_sdk.capture_exception(e)
        logger.exception(
            "Failed to delete discovery_session_items on deletion request",
            extra={"user_id": user_id},
        )

    try:
        _close_all_conversations(user_id)
    except DatabaseAccessError as e:
        sentry_sdk.capture_exception(e)
        logger.exception(
            "Failed to bulk close conversations during account deletion request",
            extra={"user_id": user_id},
        )

    if access_token:
        try:
            supabase_client.auth.admin.sign_out(access_token, "global")
        except Exception:  # noqa: BLE001
            logger.warning(
                "Failed to globally sign out user during deletion request",
                extra={"user_id": user_id},
            )


def request_deletion(
    user_id: str,
    flagged_reason_code: str | None,
    access_token: str | None = None,
) -> datetime:
    """Starts the grace window: signs the account out of new access,
    without touching any data that cancel_deletion() needs to restore. See
    the module docstring for why profiles/users/matches/chats are left
    alone here rather than deleted.
    """
    user_id = normalize_uuid(user_id)
    now = utcnow()
    grace_days = settings.account_deletion_grace_period_days
    scheduled_purge_at = now + timedelta(days=grace_days)

    try:
        supabase_client.table("users").update(
            {
                "deletion_requested_at": now.isoformat(),
                "scheduled_purge_at": scheduled_purge_at.isoformat(),
                "deletion_flagged_reason_code": flagged_reason_code,
            },
        ).eq("id", user_id).execute()
        invalidate_user_status_cache(user_id)
    except APIError as e:
        logger.exception(
            "Failed to set deletion lifecycle columns", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to request account deletion") from e

    try:
        supabase_client.table("profiles").update(
            {"is_deactivated": True, "deactivated_at": now.isoformat()},
        ).eq("id", user_id).execute()
    except APIError as e:
        logger.exception(
            "Failed to deactivate profile for deletion", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to request account deletion") from e

    _best_effort_deletion_cleanup(user_id, access_token)
    return scheduled_purge_at


def cancel_deletion(user_id: str) -> None:
    """Reverses request_deletion() during the grace window: profile data was
    never touched, matches were never unmatched, so this is a full undo,
    including reopening conversations - see reopen_conversations_for_reactivation.
    Does not touch is_suspended/moderation_status, so a previously-suspended
    user correctly falls back to the suspension block after cancelling.
    """
    try:
        supabase_client.table("users").update(
            {
                "deletion_requested_at": None,
                "scheduled_purge_at": None,
                "deletion_flagged_reason_code": None,
            },
        ).eq("id", user_id).execute()
        invalidate_user_status_cache(user_id)
    except APIError as e:
        logger.exception(
            "Failed to cancel deletion lifecycle columns", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to cancel account deletion") from e

    try:
        supabase_client.table("profiles").update(
            {"is_deactivated": False, "deactivated_at": None},
        ).eq("id", user_id).execute()
    except APIError as e:
        logger.exception("Failed to reactivate profile", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to cancel account deletion") from e

    try:
        supabase_client.table("user_devices").update(
            {"is_active": True},
        ).eq("user_id", user_id).execute()
    except APIError:
        logger.exception(
            "Failed to reactivate devices on deletion cancellation",
            extra={"user_id": user_id},
        )

    reopen_conversations_for_reactivation(user_id)


def _fetch_accounts_due_for_purge() -> list[dict[str, Any]]:
    """Fetch accounts due for purge.

        Returns:
            list[dict[str, Any]]: Response payload or result."""
    try:
        res = (
            supabase_client.table("users")
            .select("id, mobile_blind_index, deletion_flagged_reason_code")
            .not_.is_("deletion_requested_at", "null")
            .is_("purged_at", "null")
            .lte("scheduled_purge_at", utcnow().isoformat())
            .limit(500)
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to fetch accounts due for purge")
        raise DatabaseAccessError("Failed to fetch accounts due for purge") from e
    return [cast(dict[str, Any], r) for r in (res.data or []) if isinstance(r, dict)]


def _permanently_unmatch_all(user_id: str) -> None:
    """Bulk dissolves all active matches across all tabs in a single database query.

    Args:
        user_id: Unique UUID string of the authenticated user.
    """
    user_id = normalize_uuid(user_id)
    now = utcnow()
    try:
        # nosec: user_id validated via normalize_uuid
        supabase_client.table("matches").update(
            {"unmatched_at": now.isoformat(), "unmatched_by": user_id},
        ).or_(
            f"liker_id.eq.{user_id},liked_back_id.eq.{user_id}",
        ).is_("unmatched_at", "null").execute()
    except APIError as e:
        logger.exception(
            "Failed to bulk unmatch all for user", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to bulk unmatch all") from e


def _anonymize_profile_and_user(user_id: str, now: datetime) -> None:
    """Anonymizes user profile PII fields and marks the account purged in users table.

    Args:
        user_id: Unique UUID string of the user being purged.
        now: Timestamp of the purge operation.
    """
    user_id = normalize_uuid(user_id)
    profile_payload: dict[str, Any] = {col: None for col in _PROFILE_PII_COLUMNS}
    profile_payload.update({col: None for col in _PROFILE_BLIND_INDEX_COLUMNS})
    profile_payload["name"] = encrypt_to_hex(_ANONYMIZED_NAME)
    profile_payload["is_deactivated"] = True
    profile_payload["deactivated_at"] = now.isoformat()

    try:
        supabase_client.table("profiles").update(profile_payload).eq(
            "id", user_id,
        ).execute()

        supabase_client.table("users").update(
            {
                "mobile": None,
                "mobile_verified_at": None,
                "mobile_blind_index": None,
                "is_active": False,
                "purged_at": now.isoformat(),
            },
        ).eq("id", user_id).execute()
        invalidate_user_status_cache(user_id)
    except APIError as e:
        logger.exception(
            "Failed to anonymize profile and user rows", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to anonymize profile and user") from e


def _purge_vector_profiles_for_user(valid_user_id: str) -> None:
    """Defense-in-depth: Explicitly purge vector_profiles keyed by pseudonym_id."""
    try:
        pseudo_res = (
            supabase_client.table("profile_pseudonym_map")
            .select("pseudonym_id")
            .eq("user_id", valid_user_id)
            .execute()
        )
        pseudo_rows = cast(list[dict[str, Any]], pseudo_res.data or [])
        for p_row in pseudo_rows:
            p_id = str(p_row.get("pseudonym_id") or "").strip()
            if p_id:
                supabase_client.table("vector_profiles").delete().eq(
                    "pseudonym_id", p_id,
                ).execute()
    except APIError:
        logger.exception(
            "Failed to explicitly purge vector_profiles for user",
            extra={"user_id": valid_user_id},
        )


def _purge_discovery_for_user(valid_user_id: str) -> None:
    """Explicitly purges viewer discovery session items, sessions, and actions."""
    try:
        sess_res = (
            supabase_client.table("discovery_sessions")
            .select("id")
            .eq("viewer_id", valid_user_id)
            .execute()
        )
        sess_rows = cast(list[dict[str, Any]], sess_res.data or [])
        sess_ids = [
            str(r.get("id") or "").strip()
            for r in sess_rows
            if str(r.get("id") or "").strip()
        ]
        if sess_ids:
            supabase_client.table("discovery_session_items").delete().in_(
                "session_id", sess_ids,
            ).execute()
    except APIError:
        logger.exception(
            "Failed to explicitly purge viewer discovery_session_items for user",
            extra={"user_id": valid_user_id},
        )

    try:
        supabase_client.table("discovery_sessions").delete().eq(
            "viewer_id", valid_user_id,
        ).execute()
    except APIError:
        logger.exception(
            "Failed to purge discovery_sessions for user", extra={"user_id": valid_user_id},
        )
    try:
        supabase_client.table("discovery_session_items").delete().eq(
            "candidate_id", valid_user_id,
        ).execute()
    except APIError:
        logger.exception(
            "Failed to purge discovery_session_items for user",
            extra={"user_id": valid_user_id},
        )
    try:
        # nosec: valid_user_id validated via normalize_uuid
        supabase_client.table("profile_discovery_actions").delete().or_(
            f"actor_id.eq.{valid_user_id},target_id.eq.{valid_user_id}",
        ).execute()
    except APIError:
        logger.exception(
            "Failed to purge profile_discovery_actions for user",
            extra={"user_id": valid_user_id},
        )


def _delete_no_retention_rows(user_id: str) -> None:
    """Delete no retention rows.

        Args:
            user_id: Unique UUID string of the authenticated user."""
    valid_user_id = normalize_uuid(user_id)
    _purge_vector_profiles_for_user(valid_user_id)

    for table in _NO_RETENTION_TABLES:
        try:
            supabase_client.table(table).delete().eq("user_id", valid_user_id).execute()
        except APIError:
            logger.exception(
                "Failed to purge %s row(s) for user", table, extra={"user_id": valid_user_id},
            )

    _purge_discovery_for_user(valid_user_id)



def _delete_user_media_objects(user_id: str) -> None:
    """Delete user media and feedback attachment objects from storage buckets.

    Args:
        user_id: Unique UUID string of the authenticated user.
    """
    valid_user_id = normalize_uuid(user_id)
    # 1. Clean user_media bucket ({user_id}/*)
    try:
        objects = supabase_client.storage.from_(_MEDIA_BUCKET).list(valid_user_id)
        paths = [
            f"{valid_user_id}/{obj['name']}"
            for obj in (objects or [])
            if obj.get("name")
        ]
        if paths:
            supabase_client.storage.from_(_MEDIA_BUCKET).remove(paths)
    except Exception:
        logger.exception(
            "Failed to remove user_media objects for purge", extra={"user_id": valid_user_id},
        )

    # 2. Clean feedback_attachments bucket ({user_id}/*)
    try:
        fb_objects = supabase_client.storage.from_(_FEEDBACK_BUCKET).list(valid_user_id)
        fb_paths = [
            f"{valid_user_id}/{obj['name']}"
            for obj in (fb_objects or [])
            if obj.get("name")
        ]
        if fb_paths:
            supabase_client.storage.from_(_FEEDBACK_BUCKET).remove(fb_paths)
    except Exception:
        logger.exception(
            "Failed to remove feedback_attachments objects for purge",
            extra={"user_id": valid_user_id},
        )

    # 3. Clean chat_media bucket ({conversation_id}/{user_id}/*) for deleting user
    try:
        # nosec: valid_user_id validated via normalize_uuid
        conv_res = (
            supabase_client.table("chat_conversations")
            .select("id")
            .or_(f"user_a_id.eq.{valid_user_id},user_b_id.eq.{valid_user_id}")
            .execute()
        )
        conv_rows = cast(list[dict[str, Any]], conv_res.data or [])
        conv_ids = [
            str(row.get("id") or "").strip()
            for row in conv_rows
            if str(row.get("id") or "").strip()
        ]
        if conv_ids:
            delete_user_chat_media(valid_user_id, conv_ids)
    except Exception:
        logger.exception(
            "Failed to fetch conversations for user chat_media purge",
            extra={"user_id": valid_user_id},
        )


def _ban_and_scrub_auth_user(user_id: str) -> None:
    """Ban and scrub auth user.

        Args:
            user_id: Unique UUID string of the authenticated user."""
    random_suffix = secrets.token_hex(8)
    try:
        supabase_client.auth.admin.update_user_by_id(
            user_id,
            {
                "ban_duration": "876000h",  # ~100 years - effectively permanent
                "email": f"deleted-{user_id}-{random_suffix}@deleted.{settings.email_domain}",
            },
        )
    except Exception:
        logger.exception(
            "Failed to ban/scrub auth user during purge", extra={"user_id": user_id},
        )

    try:
        supabase_client.auth.admin.sign_out(user_id, "global")
    except Exception:
        logger.exception(
            "Failed to globally sign out user during purge", extra={"user_id": user_id},
        )


def _purge_single_due_account(row: dict[str, Any], now: datetime) -> None:
    """Purges a single account due for Tier-1 anonymization and cleanup."""
    user_id = str(row.get("id") or "")
    if not user_id:
        return
    try:
        blind_index = row.get("mobile_blind_index")
        reason_code = row.get("deletion_flagged_reason_code")
        # Re-evaluate deletion flag reason dynamically at purge time to capture any bans or abuse
        # reports filed during the 30-day grace period
        try:
            fresh_reason = compute_deletion_flag_reason(user_id)
            if fresh_reason is not None:
                reason_code = fresh_reason
        except Exception:  # noqa: BLE001
            logger.warning(
                "Could not dynamically re-evaluate deletion flag reason for user %s; using frozen code",
                user_id,
            )

        _permanently_unmatch_all(user_id)
        _anonymize_profile_and_user(user_id, now)

        if reason_code and blind_index:
            supabase_client.table("deleted_account_blocklist").upsert(
                {
                    "phone_blind_index": blind_index,
                    "cooldown_expires_at": (
                        now
                        + timedelta(
                            days=settings.account_deletion_blocklist_cooldown_days,
                        )
                    ).isoformat(),
                    "reason_code": reason_code,
                },
                on_conflict="phone_blind_index",
            ).execute()

        _delete_no_retention_rows(user_id)
        _delete_user_media_objects(user_id)
        _ban_and_scrub_auth_user(user_id)
    except Exception:
        logger.exception(
            "Failed to purge account; will retry next run",
            extra={"user_id": user_id},
        )


def purge_due_accounts() -> None:
    """Tier-1 purge job body, run daily by the scheduler. Per-account
    failures are logged and skipped rather than aborting the whole batch.
    Processes accounts in batches of 50 with a 1-second sleep between batches.
    """
    now = utcnow()
    accounts = _fetch_accounts_due_for_purge()
    batch_size = 50
    for i in range(0, len(accounts), batch_size):
        batch = accounts[i:i + batch_size]
        for row in batch:
            _purge_single_due_account(row, now)
        if i + batch_size < len(accounts):
            time.sleep(1.0)


def expire_blocklist_entries() -> None:
    """Executes expire blocklist entries operation."""
    try:
        supabase_client.table("deleted_account_blocklist").delete().lte(
            "cooldown_expires_at", utcnow().isoformat(),
        ).execute()
    except APIError:
        logger.exception("Failed to expire deleted_account_blocklist entries")


# ---------------------------------------------------------------------------
# Tier 2: long-tail hard purge
# ---------------------------------------------------------------------------

_ArchiveSource = tuple[str, str, str | None, str]
_ARCHIVE_SOURCE_TABLES: tuple[_ArchiveSource, ...] = (
    (
        "user_reports",
        "reporter_id.eq.{uid},target_id.eq.{uid}",
        "reason",
        "review_status",
    ),
    ("user_moderation_actions", "user_id.eq.{uid}", "reason_code", "action_type"),
    ("feedback_reports", "user_id.eq.{uid}", None, "status"),
)


def _fetch_archive_source(
    source: tuple[str, str, str | None, str],
    user_id: str,
) -> list[dict[str, Any]] | None:
    valid_user_id = normalize_uuid(user_id)
    table, _, reason_field, outcome_field = source
    try:
        select_fields = "id, created_at"
        if reason_field:
            select_fields += f", {reason_field}"
        select_fields += f", {outcome_field}"
        query = supabase_client.table(table).select(select_fields)
        if table == "user_reports":
            # nosec: valid_user_id validated via normalize_uuid preventing filter injection
            query = query.or_(f"reporter_id.eq.{valid_user_id},target_id.eq.{valid_user_id}")
        else:
            query = query.eq("user_id", valid_user_id)
        res = query.execute()
        return cast(list[dict[str, Any]], res.data or [])
    except APIError:
        logger.exception(
            "Failed to fetch %s for archival", table, extra={"user_id": valid_user_id},
        )
        return None
    except Exception:
        logger.exception(
            "Unexpected failure fetching %s for archival", table, extra={"user_id": valid_user_id},
        )
        return None


def _insert_archive_rows(
    table: str,
    rows: list[dict[str, Any]],
    reason_field: str | None,
    outcome_field: str,
    user_id: str,
) -> bool:
    archive_rows: list[dict[str, Any]] = [
        {
            "source_table": table,
            "reason_code": row.get(reason_field) if reason_field else None,
            "outcome": row.get(outcome_field),
            "event_occurred_at": row.get("created_at"),
        }
        for row in rows
        if row.get("created_at")
    ]
    if not archive_rows:
        return True
    try:
        supabase_client.table("account_history_archive").insert(archive_rows).execute()
        return True
    except APIError:
        logger.exception(
            "Failed to archive %s rows", table, extra={"user_id": user_id},
        )
        return False
    except Exception:
        logger.exception(
            "Unexpected failure inserting %s rows to archive", table, extra={"user_id": user_id},
        )
        return False


def _archive_account_history(user_id: str) -> list[str]:
    """Archive account history.

        Args:
            user_id: Unique UUID string of the authenticated user.

        Returns:
            list[str]: List of table names that failed archival."""
    failed_tables: list[str] = []
    for source in _ARCHIVE_SOURCE_TABLES:
        table, _, reason_field, outcome_field = source
        rows = _fetch_archive_source(source, user_id)
        if rows is None:
            failed_tables.append(table)
            continue
        if not _insert_archive_rows(table, rows, reason_field, outcome_field, user_id):
            failed_tables.append(table)

    return failed_tables


def _fetch_accounts_due_for_long_tail_purge() -> list[str]:
    """Fetch accounts due for long tail purge.

        Returns:
            list[str]: Response payload or result."""
    cutoff = utcnow() - timedelta(days=settings.account_deletion_long_tail_purge_days)
    try:
        res = (
            supabase_client.table("users")
            .select("id")
            .not_.is_("purged_at", "null")
            .lte("purged_at", cutoff.isoformat())
            .limit(500)
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to fetch accounts due for long-tail purge")
        raise DatabaseAccessError(
            "Failed to fetch accounts due for long-tail purge",
        ) from e
    return [
        str(r["id"]) for r in (res.data or []) if isinstance(r, dict) and r.get("id")
    ]


def _chunked_delete_by_field(
    table: str, field: str, value: str, chunk_size: int = 500,
) -> None:
    """Delete records matching field = value in chunks to avoid single-transaction cascade lock contention."""
    while True:
        try:
            res = (
                supabase_client.table(table)
                .select("id")
                .eq(field, value)
                .limit(chunk_size)
                .execute()
            )
            ids = [
                str(r["id"])
                for r in (res.data or [])
                if isinstance(r, dict) and r.get("id")
            ]
            if not ids:
                break
            supabase_client.table(table).delete().in_("id", ids).execute()
            if len(ids) < chunk_size:
                break
        except Exception:
            logger.exception(
                "Failed during chunked deletion of %s by %s",
                table,
                field,
                extra={"value": value},
            )
            break


def _chunked_delete_by_or_filter(
    table: str, filter_str: str, user_id: str, chunk_size: int = 500,
) -> None:
    """Delete records matching an OR filter in chunks to avoid lock contention."""
    while True:
        try:
            res = (
                supabase_client.table(table)
                .select("id")
                .or_(filter_str)
                .limit(chunk_size)
                .execute()
            )
            ids = [
                str(r["id"])
                for r in (res.data or [])
                if isinstance(r, dict) and r.get("id")
            ]
            if not ids:
                break
            supabase_client.table(table).delete().in_("id", ids).execute()
            if len(ids) < chunk_size:
                break
        except Exception:
            logger.exception(
                "Failed during chunked deletion of %s with filter %s",
                table,
                filter_str,
                extra={"user_id": user_id},
            )
            break


def _chunked_pre_purge_child_records(user_id: str) -> None:
    """Pre-delete high-volume child records in chunks to prevent large cascading delete lock contention."""
    valid_user_id = normalize_uuid(user_id)
    _chunked_delete_by_field("chat_messages", "sender_id", valid_user_id)
    _chunked_delete_by_field("discovery_session_items", "candidate_id", valid_user_id)
    _chunked_delete_by_field("discovery_sessions", "viewer_id", valid_user_id)
    _chunked_delete_by_or_filter(
        "profile_discovery_actions",
        f"actor_id.eq.{valid_user_id},target_id.eq.{valid_user_id}",
        valid_user_id,
    )
    _chunked_delete_by_or_filter(
        "matches",
        f"liker_id.eq.{valid_user_id},liked_back_id.eq.{valid_user_id}",
        valid_user_id,
    )
    _chunked_delete_by_or_filter(
        "chat_conversations",
        f"user_a_id.eq.{valid_user_id},user_b_id.eq.{valid_user_id}",
        valid_user_id,
    )
    _chunked_delete_by_field("user_devices", "user_id", valid_user_id)


def hard_purge_long_tail_accounts() -> None:
    """Tier-2 purge job body. Archives non-identifying report/moderation/
    feedback essentials, pre-deletes heavy child relations in chunks to prevent
    lock contention, and then deletes the auth.users row for good via admin.delete_user.
    Processes accounts in batches of 50 with a 1-second sleep between batches.
    """
    accounts = _fetch_accounts_due_for_long_tail_purge()
    batch_size = 50
    for i in range(0, len(accounts), batch_size):
        batch = accounts[i:i + batch_size]
        for user_id in batch:
            try:
                failed_tables = _archive_account_history(user_id)
                if failed_tables:
                    logger.error(
                        "Aborting hard purge for user %s due to archival failure in tables: %s; will retry next run",
                        user_id,
                        failed_tables,
                        extra={"user_id": user_id, "failed_tables": failed_tables},
                    )
                    continue

                _chunked_pre_purge_child_records(user_id)
                supabase_client.auth.admin.delete_user(user_id)
            except Exception:
                logger.exception(
                    "Failed to hard-purge long-tail account; will retry next run",
                    extra={"user_id": user_id},
                )
        if i + batch_size < len(accounts):
            time.sleep(1.0)
