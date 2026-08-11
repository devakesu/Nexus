"""Firebase Cloud Messaging (FCM) push notification sender service.

Handles device FCM token retrieval, message payload construction, multi-device push notification
dispatching, and stale token cleanup.
"""

import asyncio
import logging
from datetime import datetime
from typing import Any, cast

import firebase_admin
import firebase_admin.messaging as _fcm_module
import sentry_sdk

from app.db.client import supabase_client
from app.db.discovery import get_cached_active_block_ids

logger = logging.getLogger(__name__)

# firebase_admin untyped module handles
_fb: Any = firebase_admin
_fcm: Any = _fcm_module


def _is_firebase_initialized() -> bool:
    """Verifies if Firebase Admin SDK app instance is initialized.

    Returns:
        bool: True if initialized, False otherwise.
    """
    try:
        _fb.get_app()
        return True
    except ValueError:
        return False



def _fetch_user_fcm_tokens(user_id: str) -> list[str]:
    """Retrieve all active FCM device tokens for a given user.

    Args:
        user_id: Unique UUID string identifier of the target user.

    Returns:
        list[str]: List of active FCM registration token strings.
    """
    try:
        # Prevent sending notifications to deactivated/deleted accounts
        profile_res = (
            supabase_client.table("profiles")
            .select("is_deactivated")
            .eq("id", user_id)
            .limit(1)
            .execute()
        )
        profile_rows = cast(list[dict[str, Any]], profile_res.data or [])
        if profile_rows and profile_rows[0].get("is_deactivated") is True:
            return []
    except Exception:
        logger.exception(
            "Failed to check deactivation status during FCM token fetch",
            extra={"user_id": user_id},
        )
        return []

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
    """Retrieve the display name of a user from their profile record.

    Args:
        user_id: Unique UUID string identifier of the target user.

    Returns:
        str | None: User's display name string, or None if profile not found.
    """
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


def _deactivate_fcm_token(token: str) -> None:
    """Mark an invalid or expired FCM registration token as inactive in user_devices.

    Args:
        token: Stale FCM registration token string to deactivate.
    """
    try:
        supabase_client.table("user_devices").update({"is_active": False}).eq(
            "fcm_token",
            token,
        ).execute()
    except Exception:
        logger.exception("Failed to deactivate FCM token ...%s", token[-8:])


def _fetch_profile_details(user_id: str) -> tuple[str | None, str | None]:
    """Retrieve display name and avatar photo URL for notification payloads.

    Args:
        user_id: Unique UUID string identifier of the target user.

    Returns:
        tuple[str | None, str | None]: Tuple of (display_name, avatar_photo_url).
    """
    try:
        from app.db.profiles import fetch_peer_profile_by_id

        profile = fetch_peer_profile_by_id(user_id)
        if profile:
            return profile.get("name"), profile.get("profile_pic")
    except Exception as err:
        sentry_sdk.capture_exception(err)
        logger.exception(
            "Failed to fetch profile details",
            extra={"user_id": user_id},
        )
    return None, None


def _send_to_tokens(
    tokens: list[str],
    title: str | None,
    body: str | None,
    data: dict[str, str],
    channel_id: str,
) -> None:
    """Send to tokens.

        Args:
            tokens: Input tokens parameter.
            title: Input title parameter.
            body: Input body parameter.
            data: Input data parameter.
            channel_id: Input channel id parameter."""
    if not tokens:
        return
    notification = (
        _fcm.Notification(title=title, body=body) if title or body else None
    )
    msg = _fcm.MulticastMessage(
        tokens=tokens,
        notification=notification,
        data=data,
        android=_fcm.AndroidConfig(
            priority="high",
            notification=(
                _fcm.AndroidNotification(channel_id=channel_id)
                if notification
                else None
            ),
        ),
        apns=_fcm.APNSConfig(
            payload=_fcm.APNSPayload(
                aps=_fcm.Aps(
                    sound="default" if notification else None,
                    content_available=True,
                ),
            ),
        ),
    )
    response = _fcm.send_each_for_multicast(msg)
    if response.failure_count > 0:
        for i, resp in enumerate(response.responses):
            if not resp.success:
                exc = resp.exception
                logger.warning(
                    "FCM delivery failed for token index %d: %s",
                    i,
                    str(exc),
                )
                if exc:
                    exc_str = str(exc)
                    if (
                        getattr(exc, "code", None) == "NOT_FOUND"
                        or "NotRegistered" in exc_str
                    ):
                        _deactivate_fcm_token(tokens[i])


