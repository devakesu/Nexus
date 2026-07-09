import contextlib
import json
import logging
from datetime import timedelta
from typing import Any, cast

from postgrest.exceptions import APIError
from storage3.utils import StorageException

from app.core.crypto import decrypt_pii, encrypt_to_hex
from app.db.client import DatabaseAccessError, supabase_client, utcnow

logger = logging.getLogger(__name__)

_ALERT_INSERT_COLS = "id, created_at"
_EVIDENCE_INSERT_COLS = "id"
_SESSION_COLS = (
    "id, user_id, label, interval_seconds, next_checkin_at, event_context, "
    "status, battery_percent, connection_type, escalations_sent, "
    "last_escalated_at"
)


def sync_safety_contacts(user_id: str, contacts: list[dict[str, Any]]) -> None:
    """Replaces the caller's full trusted-contact mirror atomically using an RPC."""
    encrypted: list[dict[str, Any]] = []
    for c in contacts:
        encrypted.append({
            "name": encrypt_to_hex(c.get("name")),
            "phone": encrypt_to_hex(c.get("phone")),
        })
    try:
        supabase_client.rpc(
            "sync_safety_contacts",
            {"p_user_id": user_id, "p_contacts": encrypted},
        ).execute()
    except APIError as e:
        logger.exception("Failed to sync safety contacts", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to sync safety contacts") from e


def fetch_safety_contacts(user_id: str) -> list[dict[str, Any]]:
    try:
        res = (
            supabase_client.table("safety_contacts")
            .select("name, phone")
            .eq("user_id", user_id)
            .execute()
        )
        data = cast(list[dict[str, Any]], res.data or [])
        for row in data:
            row["name"] = decrypt_pii(row.get("name"))
            row["phone"] = decrypt_pii(row.get("phone"))
        return data
    except APIError as e:
        logger.exception(
            "Failed to fetch safety contacts",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to fetch safety contacts") from e


def record_safety_alert(
    user_id: str,
    alert_type: str,
    current_location: dict[str, float] | None,
    session_id: str | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {"user_id": user_id, "alert_type": alert_type}
    if current_location is not None:
        payload["current_location"] = encrypt_to_hex(json.dumps(current_location))
    if session_id is not None:
        payload["session_id"] = session_id

    try:
        res = (
            supabase_client.table("safety_alerts")
            .insert(payload)
            .select(_ALERT_INSERT_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            raise DatabaseAccessError("Safety alert insert returned no row")
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to insert safety alert",
            extra={"user_id": user_id, "alert_type": alert_type},
        )
        raise DatabaseAccessError("Failed to insert safety alert") from e


def fetch_safety_alert(alert_id: str) -> dict[str, Any] | None:
    try:
        res = (
            supabase_client.table("safety_alerts")
            .select("id, user_id")
            .eq("id", alert_id)
            .maybe_single()
            .execute()
        )
        if res and res.data:
            return cast(dict[str, Any], res.data)
        return None
    except APIError as e:
        logger.exception("Failed to fetch safety alert", extra={"alert_id": alert_id})
        raise DatabaseAccessError("Failed to fetch safety alert") from e


def update_alert_contacts_notified(alert_id: str, count: int) -> None:
    try:
        supabase_client.table("safety_alerts").update(
            {"contacts_notified": count},
        ).eq("id", alert_id).execute()
    except APIError as e:
        logger.exception(
            "Failed to update safety alert notified count",
            extra={"alert_id": alert_id},
        )
        raise DatabaseAccessError(
            "Failed to update safety alert notified count",
        ) from e


def register_safety_evidence(
    user_id: str,
    alert_id: str,
    storage_path: str,
    media_key_base64: str,
    content_type: str,
    duration_seconds: float | None,
) -> dict[str, Any]:
    # SECURITY NOTE: Storing media_key_base64 in safety_evidence escrows
    # the per-file AES-GCM decryption key server-side in plaintext. This
    # facilitates trusted contact decryption without needing the client app
    # active, but introduces a risk where database compromises, backups,
    # or service-role level leaks can expose the keys to decrypt the media.
    payload: dict[str, Any] = {
        "user_id": user_id,
        "alert_id": alert_id,
        "storage_path": storage_path,
        "media_key_base64": media_key_base64,
        "content_type": content_type,
    }
    if duration_seconds is not None:
        payload["duration_seconds"] = duration_seconds

    try:
        res = (
            supabase_client.table("safety_evidence")
            .insert(payload)
            .select(_EVIDENCE_INSERT_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            raise DatabaseAccessError("Safety evidence insert returned no row")
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to register safety evidence",
            extra={"user_id": user_id, "alert_id": alert_id},
        )
        raise DatabaseAccessError("Failed to register safety evidence") from e


# ---------------------------------------------------------------------------
# Recurring check-in session mirror (Milestone D: dead-man's-switch)
# ---------------------------------------------------------------------------


def start_safety_session(
    user_id: str,
    label: str | None,
    interval_seconds: int,
    next_checkin_at: str,
    event_context: dict[str, Any] | None,
    battery_percent: int | None,
    connection_type: str | None,
) -> dict[str, Any]:
    """Ends any stale active session for this user (defensive - the device
    should have already ended its previous session) and starts a new one.
    """
    try:
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
    """A successful check-in (or a fresh start) proves the device is fine,
    so this always resets escalations_sent back to 0. It also clears any
    earlier escalation_cancelled_at from a *previous* missed-checkin streak
    - that cancellation was scoped to the incident a trusted contact
    dismissed, not a permanent opt-out, so a fresh miss later in the same
    session must still be able to escalate again.
    """
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
    """Candidate sessions that have missed at least one check-in and haven't
    exhausted their 3 escalation attempts. The precise "is the *next*
    escalation actually due yet" check (which depends on escalations_sent,
    not just next_checkin_at) is done in Python by the caller, same as
    fetch_user_tickets sorts in Python rather than SQL.
    """
    try:
        cutoff = (utcnow() - timedelta(seconds=grace_seconds)).isoformat()
        res = (
            supabase_client.table("safety_sessions")
            .select(_SESSION_COLS)
            .eq("status", "active")
            .is_("escalation_cancelled_at", "null")
            .lt("escalations_sent", 3)
            .lt("next_checkin_at", cutoff)
            .execute()
        )
        return cast(list[dict[str, Any]], res.data or [])
    except APIError as e:
        logger.exception("Failed to fetch overdue safety sessions")
        raise DatabaseAccessError("Failed to fetch overdue safety sessions") from e


def record_safety_escalation_sent(session_id: str, new_count: int) -> None:
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
    """Idempotent: only takes effect the first time (escalation_cancelled_at
    IS NULL), so a trusted contact double-tapping the link (or the link
    being opened twice) doesn't overwrite an earlier reason/note.
    """
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


# ---------------------------------------------------------------------------
# Trusted-contact web portal (Milestone E)
# ---------------------------------------------------------------------------

_PORTAL_ALERT_COLS = "id, alert_type, current_location, created_at"
_PORTAL_EVIDENCE_COLS = (
    "id, alert_id, storage_path, media_key_base64, content_type, "
    "duration_seconds, created_at"
)


def fetch_alerts_for_session(session_id: str) -> list[dict[str, Any]]:
    """Newest first, so the portal's "last known location" is simply the
    first row with a non-null current_location.
    """
    try:
        res = (
            supabase_client.table("safety_alerts")
            .select(_PORTAL_ALERT_COLS)
            .eq("session_id", session_id)
            .order("created_at", desc=True)
            .execute()
        )
        alerts = cast(list[dict[str, Any]], res.data or [])
        for a in alerts:
            loc = a.get("current_location")
            if loc:
                with contextlib.suppress(Exception):
                    dec = decrypt_pii(loc)
                    a["current_location"] = json.loads(dec) if dec else None
        return alerts
    except APIError as e:
        logger.exception(
            "Failed to fetch alerts for safety session",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to fetch alerts for safety session") from e


def fetch_evidence_for_alert_ids(alert_ids: list[str]) -> list[dict[str, Any]]:
    if not alert_ids:
        return []
    try:
        res = (
            supabase_client.table("safety_evidence")
            .select(_PORTAL_EVIDENCE_COLS)
            .in_("alert_id", alert_ids)
            .order("created_at", desc=False)
            .execute()
        )
        return cast(list[dict[str, Any]], res.data or [])
    except APIError as e:
        logger.exception(
            "Failed to fetch evidence for safety alerts",
            extra={"alert_id_count": len(alert_ids)},
        )
        raise DatabaseAccessError("Failed to fetch evidence for safety alerts") from e


def create_evidence_download_url(storage_path: str, expires_in: int) -> str | None:
    """A fresh, short-lived signed URL into the private safety_evidence
    bucket - generated on demand rather than stored, so it's never sitting
    around valid longer than a single portal page load needs it.
    """
    try:
        result = supabase_client.storage.from_("safety_evidence").create_signed_url(
            storage_path,
            expires_in,
        )
        return result.get("signedURL")
    except StorageException:
        logger.exception(
            "Failed to create signed URL for safety evidence",
            extra={"storage_path": storage_path},
        )
        return None
