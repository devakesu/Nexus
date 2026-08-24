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
    """Replaces the caller's full trusted-contact mirror atomically using RPC."""
    try:
        notices_res = (
            supabase_client.table("safety_contact_notices")
            .select("phone_blind_index, self_removed_at")
            .eq("user_id", user_id)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch safety contact notices", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to sync safety contacts") from e

    notices = {
        str(row["phone_blind_index"]): row
        for row in cast(list[dict[str, Any]], notices_res.data or [])
    }

    allowed: list[dict[str, Any]] = []
    blocked: list[dict[str, Any]] = []
    newly_notified: list[dict[str, Any]] = []
    for c in contacts:
        phone = str(c.get("phone") or "")
        blind_index = _phone_blind_index(phone)
        notice = notices.get(blind_index)
        if notice is not None and notice.get("self_removed_at"):
            blocked.append(c)
            continue
        allowed.append(c)
        if notice is None:
            newly_notified.append({**c, "blind_index": blind_index})

    encrypted: list[dict[str, Any]] = [
        {
            "name": encrypt_to_hex(c.get("name")),
            "phone": encrypt_to_hex(c.get("phone")),
        }
        for c in allowed
    ]
    try:
        supabase_client.rpc(
            "sync_safety_contacts",
            {"p_user_id": user_id, "p_contacts": encrypted},
        ).execute()
    except APIError as e:
        logger.exception("Failed to sync safety contacts", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to sync safety contacts") from e

    if newly_notified:
        try:
            supabase_client.table("safety_contact_notices").upsert(
                [
                    {
                        "user_id": user_id,
                        "phone_blind_index": n["blind_index"],
                    }
                    for n in newly_notified
                ],
                on_conflict="user_id,phone_blind_index",
            ).execute()
        except APIError as e:
            logger.exception(
                "Failed to record safety contact notices", extra={"user_id": user_id},
            )
            raise DatabaseAccessError("Failed to record safety contact notices") from e

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

    blind_index = _phone_blind_index(str(contact.get("phone") or ""))
    now = utcnow().isoformat()
    try:
        supabase_client.table("safety_contact_notices").upsert(
            {
                "user_id": contact["user_id"],
                "phone_blind_index": blind_index,
                "self_removed_at": now,
            },
            on_conflict="user_id,phone_blind_index",
        ).execute()
    except APIError:
        logger.exception(
            "Failed to set self_removed_at notice",
            extra={"contact_id": contact_id, "user_id": contact["user_id"]},
        )

    return {
        "user_id": contact["user_id"],
        "name": contact["name"],
        "phone": contact["phone"],
    }
