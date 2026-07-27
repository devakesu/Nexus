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
from datetime import datetime, timedelta
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import DiscoveryTab, settings
from app.core.infra.cache import invalidate_user_status_cache
from app.db.chat import (
    close_conversation_for_match_action,
    reopen_conversations_for_reactivation,
)
from app.db.client import DatabaseAccessError, supabase_client, utcnow
from app.db.discovery import fetch_matches_for_user, set_match_unmatched

logger = logging.getLogger(__name__)

_TABS: tuple[DiscoveryTab, ...] = ("Dating", "Friends", "Professional")

# Encrypted/PII profile columns nulled at Tier-1 anonymization. Deliberately
# excludes structural/preference columns that are NOT NULL, CHECK-constrained,
# or not meaningfully identifying on their own (age, campus_year,
# search_bucket, the three *_target_buckets arrays, dating_for, role_type).
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
    "smoking_blind_index",
    "drinking_blind_index",
    "children_plans_blind_index",
    "religious_beliefs_blind_index",
)
_ANONYMIZED_NAME = "Deleted User"

# Tables holding only this user's own data, with no retention purpose once
# the account can never log in again - hard-deleted at Tier-1 purge time.
# All share a `user_id` column (some FK profiles(id), some FK users(id), but
# both ids are the same UUID, since profiles/users are 1:1 siblings keyed
# off auth.users(id) - see app/db/client.py's authorization-model comment).
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
            .select("id")
            .eq("phone_blind_index", blind_index)
            .gt("cooldown_expires_at", utcnow().isoformat())
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to check phone blocklist")
        raise DatabaseAccessError("Failed to check phone blocklist") from e
    return bool(res.data)


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
    """Close all conversations.

        Args:
            user_id: Unique UUID string of the authenticated user."""
    for tab in _TABS:
        for match in fetch_matches_for_user(user_id, tab):
            close_conversation_for_match_action(
                user_id, match["matched_user_id"], tab, reason="account_deletion",
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

    # Secondary cleanup below is best-effort - the two writes above are what
    # actually makes the account inactive/hidden/undoable, and must not be
    # blocked by a transient failure in a lower-priority side effect.
    try:
        supabase_client.table("user_devices").update(
            {"is_active": False},
        ).eq("user_id", user_id).execute()
    except APIError:
        logger.exception(
            "Failed to deactivate devices for deletion", extra={"user_id": user_id},
        )

    try:
        _close_all_conversations(user_id)
    except DatabaseAccessError:
        logger.exception(
            "Failed to close conversations for deletion", extra={"user_id": user_id},
        )

    if access_token:
        try:
            supabase_client.auth.admin.sign_out(access_token, "global")
        except Exception:  # noqa: BLE001
            logger.warning(
                "Failed to globally sign out user during deletion request",
                extra={"user_id": user_id},
            )

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
        reopen_conversations_for_reactivation(user_id)
    except DatabaseAccessError:
        logger.exception(
            "Failed to reopen conversations on reactivation",
            extra={"user_id": user_id},
        )


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
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to fetch accounts due for purge")
        raise DatabaseAccessError("Failed to fetch accounts due for purge") from e
    return [cast(dict[str, Any], r) for r in (res.data or []) if isinstance(r, dict)]


def _permanently_unmatch_all(user_id: str) -> None:
    """Permanently unmatch all.

        Args:
            user_id: Unique UUID string of the authenticated user."""
    for tab in _TABS:
        for match in fetch_matches_for_user(user_id, tab):
            set_match_unmatched(user_id, match["matched_user_id"], tab)


def _anonymize_profile_and_user(user_id: str, now: datetime) -> None:
    """Anonymize profile and user.

        Args:
            user_id: Unique UUID string of the authenticated user.
            now: Input now parameter."""
    profile_payload: dict[str, Any] = {col: None for col in _PROFILE_PII_COLUMNS}
    profile_payload.update({col: None for col in _PROFILE_BLIND_INDEX_COLUMNS})
    profile_payload["name"] = _ANONYMIZED_NAME
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


def _delete_no_retention_rows(user_id: str) -> None:
    """Delete no retention rows.

        Args:
            user_id: Unique UUID string of the authenticated user."""
    for table in _NO_RETENTION_TABLES:
        try:
            supabase_client.table(table).delete().eq("user_id", user_id).execute()
        except APIError:
            logger.exception(
                "Failed to purge %s row(s) for user", table, extra={"user_id": user_id},
            )

    try:
        supabase_client.table("discovery_sessions").delete().eq(
            "viewer_id", user_id,
        ).execute()
    except APIError:
        logger.exception(
            "Failed to purge discovery_sessions for user", extra={"user_id": user_id},
        )
    try:
        supabase_client.table("discovery_session_items").delete().eq(
            "candidate_id", user_id,
        ).execute()
    except APIError:
        logger.exception(
            "Failed to purge discovery_session_items for user",
            extra={"user_id": user_id},
        )


def _delete_user_media_objects(user_id: str) -> None:
    """Delete user media objects.

        Args:
            user_id: Unique UUID string of the authenticated user."""
    try:
        objects = supabase_client.storage.from_(_MEDIA_BUCKET).list(user_id)
    except Exception:
        logger.exception(
            "Failed to list user_media objects for purge", extra={"user_id": user_id},
        )
        return
    paths = [f"{user_id}/{obj['name']}" for obj in objects if obj.get("name")]
    if not paths:
        return
    try:
        supabase_client.storage.from_(_MEDIA_BUCKET).remove(paths)
    except Exception:
        logger.exception(
            "Failed to remove user_media objects for purge", extra={"user_id": user_id},
        )


def _ban_and_scrub_auth_user(user_id: str) -> None:
    """Ban and scrub auth user.

        Args:
            user_id: Unique UUID string of the authenticated user."""
    try:
        supabase_client.auth.admin.update_user_by_id(
            user_id,
            {
                "ban_duration": "876000h",  # ~100 years - effectively permanent
                "email": f"deleted-{user_id}@deleted.{settings.email_domain}",
            },
        )
    except Exception:
        logger.exception(
            "Failed to ban/scrub auth user during purge", extra={"user_id": user_id},
        )


def purge_due_accounts() -> None:
    """Tier-1 purge job body, run daily by the scheduler. Per-account
    failures are logged and skipped rather than aborting the whole batch.
    """
    now = utcnow()
    for row in _fetch_accounts_due_for_purge():
        user_id = str(row.get("id") or "")
        if not user_id:
            continue
        try:
            blind_index = row.get("mobile_blind_index")
            reason_code = row.get("deletion_flagged_reason_code")
            if reason_code and blind_index:
                supabase_client.table("deleted_account_blocklist").insert(
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
                ).execute()

            _permanently_unmatch_all(user_id)
            _anonymize_profile_and_user(user_id, now)
            _delete_no_retention_rows(user_id)
            _delete_user_media_objects(user_id)
            _ban_and_scrub_auth_user(user_id)
        except Exception:
            logger.exception(
                "Failed to purge account; will retry next run",
                extra={"user_id": user_id},
            )


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


def _archive_account_history(user_id: str) -> None:
    """Archive account history.

        Args:
            user_id: Unique UUID string of the authenticated user."""
    for source in _ARCHIVE_SOURCE_TABLES:
        table, or_filter_template, reason_field, outcome_field = source
        try:
            select_fields = "id, created_at"
            if reason_field:
                select_fields += f", {reason_field}"
            select_fields += f", {outcome_field}"
            query = supabase_client.table(table).select(select_fields)
            if table == "user_reports":
                query = query.or_(or_filter_template.format(uid=user_id))
            else:
                query = query.eq("user_id", user_id)
            res = query.execute()
        except APIError:
            logger.exception(
                "Failed to fetch %s for archival", table, extra={"user_id": user_id},
            )
            continue

        rows = cast(list[dict[str, Any]], res.data or [])
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
            continue
        try:
            supabase_client.table("account_history_archive").insert(archive_rows).execute()
        except APIError:
            logger.exception(
                "Failed to archive %s rows", table, extra={"user_id": user_id},
            )


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


def hard_purge_long_tail_accounts() -> None:
    """Tier-2 purge job body. Archives non-identifying report/moderation/
    feedback essentials, then deletes the auth.users row for good via the
    same admin.delete_user precedent already used at
    app/api/user.py:143 - this cascades away the anonymized profiles/users
    shell and everything still hanging off it (old matches,
    chat_conversations, chat_messages, user_reports, etc).
    """
    for user_id in _fetch_accounts_due_for_long_tail_purge():
        try:
            _archive_account_history(user_id)
            supabase_client.auth.admin.delete_user(user_id)
        except Exception:
            logger.exception(
                "Failed to hard-purge long-tail account; will retry next run",
                extra={"user_id": user_id},
            )
