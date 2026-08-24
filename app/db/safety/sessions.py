"""Safety check-in session lifecycle and dead-man-switch escalation scheduling."""

import html
import json
import logging
from datetime import timedelta
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import settings
from app.core.security.crypto import decrypt_pii, encrypt_to_hex
from app.db.client import DatabaseAccessError, normalize_uuid, supabase_client, utcnow

logger = logging.getLogger(__name__)

_SESSION_COLS = (
    "id, user_id, label, interval_seconds, next_checkin_at, event_context, "
    "status, battery_percent, connection_type, escalations_sent, "
    "last_escalated_at"
)


class EscalationInProgressError(Exception):
    """Raised when starting a new safety session while an active one is already escalating."""


def _decrypt_session_row(row: dict[str, Any]) -> dict[str, Any]:
    """Decrypts encrypted label and event_context fields in a safety_session row."""
    if not row:
        return row
    raw_label = row.get("label")
    if raw_label:
        try:
            row["label"] = decrypt_pii(raw_label)
        except Exception:
            pass

    if "event_context" in row:
        raw_event_context = row.get("event_context")
        if raw_event_context:
            if isinstance(raw_event_context, (str, bytes, memoryview)):
                try:
                    decrypted = decrypt_pii(raw_event_context)
                    if decrypted:
                        row["event_context"] = json.loads(decrypted)
                    else:
                        row["event_context"] = {}
                except Exception:
                    if not isinstance(row.get("event_context"), dict):
                        row["event_context"] = {}
            elif isinstance(raw_event_context, dict):
                row["event_context"] = raw_event_context
        else:
            row["event_context"] = {}
    return row


