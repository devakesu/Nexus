import asyncio
import logging
from typing import Annotated, Any, cast

from fastapi import APIRouter, Body, Depends, HTTPException, Path, Query, Request

from app.api.dependencies import get_authenticated_user_id, verify_app_check_token
from app.core.config import DiscoveryTab, settings
from app.core.limiter import limiter
from app.db.chat import (
    fetch_conversation_participants,
    fetch_conversations_for_user,
    fetch_started_match_ids,
    get_or_create_conversation,
    insert_message,
)
from app.db.client import DatabaseAccessError, supabase_client
from app.db.matches import fetch_matches_for_user
from app.db.profiles import decrypt_profile_rows
from app.models import (
    ChatCandidateItem,
    ChatCandidatesResponse,
    ChatConversationItem,
    ChatsListResponse,
    CreateChatRequest,
    CreateChatResponse,
    SendMessageRequest,
    SendMessageResponse,
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
    user_id: str = Depends(get_authenticated_user_id),
) -> ChatsListResponse:
    _ = request
    try:
        rows = await asyncio.to_thread(fetch_conversations_for_user, user_id, tab)

        if not rows:
            return ChatsListResponse(conversations=[])

        counterpart_ids = [
            str(r["matched_user_id"]) for r in rows if r.get("matched_user_id")
        ]

        profiles_res = await asyncio.to_thread(
            lambda: supabase_client.table("profiles")
            .select("id, name, age, profile_pic")
            .in_("id", counterpart_ids)
            .eq("is_deactivated", False)
            .execute(),
        )
        profile_map = decrypt_profile_rows(cast(list[Any], profiles_res.data or []))

        items: list[ChatConversationItem] = []
        for row in rows:
            uid = str(row.get("matched_user_id") or "")
            profile = profile_map.get(uid, {})
            items.append(
                ChatConversationItem(
                    conversation_id=str(row.get("conversation_id") or ""),
                    matched_user_id=uid,
                    name=profile.get("name"),
                    age=profile.get("age"),
                    profile_pic=profile.get("profile_pic"),
                    last_message_at=row["last_message_at"],
                ),
            )

        return ChatsListResponse(conversations=items)

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
    user_id: str = Depends(get_authenticated_user_id),
) -> ChatCandidatesResponse:
    """Matches in this tab that have no conversation started yet."""
    _ = request
    try:
        matches, started_match_ids = await asyncio.gather(
            asyncio.to_thread(fetch_matches_for_user, user_id, tab),
            asyncio.to_thread(fetch_started_match_ids, user_id, tab),
        )

        candidate_rows = [
            m for m in matches if str(m.get("match_id")) not in started_match_ids
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
    user_id: str = Depends(get_authenticated_user_id),
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
    user_id: str = Depends(get_authenticated_user_id),
) -> SendMessageResponse:
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
        asyncio.create_task(
            send_chat_message_notification(
                sender_id=user_id,
                recipient_id=recipient_id,
                conversation_id=conversation_id,
                tab=str(conversation.get("tab") or "Dating"),
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
