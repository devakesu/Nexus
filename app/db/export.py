"""Builds the personal-data export returned by POST /api/v1/account/export
(app/api/export.py) - DPDP §11 access / GDPR Art 20 portability.

Reuses existing per-table decrypt helpers wherever they already exist
(fetch_safety_contacts, fetch_alerts_for_session's inline pattern,
fetch_playlists_for_owner, decrypt_profile_record, chat.py's
decrypt_event_row) rather than re-deriving decryption logic here. Each
section is fetched independently and wrapped in its own try/except so one
table's failure doesn't blank out the rest of the export.

Deliberately excluded (see the compliance plan for the reasoning behind
each): chat_messages.ciphertext/ciphertext_metadata (Signal-Protocol
content - no server-side plaintext exists, ever); safety_evidence's raw
media_key_base64 (a signed URL to the still-encrypted file is included
instead); spotify_connections.refresh_token (a live OAuth credential, not
"data about you"); user_reports filed *against* the user have reporter_id
stripped (protects the reporter from retaliation) but action_type/
reason_code/outcome are kept; user_moderation_actions drops private_notes
and created_by (staff-internal); blind-index hash columns and the
matching-engine-only artist_affinity field are never included anywhere.
"""

import logging
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.crypto import DecryptFailedError, decrypt_pii
from app.db.chat import decrypt_event_row
from app.db.client import supabase_client
from app.db.profiles import decrypt_profile_record, sanitize_decrypted_profile
from app.db.safety import fetch_safety_contacts
from app.db.spotify import fetch_playlists_for_owner
from app.db.users import get_user_email_by_id

logger = logging.getLogger(__name__)

_MEDIA_BUCKET = "user_media"
_SAFETY_EVIDENCE_BUCKET = "safety_evidence"
_EXPORT_SIGNED_URL_TTL_SECONDS = 24 * 60 * 60  # 24h - longer than the app's
# usual 1h profile-photo TTL, since an export may sit unopened for a while.

_PROFILE_SELECT = (
    "id, created_at, updated_at, name, age, campus_year, campus_branch, "
    "campus_name, display_gender, display_sexuality, pronouns, bio, "
    "hometown, current_place, partner_values, children_plans, "
    "religious_beliefs, lifestyle, drinking, smoking, role_at, role_type, "
    "looking_for, activities, causes_supported, top_artists, tech_skills, "
    "languages, ai_vibe_tags, pets, interests, sub_interests, "
    "value_dimensions, profile_pic, normal_pics, search_bucket, "
    "dating_target_buckets, friends_target_buckets, "
    "professional_target_buckets, dating_for, is_deactivated, "
    "deactivated_at, is_dating_active, is_friends_active, "
    "is_professional_active, hidden_profile_fields, share_active_status, "
    "share_read_receipts"
)

_USER_SELECT = (
    "id, created_at, updated_at, accepted_terms_version, terms_accepted_at, "
    "special_category_consent_version, special_category_consent_at, "
    "safety_data_consent_version, safety_data_consent_at, is_active, "
    "is_suspended, moderation_status, app_variant, mobile_verified_at"
)


def _safe_select(
    table: str,
    columns: str,
    user_id: str,
    *,
    id_column: str = "user_id",
) -> list[dict[str, Any]]:
    """Fail-soft select-all-for-user helper: logs and returns an empty list
    on failure rather than aborting the whole export over one table.
    """
    try:
        res = (
            supabase_client.table(table)
            .select(columns)
            .eq(id_column, user_id)
            .execute()
        )
        return [r for r in cast(list[Any], res.data or []) if isinstance(r, dict)]
    except APIError:
        logger.exception(
            "Failed to fetch %s for data export", table, extra={"user_id": user_id},
        )
        return []


def _sign_urls(bucket: str, paths: list[str]) -> dict[str, str]:
    unique_paths = list(dict.fromkeys(p for p in paths if p))
    if not unique_paths:
        return {}
    try:
        signed = supabase_client.storage.from_(bucket).create_signed_urls(
            unique_paths, _EXPORT_SIGNED_URL_TTL_SECONDS,
        )
    except Exception:
        logger.exception("Failed to sign export URLs", extra={"bucket": bucket})
        return {}
    result: dict[str, str] = {}
    for item in signed:
        path = item.get("path")
        url = item.get("signedURL")
        if path and url:
            result[path] = url
    return result


