"""Emergency safety alert recording, portal summary, and retention purge jobs."""

import contextlib
import json
import logging
from datetime import timedelta
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import settings
from app.core.security.crypto import DecryptFailedError, decrypt_pii, encrypt_to_hex
from app.db.client import DatabaseAccessError, parse_utc_datetime, supabase_client, utcnow
from app.db.profiles import (
    decrypt_profile_record,
    sanitize_decrypted_profile,
    sign_profile_media,
)

logger = logging.getLogger(__name__)

_ALERT_INSERT_COLS = "id, created_at"
_PORTAL_ALERT_COLS = "id, alert_type, current_location, created_at"
_PORTAL_LOCATION_MAX_AGE = timedelta(hours=4)


def fetch_contact_facing_profile_summary(user_id: str) -> dict[str, Any] | None:
    """Narrow profile view for safety contact self-removal portal."""
    try:
        res = (
            supabase_client.table("profiles")
            .select("name, profile_pic, hometown, current_place")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        if not res or not res.data:
            return None
        row = cast(dict[str, Any], res.data)
    except APIError as e:
        logger.exception(
            "Failed to fetch profile summary for contact portal",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to fetch profile summary") from e

    try:
        decrypted = sanitize_decrypted_profile(decrypt_profile_record(row))
    except DecryptFailedError:
        logger.exception(
            "Failed to decrypt profile summary for contact portal",
            extra={"user_id": user_id},
        )
        return None
    return sign_profile_media(decrypted)


def record_safety_alert(
    user_id: str,
    alert_type: str,
    current_location: dict[str, float] | None,
    session_id: str | None = None,
) -> dict[str, Any]:
    """Records emergency safety alert with encrypted location snapshot."""
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
    """Fetch single safety alert by alert ID."""
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
    """Update contacts notified count on safety alert."""
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


def fetch_alerts_for_session(
    session_id: str,
    decrypt_locations: bool = True,
    max_location_age: timedelta | None = _PORTAL_LOCATION_MAX_AGE,
) -> list[dict[str, Any]]:
    """Fetch safety alerts for a given safety session.
    
    Locations are only decrypted if decrypt_locations is True and the alert timestamp
    is within max_location_age (staleness guard against exposure of old coordinates).
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
        now = utcnow()
        for a in alerts:
            loc = a.get("current_location")
            created_at_raw = a.get("created_at")
            if loc and decrypt_locations:
                is_stale = False
                if max_location_age is not None and created_at_raw:
                    with contextlib.suppress(Exception):
                        alert_time = parse_utc_datetime(created_at_raw)
                        if now - alert_time > max_location_age:
                            is_stale = True
                if not is_stale:
                    with contextlib.suppress(Exception):
                        dec = decrypt_pii(loc)
                        a["current_location"] = json.loads(dec) if dec else None
                else:
                    a["current_location"] = None
            else:
                a["current_location"] = None
        return alerts
    except APIError as e:
        logger.exception(
            "Failed to fetch alerts for safety session",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to fetch alerts for safety session") from e


def purge_expired_safety_evidence() -> None:
    """Purge safety evidence older than safety_evidence_active_retention_days."""
    cutoff = (
        utcnow() - timedelta(days=settings.safety_evidence_active_retention_days)
    ).isoformat()
    try:
        res = (
            supabase_client.table("safety_evidence")
            .select("id, storage_path")
            .lt("created_at", cutoff)
            .execute()
        )
    except APIError:
        logger.exception("Failed to fetch expired safety evidence")
        return

    rows = cast(list[dict[str, Any]], res.data or [])
    if not rows:
        return

    paths = [str(r["storage_path"]) for r in rows if r.get("storage_path")]
    if paths:
        try:
            supabase_client.storage.from_("safety_evidence").remove(paths)
        except Exception:
            logger.exception(
                "Failed to remove expired safety evidence storage objects",
            )

    ids = [str(r["id"]) for r in rows if r.get("id")]
    try:
        supabase_client.table("safety_evidence").delete().in_("id", ids).execute()
    except APIError:
        logger.exception("Failed to delete expired safety evidence rows")


def purge_safety_data_for_purged_accounts() -> None:
    """Purge safety alerts and evidence for accounts anonymized beyond legal hold window."""
    cutoff = (
        utcnow() - timedelta(days=settings.safety_data_legal_hold_days)
    ).isoformat()
    try:
        res = (
            supabase_client.table("users")
            .select("id")
            .not_.is_("purged_at", "null")
            .lte("purged_at", cutoff)
            .execute()
        )
    except APIError:
        logger.exception("Failed to fetch accounts due for safety data purge")
        return

    user_ids = [
        str(r["id"]) for r in cast(list[dict[str, Any]], res.data or []) if r.get("id")
    ]
    if not user_ids:
        return

    try:
        evidence_res = (
            supabase_client.table("safety_evidence")
            .select("id, storage_path")
            .in_("user_id", user_ids)
            .execute()
        )
        evidence_rows = cast(list[dict[str, Any]], evidence_res.data or [])
        paths = [
            str(r["storage_path"]) for r in evidence_rows if r.get("storage_path")
        ]
        if paths:
            with contextlib.suppress(Exception):
                supabase_client.storage.from_("safety_evidence").remove(paths)
        supabase_client.table("safety_evidence").delete().in_(
            "user_id", user_ids,
        ).execute()
    except APIError:
        logger.exception(
            "Failed to purge safety_evidence for purged accounts",
        )

    try:
        supabase_client.table("safety_alerts").delete().in_(
            "user_id", user_ids,
        ).execute()
    except APIError:
        logger.exception("Failed to purge safety_alerts for purged accounts")
