"""Database chat conversation, messaging, and encrypted payload persistence layer.

Provides database interaction routines for fetching active user conversations, sending messages,
managing read receipts, checking block states, and persisting encrypted message contents.
"""

import contextlib
import json
import logging
import uuid
from datetime import datetime, timedelta
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import DiscoveryTab
from app.core.infra.cache import sync_redis_client
from app.core.security.crypto import decrypt_pii, encrypt_to_hex
from app.db.client import (
    DatabaseAccessError,
    normalize_uuid,
    parse_utc_datetime,
    supabase_client,
    utcnow,
)

logger = logging.getLogger(__name__)



def fetch_conversations_for_user(
    user_id: str, tab: DiscoveryTab = "Dating",
) -> list[dict[str, Any]]:
    """Return active, already-started conversations for user_id in a tab."""
    user_id = normalize_uuid(user_id)
    try:
        # nosec: user_id validated via normalize_uuid
        res = (
            supabase_client.table("chat_conversations")
            .select("id, user_a_id, user_b_id, last_message_at")
            .or_(f"user_a_id.eq.{user_id},user_b_id.eq.{user_id}")
            .eq("tab", tab)
            .is_("closed_at", "null")
            .not_.is_("last_message_at", "null")
            .order("last_message_at", desc=True)
            .limit(1000)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        result: list[dict[str, Any]] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            row_dict = cast(dict[str, Any], row)
            user_a_id = str(row_dict.get("user_a_id") or "")
            user_b_id = str(row_dict.get("user_b_id") or "")
            counterpart_id = user_b_id if user_a_id == user_id else user_a_id
            result.append(
                {
                    "conversation_id": str(row_dict.get("id") or ""),
                    "matched_user_id": counterpart_id,
                    "last_message_at": row_dict.get("last_message_at"),
                },
            )
        return result
    except APIError as e:
        logger.exception(
            "Failed to fetch conversations", extra={"user_id": user_id, "tab": tab},
        )
        raise DatabaseAccessError("Failed to fetch conversations") from e


def fetch_started_match_ids(user_id: str, tab: DiscoveryTab = "Dating") -> set[str]:
    """Return match_ids whose conversation already has at least one message."""
    user_id = normalize_uuid(user_id)
    try:
        # nosec: user_id validated via normalize_uuid
        res = (
            supabase_client.table("chat_conversations")
            .select("match_id")
            .or_(f"user_a_id.eq.{user_id},user_b_id.eq.{user_id}")
            .eq("tab", tab)
            .is_("closed_at", "null")
            .not_.is_("last_message_at", "null")
            .limit(1000)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        match_ids: set[str] = set()
        for row in rows:
            if not isinstance(row, dict):
                continue
            row_dict = cast(dict[str, Any], row)
            if row_dict.get("match_id"):
                match_ids.add(str(row_dict["match_id"]))
        return match_ids
    except APIError as e:
        logger.exception(
            "Failed to fetch started match ids", extra={"user_id": user_id, "tab": tab},
        )
        raise DatabaseAccessError("Failed to fetch started match ids") from e


def fetch_conversation_for_match(match_id: str) -> dict[str, Any] | None:
    """Fetch the chat conversation record associated with a specific match ID.

    Args:
        match_id: Unique string UUID identifier of the match.

    Returns:
        dict[str, Any] | None: Dictionary representing the conversation row, or None if not found.
    """
    try:
        res = (
            supabase_client.table("chat_conversations")
            .select("id, match_id, user_a_id, user_b_id, tab, closed_at")
            .eq("match_id", match_id)
            .maybe_single()
            .execute()
        )
        data = getattr(res, "data", None)
        return cast(dict[str, Any] | None, data)
    except APIError as e:
        logger.exception(
            "Failed to fetch conversation for match", extra={"match_id": match_id},
        )
        raise DatabaseAccessError("Failed to fetch conversation for match") from e


def get_or_create_conversation(user_id: str, match_id: str) -> dict[str, Any]:
    """
    Idempotently create (or fetch) the conversation for a match.
    Verifies user_id is a participant of an active match before creating.
    """
    user_id = str(uuid.UUID(user_id)).lower()
    match_id = str(uuid.UUID(match_id)).lower()

    existing = fetch_conversation_for_match(match_id)
    if existing is not None:
        if existing["user_a_id"] != user_id and existing["user_b_id"] != user_id:
            raise DatabaseAccessError("User is not a participant of this match")
        return existing

    try:
        match_res = (
            supabase_client.table("matches")
            .select("id, liker_id, liked_back_id, tab")
            .eq("id", match_id)
            .is_("unmatched_at", "null")
            .maybe_single()
            .execute()
        )
        match_row = cast(dict[str, Any] | None, getattr(match_res, "data", None))
        if match_row is None:
            raise DatabaseAccessError("No active match found for match_id")

        liker_id = str(match_row.get("liker_id") or "")
        liked_back_id = str(match_row.get("liked_back_id") or "")
        if user_id not in (liker_id, liked_back_id):
            raise DatabaseAccessError("User is not a participant of this match")

        insert_res = (
            supabase_client.table("chat_conversations")
            .upsert(
                {
                    "match_id": match_id,
                    "user_a_id": liker_id,
                    "user_b_id": liked_back_id,
                    "tab": match_row.get("tab"),
                },
                on_conflict="match_id",
            )
            .execute()
        )
        rows = cast(list[Any], insert_res.data or [])
        if rows and isinstance(rows[0], dict):
            return cast(dict[str, Any], rows[0])

        # Upsert raced with another request; fetch what landed.
        created = fetch_conversation_for_match(match_id)
        if created is None:
            raise DatabaseAccessError("Failed to create conversation")
        return created
    except APIError as e:
        logger.exception(
            "Failed to create conversation",
            extra={"user_id": user_id, "match_id": match_id},
        )
        raise DatabaseAccessError("Failed to create conversation") from e


_CHAT_MEDIA_BUCKET = "chat_media"


def delete_conversation_chat_media(conversation_id: str) -> None:
    """Purges all encrypted media blobs associated with a conversation from chat_media bucket."""
    if not conversation_id:
        return
    batch_delete_conversations_chat_media([conversation_id])


def batch_delete_conversations_chat_media(conversation_ids: list[str]) -> None:
    """Purges encrypted media blobs for multiple conversations in batched storage remove calls."""
    if not conversation_ids:
        return
    all_paths: list[str] = []
    for conv_id in conversation_ids:
        if not conv_id:
            continue
        try:
            objects = supabase_client.storage.from_(_CHAT_MEDIA_BUCKET).list(conv_id)
            for obj in (objects or []):
                name = obj.get("name")
                if not name:
                    continue
                # If name is a subdirectory (e.g. uploader_id), list objects inside it
                if obj.get("id") is None and obj.get("metadata") is None and "." not in name:
                    try:
                        sub_objects = supabase_client.storage.from_(_CHAT_MEDIA_BUCKET).list(
                            f"{conv_id}/{name}"
                        )
                        for sub in (sub_objects or []):
                            sub_name = sub.get("name")
                            if sub_name:
                                all_paths.append(f"{conv_id}/{name}/{sub_name}")
                    except Exception:
                        all_paths.append(f"{conv_id}/{name}")
                else:
                    all_paths.append(f"{conv_id}/{name}")
        except Exception:
            logger.exception(
                "Failed to list chat_media objects for conversation %s",
                conv_id,
            )

    if all_paths:
        chunk_size = 100
        for i in range(0, len(all_paths), chunk_size):
            chunk = all_paths[i : i + chunk_size]
            try:
                supabase_client.storage.from_(_CHAT_MEDIA_BUCKET).remove(chunk)
            except Exception:
                logger.exception(
                    "Failed to batch remove chat_media objects chunk of size %s",
                    len(chunk),
                )


def close_conversation_for_match_action(
    user_id: str,
    target_id: str,
    tab: DiscoveryTab | None = None,
    reason: str = "block",
) -> None:
    """Close the conversation between two users (mirrors set_match_unmatched).
    If tab is None, closes active conversations across all discovery tabs.
    """
    user_id = normalize_uuid(user_id)
    target_id = normalize_uuid(target_id)
    now = utcnow()
    try:
        # nosec: user_id and target_id validated via normalize_uuid
        q = (
            supabase_client.table("chat_conversations")
            .update({"closed_at": now.isoformat(), "closed_reason": reason})
            .or_(
                f"and(user_a_id.eq.{user_id},user_b_id.eq.{target_id}),"
                f"and(user_a_id.eq.{target_id},user_b_id.eq.{user_id})",
            )
            .is_("closed_at", "null")
            .select("id")
        )
        if tab is not None:
            q = q.eq("tab", tab)
        res = q.execute()
        closed_rows = cast(list[dict[str, Any]], res.data or [])
        for row in closed_rows:
            conv_id = str(row.get("id") or "").strip()
            if conv_id:
                delete_conversation_chat_media(conv_id)
    except APIError as e:
        logger.exception(
            "Failed to close conversation",
            extra={"user_id": user_id, "target_id": target_id},
        )
        raise DatabaseAccessError("Failed to close conversation") from e


def _fetch_conversations_for_reactivation(user_id: str) -> list[dict[str, Any]]:
    valid_user_id = normalize_uuid(user_id)
    try:
        # nosec: valid_user_id validated via normalize_uuid
        res = (
            supabase_client.table("chat_conversations")
            .select("id, user_a_id, user_b_id")
            .or_(f"user_a_id.eq.{valid_user_id},user_b_id.eq.{valid_user_id}")
            .eq("closed_reason", "account_deletion")
            .execute()
        )
        return cast(list[dict[str, Any]], res.data or [])
    except APIError as e:
        logger.exception(
            "Failed to fetch conversations for reactivation",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to fetch conversations for reactivation") from e
    except Exception as e:
        logger.exception(
            "Unexpected error fetching conversations for reactivation",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Unexpected error fetching conversations") from e


def _partition_reactivation_conversations(
    conversations: list[dict[str, Any]],
    user_id: str,
) -> tuple[list[str], list[str]]:
    from app.db.discovery.exclusions import fetch_active_block_ids

    blocked_ids = fetch_active_block_ids(user_id)
    reopen_ids: list[str] = []
    blocked_conv_ids: list[str] = []

    for conv in conversations:
        conv_id = str(conv.get("id"))
        user_a = str(conv.get("user_a_id", "")).lower()
        user_b = str(conv.get("user_b_id", "")).lower()
        counterpart_id = user_b if user_a == user_id else user_a

        if counterpart_id in blocked_ids:
            blocked_conv_ids.append(conv_id)
        else:
            reopen_ids.append(conv_id)

    return reopen_ids, blocked_conv_ids


def _apply_reactivation_updates(
    reopen_ids: list[str],
    blocked_conv_ids: list[str],
    user_id: str,
) -> None:
    if reopen_ids:
        try:
            (
                supabase_client.table("chat_conversations")
                .update({"closed_at": None, "closed_reason": None})
                .in_("id", reopen_ids)
                .execute()
            )
        except APIError as e:
            logger.exception(
                "Failed to reopen conversations for reactivation",
                extra={"user_id": user_id, "reopen_count": len(reopen_ids)},
            )
            raise DatabaseAccessError("Failed to reopen conversations") from e
        except Exception as e:
            logger.exception(
                "Unexpected error reopening conversations for reactivation",
                extra={"user_id": user_id},
            )
            raise DatabaseAccessError("Unexpected error reopening conversations") from e

    if blocked_conv_ids:
        try:
            (
                supabase_client.table("chat_conversations")
                .update({"closed_reason": "block"})
                .in_("id", blocked_conv_ids)
                .execute()
            )
        except Exception:
            logger.exception(
                "Failed to update closed_reason for blocked conversations on reactivation",
                extra={"user_id": user_id, "blocked_count": len(blocked_conv_ids)},
            )


def reopen_conversations_for_reactivation(user_id: str) -> None:
    """Reopens conversations closed by request_deletion() (reason=
    'account_deletion') when the user cancels within the grace window.

    The closed_reason='account_deletion' filter is exact, so this can never
    reopen a conversation that was separately closed by a genuine
    unmatch/block/report before the deletion request. Additionally, verifies
    neither participant has an active block in place before reopening.
    """
    normalized_uid = str(uuid.UUID(user_id)).lower()
    conversations = _fetch_conversations_for_reactivation(normalized_uid)
    if not conversations:
        return

    reopen_ids, blocked_conv_ids = _partition_reactivation_conversations(
        conversations,
        normalized_uid,
    )
    _apply_reactivation_updates(reopen_ids, blocked_conv_ids, normalized_uid)


def fetch_conversation_participants(conversation_id: str) -> dict[str, Any] | None:
    """Executes fetch conversation participants operation.

        Args:
            conversation_id: Input conversation id parameter.

        Returns:
            dict[str, Any] | None: Response payload or result."""
    try:
        res = (
            supabase_client.table("chat_conversations")
            .select("user_a_id, user_b_id, tab, closed_at")
            .eq("id", conversation_id)
            .maybe_single()
            .execute()
        )
        return cast(dict[str, Any] | None, getattr(res, "data", None))
    except APIError as e:
        logger.exception(
            "Failed to fetch conversation participants",
            extra={"conversation_id": conversation_id},
        )
        raise DatabaseAccessError("Failed to fetch conversation participants") from e


def insert_message(
    conversation_id: str,
    sender_id: str,
    message_type: str,
    ciphertext: str,
    ciphertext_metadata: dict[str, Any],
) -> dict[str, Any]:
    """Executes insert message operation.

        Args:
            conversation_id: Input conversation id parameter.
            sender_id: Input sender id parameter.
            message_type: Input message type parameter.
            ciphertext: Input ciphertext parameter.
            ciphertext_metadata: Input ciphertext metadata parameter.

        Returns:
            dict[str, Any]: Response payload or result."""
    try:
        res = (
            supabase_client.table("chat_messages")
            .insert(
                {
                    "conversation_id": conversation_id,
                    "sender_id": sender_id,
                    "message_type": message_type,
                    "ciphertext": ciphertext,
                    "ciphertext_metadata": ciphertext_metadata,
                },
            )
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            raise DatabaseAccessError("Message insert returned no row")
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to insert message",
            extra={"conversation_id": conversation_id, "sender_id": sender_id},
        )
        raise DatabaseAccessError("Failed to insert message") from e


def fetch_user_share_flags(user_id: str) -> dict[str, bool]:
    """Executes fetch user share flags operation.

    Args:
        user_id: Unique UUID string of the authenticated user.

    Returns:
        dict[str, bool]: Response payload or result.
    """
    try:
        res = (
            supabase_client.table("profiles")
            .select("share_active_status, share_read_receipts")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        data = cast(dict[str, Any] | None, getattr(res, "data", None))
        if data is None:
            return {"share_active_status": True, "share_read_receipts": True}
        return {
            "share_active_status": bool(data.get("share_active_status", True)),
            "share_read_receipts": bool(data.get("share_read_receipts", True)),
        }
    except APIError as e:
        logger.exception("Failed to fetch share flags", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to fetch share flags") from e


def batch_fetch_user_share_flags(user_ids: list[str]) -> dict[str, dict[str, bool]]:
    """Fetch share flags for multiple user IDs in a single database query.

    Args:
        user_ids: List of user UUID strings.

    Returns:
        dict[str, dict[str, bool]]: Map of user ID to share flags.
    """
    if not user_ids:
        return {}
    target_uuids = [normalize_uuid(uid) for uid in user_ids]
    try:
        res = (
            supabase_client.table("profiles")
            .select("id, share_active_status, share_read_receipts")
            .in_("id", target_uuids)
            .execute()
        )
        rows = cast(list[dict[str, Any]], res.data or [])
        flags_map: dict[str, dict[str, bool]] = {}
        for r in rows:
            uid = str(r.get("id") or "")
            if uid:
                flags_map[uid] = {
                    "share_active_status": bool(r.get("share_active_status", True)),
                    "share_read_receipts": bool(r.get("share_read_receipts", True)),
                }
        for uid in user_ids:
            if uid not in flags_map:
                flags_map[uid] = {
                    "share_active_status": True,
                    "share_read_receipts": True,
                }
        return flags_map
    except APIError as e:
        logger.exception("Failed to batch fetch share flags")
        raise DatabaseAccessError("Failed to batch fetch share flags") from e


def upsert_presence_heartbeat(user_id: str, is_online: bool) -> None:
    """Executes upsert presence heartbeat operation into Redis with 90s TTL.

    Args:
        user_id: Unique UUID string of the authenticated user.
        is_online: Input is online parameter.
    """
    now = utcnow()
    try:
        data = json.dumps(
            {
                "user_id": user_id,
                "last_active_at": now.isoformat(),
                "is_online": is_online,
            },
        )
        sync_redis_client.set(f"presence:{user_id}", data, ex=90)
    except Exception as e:
        logger.warning(
            "Failed to set presence in Redis: %s; falling back to DB",
            e,
            extra={"user_id": user_id},
        )
        try:
            supabase_client.table("chat_presence").upsert(
                {
                    "user_id": user_id,
                    "last_active_at": now.isoformat(),
                    "is_online": is_online,
                },
                on_conflict="user_id",
            ).execute()
        except APIError as db_err:
            logger.exception(
                "Failed to upsert presence heartbeat", extra={"user_id": user_id},
            )
            raise DatabaseAccessError("Failed to upsert presence heartbeat") from db_err


def fetch_presence(user_id: str) -> dict[str, Any] | None:
    """Executes fetch presence operation, reading from Redis cache first.

    Args:
        user_id: Unique UUID string of the authenticated user.

    Returns:
        dict[str, Any] | None: Response payload or result.
    """
    try:
        raw = sync_redis_client.get(f"presence:{user_id}")
        if raw:
            data = json.loads(raw)
            if isinstance(data, dict):
                return cast(dict[str, Any], data)
    except Exception as e:
        logger.warning(
            "Failed to fetch presence from Redis: %s",
            e,
            extra={"user_id": user_id},
        )

    try:
        res = (
            supabase_client.table("chat_presence")
            .select("last_active_at, is_online")
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        return cast(dict[str, Any] | None, getattr(res, "data", None))
    except APIError as e:
        logger.exception("Failed to fetch presence", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to fetch presence") from e


def batch_fetch_presence_from_db(user_ids: list[str]) -> dict[str, dict[str, Any] | None]:
    """Fetch presence records from PostgreSQL for multiple user IDs in a single query.

    Args:
        user_ids: List of user UUID strings.

    Returns:
        dict[str, dict[str, Any] | None]: Map of user ID to presence record dict or None.
    """
    if not user_ids:
        return {}
    uuids = [normalize_uuid(uid) for uid in user_ids]
    try:
        res = (
            supabase_client.table("chat_presence")
            .select("user_id, last_active_at, is_online")
            .in_("user_id", uuids)
            .execute()
        )
        rows = cast(list[dict[str, Any]], res.data or [])
        result: dict[str, dict[str, Any] | None] = {uid: None for uid in user_ids}
        for r in rows:
            uid = str(r.get("user_id") or "")
            if uid:
                result[uid] = r
        return result
    except APIError as e:
        logger.exception("Failed to batch fetch presence from DB")
        raise DatabaseAccessError("Failed to batch fetch presence from DB") from e


def mark_messages_read(conversation_id: str, reader_id: str) -> int:
    """Marks unread messages from the peer as read. Returns rows updated."""
    now = utcnow()
    try:
        res = (
            supabase_client.table("chat_messages")
            .update({"read_at": now.isoformat()})
            .eq("conversation_id", conversation_id)
            .neq("sender_id", reader_id)
            .is_("read_at", "null")
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        return len(rows)
    except APIError as e:
        logger.exception(
            "Failed to mark messages read",
            extra={"conversation_id": conversation_id, "reader_id": reader_id},
        )
        raise DatabaseAccessError("Failed to mark messages read") from e


def _decrypt_float_field(val: Any) -> float | None:
    """Decrypt float field.

        Args:
            val: Input val parameter.

        Returns:
            float | None: Response payload or result."""
    if not val:
        return None
    from app.core.security.crypto import DecryptFailedError
    try:
        return float(decrypt_pii(val, category="chat"))
    except DecryptFailedError:
        with contextlib.suppress(ValueError, TypeError):
            return float(val)


def _decrypt_str_field(val: Any) -> str | None:
    """Decrypt str field.

        Args:
            val: Input val parameter.

        Returns:
            str | None: Response payload or result."""
    if not val:
        return None
    from app.core.security.crypto import DecryptFailedError
    with contextlib.suppress(DecryptFailedError):
        return decrypt_pii(val, category="chat")
    return str(val)


def decrypt_event_row(row: dict[str, Any] | None) -> dict[str, Any] | None:
    """Executes decrypt event row operation.

        Args:
            row: Input row parameter.

        Returns:
            dict[str, Any] | None: Response payload or result."""
    if row is None:
        return None
    from app.core.security.crypto import DecryptFailedError

    # Decrypt event_time
    event_time_raw = row.get("event_time")
    if event_time_raw:
        try:
            decrypted = decrypt_pii(event_time_raw, category="chat")
            row["event_time"] = parse_utc_datetime(decrypted)
        except DecryptFailedError:
            with contextlib.suppress(Exception):
                row["event_time"] = parse_utc_datetime(event_time_raw)

    row["location_lat"] = _decrypt_float_field(row.get("location_lat"))
    row["location_lng"] = _decrypt_float_field(row.get("location_lng"))
    row["location_label"] = _decrypt_str_field(row.get("location_label"))

    return row


def create_event_with_message(
    conversation_id: str,
    sender_id: str,
    ciphertext: str,
    ciphertext_metadata: dict[str, Any],
    event_time: datetime,
    location_lat: float | None,
    location_lng: float | None,
    location_label: str | None,
    safety_enabled: bool = False,
    safety_interval_seconds: int | None = None,
) -> dict[str, Any]:
    """
    Creates the linked chat_messages (type=event) + chat_events rows.
    Not a single DB transaction (postgrest doesn't expose cross-table
    transactions to this client) - on event-row failure, the just-created
    message is deleted so we never leave an event-typed message with no
    event data.
    """
    message_row = insert_message(
        conversation_id, sender_id, "event", ciphertext, ciphertext_metadata,
    )
    message_id = str(message_row["id"])
    try:
        res = (
            supabase_client.table("chat_events")
            .insert(
                {
                    "conversation_id": conversation_id,
                    "message_id": message_id,
                    "created_by": sender_id,
                    "event_time": encrypt_to_hex(event_time.isoformat(), category="chat"),
                    "location_lat": (
                        encrypt_to_hex(str(location_lat), category="chat")
                        if location_lat is not None
                        else None
                    ),
                    "location_lng": (
                        encrypt_to_hex(str(location_lng), category="chat")
                        if location_lng is not None
                        else None
                    ),
                    "location_label": (
                        encrypt_to_hex(location_label, category="chat")
                        if location_label is not None
                        else None
                    ),
                    "safety_enabled": safety_enabled,
                    "safety_interval_seconds": safety_interval_seconds,
                },
            )
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            raise DatabaseAccessError("Event insert returned no row")
        decrypted_event = decrypt_event_row(cast(dict[str, Any], rows[0]))
        return {"message": message_row, "event": decrypted_event}
    except APIError as e:
        try:
            supabase_client.table("chat_messages").delete().eq(
                "id", message_id,
            ).execute()
        except APIError:
            logger.exception(
                "Failed to clean up orphaned event message",
                extra={"message_id": message_id},
            )
        logger.exception(
            "Failed to insert event", extra={"conversation_id": conversation_id},
        )
        raise DatabaseAccessError("Failed to insert event") from e


def fetch_event(event_id: str) -> dict[str, Any] | None:
    """Executes fetch event operation.

        Args:
            event_id: Input event id parameter.

        Returns:
            dict[str, Any] | None: Response payload or result."""
    try:
        res = (
            supabase_client.table("chat_events")
            .select(
                "id, conversation_id, message_id, created_by, event_time, "
                "location_lat, location_lng, location_label, status",
            )
            .eq("id", event_id)
            .maybe_single()
            .execute()
        )
        data = getattr(res, "data", None)
        if data is None:
            return None
        return decrypt_event_row(cast(dict[str, Any], data))
    except APIError as e:
        logger.exception("Failed to fetch event", extra={"event_id": event_id})
        raise DatabaseAccessError("Failed to fetch event") from e


def update_event_status(event_id: str, status: str) -> dict[str, Any] | None:
    """Executes update event status operation.

        Args:
            event_id: Input event id parameter.
            status: Input status parameter.

        Returns:
            dict[str, Any] | None: Response payload or result."""
    try:
        res = (
            supabase_client.table("chat_events")
            .update({"status": status})
            .eq("id", event_id)
            .select(
                "id, conversation_id, message_id, created_by, event_time, "
                "location_lat, location_lng, location_label, status, created_at",
            )
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            return None
        return decrypt_event_row(cast(dict[str, Any], rows[0]))
    except APIError as e:
        logger.exception(
            "Failed to update event status", extra={"event_id": event_id},
        )
        raise DatabaseAccessError("Failed to update event status") from e


def fetch_due_event_reminders(window_minutes: int = 60) -> list[dict[str, Any]]:
    """Events starting within window_minutes that haven't been reminded yet."""
    try:
        res = (
            supabase_client.table("chat_events")
            .select("id, conversation_id, created_by, event_time, location_label")
            .is_("reminder_sent_at", "null")
            .neq("status", "cancelled")
            .limit(500)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        due_events: list[dict[str, Any]] = []
        now = utcnow()
        window_end = now + timedelta(minutes=window_minutes)
        for row in rows:
            if not isinstance(row, dict):
                continue
            decrypted_row = decrypt_event_row(cast(dict[str, Any], row))
            if decrypted_row and decrypted_row.get("event_time"):
                e_time = decrypted_row["event_time"]
                if now <= e_time <= window_end:
                    due_events.append(decrypted_row)
        return due_events
    except APIError as e:
        logger.exception("Failed to fetch due event reminders")
        raise DatabaseAccessError("Failed to fetch due event reminders") from e


def mark_reminder_sent(event_id: str) -> bool:
    """Atomically marks reminder_sent_at timestamp if not already marked.

    Uses a conditional update (WHERE reminder_sent_at IS NULL) to prevent duplicate marking.

    Args:
        event_id: The chat event ID.

    Returns:
        bool: True if the reminder was claimed and marked, False if already marked.
    """
    try:
        res = (
            supabase_client.table("chat_events")
            .update({"reminder_sent_at": utcnow().isoformat()})
            .eq("id", event_id)
            .is_("reminder_sent_at", "null")
            .select("id")
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        return bool(rows)
    except APIError as e:
        logger.exception(
            "Failed to mark reminder sent", extra={"event_id": event_id},
        )
        raise DatabaseAccessError("Failed to mark reminder sent") from e


def fetch_due_safety_reminders(window_minutes: int = 35) -> list[dict[str, Any]]:
    """Events with Meetup Safety auto-configured, starting within
    window_minutes, that haven't had their pre-event safety push sent yet.
    Tracked independently of fetch_due_event_reminders since this one is
    creator-only and has a tighter/different lead time.
    """
    try:
        res = (
            supabase_client.table("chat_events")
            .select(
                "id, conversation_id, created_by, event_time, "
                "safety_interval_seconds",
            )
            .eq("safety_enabled", True)
            .is_("safety_reminder_sent_at", "null")
            .neq("status", "cancelled")
            .limit(500)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        due_events: list[dict[str, Any]] = []
        now = utcnow()
        window_end = now + timedelta(minutes=window_minutes)
        for row in rows:
            if not isinstance(row, dict):
                continue
            decrypted_row = decrypt_event_row(cast(dict[str, Any], row))
            if decrypted_row and decrypted_row.get("event_time"):
                e_time = decrypted_row["event_time"]
                if now <= e_time <= window_end:
                    due_events.append(decrypted_row)
        return due_events
    except APIError as e:
        logger.exception("Failed to fetch due meetup safety reminders")
        raise DatabaseAccessError("Failed to fetch due meetup safety reminders") from e


def mark_safety_reminder_sent(event_id: str) -> bool:
    """Atomically marks safety_reminder_sent_at timestamp if not already marked.

    Uses a conditional update (WHERE safety_reminder_sent_at IS NULL) to prevent duplicate marking.

    Args:
        event_id: The chat event ID.

    Returns:
        bool: True if the safety reminder was claimed and marked, False if already marked.
    """
    try:
        res = (
            supabase_client.table("chat_events")
            .update({"safety_reminder_sent_at": utcnow().isoformat()})
            .eq("id", event_id)
            .is_("safety_reminder_sent_at", "null")
            .select("id")
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        return bool(rows)
    except APIError as e:
        logger.exception(
            "Failed to mark meetup safety reminder sent",
            extra={"event_id": event_id},
        )
        raise DatabaseAccessError(
            "Failed to mark meetup safety reminder sent",
        ) from e

