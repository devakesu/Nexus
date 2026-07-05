import asyncio
import logging
from typing import Any, cast

import firebase_admin
import firebase_admin.messaging as _fcm_module

from app.db.client import supabase_client

logger = logging.getLogger(__name__)

# firebase_admin ships without type stubs; cast to Any to keep Pyright happy,
# matching the same pattern used in app/main.py.
_fb: Any = firebase_admin
_fcm: Any = _fcm_module


def _is_firebase_initialized() -> bool:
    try:
        _fb.get_app()
        return True
    except ValueError:
        return False


def _fetch_user_fcm_tokens(user_id: str) -> list[str]:
    res = (
        supabase_client.table("user_devices")
        .select("fcm_token")
        .eq("user_id", user_id)
        .eq("is_active", True)
        .execute()
    )
    rows = cast(list[dict[str, Any]], res.data or [])
    return [str(row["fcm_token"]) for row in rows if row.get("fcm_token")]


def _fetch_profile_name(user_id: str) -> str | None:
    res = (
        supabase_client.table("profiles")
        .select("name")
        .eq("id", user_id)
        .limit(1)
        .execute()
    )
    rows = cast(list[dict[str, Any]], res.data or [])
    if not rows:
        return None
    name = rows[0].get("name")
    return str(name) if name is not None else None


def _send_to_tokens(
    tokens: list[str],
    title: str,
    body: str,
    data: dict[str, str],
    channel_id: str,
) -> None:
    if not tokens:
        return
    msg = _fcm.MulticastMessage(
        tokens=tokens,
        notification=_fcm.Notification(title=title, body=body),
        data=data,
        android=_fcm.AndroidConfig(
            priority="high",
            notification=_fcm.AndroidNotification(channel_id=channel_id),
        ),
        apns=_fcm.APNSConfig(
            payload=_fcm.APNSPayload(
                aps=_fcm.Aps(sound="default"),
            ),
        ),
    )
    response = _fcm.send_each_for_multicast(msg)
    if response.failure_count > 0:
        for i, resp in enumerate(response.responses):
            if not resp.success:
                logger.warning(
                    "FCM delivery failed for token index %d: %s",
                    i,
                    str(resp.exception),
                )


async def send_like_notification(
    actor_id: str,
    target_id: str,
    is_superlike: bool,
) -> None:
    """Fire-and-forget: notify target_id that actor_id liked/superliked them."""
    if not _is_firebase_initialized():
        return
    try:
        tokens, actor_name = await asyncio.gather(
            asyncio.to_thread(_fetch_user_fcm_tokens, target_id),
            asyncio.to_thread(_fetch_profile_name, actor_id),
        )
        if not tokens:
            return
        name = actor_name or "Someone"
        if is_superlike:
            title = f"{name} super liked you ⭐"
            channel_id = "likes_superlike"
        else:
            title = f"{name} liked you"
            channel_id = "likes_like"
        await asyncio.to_thread(
            _send_to_tokens,
            tokens,
            title,
            "Open Nexus to see them in your likes",
            {
                "type": "superlike" if is_superlike else "like",
                "actor_id": actor_id,
            },
            channel_id,
        )
    except Exception:
        logger.exception(
            "Failed to send like notification",
            extra={"actor_id": actor_id, "target_id": target_id},
        )


async def send_match_notification(
    user_a_id: str,
    user_b_id: str,
) -> None:
    """Fire-and-forget: notify both users that they matched."""
    if not _is_firebase_initialized():
        return
    try:
        tokens_a, tokens_b, name_a, name_b = await asyncio.gather(
            asyncio.to_thread(_fetch_user_fcm_tokens, user_a_id),
            asyncio.to_thread(_fetch_user_fcm_tokens, user_b_id),
            asyncio.to_thread(_fetch_profile_name, user_a_id),
            asyncio.to_thread(_fetch_profile_name, user_b_id),
        )
        name_a = name_a or "Someone"
        name_b = name_b or "Someone"

        if tokens_a:
            await asyncio.to_thread(
                _send_to_tokens,
                tokens_a,
                "It's a match! \U0001f389",
                f"You and {name_b} liked each other",
                {"type": "match", "actor_id": user_b_id},
                "matches_new",
            )
        if tokens_b:
            await asyncio.to_thread(
                _send_to_tokens,
                tokens_b,
                "It's a match! \U0001f389",
                f"You and {name_a} liked each other",
                {"type": "match", "actor_id": user_a_id},
                "matches_new",
            )
    except Exception:
        logger.exception(
            "Failed to send match notifications",
            extra={"user_a_id": user_a_id, "user_b_id": user_b_id},
        )


async def send_chat_message_notification(
    sender_id: str,
    recipient_id: str,
    conversation_id: str,
    tab: str,
) -> None:
    """
    Fire-and-forget: notify recipient_id of a new message from sender_id.

    The body is deliberately generic - the server never has message
    plaintext, so it cannot include a content preview. conversation_id/tab/
    name are included as data-only fields so the client can deep-link
    straight into the conversation on tap.
    """
    if not _is_firebase_initialized():
        return
    try:
        tokens, sender_name = await asyncio.gather(
            asyncio.to_thread(_fetch_user_fcm_tokens, recipient_id),
            asyncio.to_thread(_fetch_profile_name, sender_id),
        )
        if not tokens:
            return
        name = sender_name or "Someone"
        await asyncio.to_thread(
            _send_to_tokens,
            tokens,
            f"New message from {name}",
            "Open Nexus to read it",
            {
                "type": "chat_message",
                "actor_id": sender_id,
                "conversation_id": conversation_id,
                "tab": tab,
                "name": name,
            },
            "chat_message",
        )
    except Exception:
        logger.exception(
            "Failed to send chat message notification",
            extra={"sender_id": sender_id, "recipient_id": recipient_id},
        )


async def send_chat_event_reminder_notification(
    user_a_id: str,
    user_b_id: str,
    conversation_id: str,
    tab: str,
    location_label: str | None,
) -> None:
    """
    Fire-and-forget: reminds both participants about an upcoming plan.

    The body is deliberately generic (only the plaintext location_label,
    if any) - the event's title/notes are E2E encrypted and the server
    never has them. Exact time is shown by the client from data it already
    has once the notification is tapped open.
    """
    if not _is_firebase_initialized():
        return
    try:
        tokens_a, tokens_b = await asyncio.gather(
            asyncio.to_thread(_fetch_user_fcm_tokens, user_a_id),
            asyncio.to_thread(_fetch_user_fcm_tokens, user_b_id),
        )
        body = (
            f"Your plan at {location_label} is coming up soon"
            if location_label
            else "Your plan is coming up soon"
        )
        data = {
            "type": "chat_event_reminder",
            "conversation_id": conversation_id,
            "tab": tab,
        }
        if tokens_a:
            await asyncio.to_thread(
                _send_to_tokens,
                tokens_a,
                "Upcoming plan reminder",
                body,
                data,
                "chat_event_reminder",
            )
        if tokens_b:
            await asyncio.to_thread(
                _send_to_tokens,
                tokens_b,
                "Upcoming plan reminder",
                body,
                data,
                "chat_event_reminder",
            )
    except Exception:
        logger.exception(
            "Failed to send event reminder notification",
            extra={"conversation_id": conversation_id},
        )
