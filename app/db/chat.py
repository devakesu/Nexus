import logging
import uuid
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import DiscoveryTab
from app.db.client import DatabaseAccessError, supabase_client, utcnow

logger = logging.getLogger(__name__)


def fetch_conversations_for_user(
    user_id: str, tab: DiscoveryTab = "Dating",
) -> list[dict[str, Any]]:
    """Return active, already-started conversations for user_id in a tab."""
    user_id = str(uuid.UUID(user_id)).lower()
    try:
        res = (
            supabase_client.table("chat_conversations")
            .select("id, user_a_id, user_b_id, last_message_at")
            .or_(f"user_a_id.eq.{user_id},user_b_id.eq.{user_id}")
            .eq("tab", tab)
            .is_("closed_at", "null")
            .not_.is_("last_message_at", "null")
            .order("last_message_at", desc=True)
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
    user_id = str(uuid.UUID(user_id)).lower()
    try:
        res = (
            supabase_client.table("chat_conversations")
            .select("match_id")
            .or_(f"user_a_id.eq.{user_id},user_b_id.eq.{user_id}")
            .eq("tab", tab)
            .is_("closed_at", "null")
            .not_.is_("last_message_at", "null")
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


def close_conversation_for_match_action(
    user_id: str,
    target_id: str,
    tab: DiscoveryTab,
    reason: str,
) -> None:
    """Close the conversation between two users (mirrors set_match_unmatched)."""
    user_id = str(uuid.UUID(user_id)).lower()
    target_id = str(uuid.UUID(target_id)).lower()
    now = utcnow()
    try:
        (
            supabase_client.table("chat_conversations")
            .update({"closed_at": now.isoformat(), "closed_reason": reason})
            .or_(
                f"and(user_a_id.eq.{user_id},user_b_id.eq.{target_id}),"
                f"and(user_a_id.eq.{target_id},user_b_id.eq.{user_id})",
            )
            .eq("tab", tab)
            .is_("closed_at", "null")
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to close conversation",
            extra={"user_id": user_id, "target_id": target_id},
        )
        raise DatabaseAccessError("Failed to close conversation") from e


def fetch_conversation_participants(conversation_id: str) -> dict[str, Any] | None:
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


def upsert_presence_heartbeat(user_id: str, is_online: bool) -> None:
    now = utcnow()
    try:
        supabase_client.table("chat_presence").upsert(
            {
                "user_id": user_id,
                "last_active_at": now.isoformat(),
                "is_online": is_online,
            },
            on_conflict="user_id",
        ).execute()
    except APIError as e:
        logger.exception(
            "Failed to upsert presence heartbeat", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to upsert presence heartbeat") from e


def fetch_presence(user_id: str) -> dict[str, Any] | None:
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
