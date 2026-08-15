"""Safety check-in session lifecycle and dead-man-switch escalation scheduling."""

import logging
from datetime import timedelta
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import settings
from app.db.client import DatabaseAccessError, supabase_client, utcnow

logger = logging.getLogger(__name__)

_SESSION_COLS = (
    "id, user_id, label, interval_seconds, next_checkin_at, event_context, "
    "status, battery_percent, connection_type, escalations_sent, "
    "last_escalated_at"
)


class EscalationInProgressError(Exception):
    """Raised when starting a new safety session while an active one is already escalating."""


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

        payload: dict[str, Any] = {
            "user_id": user_id,
            "label": label,
            "interval_seconds": interval_seconds,
            "next_checkin_at": next_checkin_at,
            "event_context": event_context or {},
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
        return cast(dict[str, Any], rows[0])
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
        return cast(dict[str, Any], rows[0])
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


def fetch_overdue_safety_sessions(grace_seconds: int) -> list[dict[str, Any]]:
    """Fetch active safety sessions that missed a checkin beyond grace_seconds."""
    try:
        cutoff = (utcnow() - timedelta(seconds=grace_seconds)).isoformat()
        res = (
            supabase_client.table("safety_sessions")
            .select(_SESSION_COLS)
            .eq("status", "active")
            .is_("escalation_cancelled_at", "null")
            .lt("escalations_sent", settings.max_safety_escalations)
            .lt("next_checkin_at", cutoff)
            .limit(500)
            .execute()
        )
        return cast(list[dict[str, Any]], res.data or [])
    except APIError as e:
        logger.exception("Failed to fetch overdue safety sessions")
        raise DatabaseAccessError("Failed to fetch overdue safety sessions") from e


def record_safety_escalation_sent(session_id: str, new_count: int) -> None:
    """Record escalation attempt count and timestamp."""
    try:
        supabase_client.table("safety_sessions").update(
            {
                "escalations_sent": new_count,
                "last_escalated_at": utcnow().isoformat(),
            },
        ).eq("id", session_id).execute()
    except APIError as e:
        logger.exception(
            "Failed to record safety escalation",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to record safety escalation") from e


def fetch_safety_session(session_id: str) -> dict[str, Any] | None:
    """Fetch single safety session by ID."""
    try:
        res = (
            supabase_client.table("safety_sessions")
            .select(_SESSION_COLS)
            .eq("id", session_id)
            .maybe_single()
            .execute()
        )
        if res and res.data:
            return cast(dict[str, Any], res.data)
        return None
    except APIError as e:
        logger.exception(
            "Failed to fetch safety session",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to fetch safety session") from e


def cancel_safety_escalation(
    session_id: str,
    reason: str,
    note: str | None,
) -> dict[str, Any] | None:
    """Cancel safety escalation idempotently."""
    try:
        res = (
            supabase_client.table("safety_sessions")
            .update(
                {
                    "escalation_cancelled_at": utcnow().isoformat(),
                    "escalation_cancel_reason": reason,
                    "escalation_cancel_note": note,
                },
            )
            .eq("id", session_id)
            .is_("escalation_cancelled_at", "null")
            .select(_SESSION_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            return None
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to cancel safety escalation",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to cancel safety escalation") from e
