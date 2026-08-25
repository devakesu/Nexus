"""Database audio and location evidence registration and portal lookup routines.

Memory Lifetime & Key Material (F-10):
Evidence AES media encryption keys transit backend memory during registration and contact portal lookup.
Callers managing transient media key bytes should utilize mutable `bytearray` structures and invoke
`zero_sensitive_buffer()` when processing raw cryptographic key material.
"""

import contextlib
import logging
from typing import Any, cast

from postgrest.exceptions import APIError
from storage3.utils import StorageException

from app.core.security.crypto import decrypt_pii, encrypt_to_hex
from app.db.client import DatabaseAccessError, supabase_client

logger = logging.getLogger(__name__)

_EVIDENCE_INSERT_COLS = "id"
_PORTAL_EVIDENCE_COLS = (
    "id, alert_id, storage_path, media_key_base64, content_type, "
    "duration_seconds, created_at"
)


def register_safety_evidence(
    user_id: str,
    alert_id: str,
    storage_path: str,
    media_key_base64: str,
    content_type: str,
    duration_seconds: float | None,
) -> dict[str, Any]:
    """Register safety evidence entry into database with encrypted media key."""
    payload: dict[str, Any] = {
        "user_id": user_id,
        "alert_id": alert_id,
        "storage_path": storage_path,
        "media_key_base64": encrypt_to_hex(media_key_base64, category="media_escrow"),
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


def fetch_evidence_for_alert_ids(alert_ids: list[str]) -> list[dict[str, Any]]:
    """Fetch decrypted safety evidence records for given alert IDs."""
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
        rows = cast(list[dict[str, Any]], res.data or [])
        for row in rows:
            key = row.get("media_key_base64")
            if key:
                with contextlib.suppress(Exception):
                    row["media_key_base64"] = decrypt_pii(key, category="media_escrow")
        return rows
    except APIError as e:
        logger.exception(
            "Failed to fetch evidence for safety alerts",
            extra={"alert_id_count": len(alert_ids)},
        )
        raise DatabaseAccessError("Failed to fetch evidence for safety alerts") from e


def create_evidence_download_url(storage_path: str, expires_in: int) -> str | None:
    """Create short-lived signed download URL for private safety evidence."""
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
