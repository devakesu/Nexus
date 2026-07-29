"""Background job scheduler and periodic task manager.

Uses APScheduler to execute background cron routines including meetup event reminders,
safety check-in escalations, FCM notification dispatches, and account deletion purges.
"""

import asyncio
import logging
from datetime import timedelta
from typing import Any, cast

import sentry_sdk
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app.core.config import settings
from app.core.utils.sms import (
    compose_unreachable_message,
    make_escalation_cancel_token,
    send_sms,
)
from app.db.chat import (
    fetch_conversation_participants,
    fetch_due_event_reminders,
    fetch_due_safety_reminders,
    mark_reminder_sent,
    mark_safety_reminder_sent,
)
from app.db.client import DatabaseAccessError, parse_utc_datetime, utcnow
from app.db.safety import (
    fetch_overdue_safety_sessions,
    fetch_safety_contacts,
    purge_expired_safety_evidence,
    purge_safety_data_for_purged_accounts,
    record_safety_escalation_sent,
)
from app.db.users import (
    expire_blocklist_entries,
    hard_purge_long_tail_accounts,
    purge_due_accounts,
)
from app.services.fcm_sender import (
    send_chat_event_reminder_notification,
    send_meetup_safety_reminder_notification,
)

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
    """Polls for upcoming chat event reminders due within the lookahead window, dispatches push
    notifications to both conversation participants, and marks reminders as sent in the database.
    On database access failure, captures the exception to Sentry and logs error before returning.
    """
    try:
        due_events = await asyncio.to_thread(
            fetch_due_event_reminders, _REMINDER_WINDOW_MINUTES,
        )
    except DatabaseAccessError as err:
        sentry_sdk.capture_exception(err)
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
        except DatabaseAccessError as err:
            sentry_sdk.capture_exception(err)
            logger.exception(
                "Failed to process event reminder", extra={"event_id": event_id},
            )


# Meetup Safety auto-configure (Milestone F): lookahead/poll for the
# creator-only "turns on soon" push. Tighter window than the general event
# reminder above since the copy promises "~30 minutes", not "sometime soon".
_SAFETY_EVENT_REMINDER_WINDOW_MINUTES = 35
_SAFETY_EVENT_REMINDER_POLL_MINUTES = 10


async def _check_upcoming_safety_reminders() -> None:
    """Polls for upcoming meetup safety check-in reminders due within the 35-minute lookahead window,
    dispatches push notifications to event creators, and marks safety reminders as sent in the database.
    On database access failure, captures the exception to Sentry and logs error before returning.
    """
    try:
        due_events = await asyncio.to_thread(
            fetch_due_safety_reminders, _SAFETY_EVENT_REMINDER_WINDOW_MINUTES,
        )
    except DatabaseAccessError as err:
        sentry_sdk.capture_exception(err)
        logger.exception("Failed to fetch due meetup safety reminders")
        return

    for event in due_events:
        event_id = str(event.get("id") or "")
        conversation_id = str(event.get("conversation_id") or "")
        created_by = str(event.get("created_by") or "")
        try:
            conversation = await asyncio.to_thread(
                fetch_conversation_participants, conversation_id,
            )
            if conversation is None:
                continue
            user_a_id = str(conversation.get("user_a_id") or "")
            user_b_id = str(conversation.get("user_b_id") or "")
            peer_id = user_b_id if created_by == user_a_id else user_a_id
            await send_meetup_safety_reminder_notification(
                user_id=created_by,
                peer_id=peer_id,
                conversation_id=conversation_id,
                tab=str(conversation.get("tab") or "Dating"),
            )
            await asyncio.to_thread(mark_safety_reminder_sent, event_id)
        except DatabaseAccessError as err:
            sentry_sdk.capture_exception(err)
            logger.exception(
                "Failed to process meetup safety reminder",
                extra={"event_id": event_id},
            )


