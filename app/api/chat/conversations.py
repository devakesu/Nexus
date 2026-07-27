"""Active chat conversation listing, candidate lookup, and creation endpoints."""

import asyncio
import logging
from typing import Annotated, Any, cast

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request

from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.core.config import DiscoveryTab, settings
from app.core.infra.limiter import limiter
from app.db.chat import (
    fetch_conversations_for_user,
    fetch_started_match_ids,
    get_or_create_conversation,
)
from app.db.client import DatabaseAccessError, supabase_client
from app.db.discovery import fetch_matches_for_user, get_cached_active_block_ids
from app.db.profiles import decrypt_profile_rows
from app.models import (
    ChatCandidateItem,
    ChatCandidatesResponse,
    ChatConversationItem,
    ChatsListResponse,
    CreateChatRequest,
    CreateChatResponse,
)

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
    """Fetches active chat conversations for the caller in the specified discovery tab."""
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
    except DatabaseAccessError as err:
        logger.exception("Database failure listing chats", extra={"user_id": user_id})
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err


@router.get("/api/v1/chats/candidates", response_model=ChatCandidatesResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_chat_candidates(
    request: Request,
    tab: Annotated[DiscoveryTab, Query()] = "Dating",
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> ChatCandidatesResponse:
    """Fetches candidate matches eligible to start a new chat conversation."""
    _ = request
    try:
        candidate_rows = await asyncio.to_thread(fetch_matches_for_user, user_id, tab)
        if not candidate_rows:
            return ChatCandidatesResponse(candidates=[])

        started_match_ids = await asyncio.to_thread(fetch_started_match_ids, user_id)
        candidate_rows = [
            r for r in candidate_rows if str(r.get("match_id")) not in started_match_ids
        ]
        if not candidate_rows:
            return ChatCandidatesResponse(candidates=[])

        block_ids = await get_cached_active_block_ids(user_id)
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
    payload: CreateChatRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> CreateChatResponse:
    """Idempotently creates or retrieves an active E2EE conversation for a mutual match."""
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
