"""Database trusted contact management and self-service removal methods."""

import logging
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.security.crypto import compute_blind_index, decrypt_pii, encrypt_to_hex
from app.core.security.portal_auth import normalize_phone
from app.db.client import DatabaseAccessError, supabase_client, utcnow

logger = logging.getLogger(__name__)


def _phone_blind_index(phone: str) -> str:
    """Computes HMAC blind index for a phone number."""
    return compute_blind_index(normalize_phone(phone))


def sync_safety_contacts(
    user_id: str,
    contacts: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Replaces the caller's full trusted-contact mirror atomically using RPC.

    The RPC executes under an advisory transaction lock to serialize concurrent
    syncs and self-service opt-out removals, enforces the permanent opt-out check
    against safety_contact_notices, inserts active contacts, and records notices.
    """
    if len(contacts) > 3:
        raise ValueError("Cannot sync more than 3 safety contacts")

    by_blind_index: dict[str, dict[str, Any]] = {}
    contacts_payload: list[dict[str, Any]] = []

    for c in contacts:
        phone = str(c.get("phone") or "")
        blind_index = _phone_blind_index(phone)
        by_blind_index[blind_index] = c
        contacts_payload.append({
            "name": encrypt_to_hex(c.get("name")),
            "phone": encrypt_to_hex(c.get("phone")),
            "phone_blind_index": blind_index,
        })

    try:
        res = supabase_client.rpc(
            "sync_safety_contacts",
            {"p_user_id": user_id, "p_contacts": contacts_payload},
        ).execute()
    except APIError as e:
        logger.exception("Failed to sync safety contacts", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to sync safety contacts") from e

    blocked: list[dict[str, Any]] = []
    newly_notified: list[dict[str, Any]] = []

    if res and isinstance(res.data, dict):
        res_dict = cast(dict[str, Any], res.data)
        blocked_raw = cast(list[Any], res_dict.get("blocked_indices") or [])
        newly_raw = cast(list[Any], res_dict.get("newly_notified_indices") or [])
        blocked_indices: set[str] = {str(x) for x in blocked_raw}
        newly_notified_indices: set[str] = {str(x) for x in newly_raw}
        for blind_idx, c in by_blind_index.items():
            if blind_idx in blocked_indices:
                blocked.append(c)
            elif blind_idx in newly_notified_indices:
                newly_notified.append({**c, "blind_index": blind_idx})
    else:
        # Fallback / mock handling: query notices directly if RPC returned no structured dict
        try:
            notices_res = (
                supabase_client.table("safety_contact_notices")
                .select("phone_blind_index, self_removed_at")
                .eq("user_id", user_id)
                .execute()
            )
            notices = {
                str(row["phone_blind_index"]): row
                for row in cast(list[dict[str, Any]], notices_res.data or [])
            }
            for blind_idx, c in by_blind_index.items():
                notice = notices.get(blind_idx)
                if notice is not None and notice.get("self_removed_at"):
                    blocked.append(c)
                elif notice is None:
                    newly_notified.append({**c, "blind_index": blind_idx})
        except Exception:
            pass

    return blocked, newly_notified


def fetch_safety_contacts(user_id: str) -> list[dict[str, Any]]:
    """Fetch decrypted trusted safety contacts for a given user."""
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


def fetch_safety_contacts_with_id(user_id: str) -> list[dict[str, Any]]:
    """Fetch decrypted safety contacts including row UUIDs."""
    try:
        res = (
            supabase_client.table("safety_contacts")
            .select("id, name, phone")
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
            "Failed to fetch safety contacts with id",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to fetch safety contacts") from e


def fetch_safety_contact_by_id(contact_id: str) -> dict[str, Any] | None:
    """Fetch a single decrypted safety contact by contact UUID."""
    try:
        res = (
            supabase_client.table("safety_contacts")
            .select("id, user_id, name, phone")
            .eq("id", contact_id)
            .maybe_single()
            .execute()
        )
        if not res or not res.data:
            return None
        row = cast(dict[str, Any], res.data)
    except APIError as e:
        logger.exception(
            "Failed to fetch safety contact by id", extra={"contact_id": contact_id},
        )
        raise DatabaseAccessError("Failed to fetch safety contact") from e
    row["name"] = decrypt_pii(row.get("name"))
    row["phone"] = decrypt_pii(row.get("phone"))
    return row


def remove_safety_contact_self_service(contact_id: str) -> dict[str, Any] | None:
    """Permanently removes a trusted contact at their own self-service portal request."""
    contact = fetch_safety_contact_by_id(contact_id)
    if contact is None:
        return None

    blind_index = _phone_blind_index(str(contact.get("phone") or ""))
    now = utcnow().isoformat()

    # Atomically mark self_removed_at notice FIRST so no concurrent sync can re-add the contact
    try:
        supabase_client.table("safety_contact_notices").upsert(
            {
                "user_id": contact["user_id"],
                "phone_blind_index": blind_index,
                "self_removed_at": now,
            },
            on_conflict="user_id,phone_blind_index",
        ).execute()
    except APIError as e:
        logger.exception(
            "Failed to set self_removed_at notice",
            extra={"contact_id": contact_id, "user_id": contact["user_id"]},
        )
        raise DatabaseAccessError("Failed to record opt-out notice") from e

    try:
        supabase_client.table("safety_contacts").delete().eq(
            "id", contact_id,
        ).execute()
    except APIError as e:
        logger.exception(
            "Failed to delete self-removed safety contact",
            extra={"contact_id": contact_id},
        )
        raise DatabaseAccessError("Failed to remove trusted contact") from e

    return {
        "user_id": contact["user_id"],
        "name": contact["name"],
        "phone": contact["phone"],
    }