def _build_profile_section(user_id: str) -> dict[str, Any]:
    try:
        res = (
            supabase_client.table("profiles")
            .select(_PROFILE_SELECT)
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
    except APIError:
        logger.exception(
            "Failed to fetch profile for data export", extra={"user_id": user_id},
        )
        return {}
    row = getattr(res, "data", None)
    if not isinstance(row, dict):
        return {}
    row_dict = cast(dict[str, Any], row)
    try:
        decrypted = sanitize_decrypted_profile(decrypt_profile_record(row_dict))
    except DecryptFailedError:
        logger.exception(
            "Failed to decrypt profile for data export", extra={"user_id": user_id},
        )
        return {}

    profile_pic = cast("str | None", decrypted.get("profile_pic"))
    normal_pics = cast("list[Any] | None", decrypted.get("normal_pics"))
    photo_paths: list[str] = [profile_pic] if profile_pic else []
    if isinstance(normal_pics, list):
        photo_paths.extend(str(p) for p in normal_pics if isinstance(p, str) and p)
    signed = _sign_urls(_MEDIA_BUCKET, photo_paths)
    if profile_pic:
        decrypted["profile_pic"] = signed.get(profile_pic)
    if isinstance(normal_pics, list):
        decrypted["normal_pics"] = [
            signed[p] for p in normal_pics if isinstance(p, str) and p in signed
        ]

    return decrypted


def _build_account_section(user_id: str) -> dict[str, Any]:
    try:
        res = (
            supabase_client.table("users")
            .select(_USER_SELECT)
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
    except APIError:
        logger.exception(
            "Failed to fetch account for data export", extra={"user_id": user_id},
        )
        return {}
    row = getattr(res, "data", None)
    account = cast(dict[str, Any], row) if isinstance(row, dict) else {}
    account["email"] = get_user_email_by_id(user_id)
    return account


def _build_matches_and_discovery(user_id: str) -> dict[str, Any]:
    try:
        matches_res = (
            supabase_client.table("matches")
            .select("id, liker_id, liked_back_id, tab, created_at, unmatched_at")
            .or_(f"liker_id.eq.{user_id},liked_back_id.eq.{user_id}")
            .execute()
        )
        matches: list[dict[str, Any]] = [
            cast(dict[str, Any], r)
            for r in cast(list[Any], matches_res.data or [])
            if isinstance(r, dict)
        ]
    except APIError:
        logger.exception(
            "Failed to fetch matches for data export", extra={"user_id": user_id},
        )
        matches = []

    discovery_actions = _safe_select(
        "profile_discovery_actions",
        "id, target_id, tab, action, created_at, revoked_at",
        user_id,
        id_column="actor_id",
    )
    return {"matches": matches, "discovery_actions": discovery_actions}


def _build_chat_section(user_id: str) -> dict[str, Any]:
    try:
        conv_res = (
            supabase_client.table("chat_conversations")
            .select(
                "id, match_id, tab, created_at, last_message_at, "
                "closed_at, closed_reason",
            )
            .or_(f"user_a_id.eq.{user_id},user_b_id.eq.{user_id}")
            .execute()
        )
        conversations: list[dict[str, Any]] = [
            cast(dict[str, Any], r)
            for r in cast(list[Any], conv_res.data or [])
            if isinstance(r, dict)
        ]
    except APIError:
        logger.exception(
            "Failed to fetch conversations for data export", extra={"user_id": user_id},
        )
        conversations = []

    conversation_ids = [str(c["id"]) for c in conversations if c.get("id")]
    messages: list[dict[str, Any]] = []
    events: list[dict[str, Any]] = []
    if conversation_ids:
        try:
            msg_res = (
                supabase_client.table("chat_messages")
                .select(
                    "id, conversation_id, sender_id, message_type, "
                    "created_at, delivered_at, read_at",
                )
                .in_("conversation_id", conversation_ids)
                .execute()
            )
            messages = [
                {**r, "content_excluded_reason": (
                    "End-to-end encrypted with the Signal Protocol - Nexus "
                    "never holds a decryptable copy of message content."
                )}
                for r in cast(list[Any], msg_res.data or [])
                if isinstance(r, dict)
            ]
        except APIError:
            logger.exception(
                "Failed to fetch messages for data export", extra={"user_id": user_id},
            )

        try:
            event_res = (
                supabase_client.table("chat_events")
                .select(
                    "id, conversation_id, created_by, event_time, location_lat, "
                    "location_lng, location_label, status, created_at",
                )
                .in_("conversation_id", conversation_ids)
                .execute()
            )
            for row in cast(list[Any], event_res.data or []):
                if not isinstance(row, dict):
                    continue
                decrypted_event = decrypt_event_row(cast(dict[str, Any], row))
                if decrypted_event is not None:
                    events.append(decrypted_event)
        except APIError:
            logger.exception(
                "Failed to fetch events for data export", extra={"user_id": user_id},
            )

    presence = _safe_select(
        "chat_presence", "last_active_at, is_online, updated_at", user_id,
    )

    return {
        "conversations": conversations,
        "messages": messages,
        "events": events,
        "presence": presence[0] if presence else None,
    }


def _build_reports_section(user_id: str) -> dict[str, Any]:
    filed_by_you: list[dict[str, Any]] = []
    against_you: list[dict[str, Any]] = []
    try:
        res = (
            supabase_client.table("user_reports")
            .select(
                "id, reporter_id, target_id, tab, reason, reason_detail, "
                "review_status, created_at",
            )
            .or_(f"reporter_id.eq.{user_id},target_id.eq.{user_id}")
            .execute()
        )
        for row in cast(list[Any], res.data or []):
            if not isinstance(row, dict):
                continue
            row_dict = cast(dict[str, Any], row)
            if str(row_dict.get("reporter_id")) == user_id:
                filed_by_you.append(row_dict)
            else:
                # Reporter's identity is withheld to protect them from
                # retaliation - the substance of the report (reason,
                # outcome) is still disclosed.
                row_dict.pop("reporter_id", None)
                against_you.append(row_dict)
    except APIError:
        logger.exception(
            "Failed to fetch user_reports for data export", extra={"user_id": user_id},
        )

    moderation_actions = [
        {
            "action_type": r.get("action_type"),
            "reason_code": r.get("reason_code"),
            "created_at": r.get("created_at"),
            "expires_at": r.get("expires_at"),
            "revoked_at": r.get("revoked_at"),
        }
        for r in _safe_select(
            "user_moderation_actions",
            "action_type, reason_code, created_at, expires_at, revoked_at",
            user_id,
        )
    ]

    return {
        "reports_you_filed": filed_by_you,
        "reports_against_you": against_you,
        "moderation_actions": moderation_actions,
    }


def _build_feedback_section(user_id: str) -> list[dict[str, Any]]:
    tickets = _safe_select(
        "feedback_reports",
        "id, query_type, subject, message, status, created_at, updated_at",
        user_id,
    )
    for ticket in tickets:
        report_id = str(ticket.get("id") or "")
        if not report_id:
            continue
        try:
            history_res = (
                supabase_client.table("feedback_report_status_history")
                .select("status, note, created_at")
                .eq("report_id", report_id)
                .execute()
            )
            ticket["status_history"] = [
                r
                for r in cast(list[Any], history_res.data or [])
                if isinstance(r, dict)
            ]
        except APIError:
            ticket["status_history"] = []
        try:
            comments_res = (
                supabase_client.table("feedback_report_comments")
                .select("body, created_at")
                .eq("report_id", report_id)
                .execute()
            )
            ticket["comments"] = [
                r
                for r in cast(list[Any], comments_res.data or [])
                if isinstance(r, dict)
            ]
        except APIError:
            ticket["comments"] = []
    return tickets


def _build_safety_alerts(user_id: str) -> list[dict[str, Any]]:
    alerts: list[dict[str, Any]] = []
    try:
        alerts_res = (
            supabase_client.table("safety_alerts")
            .select("id, alert_type, current_location, created_at")
            .eq("user_id", user_id)
            .execute()
        )
        for row in cast(list[Any], alerts_res.data or []):
            if not isinstance(row, dict):
                continue
            row_dict = cast(dict[str, Any], row)
            loc = row_dict.get("current_location")
            if loc:
                try:
                    row_dict["current_location"] = decrypt_pii(loc)
                except DecryptFailedError:
                    row_dict["current_location"] = None
            alerts.append(row_dict)
    except APIError:
        logger.exception(
            "Failed to fetch safety alerts for data export", extra={"user_id": user_id},
        )
    return alerts


def _build_safety_evidence(user_id: str) -> list[dict[str, Any]]:
    evidence: list[dict[str, Any]] = []
    try:
        evidence_res = (
            supabase_client.table("safety_evidence")
            .select(
                "id, alert_id, storage_path, content_type, "
                "duration_seconds, created_at",
            )
            .eq("user_id", user_id)
            .execute()
        )
        raw_evidence: list[dict[str, Any]] = [
            cast(dict[str, Any], r)
            for r in cast(list[Any], evidence_res.data or [])
            if isinstance(r, dict)
        ]
        signed = _sign_urls(
            _SAFETY_EVIDENCE_BUCKET,
            [str(r["storage_path"]) for r in raw_evidence if r.get("storage_path")],
        )
        for row in raw_evidence:
            path = cast("str | None", row.pop("storage_path", None))
            row["download_url"] = signed.get(path) if path else None
            row["note"] = (
                "The decryption key is intentionally not included in this "
                "export - contact support if you need the raw recording."
            )
            evidence.append(row)
    except APIError:
        logger.exception(
            "Failed to fetch safety evidence for data export",
            extra={"user_id": user_id},
        )
    return evidence


def _build_safety_section(user_id: str) -> dict[str, Any]:
    try:
        contacts = fetch_safety_contacts(user_id)
    except Exception:
        logger.exception(
            "Failed to fetch safety contacts for data export",
            extra={"user_id": user_id},
        )
        contacts = []

    sessions = _safe_select(
        "safety_sessions",
        "label, interval_seconds, status, created_at, updated_at",
        user_id,
    )

    return {
        "trusted_contacts": contacts,
        "checkin_sessions": sessions,
        "alerts": _build_safety_alerts(user_id),
        "evidence": _build_safety_evidence(user_id),
    }


def _build_spotify_section(user_id: str) -> list[dict[str, Any]]:
    try:
        return fetch_playlists_for_owner(user_id)
    except Exception:
        logger.exception(
            "Failed to fetch spotify playlists for data export",
            extra={"user_id": user_id},
        )
        return []


def _build_consent_history(user_id: str) -> list[dict[str, Any]]:
    return _safe_select(
        "terms_consent_log",
        "category, granted, terms_version, created_at",
        user_id,
    )


def build_user_data_export(user_id: str) -> dict[str, Any]:
    """Assembles the full export payload. Called via run_in_threadpool from
    POST /api/v1/account/export (app/api/export.py) - a synchronous,
    single-request build, since one user's data volume is light enough
    that no background-job/email-link infrastructure is warranted (unlike
    the account-deletion purge job, which processes many accounts at once).
    """
    return {
        "profile": _build_profile_section(user_id),
        "account": _build_account_section(user_id),
        "devices": _safe_select(
            "user_devices", "platform, is_active, last_seen_at, created_at", user_id,
        ),
        **_build_matches_and_discovery(user_id),
        "chat": _build_chat_section(user_id),
        **_build_reports_section(user_id),
        "feedback_tickets": _build_feedback_section(user_id),
        "safety": _build_safety_section(user_id),
        "spotify_playlists": _build_spotify_section(user_id),
        "identity_change_history": {
            "name_changes": _safe_select(
                "profile_name_change_log", "changed_at", user_id,
            ),
            "age_changes": _safe_select(
                "profile_age_change_log", "changed_at", user_id,
            ),
        },
        "consent_history": _build_consent_history(user_id),
    }
