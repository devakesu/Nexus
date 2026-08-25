"""Encrypted message dispatch and read receipt management endpoints."""

import asyncio
import hashlib
import logging

from fastapi import APIRouter, Body, Depends, HTTPException, Path, Request

from app.api.dependencies import (
    get_active_user_id,
    verify_app_check_token,
    verify_app_check_with_replay_protection,
)
from app.core.config import settings
from app.core.infra.cache import redis_client
from app.core.infra.limiter import limiter
from app.core.infra.tasks import safe_create_task
from app.db.chat import (
    ConversationClosedError,
    fetch_conversation_participants,
    fetch_user_share_flags,
    insert_message,
    mark_messages_read,
)
from app.db.client import DatabaseAccessError
from app.db.discovery import get_cached_active_block_ids
from app.models import (
    MarkMessagesReadResponse,
    SendMessageRequest,
    SendMessageResponse,
)
from app.services.fcm_sender import send_chat_message_notification

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post(
    "/api/v1/chats/{conversation_id}/messages",
    response_model=SendMessageResponse,
)
@limiter.limit(settings.rate_limit_chat)
async def send_message(
    request: Request,
    conversation_id: str = Path(...),
    payload: SendMessageRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_active_user_id),
) -> SendMessageResponse:
    """Sends an end-to-end encrypted message in an active conversation and triggers push notifications."""
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

        recipient_id = user_b_id if user_id == user_a_id else user_a_id
        recipient_block_ids = await get_cached_active_block_ids(recipient_id)
        if user_id in recipient_block_ids:
            raise HTTPException(
                status_code=403,
                detail="Not a participant of this conversation.",
            )
        sender_block_ids = await get_cached_active_block_ids(user_id)
        if recipient_id in sender_block_ids:
            raise HTTPException(
                status_code=403,
                detail="Not a participant of this conversation.",
            )

        # Replay & Deduplication Protection:
        # Check both client_message_id idempotency and ciphertext hash
        ct_hash = hashlib.sha256(payload.ciphertext.encode()).hexdigest()
        hash_key = f"chat:msg_hash:{conversation_id}:{ct_hash}"

        try:
            if payload.client_message_id:
                client_id_key = f"chat:msg_idempotency:{conversation_id}:{payload.client_message_id}"
                id_acquired = await redis_client.set(client_id_key, "1", ex=86400, nx=True)
                if not id_acquired:
                    logger.warning(
                        "Duplicate client_message_id detected in chat",
                        extra={"conversation_id": conversation_id, "client_message_id": payload.client_message_id},
                    )
                    raise HTTPException(
                        status_code=409,
                        detail="Duplicate message submission.",
                    )

            hash_acquired = await redis_client.set(hash_key, "1", ex=86400, nx=True)
            if not hash_acquired:
                logger.warning(
                    "Duplicate ciphertext replay detected in chat",
                    extra={"conversation_id": conversation_id},
                )
                raise HTTPException(
                    status_code=409,
                    detail="Duplicate message submission.",
                )
        except HTTPException:
            raise
        except Exception:
            logger.debug("Redis error checking message replay protection, proceeding without check")

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
    except ConversationClosedError as err:
        logger.warning(
            "Message rejected because conversation is closed",
            extra={"user_id": user_id, "conversation_id": conversation_id},
        )
        raise HTTPException(
            status_code=403,
            detail="This conversation is closed.",
        ) from err
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


@router.patch(
    "/api/v1/chats/{conversation_id}/messages/read",
    response_model=MarkMessagesReadResponse,
)
@limiter.limit(settings.rate_limit_read_receipts)
async def mark_conversation_messages_read(
    request: Request,
    conversation_id: str = Path(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> MarkMessagesReadResponse:
    """Marks conversation messages as read according to user read-receipt privacy settings."""
    _ = request
    try:
        conversation = await asyncio.to_thread(
            fetch_conversation_participants, conversation_id,
        )
        if conversation is None:
            raise HTTPException(status_code=404, detail="Conversation not found.")

        if conversation.get("closed_at") is not None:
            raise HTTPException(
                status_code=400,
                detail="Conversation is closed.",
            )

        user_a_id = str(conversation.get("user_a_id") or "")
        user_b_id = str(conversation.get("user_b_id") or "")
        if user_id not in (user_a_id, user_b_id):
            raise HTTPException(
                status_code=403,
                detail="Not a participant of this conversation.",
            )

        recipient_id = user_b_id if user_id == user_a_id else user_a_id
        recipient_block_ids = await get_cached_active_block_ids(recipient_id)
        if user_id in recipient_block_ids:
            raise HTTPException(
                status_code=403,
                detail="Not a participant of this conversation.",
            )
        sender_block_ids = await get_cached_active_block_ids(user_id)
        if recipient_id in sender_block_ids:
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
