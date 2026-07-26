"""FastAPI router for real-time messaging, chat conversations, presence updates, and meetup scheduling.

Provides endpoints for listing active conversations, fetching and sending encrypted messages,
updating presence status, and creating meetup event proposals with automated reminders.
"""

import asyncio
import logging
from datetime import timedelta
from typing import Annotated, Any, cast

from fastapi import APIRouter, Body, Depends, HTTPException, Path, Query, Request

from app.api.dependencies import (
    assert_safety_consent,
    get_active_user_id,
    verify_app_check_token,
)
from app.core.config import DiscoveryTab, settings
from app.core.limiter import limiter
from app.core.tasks import safe_create_task
from app.db.chat import (
    create_event_with_message,
    fetch_conversation_participants,
    fetch_conversations_for_user,
    fetch_event,
    fetch_presence,
    fetch_started_match_ids,
    fetch_user_share_flags,
    get_or_create_conversation,
    insert_message,
    mark_messages_read,
    update_event_status,
    upsert_presence_heartbeat,
)
from app.db.chat_keys import has_active_match
from app.db.client import (
    DatabaseAccessError,
    parse_utc_datetime,
    supabase_client,
    utcnow,
)
from app.db.exclusions import get_cached_active_block_ids
from app.db.matches import fetch_matches_for_user
from app.db.profiles import decrypt_profile_rows
from app.db.users import fetch_public_user
from app.models import (
    ChatCandidateItem,
    ChatCandidatesResponse,
    ChatConversationItem,
    ChatsListResponse,
    CreateChatRequest,
    CreateChatResponse,
    CreateEventRequest,
    EventResponse,
    MarkMessagesReadResponse,
    PresenceHeartbeatRequest,
    PresenceResponse,
    SendMessageRequest,
    SendMessageResponse,
    UpdateEventStatusRequest,
)
from app.services.fcm_sender import send_chat_message_notification

router = APIRouter()
logger = logging.getLogger(__name__)