# Meetup Safety dead-man's-switch: how overdue a check-in must be (past its
# deadline) before the first escalation fires, and how often this job polls
# for overdue sessions. Subsequent escalations (2nd, 3rd) are spaced by each
# session's own interval_seconds instead of this poll interval - see the
# per-session cadence check in _check_overdue_safety_sessions.
_SAFETY_ESCALATION_GRACE_SECONDS = 5 * 60
_SAFETY_POLL_INTERVAL_MINUTES = 5


def _next_escalation_due(session: dict[str, Any], now: Any) -> bool:
    """A session is only fetched here once it's past next_checkin_at by the
    grace window, so escalations_sent==0 is always due. Later escalations are
    spaced by the session's own interval_seconds instead - "once per check-in
    interval", per the Meetup Safety plan.
    """
    escalations_sent = int(session.get("escalations_sent") or 0)
    if escalations_sent == 0:
        return True
    last_escalated_raw = session.get("last_escalated_at")
    if not last_escalated_raw:
        return False
    interval_seconds = int(session.get("interval_seconds") or 0)
    last_escalated = parse_utc_datetime(last_escalated_raw)
    return now >= last_escalated + timedelta(seconds=interval_seconds)


async def _escalate_safety_session(session: dict[str, Any]) -> None:
    """Escalate safety session.

        Args:
            session: Input session parameter."""
    session_id = str(session.get("id") or "")
    escalations_sent = int(session.get("escalations_sent") or 0)

    try:
        contacts = await asyncio.to_thread(
            fetch_safety_contacts, str(session.get("user_id") or ""),
        )
    except DatabaseAccessError:
        logger.exception(
            "Failed to fetch contacts for overdue safety session",
            extra={"session_id": session_id},
        )
        return

    if not contacts:
        return

    event_context = session.get("event_context")
    event_label = (
        cast(dict[str, Any], event_context).get("label")
        if isinstance(event_context, dict)
        else None
    )
    escalation_number = escalations_sent + 1
    token = make_escalation_cancel_token(session_id)
    cancel_link = (
        f"{settings.backend_url}/api/v1/safety/escalation/"
        f"{session_id}/cancel?token={token}&reason=safe"
    )

    body = compose_unreachable_message(
        name=session.get("label") or "A Nexus user",
        escalation_number=escalation_number,
        battery_percent=session.get("battery_percent"),
        connection_type=session.get("connection_type"),
        event_label=event_label,
        cancel_link=cancel_link,
    )

    notified = False
    for contact in contacts:
        result = await send_sms(contact["phone"], body)
        notified = notified or result.success

    if not notified:
        sentry_sdk.capture_message(
            "CRITICAL: All SMS deliveries failed for overdue safety session",
            level="error",
            extras={"session_id": session_id},
        )
        logger.error(
            "Failed to reach any trusted contact for an overdue safety session",
            extra={"session_id": session_id},
        )
        return

    try:
        await asyncio.to_thread(
            record_safety_escalation_sent, session_id, escalation_number,
        )
    except DatabaseAccessError as err:
        sentry_sdk.capture_exception(err)
        logger.exception(
            "Failed to record safety escalation",
            extra={"session_id": session_id},
        )


async def _check_overdue_safety_sessions() -> None:
    """Check overdue safety sessions."""
    try:
        overdue = await asyncio.to_thread(
            fetch_overdue_safety_sessions, _SAFETY_ESCALATION_GRACE_SECONDS,
        )
    except DatabaseAccessError as err:
        sentry_sdk.capture_exception(err)
        logger.exception("Failed to fetch overdue safety sessions")
        return

    now = utcnow()
    for session in overdue:
        if _next_escalation_due(session, now):
            await _escalate_safety_session(session)


# Account deletion (Tier 1 grace-window purge, Tier-1 blocklist expiry, and
# Tier-2 long-tail hard purge) - see app/db/account_deletion.py. All three
# are naturally idempotent (purged_at/age-based filters, expiry-based
# DELETE, and delete_user on an already-gone id is a no-op), so the
# single-instance caveat above doesn't block correctness here even though
# it still applies if this service is ever scaled to multiple replicas.
_ACCOUNT_DELETION_POLL_HOURS = 24


