"""Meetup scheduling and event status transition endpoints."""

import asyncio
import logging

from fastapi import APIRouter, Body, Depends, HTTPException, Path, Request

from app.api.dependencies import (
    assert_safety_consent,
    get_active_user_id,
    get_cached_public_user,
    verify_app_check_token,
)
from app.core.config import settings
from app.core.infra.limiter import limiter
from app.core.infra.tasks import safe_create_task
from app.db.chat import (
    ConversationClosedError,
    create_event_with_message,
    fetch_conversation_participants,
    fetch_event,
    update_event_status,
)
from app.db.client import DatabaseAccessError, utcnow
from app.models import (
    CreateEventRequest,
    EventResponse,
    UpdateEventStatusRequest,
)
from app.services.fcm_sender import send_chat_message_notification

router = APIRouter()
logger = logging.getLogger(__name__)


def _validate_event_status_transition(
    current_status: str,
    new_status: str,
    user_id: str,
    created_by: str,
) -> None:
    """Validates permitted meetup event status state transitions."""
    if new_status == "proposed":
        raise HTTPException(
            status_code=400,
            detail="Cannot revert event to proposed status.",
        )

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


@router.post("/api/v1/chats/{conversation_id}/events", response_model=EventResponse)
@limiter.limit(settings.rate_limit_discover)
async def create_chat_event(
    request: Request,
    conversation_id: str = Path(...),
    payload: CreateEventRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> EventResponse:
    """Creates a date/plan proposal within a conversation."""
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
            user_row = await get_cached_public_user(user_id)
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
    except ConversationClosedError as err:
        logger.warning(
            "Event rejected because conversation is closed",
            extra={"user_id": user_id, "conversation_id": conversation_id},
        )
        raise HTTPException(
            status_code=403,
            detail="This conversation is closed.",
        ) from err
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


@router.patch(
    "/api/v1/chats/{conversation_id}/events/{event_id}",
    response_model=EventResponse,
)
@limiter.limit(settings.rate_limit_discover)
async def update_chat_event(
    request: Request,
    conversation_id: str = Path(...),
    event_id: str = Path(...),
    payload: UpdateEventStatusRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> EventResponse:
    """Updates meetup event status (proposed -> confirmed / cancelled)."""
    try:
        _ = request
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

        event = await asyncio.to_thread(fetch_event, event_id)
        if event is None or str(event.get("conversation_id")) != conversation_id:
            raise HTTPException(status_code=404, detail="Event not found.")

        _validate_event_status_transition(
            current_status=str(event.get("status") or ""),
            new_status=payload.status,
            user_id=user_id,
            created_by=str(event.get("created_by") or ""),
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