@router.get("/api/v1/chats", response_model=ChatsListResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_chats(
    request: Request,
    tab: Annotated[DiscoveryTab, Query()] = "Dating",
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> ChatsListResponse:
    """Get chats.

        Args:
            request: get chats.
            tab: get chats.
            _device: get chats.
            user_id: get chats.

        Returns:
            ChatsListResponse: Result value.
        """
    _ = request
    try:
        rows = await asyncio.to_thread(fetch_conversations_for_user, user_id, tab)

        if not rows:
            return ChatsListResponse(conversations=[])

        block_ids = await get_cached_active_block_ids(user_id)
        counterpart_ids = [
            str(r["matched_user_id"]) for r in rows if r.get("matched_user_id")
        ]
        counterpart_ids = [cid for cid in counterpart_ids if cid not in block_ids]

        profiles_res = await asyncio.to_thread(
            lambda: supabase_client.table("profiles")
            .select("id, name, age, profile_pic")
            .in_("id", counterpart_ids)
            .eq("is_deactivated", False)
            .execute(),
        )
        profile_map = decrypt_profile_rows(cast(list[Any], profiles_res.data or []))

        convo_ids = [
            str(r["conversation_id"]) for r in rows if r.get("conversation_id")
        ]
        unread_counts: dict[str, int] = {}
        if convo_ids:
            unread_res = await asyncio.to_thread(
                lambda: supabase_client.table("chat_messages")
                .select("conversation_id")
                .in_("conversation_id", convo_ids)
                .neq("sender_id", user_id)
                .is_("read_at", "null")
                .execute(),
            )
            raw_unread = cast(list[dict[str, Any]], unread_res.data or [])
            for r in raw_unread:
                c_id = str(r.get("conversation_id") or "")
                if c_id:
                    unread_counts[c_id] = unread_counts.get(c_id, 0) + 1

        items: list[ChatConversationItem] = []
        for row in rows:
            uid = str(row.get("matched_user_id") or "")
            if uid in block_ids or uid not in profile_map:
                continue
            profile = profile_map.get(uid, {})
            conversation_id = str(row.get("conversation_id") or "")
            items.append(
                ChatConversationItem(
                    conversation_id=conversation_id,
                    matched_user_id=uid,
                    name=profile.get("name"),
                    age=profile.get("age"),
                    profile_pic=profile.get("profile_pic"),
                    last_message_at=row["last_message_at"],
                    has_unread=conversation_id in unread_counts,
                    unread_count=unread_counts.get(conversation_id, 0),
                ),
            )

        return ChatsListResponse(conversations=items)

    except HTTPException:
        raise
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure fetching chats", extra={"user_id": user_id, "tab": tab},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err


@router.get(
    "/api/v1/chats/new-chat-candidates", response_model=ChatCandidatesResponse,
)
@limiter.limit(settings.rate_limit_discover)
async def get_new_chat_candidates(
    request: Request,
    tab: Annotated[DiscoveryTab, Query()] = "Dating",
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> ChatCandidatesResponse:
    """Matches in this tab that have no conversation started yet."""
    _ = request
    try:
        matches, started_match_ids = await asyncio.gather(
            asyncio.to_thread(fetch_matches_for_user, user_id, tab),
            asyncio.to_thread(fetch_started_match_ids, user_id, tab),
        )

        block_ids = await get_cached_active_block_ids(user_id)
        candidate_rows = [
            m for m in matches if str(m.get("match_id")) not in started_match_ids
        ]
        candidate_rows = [
            m for m in candidate_rows if str(m.get("matched_user_id")) not in block_ids
        ]
        if not candidate_rows:
            return ChatCandidatesResponse(candidates=[])

        counterpart_ids = [
            str(r["matched_user_id"])
            for r in candidate_rows
            if r.get("matched_user_id")
        ]

        profiles_res = await asyncio.to_thread(
            lambda: supabase_client.table("profiles")
            .select("id, name, age, profile_pic")
            .in_("id", counterpart_ids)
            .eq("is_deactivated", False)
            .execute(),
        )
        profile_map = decrypt_profile_rows(cast(list[Any], profiles_res.data or []))

        items: list[ChatCandidateItem] = []
        for row in candidate_rows:
            uid = str(row.get("matched_user_id") or "")
            if uid in block_ids or uid not in profile_map:
                continue
            profile = profile_map.get(uid, {})
            items.append(
                ChatCandidateItem(
                    match_id=str(row.get("match_id") or ""),
                    matched_user_id=uid,
                    name=profile.get("name"),
                    age=profile.get("age"),
                    profile_pic=profile.get("profile_pic"),
                    matched_at=row["created_at"],
                ),
            )

        return ChatCandidatesResponse(candidates=items)

    except HTTPException:
        raise
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure fetching new chat candidates",
            extra={"user_id": user_id, "tab": tab},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err


@router.post("/api/v1/chats", response_model=CreateChatResponse)
@limiter.limit(settings.rate_limit_discover)
async def create_chat(
    request: Request,
    payload: CreateChatRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> CreateChatResponse:
    """Idempotently create (or fetch) the conversation for a match."""
    _ = request
    try:
        conversation = await asyncio.to_thread(
            get_or_create_conversation, user_id, payload.match_id,
        )
        user_a_id = str(conversation.get("user_a_id") or "")
        matched_user_id = (
            str(conversation.get("user_b_id") or "")
            if user_a_id == user_id
            else user_a_id
        )
        return CreateChatResponse(
            conversation_id=str(conversation.get("id") or ""),
            matched_user_id=matched_user_id,
            tab=cast(DiscoveryTab, conversation.get("tab")),
        )
    except DatabaseAccessError as err:
        orig = err.__cause__
        detail = str(orig) if orig else str(err)
        if "not a participant" in detail or "No active match found" in detail:
            raise HTTPException(status_code=403, detail=detail) from err
        logger.exception(
            "Database failure creating chat",
            extra={"user_id": user_id, "match_id": payload.match_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err


@router.post(
    "/api/v1/chats/{conversation_id}/messages",
    response_model=SendMessageResponse,
)
@limiter.limit(settings.rate_limit_discover)
async def send_message(
    request: Request,
    conversation_id: str = Path(...),
    payload: SendMessageRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> SendMessageResponse:
    """Send message.

        Args:
            request: send message.
            conversation_id: send message.
            payload: send message.
            _device: send message.
            user_id: send message.

        Returns:
            SendMessageResponse: Result value.
        """
    _ = request
    try:
        conversation = await asyncio.to_thread(
            fetch_conversation_participants, conversation_id,
        )
        if conversation is None:
            raise HTTPException(status_code=404, detail="Conversation not found.")

        user_a_id = str(conversation.get("user_a_id") or "")
        user_b_id = str(conversation.get("user_b_id") or "")
        if user_id not in (user_a_id, user_b_id):
            raise HTTPException(
                status_code=403,
                detail="Not a participant of this conversation.",
            )
        if conversation.get("closed_at") is not None:
            raise HTTPException(
                status_code=403,
                detail="This conversation is closed.",
            )

        row = await asyncio.to_thread(
            insert_message,
            conversation_id,
            user_id,
            payload.message_type,
            payload.ciphertext,
            payload.ciphertext_metadata,
        )

        recipient_id = user_b_id if user_id == user_a_id else user_a_id
        safe_create_task(
            send_chat_message_notification(
                sender_id=user_id,
                recipient_id=recipient_id,
                conversation_id=conversation_id,
                tab=str(conversation.get("tab") or "Dating"),
                message_id=str(row.get("id") or ""),
                ciphertext=payload.ciphertext,
                ciphertext_metadata=payload.ciphertext_metadata,
                message_type=payload.message_type,
                created_at=row["created_at"],
            ),
        )

        return SendMessageResponse(
            message_id=str(row.get("id") or ""),
            created_at=row["created_at"],
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure sending message",
            extra={"user_id": user_id, "conversation_id": conversation_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err
    except HTTPException:
        raise


@router.post("/api/v1/chat/presence/heartbeat")
@limiter.limit(settings.rate_limit_discover)
async def send_presence_heartbeat(
    request: Request,
    payload: PresenceHeartbeatRequest = Body(default=PresenceHeartbeatRequest()),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Send presence heartbeat.

        Args:
            request: send presence heartbeat.
            payload: send presence heartbeat.
            _device: send presence heartbeat.
            user_id: send presence heartbeat.

        Returns:
            dict[str, bool]: Result value.
        """
    _ = request
    try:
        await asyncio.to_thread(upsert_presence_heartbeat, user_id, payload.is_online)
        return {"success": True}
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure recording presence heartbeat",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err


# Presence is treated as offline once the heartbeat is older than this, even
# if is_online was never explicitly flipped false (e.g. the app was killed).
_PRESENCE_STALE_AFTER = timedelta(seconds=90)


@router.get(
    "/api/v1/chat/presence/{target_user_id}",
    response_model=PresenceResponse,
)
@limiter.limit(settings.rate_limit_discover)
async def get_presence(
    request: Request,
    target_user_id: str = Path(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> PresenceResponse:
    """
    Deliberately returns an empty PresenceResponse (nulls) for every case
    that should hide presence: no active match, the peer's Active Status
    is off, or the peer has never been active. These are indistinguishable
    on purpose so a client can't infer the privacy setting is off.
    """
    _ = request
    try:
        if not await asyncio.to_thread(has_active_match, user_id, target_user_id):
            return PresenceResponse()

        flags = await asyncio.to_thread(fetch_user_share_flags, target_user_id)
        if not flags["share_active_status"]:
            return PresenceResponse()

        presence = await asyncio.to_thread(fetch_presence, target_user_id)
        if presence is None:
            return PresenceResponse()

        raw_last_active = presence.get("last_active_at")
        if raw_last_active is None:
            return PresenceResponse()

        last_active_at = parse_utc_datetime(raw_last_active)
        is_online = bool(presence.get("is_online", False)) and (
            utcnow() - last_active_at < _PRESENCE_STALE_AFTER
        )
        return PresenceResponse(is_online=is_online, last_active_at=last_active_at)
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure fetching presence",
            extra={"user_id": user_id, "target_user_id": target_user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err


@router.patch(
    "/api/v1/chats/{conversation_id}/messages/read",
    response_model=MarkMessagesReadResponse,
)
@limiter.limit(settings.rate_limit_discover)
async def mark_conversation_messages_read(
    request: Request,
    conversation_id: str = Path(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> MarkMessagesReadResponse:
    """
    Silently no-ops (returns marked_count=0) if the reader has Read
    Receipts turned off, rather than erroring - the client can still track
    its own unread count locally without telling the sender anything.
    """
    _ = request
    try:
        conversation = await asyncio.to_thread(
            fetch_conversation_participants, conversation_id,
        )
        if conversation is None:
            raise HTTPException(status_code=404, detail="Conversation not found.")

        user_a_id = str(conversation.get("user_a_id") or "")
        user_b_id = str(conversation.get("user_b_id") or "")
        if user_id not in (user_a_id, user_b_id):
            raise HTTPException(
                status_code=403,
                detail="Not a participant of this conversation.",
            )

        flags = await asyncio.to_thread(fetch_user_share_flags, user_id)
        if not flags["share_read_receipts"]:
            return MarkMessagesReadResponse(marked_count=0)

        marked = await asyncio.to_thread(mark_messages_read, conversation_id, user_id)
        return MarkMessagesReadResponse(marked_count=marked)
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure marking messages read",
            extra={"user_id": user_id, "conversation_id": conversation_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err
    except HTTPException:
        raise


@router.post("/api/v1/chats/{conversation_id}/events", response_model=EventResponse)
@limiter.limit(settings.rate_limit_discover)
async def create_chat_event(
    request: Request,
    conversation_id: str = Path(...),
    payload: CreateEventRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> EventResponse:
    """
    Creates a date/plan proposal: event_time/location are stored in
    plaintext (needed for reminder scheduling), title/notes travel only as
    the ratchet-encrypted ciphertext of the linked chat_messages row.
    """
    _ = request
    try:
        conversation = await asyncio.to_thread(
            fetch_conversation_participants, conversation_id,
        )
        if conversation is None:
            raise HTTPException(status_code=404, detail="Conversation not found.")

        user_a_id = str(conversation.get("user_a_id") or "")
        user_b_id = str(conversation.get("user_b_id") or "")
        if user_id not in (user_a_id, user_b_id):
            raise HTTPException(
                status_code=403,
                detail="Not a participant of this conversation.",
            )
        if conversation.get("closed_at") is not None:
            raise HTTPException(status_code=403, detail="This conversation is closed.")

        if payload.safety_enabled:
            user_row = await asyncio.to_thread(fetch_public_user, user_id)
            if not user_row:
                raise HTTPException(status_code=404, detail="User not found.")
            assert_safety_consent(user_row)

        result = await asyncio.to_thread(
            create_event_with_message,
            conversation_id,
            user_id,
            payload.ciphertext,
            payload.ciphertext_metadata,
            payload.event_time,
            payload.location_lat,
            payload.location_lng,
            payload.location_label,
            payload.safety_enabled,
            payload.safety_interval_seconds,
        )
        message_row = result["message"]
        event_row = result["event"]

        recipient_id = user_b_id if user_id == user_a_id else user_a_id
        safe_create_task(
            send_chat_message_notification(
                sender_id=user_id,
                recipient_id=recipient_id,
                conversation_id=conversation_id,
                tab=str(conversation.get("tab") or "Dating"),
                message_id=str(message_row.get("id") or ""),
                ciphertext=payload.ciphertext,
                ciphertext_metadata=payload.ciphertext_metadata,
                message_type="event",
                created_at=message_row["created_at"],
            ),
        )

        return EventResponse(
            event_id=str(event_row["id"]),
            message_id=str(message_row["id"]),
            conversation_id=conversation_id,
            event_time=event_row["event_time"],
            location_lat=event_row.get("location_lat"),
            location_lng=event_row.get("location_lng"),
            location_label=event_row.get("location_label"),
            status=event_row["status"],
            created_at=message_row["created_at"],
            safety_enabled=bool(event_row.get("safety_enabled") or False),
            safety_interval_seconds=event_row.get("safety_interval_seconds"),
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure creating event",
            extra={"user_id": user_id, "conversation_id": conversation_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err
    except HTTPException:
        raise


def _validate_event_status_transition(
    current_status: str,
    new_status: str,
    user_id: str,
    created_by: str,
) -> None:
    """Validate event status transition.

        Args:
            current_status: validate event status transition.
            new_status: validate event status transition.
            user_id: validate event status transition.
            created_by: validate event status transition.

        Returns:
            None: Result value.
        """
    if current_status == "cancelled":
        raise HTTPException(
            status_code=400,
            detail="Cannot update status of a cancelled event.",
        )

    if new_status == "confirmed":
        if current_status != "proposed":
            raise HTTPException(
                status_code=400,
                detail="Event is already confirmed.",
            )
        if user_id == created_by:
            raise HTTPException(
                status_code=400,
                detail="Proposer cannot confirm their own proposed event.",
            )


@router.patch(
    "/api/v1/chats/{conversation_id}/events/{event_id}",
    response_model=EventResponse,
)
@limiter.limit(settings.rate_limit_discover)
async def update_chat_event(
    request: Request,
    conversation_id: str = Path(...),
    event_id: str = Path(...),
    payload: UpdateEventStatusRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> EventResponse:
    """Update chat event.

        Args:
            request: update chat event.
            conversation_id: update chat event.
            event_id: update chat event.
            payload: update chat event.
            _device: update chat event.
            user_id: update chat event.

        Returns:
            EventResponse: Result value.
        """
    _ = request
    try:
        event = await asyncio.to_thread(fetch_event, event_id)
        if event is None or str(event.get("conversation_id")) != conversation_id:
            raise HTTPException(status_code=404, detail="Event not found.")

        _validate_event_status_transition(
            current_status=str(event.get("status") or ""),
            new_status=payload.status,
            user_id=user_id,
            created_by=str(event.get("created_by") or ""),
        )

        conversation = await asyncio.to_thread(
            fetch_conversation_participants, conversation_id,
        )
        if conversation is None:
            raise HTTPException(status_code=404, detail="Conversation not found.")
        if user_id not in (
            str(conversation.get("user_a_id") or ""),
            str(conversation.get("user_b_id") or ""),
        ):
            raise HTTPException(
                status_code=403,
                detail="Not a participant of this conversation.",
            )

        updated = await asyncio.to_thread(
            update_event_status, event_id, payload.status,
        )
        if updated is None:
            raise HTTPException(status_code=404, detail="Event not found.")

        return EventResponse(
            event_id=str(updated["id"]),
            message_id=str(updated.get("message_id") or event.get("message_id") or ""),
            conversation_id=conversation_id,
            event_time=updated["event_time"],
            location_lat=updated.get("location_lat"),
            location_lng=updated.get("location_lng"),
            location_label=updated.get("location_label"),
            status=updated["status"],
            created_at=updated.get("created_at") or utcnow(),
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure updating event",
            extra={"user_id": user_id, "event_id": event_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err
    except HTTPException:
        raise
