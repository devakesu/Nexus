"""Safety check-in session lifecycle and dead-man-switch escalation scheduling."""

import html
import json
import logging
from datetime import timedelta
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import settings
from app.core.security.crypto import decrypt_pii, encrypt_to_hex
from app.db.client import (
    DatabaseAccessError,
    normalize_uuid,
    parse_utc_datetime,
    supabase_client,
    utcnow,
)

logger = logging.getLogger(__name__)

_SESSION_COLS = (
    "id, user_id, label, interval_seconds, next_checkin_at, event_context, "
    "status, battery_percent, connection_type, escalations_sent, "
    "last_escalated_at"
)


class EscalationInProgressError(Exception):
    """Raised when starting a new safety session while an active one is already escalating."""


def _decrypt_session_label(row: dict[str, Any]) -> None:
    raw_label = row.get("label")
    if raw_label:
        try:
            row["label"] = decrypt_pii(raw_label, category="media_escrow")
        except Exception as e:  # noqa: BLE001
            logger.debug("Failed to decrypt session label: %s", e)


def _decrypt_session_event_context(row: dict[str, Any]) -> None:
    if "event_context" not in row:
        return
    raw_event_context = row.get("event_context")
    if not raw_event_context:
        row["event_context"] = {}
        return
    if isinstance(raw_event_context, dict):
        row["event_context"] = raw_event_context
        return
    if isinstance(raw_event_context, (str, bytes, memoryview)):
        try:
            decrypted = decrypt_pii(raw_event_context, category="media_escrow")
            row["event_context"] = json.loads(decrypted) if decrypted else {}
        except Exception as e:  # noqa: BLE001
            logger.debug("Failed to decrypt session event_context: %s", e)
            if not isinstance(row.get("event_context"), dict):
                row["event_context"] = {}


def _decrypt_session_row(row: dict[str, Any]) -> dict[str, Any]:
    """Decrypts encrypted label and event_context fields in a safety_session row."""
    if not row:
        return row
    _decrypt_session_label(row)
    _decrypt_session_event_context(row)
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
    """Ends any stale active session for this user and starts a new one atomically via RPC.

    Raises EscalationInProgressError if there is an active session currently escalating.
    """
    user_id = normalize_uuid(user_id)
    encrypted_label = encrypt_to_hex(label, category="media_escrow") if label else None
    encrypted_event_context = (
        encrypt_to_hex(json.dumps(event_context), category="media_escrow")
        if event_context
        else None
    )

    try:
        res = supabase_client.rpc(
            "start_safety_session",
            {
                "p_user_id": user_id,
                "p_label": encrypted_label,
                "p_interval_seconds": interval_seconds,
                "p_next_checkin_at": next_checkin_at,
                "p_event_context": encrypted_event_context,
                "p_battery_percent": battery_percent,
                "p_connection_type": connection_type,
            },
        ).execute()
    except APIError as e:
        error_msg = str(e)
        if "escalation already in progress" in error_msg:
            raise EscalationInProgressError(
                "Cannot start session: escalation already in progress",
            ) from e
        logger.exception(
            "Failed to start safety session",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to start safety session") from e

    data = res.data if res else None
    if isinstance(data, list) and len(data) > 0:
        row = data[0]
    elif isinstance(data, dict):
        row = data
    else:
        raise DatabaseAccessError("Safety session insert returned no row")

    return _decrypt_session_row(cast(dict[str, Any], row))


def _compute_heartbeat_payload(
    current_session: dict[str, Any],
    next_checkin_at: str,
    battery_percent: int | None,
    connection_type: str | None,
) -> dict[str, Any]:
    curr_next_checkin = current_session.get("next_checkin_at")
    last_escalated_at = current_session.get("last_escalated_at")
    escalations_sent = int(current_session.get("escalations_sent") or 0)

    new_dt = parse_utc_datetime(next_checkin_at)

    # Check if next_checkin_at regresses against current next_checkin_at
    is_stale_deadline = bool(curr_next_checkin and new_dt <= parse_utc_datetime(curr_next_checkin))

    # Check if next_checkin_at is newer than last_escalated_at
    should_reset_escalation = not (
        escalations_sent > 0
        and last_escalated_at
        and new_dt <= parse_utc_datetime(last_escalated_at)
    )

    update_payload: dict[str, Any] = {
        "last_heartbeat_at": utcnow().isoformat(),
        "battery_percent": battery_percent,
        "connection_type": connection_type,
    }
    if not is_stale_deadline:
        update_payload["next_checkin_at"] = next_checkin_at

    if should_reset_escalation and not is_stale_deadline:
        update_payload["escalations_sent"] = 0
        update_payload["last_escalated_at"] = None
        update_payload["escalation_cancelled_at"] = None
        update_payload["escalation_cancel_reason"] = None
        update_payload["escalation_cancel_note"] = None

    return update_payload


def heartbeat_safety_session(
    user_id: str,
    session_id: str,
    next_checkin_at: str,
    battery_percent: int | None,
    connection_type: str | None,
) -> dict[str, Any] | None:
    """Updates next check-in time and conditionally resets escalations_sent.

    Only resets escalations_sent to 0 and clears escalation state if next_checkin_at is
    strictly newer than last_escalated_at (or if no escalation has occurred), and does not
    regress next_checkin_at if a stale/buffered heartbeat is received.
    """
    user_id = normalize_uuid(user_id)
    session_id = normalize_uuid(session_id)
    try:
        session_res = (
            supabase_client.table("safety_sessions")
            .select("id, next_checkin_at, escalations_sent, last_escalated_at")
            .eq("id", session_id)
            .eq("user_id", user_id)
            .eq("status", "active")
            .execute()
        )
        rows = cast(list[dict[str, Any]], session_res.data or [])
        if not rows:
            return None

        update_payload = _compute_heartbeat_payload(
            rows[0],
            next_checkin_at,
            battery_percent,
            connection_type,
        )

        res = (
            supabase_client.table("safety_sessions")
            .update(update_payload)
            .eq("id", session_id)
            .eq("user_id", user_id)
            .eq("status", "active")
            .select(_SESSION_COLS)
            .execute()
        )
        updated_rows = cast(list[Any], res.data or [])
        if not updated_rows or not isinstance(updated_rows[0], dict):
            return None
        return _decrypt_session_row(cast(dict[str, Any], updated_rows[0]))
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