async def send_like_notification(
    actor_id: str,
    target_id: str,
    is_superlike: bool,
) -> None:
    """Fire-and-forget: notify target_id that actor_id liked/superliked them."""
    if not _is_firebase_initialized():
        return
    try:
        block_ids = await get_cached_active_block_ids(target_id)
        if actor_id in block_ids:
            logger.info(
                "Skipping like notification: actor is blocked by target or vice versa",
                extra={"actor_id": actor_id, "target_id": target_id},
            )
            return

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
    message_id: str,
    ciphertext: str,
    ciphertext_metadata: dict[str, Any] | str,
    message_type: str = "text",
    created_at: str | datetime | None = None,
) -> None:
    """Fire-and-forget: notify recipient_id of a new message from sender_id.

    The body is deliberately omitted for E2EE messages - the payload is sent
    as a data-only push, allowing the recipient's client to decrypt the
    ciphertext locally on receipt and construct the notification.
    """
    if not _is_firebase_initialized():
        return
    try:
        block_ids = await get_cached_active_block_ids(recipient_id)
        if sender_id in block_ids:
            logger.info(
                "Skipping chat notification: sender is blocked by recipient or vice versa",
                extra={"sender_id": sender_id, "recipient_id": recipient_id},
            )
            return

        import json

        tokens, (sender_name, profile_pic) = await asyncio.gather(
            asyncio.to_thread(_fetch_user_fcm_tokens, recipient_id),
            asyncio.to_thread(_fetch_profile_details, sender_id),
        )
        if not tokens:
            return
        name = sender_name or "Someone"

        meta_str = (
            json.dumps(ciphertext_metadata)
            if isinstance(ciphertext_metadata, dict)
            else str(ciphertext_metadata)
        )
        created_at_str = (
            created_at.isoformat()
            if isinstance(created_at, datetime)
            else str(created_at or "")
        )

        data = {
            "type": "chat_message",
            "actor_id": sender_id,
            "conversation_id": conversation_id,
            "tab": tab,
            "name": name,
            "profile_pic": profile_pic or "",
            "message_id": message_id,
            "ciphertext": ciphertext,
            "ciphertext_metadata": meta_str,
            "msg_type": message_type,
            "created_at": created_at_str,
        }

        await asyncio.to_thread(
            _send_to_tokens,
            tokens,
            None,
            None,
            data,
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


_SAFETY_REMINDER_NOUN_BY_TAB = {
    "Friends": "meetup",
    "Professional": "meeting",
}


async def send_trusted_contact_removed_notification(
    user_id: str,
    contact_name: str,
) -> None:
    """Fire-and-forget: alongside email and SMS, pushes an immediate
    in-app-visible notice that a trusted contact removed themselves - see
    app/api/safety_portal.py's remove_trusted_contact endpoint.
    """
    if not _is_firebase_initialized():
        return
    try:
        tokens = await asyncio.to_thread(_fetch_user_fcm_tokens, user_id)
        if not tokens:
            return
        await asyncio.to_thread(
            _send_to_tokens,
            tokens,
            "A trusted contact removed themselves",
            f"{contact_name} is no longer one of your Meetup Safety "
            "trusted contacts.",
            {
                "type": "safety_contact_removed",
            },
            "safety_contact_removed",
        )
    except Exception:
        logger.exception(
            "Failed to send trusted contact removed notification",
            extra={"user_id": user_id},
        )


async def send_meetup_safety_reminder_notification(
    user_id: str,
    peer_id: str,
    conversation_id: str,
    tab: str,
) -> None:
    """
    Fire-and-forget: nudges the event's creator that the Meetup Safety
    check-in they configured at creation time is about to start.

    Sent only to the creator (user_id), never both participants - Meetup
    Safety is personal (their own trusted contacts, their own device), not
    shared conversation state, unlike send_chat_event_reminder_notification.
    Tapping deep-links into the conversation (same as a chat_message tap) so
    the client lands on the event card and its existing "Set up a safety
    check-in" shortcut, rather than trying to prefill a screen from a title
    the server never has plaintext access to. peer_id (the *other*
    participant) is included because the client's chat-conversation route
    requires it to open the thread, same as chat_message's actor_id.
    """
    if not _is_firebase_initialized():
        return
    try:
        tokens = await asyncio.to_thread(_fetch_user_fcm_tokens, user_id)
        if not tokens:
            return
        noun = _SAFETY_REMINDER_NOUN_BY_TAB.get(tab, "date")
        await asyncio.to_thread(
            _send_to_tokens,
            tokens,
            "Meetup Safety turns on soon",
            f"Your {noun} starts in about 30 minutes - open the chat to "
            "start your check-in.",
            {
                "type": "meetup_safety_reminder",
                "conversation_id": conversation_id,
                "peer_id": peer_id,
                "tab": tab,
            },
            "meetup_safety_reminder",
        )
    except Exception:
        logger.exception(
            "Failed to send meetup safety reminder notification",
            extra={"user_id": user_id, "conversation_id": conversation_id},
        )