def start_safety_session(
    user_id: str,
    label: str | None,
    interval_seconds: int,
    next_checkin_at: str,
    event_context: dict[str, Any] | None,
    battery_percent: int | None,
    connection_type: str | None,
) -> dict[str, Any]:
    """Ends any stale active session for this user and starts a new one.

    Raises EscalationInProgressError if there is an active session currently escalating.
    """
    try:
        active_res = (
            supabase_client.table("safety_sessions")
            .select("id, escalations_sent")
            .eq("user_id", user_id)
            .eq("status", "active")
            .execute()
        )
        active_sessions = cast(list[dict[str, Any]], active_res.data or [])
        for session in active_sessions:
            if int(session.get("escalations_sent") or 0) > 0:
                raise EscalationInProgressError(
                    "Cannot start session: escalation already in progress",
                )

        supabase_client.table("safety_sessions").update({"status": "ended"}).eq(
            "user_id",
            user_id,
        ).eq("status", "active").execute()

        encrypted_label = encrypt_to_hex(label) if label else None
        encrypted_event_context = (
            encrypt_to_hex(json.dumps(event_context))
            if event_context
            else None
        )

        payload: dict[str, Any] = {
            "user_id": user_id,
            "label": encrypted_label,
            "interval_seconds": interval_seconds,
            "next_checkin_at": next_checkin_at,
            "event_context": encrypted_event_context,
            "last_heartbeat_at": utcnow().isoformat(),
            "battery_percent": battery_percent,
            "connection_type": connection_type,
        }
        res = (
            supabase_client.table("safety_sessions")
            .insert(payload)
            .select(_SESSION_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            raise DatabaseAccessError("Safety session insert returned no row")
        return _decrypt_session_row(cast(dict[str, Any], rows[0]))
    except APIError as e:
        logger.exception(
            "Failed to start safety session",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to start safety session") from e


def heartbeat_safety_session(
    user_id: str,
    session_id: str,
    next_checkin_at: str,
    battery_percent: int | None,
    connection_type: str | None,
) -> dict[str, Any] | None:
    """Updates next check-in time and resets escalations_sent count to 0."""
    try:
        res = (
            supabase_client.table("safety_sessions")
            .update(
                {
                    "next_checkin_at": next_checkin_at,
                    "last_heartbeat_at": utcnow().isoformat(),
                    "battery_percent": battery_percent,
                    "connection_type": connection_type,
                    "escalations_sent": 0,
                    "last_escalated_at": None,
                    "escalation_cancelled_at": None,
                    "escalation_cancel_reason": None,
                    "escalation_cancel_note": None,
                },
            )
            .eq("id", session_id)
            .eq("user_id", user_id)
            .eq("status", "active")
            .select(_SESSION_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            return None
        return _decrypt_session_row(cast(dict[str, Any], rows[0]))
    except APIError as e:
        logger.exception(
            "Failed to heartbeat safety session",
            extra={"user_id": user_id, "session_id": session_id},
        )
        raise DatabaseAccessError("Failed to heartbeat safety session") from e


def end_safety_session(user_id: str, session_id: str) -> None:
    """Marks safety session as ended."""
    try:
        supabase_client.table("safety_sessions").update(
            {"status": "ended"},
        ).eq("id", session_id).eq("user_id", user_id).execute()
    except APIError as e:
        logger.exception(
            "Failed to end safety session",
            extra={"user_id": user_id, "session_id": session_id},
        )
        raise DatabaseAccessError("Failed to end safety session") from e


def fetch_overdue_safety_sessions(
    grace_seconds: int,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """Fetch active safety sessions that missed a checkin beyond grace_seconds,
    excluding sessions whose users are suspended, deactivated, or pending deletion.
    """
    try:
        cutoff = (utcnow() - timedelta(seconds=grace_seconds)).isoformat()
        res = (
            supabase_client.table("safety_sessions")
            .select(f"{_SESSION_COLS}, users!inner(is_active, is_suspended, deletion_requested_at, purged_at)")
            .eq("status", "active")
            .is_("escalation_cancelled_at", "null")
            .eq("users.is_active", True)
            .eq("users.is_suspended", False)
            .is_("users.deletion_requested_at", "null")
            .is_("users.purged_at", "null")
            .lt("escalations_sent", settings.max_safety_escalations)
            .lt("next_checkin_at", cutoff)
            .limit(limit)
            .execute()
        )
        data = cast(list[dict[str, Any]], res.data or [])
        cleaned_rows: list[dict[str, Any]] = []
        for row in data:
            row_copy = dict(row)
            row_copy.pop("users", None)
            cleaned_rows.append(_decrypt_session_row(row_copy))
        return cleaned_rows
    except APIError as e:
        logger.exception("Failed to fetch overdue safety sessions")
        raise DatabaseAccessError("Failed to fetch overdue safety sessions") from e


def record_safety_escalation_sent(
    session_id: str,
    new_count: int,
    expected_count: int | None = None,
) -> bool:
    """Record escalation attempt count and timestamp with optimistic-locking idempotency.

    Args:
        session_id: Safety session UUID.
        new_count: The new escalations_sent count (e.g. N + 1).
        expected_count: Optional expected current escalations_sent (e.g. N) for optimistic locking.

    Returns:
        bool: True if row updated, False if update matched 0 rows (concurrent execution).
    """
    session_id = normalize_uuid(session_id)
    try:
        builder = (
            supabase_client.table("safety_sessions")
            .update(
                {
                    "escalations_sent": new_count,
                    "last_escalated_at": utcnow().isoformat(),
                },
            )
            .eq("id", session_id)
        )
        if expected_count is not None:
            builder = builder.eq("escalations_sent", expected_count)
        else:
            builder = builder.lt("escalations_sent", new_count)

        res = builder.execute()
        rows = cast(list[Any], getattr(res, "data", None) or [])
        return len(rows) > 0
    except APIError as e:
        logger.exception(
            "Failed to record safety escalation",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to record safety escalation") from e


def fetch_safety_session(session_id: str) -> dict[str, Any] | None:
    """Fetch single safety session by ID for contact portal and escalation cancel token flows.

    Note: Account-holder flows must use fetch_safety_session_for_user to enforce ownership.
    """
    try:
        res = (
            supabase_client.table("safety_sessions")
            .select(_SESSION_COLS)
            .eq("id", session_id)
            .maybe_single()
            .execute()
        )
        if res and res.data:
            return _decrypt_session_row(cast(dict[str, Any], res.data))
        return None
    except APIError as e:
        logger.exception(
            "Failed to fetch safety session",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to fetch safety session") from e


def fetch_safety_session_for_user(
    user_id: str,
    session_id: str,
) -> dict[str, Any] | None:
    """Fetch single safety session scoped to caller's user_id."""
    try:
        res = (
            supabase_client.table("safety_sessions")
            .select(_SESSION_COLS)
            .eq("id", session_id)
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        if res and res.data:
            return _decrypt_session_row(cast(dict[str, Any], res.data))
        return None
    except APIError as e:
        logger.exception(
            "Failed to fetch safety session for user",
            extra={"user_id": user_id, "session_id": session_id},
        )
        raise DatabaseAccessError("Failed to fetch safety session for user") from e


def cancel_safety_escalation(
    user_id: str,
    session_id: str,
    reason: str,
    note: str | None,
) -> dict[str, Any] | None:
    """Cancel safety escalation idempotently."""
    sanitized_note = html.escape(note.strip())[:500] if note else None
    try:
        res = (
            supabase_client.table("safety_sessions")
            .update(
                {
                    "escalation_cancelled_at": utcnow().isoformat(),
                    "escalation_cancel_reason": reason,
                    "escalation_cancel_note": sanitized_note,
                },
            )
            .eq("id", session_id)
            .eq("user_id", user_id)
            .is_("escalation_cancelled_at", "null")
            .select(_SESSION_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            return None
        return _decrypt_session_row(cast(dict[str, Any], rows[0]))
    except APIError as e:
        logger.exception(
            "Failed to cancel safety escalation",
            extra={"user_id": user_id, "session_id": session_id},
        )
        raise DatabaseAccessError("Failed to cancel safety escalation") from e

