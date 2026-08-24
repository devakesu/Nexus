"""Database End-to-End Encryption (E2EE) cryptographic key bundle persistence layer.

Provides storage and retrieval routines for user Signal identity keys, signed prekeys,
and one-time prekey bundles required for Signal Protocol key exchange.
"""

import logging
from typing import Any, cast

import sentry_sdk
from postgrest.exceptions import APIError
from postgrest.types import CountMethod

from app.db.client import (
    DatabaseAccessError,
    ProfileNotFoundError,
    normalize_uuid,
    supabase_client,
    utcnow,
)

logger = logging.getLogger(__name__)


def _to_bytea_hex(value: bytes) -> str:
    """Encodes raw bytes into a PostgREST BYTEA hex literal string ('\\x...').

    Args:
        value: Raw bytes input.

    Returns:
        str: Formatted hex string literal.
    """
    return f"\\x{value.hex()}"


def _from_bytea(raw: Any) -> bytes:
    """Decodes a BYTEA column value returned by PostgREST into raw bytes.

    Args:
        raw: Input bytes, memoryview, or hex string.

    Returns:
        bytes: Decoded raw bytes.
    """

    if isinstance(raw, memoryview):
        return raw.tobytes()
    if isinstance(raw, bytes):
        return raw
    if isinstance(raw, str) and raw.startswith("\\x"):
        return bytes.fromhex(raw[2:])
    raise DatabaseAccessError(f"Unexpected BYTEA representation: {raw!r}")


