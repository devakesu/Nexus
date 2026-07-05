import asyncio
import logging
from typing import Any

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app.db.chat import (
    fetch_conversation_participants,
    fetch_due_event_reminders,
    mark_reminder_sent,
)
from app.db.client import DatabaseAccessError
from app.services.fcm_sender import send_chat_event_reminder_notification

logger = logging.getLogger(__name__)

_scheduler: AsyncIOScheduler | None = None

# Look ahead this far for events needing a reminder; poll this often. A
# 60-minute lookahead + 15-minute poll means each event's reminder fires
# somewhere in the [45, 60]-minutes-before-start window.
#
# In-process scheduler: only safe with a single backend instance. If this
# service is ever scaled to multiple replicas, add a leader-election lock
# (e.g. a Postgres advisory lock) before firing, or switch to pg_cron.
_REMINDER_WINDOW_MINUTES = 60
_POLL_INTERVAL_MINUTES = 15


async def _check_due_reminders() -> None:
    try:
        due_events = await asyncio.to_thread(
            fetch_due_event_reminders, _REMINDER_WINDOW_MINUTES,
        )
    except DatabaseAccessError:
        logger.exception("Failed to fetch due event reminders")
        return

    for event in due_events:
        event_id = str(event.get("id") or "")
        conversation_id = str(event.get("conversation_id") or "")
        location_label = event.get("location_label")
        try:
            conversation = await asyncio.to_thread(
                fetch_conversation_participants, conversation_id,
            )
            if conversation is None:
                continue
            await send_chat_event_reminder_notification(
                user_a_id=str(conversation.get("user_a_id") or ""),
                user_b_id=str(conversation.get("user_b_id") or ""),
                conversation_id=conversation_id,
                tab=str(conversation.get("tab") or "Dating"),
                location_label=location_label,
            )
            await asyncio.to_thread(mark_reminder_sent, event_id)
        except DatabaseAccessError:
            logger.exception(
                "Failed to process event reminder", extra={"event_id": event_id},
            )


def start_reminder_scheduler() -> AsyncIOScheduler:
    global _scheduler
    if _scheduler is not None:
        return _scheduler
    scheduler = AsyncIOScheduler()
    # apscheduler ships without type stubs; cast to Any to keep Pyright happy,
    # matching the same pattern used for firebase_admin in fcm_sender.py.
    scheduler_any: Any = scheduler
    scheduler_any.add_job(
        _check_due_reminders,
        trigger=IntervalTrigger(minutes=_POLL_INTERVAL_MINUTES),
        id="chat_event_reminders",
        max_instances=1,
    )
    scheduler.start()
    _scheduler = scheduler
    logger.info("Chat event reminder scheduler started")
    return scheduler


def stop_reminder_scheduler() -> None:
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