async def _run_account_deletion_purge() -> None:
    """Run account deletion purge."""
    try:
        await asyncio.to_thread(purge_due_accounts)
    except DatabaseAccessError as err:
        sentry_sdk.capture_exception(err)
        logger.exception("Failed to run account deletion purge")


async def _run_blocklist_expiry() -> None:
    """Run blocklist expiry."""
    try:
        await asyncio.to_thread(expire_blocklist_entries)
    except DatabaseAccessError as err:
        sentry_sdk.capture_exception(err)
        logger.exception("Failed to expire deleted-account blocklist entries")


async def _run_account_deletion_long_tail_purge() -> None:
    """Run account deletion long tail purge."""
    try:
        await asyncio.to_thread(hard_purge_long_tail_accounts)
    except DatabaseAccessError as err:
        sentry_sdk.capture_exception(err)
        logger.exception("Failed to run account deletion long-tail purge")


# Meetup Safety data retention - see app/db/safety.py for the reasoning
# behind each window. Same 24h cadence as the account deletion jobs above;
# both are cheap, bounded batch scans.
async def _run_safety_evidence_retention_purge() -> None:
    """Run safety evidence retention purge."""
    try:
        await asyncio.to_thread(purge_expired_safety_evidence)
    except DatabaseAccessError as err:
        sentry_sdk.capture_exception(err)
        logger.exception("Failed to run safety evidence retention purge")


async def _run_safety_data_legal_hold_purge() -> None:
    """Run safety data legal hold purge."""
    try:
        await asyncio.to_thread(purge_safety_data_for_purged_accounts)
    except DatabaseAccessError as err:
        sentry_sdk.capture_exception(err)
        logger.exception("Failed to run safety data legal-hold purge")


def start_reminder_scheduler() -> AsyncIOScheduler:
    """Executes start reminder scheduler operation.

        Returns:
            AsyncIOScheduler: Response payload or result."""
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
    scheduler_any.add_job(
        _check_upcoming_safety_reminders,
        trigger=IntervalTrigger(minutes=_SAFETY_EVENT_REMINDER_POLL_MINUTES),
        id="chat_event_safety_reminders",
        max_instances=1,
    )
    scheduler_any.add_job(
        _check_overdue_safety_sessions,
        trigger=IntervalTrigger(minutes=_SAFETY_POLL_INTERVAL_MINUTES),
        id="meetup_safety_escalations",
        max_instances=1,
    )
    scheduler_any.add_job(
        _run_account_deletion_purge,
        trigger=IntervalTrigger(hours=_ACCOUNT_DELETION_POLL_HOURS),
        id="account_deletion_purge",
        max_instances=1,
    )
    scheduler_any.add_job(
        _run_blocklist_expiry,
        trigger=IntervalTrigger(hours=_ACCOUNT_DELETION_POLL_HOURS),
        id="deleted_account_blocklist_expiry",
        max_instances=1,
    )
    scheduler_any.add_job(
        _run_account_deletion_long_tail_purge,
        trigger=IntervalTrigger(hours=_ACCOUNT_DELETION_POLL_HOURS),
        id="account_deletion_long_tail_purge",
        max_instances=1,
    )
    scheduler_any.add_job(
        _run_safety_evidence_retention_purge,
        trigger=IntervalTrigger(hours=_ACCOUNT_DELETION_POLL_HOURS),
        id="safety_evidence_retention_purge",
        max_instances=1,
    )
    scheduler_any.add_job(
        _run_safety_data_legal_hold_purge,
        trigger=IntervalTrigger(hours=_ACCOUNT_DELETION_POLL_HOURS),
        id="safety_data_legal_hold_purge",
        max_instances=1,
    )
    try:
        scheduler.start()
        _scheduler = scheduler
        logger.info("Chat event reminder scheduler started")
    except Exception as err:
        sentry_sdk.capture_exception(err)
        logger.exception("Failed to start reminder scheduler")
        raise
    return scheduler


def stop_reminder_scheduler() -> None:
    """Executes stop reminder scheduler operation."""
    global _scheduler
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
