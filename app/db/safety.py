import logging
from typing import Any, cast

from postgrest.exceptions import APIError

from app.db.client import DatabaseAccessError, supabase_client

logger = logging.getLogger(__name__)

_ALERT_INSERT_COLS = "id, created_at"
_EVIDENCE_INSERT_COLS = "id"


def sync_safety_contacts(user_id: str, contacts: list[dict[str, Any]]) -> None:
    """Replaces the caller's full trusted-contact mirror.

    Delete-then-insert rather than a diff, since the list is always small
    (device caps it at 3) and this can never drift out of order with the
    device's copy.
    """
    try:
        supabase_client.table("safety_contacts").delete().eq(
            "user_id",
            user_id,
        ).execute()
        if contacts:
            rows = [{**c, "user_id": user_id} for c in contacts]
            supabase_client.table("safety_contacts").insert(rows).execute()
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
        return cast(list[dict[str, Any]], res.data or [])
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
) -> dict[str, Any]:
    payload: dict[str, Any] = {"user_id": user_id, "alert_type": alert_type}
    if current_location is not None:
        payload["current_location"] = current_location

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
