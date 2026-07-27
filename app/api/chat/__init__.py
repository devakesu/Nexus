"""FastAPI router for real-time messaging, chat conversations, presence updates, and meetup scheduling.

Provides endpoints for listing active conversations, fetching and sending encrypted messages,
updating presence status, and creating meetup event proposals with automated reminders.
"""

from fastapi import APIRouter

from app.api.chat.conversations import (
    create_chat,
    get_chat_candidates,
    get_chats,
)
from app.api.chat.conversations import (
    router as conversations_router,
)
from app.api.chat.events import (
    _validate_event_status_transition,
    create_chat_event,
    update_chat_event,
)
from app.api.chat.events import (
    router as events_router,
)
from app.api.chat.messages import (
    mark_conversation_messages_read,
    send_message,
)
from app.api.chat.messages import (
    router as messages_router,
)
from app.api.chat.presence import (
    _PRESENCE_STALE_AFTER,
    get_presence,
    send_presence_heartbeat,
)
from app.api.chat.presence import (
    router as presence_router,
)

router = APIRouter()

router.include_router(conversations_router)
router.include_router(messages_router)
router.include_router(presence_router)
router.include_router(events_router)

__all__ = [
    "_PRESENCE_STALE_AFTER",
    "_validate_event_status_transition",
    "create_chat",
    "create_chat_event",
    "get_chat_candidates",
    "get_chats",
    "get_presence",
    "mark_conversation_messages_read",
    "router",
    "send_message",
    "send_presence_heartbeat",
    "update_chat_event",
]