def upsert_identity_key(
    user_id: str, identity_public_key: bytes, registration_id: int,
) -> None:
    """Store or update a user's E2EE Signal identity public key and registration ID.

    Args:
        user_id: Unique UUID string identifier of the user.
        identity_public_key: 32-byte public key payload for the identity key.
        registration_id: 32-bit unsigned integer registration ID generated during client init.
    """
    try:
        supabase_client.table("chat_identity_keys").upsert(
            {
                "user_id": user_id,
                "identity_public_key": _to_bytea_hex(identity_public_key),
                "registration_id": registration_id,
            },
            on_conflict="user_id",
        ).execute()
        # Invalidate old one-time prekeys associated with any previous device identity
        supabase_client.table("chat_one_time_prekeys").delete().eq("user_id", user_id).execute()
        # Deactivate previous device push tokens since Signal Protocol v1 is single-device per user
        try:
            supabase_client.table("user_devices").update({"is_active": False}).eq("user_id", user_id).execute()
        except Exception:
            logger.warning("Failed to deactivate prior device tokens on identity key upload", extra={"user_id": user_id}, exc_info=True)
    except APIError as e:
        if e.code == "23503":
            raise ProfileNotFoundError(f"Profile not found for user {user_id}") from e
        logger.exception("Failed to upsert identity key", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to upsert identity key") from e


def fetch_identity_key(user_id: str) -> dict[str, Any] | None:
    """Fetch a user's registered Signal identity public key and registration ID.

    Args:
        user_id: Unique UUID string identifier of the user.

    Returns:
        dict[str, Any] | None: Stored identity dictionary with raw bytes, or None if uninitialized.
    """
    try:
        res = (
            supabase_client.table("chat_identity_keys")
            .select("identity_public_key, registration_id")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        row = cast(dict[str, Any] | None, getattr(res, "data", None))
        if row is None:
            return None
        return {
            "identity_public_key": _from_bytea(row["identity_public_key"]),
            "registration_id": row["registration_id"],
        }
    except APIError as e:
        logger.exception("Failed to fetch identity key", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to fetch identity key") from e



def upsert_signed_prekey(
    user_id: str, key_id: int, public_key: bytes, signature: bytes,
) -> None:
    """Rotate: mark any current signed prekey as rotated, then insert the new one."""
    try:
        supabase_client.rpc(
            "upsert_signed_prekey",
            {
                "target_user_id": user_id,
                "new_key_id": key_id,
                "new_public_key": _to_bytea_hex(public_key),
                "new_signature": _to_bytea_hex(signature),
            },
        ).execute()
    except APIError as e:
        if e.code == "23503":
            raise ProfileNotFoundError(f"Profile not found for user {user_id}") from e
        logger.exception(
            "Failed to upsert signed prekey", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to upsert signed prekey") from e


def bulk_insert_one_time_prekeys(
    user_id: str, prekeys: list[dict[str, Any]],
) -> None:
    """Executes bulk insert one time prekeys operation.

        Args:
            user_id: Unique UUID string of the authenticated user.
            prekeys: Input prekeys parameter."""
    if not prekeys:
        return
    rows = [
        {
            "user_id": user_id,
            "key_id": p["key_id"],
            "public_key": _to_bytea_hex(p["public_key"]),
        }
        for p in prekeys
    ]
    try:
        supabase_client.table("chat_one_time_prekeys").insert(rows).execute()
    except APIError as e:
        if e.code == "23503":
            raise ProfileNotFoundError(f"Profile not found for user {user_id}") from e
        logger.exception(
            "Failed to bulk insert one-time prekeys", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to bulk insert one-time prekeys") from e


def count_unused_one_time_prekeys(user_id: str) -> int:
    """Executes count unused one time prekeys operation.

        Args:
            user_id: Unique UUID string of the authenticated user.

        Returns:
            int: Response payload or result."""
    try:
        res = (
            supabase_client.table("chat_one_time_prekeys")
            .select("id", count=CountMethod.exact)
            .eq("user_id", user_id)
            .is_("used_at", "null")
            .execute()
        )
        return int(res.count or 0)
    except APIError as e:
        logger.exception(
            "Failed to count one-time prekeys", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to count one-time prekeys") from e


def has_active_match(user_a: str, user_b: str) -> bool:
    """Whether two users currently share any active match, in any tab."""
    user_a = normalize_uuid(user_a)
    user_b = normalize_uuid(user_b)
    try:
        # nosec: user_a and user_b validated via normalize_uuid
        res = (
            supabase_client.table("matches")
            .select("id")
            .or_(
                f"and(liker_id.eq.{user_a},liked_back_id.eq.{user_b}),"
                f"and(liker_id.eq.{user_b},liked_back_id.eq.{user_a})",
            )
            .is_("unmatched_at", "null")
            .limit(1)
            .execute()
        )
        return bool(res.data)
    except APIError as e:
        logger.exception(
            "Failed to check active match", extra={"user_a": user_a, "user_b": user_b},
        )
        raise DatabaseAccessError("Failed to check active match") from e


def fetch_active_matches_for_targets(user_id: str, target_ids: list[str]) -> set[str]:
    """Return the subset of target_ids that share an active, un-ended match with user_id."""
    if not target_ids:
        return set()
    user_id = normalize_uuid(user_id)
    target_uuids = [normalize_uuid(tid) for tid in target_ids]
    try:
        res = (
            supabase_client.table("matches")
            .select("liker_id, liked_back_id")
            .or_(
                f"and(liker_id.eq.{user_id},liked_back_id.in.({','.join(target_uuids)})),"
                f"and(liker_id.in.({','.join(target_uuids)}),liked_back_id.eq.{user_id})",
            )
            .is_("unmatched_at", "null")
            .execute()
        )
        rows = cast(list[dict[str, Any]], res.data or [])
        matched_target_ids: set[str] = set()
        for r in rows:
            liker = str(r.get("liker_id") or "")
            liked_back = str(r.get("liked_back_id") or "")
            if liker == user_id and liked_back:
                matched_target_ids.add(liked_back)
            elif liked_back == user_id and liker:
                matched_target_ids.add(liker)
        return matched_target_ids
    except APIError as e:
        logger.exception(
            "Failed to check active matches for targets",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to check active matches for targets") from e


def fetch_key_bundle(user_id: str) -> dict[str, Any] | None:
    """
    Fetch a user's X3DH bundle: identity key, current signed prekey, and one
    atomically-claimed one-time prekey (if the pool isn't exhausted).
    Returns None if the user has no identity key registered yet.
    """
    try:
        identity_res = (
            supabase_client.table("chat_identity_keys")
            .select("identity_public_key, registration_id")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        identity_row = cast(dict[str, Any] | None, getattr(identity_res, "data", None))
        if identity_row is None:
            return None

        signed_prekey_res = (
            supabase_client.table("chat_signed_prekeys")
            .select("key_id, public_key, signature")
            .eq("user_id", user_id)
            .is_("rotated_at", "null")
            .order("created_at", desc=True)
            .limit(1)
            .maybe_single()
            .execute()
        )
        signed_prekey_row = cast(
            dict[str, Any] | None, getattr(signed_prekey_res, "data", None),
        )
        if signed_prekey_row is None:
            return None

        one_time_prekey_id: int | None = None
        one_time_prekey_public: bytes | None = None
        claim_res = supabase_client.rpc(
            "claim_one_time_prekey", {"target_user_id": user_id},
        ).execute()
        claim_rows = cast(list[Any], claim_res.data or [])
        if claim_rows and isinstance(claim_rows[0], dict):
            claimed = cast(dict[str, Any], claim_rows[0])
            one_time_prekey_id = claimed["key_id"]
            one_time_prekey_public = _from_bytea(claimed["public_key"])
        else:
            logger.warning(
                "One-time prekey pool exhausted; degrading to prekey-less X3DH",
                extra={"user_id": user_id},
            )
            sentry_sdk.capture_message(
                "One-time prekey pool exhausted for user",
                level="warning",
                tags={"user_id": user_id, "location": "fetch_key_bundle"},
            )

        return {
            "identity_public_key": _from_bytea(identity_row["identity_public_key"]),
            "registration_id": identity_row["registration_id"],
            "signed_prekey_id": signed_prekey_row["key_id"],
            "signed_prekey_public": _from_bytea(signed_prekey_row["public_key"]),
            "signed_prekey_signature": _from_bytea(signed_prekey_row["signature"]),
            "one_time_prekey_id": one_time_prekey_id,
            "one_time_prekey_public": one_time_prekey_public,
            "one_time_prekey_used": one_time_prekey_public is not None,
        }
    except APIError as e:
        logger.exception("Failed to fetch key bundle", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to fetch key bundle") from e


def fetch_x3dh_key_bundle_unified(
    requester_id: str,
    target_user_id: str,
) -> tuple[dict[str, Any] | None, str | None]:
    """
    Fetches X3DH key bundle in a single atomic database RPC call.
    Returns (bundle_dict, error_code).
    error_code can be 'NOT_MATCHED', 'IDENTITY_NOT_FOUND', 'SIGNED_PREKEY_NOT_FOUND', or None.
    If the unified RPC is not yet available, gracefully falls back to sequential lookups.
    """
    try:
        req_uuid = normalize_uuid(requester_id)
        target_uuid = normalize_uuid(target_user_id)
    except ValueError:
        req_uuid = requester_id
        target_uuid = target_user_id
    try:
        rpc_res = supabase_client.rpc(
            "get_x3dh_key_bundle",
            {"p_requester_id": req_uuid, "p_target_id": target_uuid},
        ).execute()
        if isinstance(rpc_res.data, dict):
            data = cast(dict[str, Any], rpc_res.data)
            if "error" in data:
                return None, str(data["error"])
            return {
                "identity_public_key": _from_bytea(str(data["identity_public_key"])),
                "registration_id": int(str(data["registration_id"])),
                "signed_prekey_id": int(str(data["signed_prekey_id"])),
                "signed_prekey_public": _from_bytea(str(data["signed_prekey_public"])),
                "signed_prekey_signature": _from_bytea(str(data["signed_prekey_signature"])),
                "one_time_prekey_id": (
                    int(str(data["one_time_prekey_id"]))
                    if data.get("one_time_prekey_id") is not None
                    else None
                ),
                "one_time_prekey_public": (
                    _from_bytea(str(data["one_time_prekey_public"]))
                    if data.get("one_time_prekey_public") is not None
                    else None
                ),
                "one_time_prekey_used": bool(data.get("one_time_prekey_used")),
            }, None
    except APIError as e:
        logger.warning(
            "get_x3dh_key_bundle RPC not available or failed, falling back to sequential fetch",
            extra={"error": str(e), "user_id": requester_id, "target_user_id": target_user_id},
        )
    except Exception as e:
        logger.warning(
            "get_x3dh_key_bundle RPC encountered exception, falling back",
            extra={"error": str(e), "user_id": requester_id, "target_user_id": target_user_id},
        )

    # Fallback path
    if not has_active_match(req_uuid, target_uuid):
        return None, "NOT_MATCHED"
    bundle = fetch_key_bundle(target_uuid)
    if bundle is None:
        return None, "IDENTITY_NOT_FOUND"
    return bundle, None


def mark_session_established(user_id: str, conversation_id: str) -> None:
    """Record that user_id completed X3DH toward the conversation's peer."""
    now = utcnow()
    valid_user_id = normalize_uuid(user_id)
    try:
        # PostgREST chains separate filter methods with an implicit logical AND.
        # This query evaluates to: id = conversation_id AND (user_a_id = valid_user_id OR user_b_id = valid_user_id).
        # This ensures we strictly target only the specific conversation_id, while validating caller membership.
        # nosec: valid_user_id validated via normalize_uuid
        (
            supabase_client.table("chat_conversations")
            .update({"session_established_at": now.isoformat()})
            .eq("id", conversation_id)
            .or_(f"user_a_id.eq.{valid_user_id},user_b_id.eq.{valid_user_id}")
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to mark session established",
            extra={"user_id": user_id, "conversation_id": conversation_id},
        )
        raise DatabaseAccessError("Failed to mark session established") from e
