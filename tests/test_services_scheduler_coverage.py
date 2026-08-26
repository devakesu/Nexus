"""Test coverage suite for Reminder Scheduler and Periodic Maintenance services.

Covers:
- app/services/reminder_scheduler.py
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from apscheduler.schedulers.asyncio import AsyncIOScheduler

from app.db.client import DatabaseAccessError
from app.services.reminder_scheduler import (
    _acquire_escalation_idempotency,
    _check_due_reminders,
    _check_overdue_safety_sessions,
    _check_upcoming_safety_reminders,
    _compose_session_unreachable_message,
    _dispatch_escalation_sms_and_record,
    _escalate_safety_session,
    _mask_id,
    _next_escalation_due,
    _run_account_deletion_long_tail_purge,
    _run_account_deletion_purge,
    _run_blocklist_expiry,
    _run_in_maintenance_executor,
    _run_safety_data_legal_hold_purge,
    _run_safety_evidence_retention_purge,
    get_maintenance_executor,
    start_reminder_scheduler,
    stop_reminder_scheduler,
    with_distributed_lock,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
SESSION_1 = "00000000-0000-0000-0000-000000000011"
EVENT_1 = "00000000-0000-0000-0000-000000000022"


# ==============================================================================
# 1. SCHEDULER UTILITIES & DISTRIBUTED LOCKS
# ==============================================================================

async def test_scheduler_utils_and_distributed_lock():
    # _mask_id
    assert _mask_id("") == ""
    assert _mask_id("12345") == "***"
    assert _mask_id("123456789") == "1234...6789"

    # with_distributed_lock - acquired
    mock_lock = AsyncMock()
    mock_lock.acquire.return_value = True
    mock_lock.release.return_value = None

    called = False

    @with_distributed_lock("test_job", ttl_seconds=10)
    async def sample_job():
        nonlocal called
        called = True

    with patch("app.services.reminder_scheduler.redis_client.lock", return_value=mock_lock):
        await sample_job()
        assert called is True
        mock_lock.acquire.assert_called_once()
        mock_lock.release.assert_called_once()

    # with_distributed_lock - not acquired
    called_skip = False

    @with_distributed_lock("test_job_skip", ttl_seconds=10)
    async def sample_job_skip():
        nonlocal called_skip
        called_skip = True

    mock_lock.acquire.return_value = False
    with patch("app.services.reminder_scheduler.redis_client.lock", return_value=mock_lock):
        await sample_job_skip()
        assert called_skip is False

    # with_distributed_lock - redis error
    mock_lock.acquire.side_effect = Exception("Redis connection failed")
    with patch("app.services.reminder_scheduler.redis_client.lock", return_value=mock_lock), \
         patch("sentry_sdk.capture_exception"):
        await sample_job_skip()


# ==============================================================================
# 2. CHAT & MEETUP REMINDERS
# ==============================================================================

async def test_chat_and_meetup_reminders():
    # _check_due_reminders success
    mock_events = [{"id": EVENT_1, "conversation_id": "c1", "location_label": "Cafe"}]
    mock_conv = {"user_a_id": USER_1, "user_b_id": "u2", "tab": "Dating"}
    with patch("app.services.reminder_scheduler.fetch_due_event_reminders", return_value=mock_events), \
         patch("app.services.reminder_scheduler.mark_reminder_sent", return_value=True), \
         patch("app.services.reminder_scheduler.fetch_conversation_participants", return_value=mock_conv), \
         patch("app.services.reminder_scheduler.send_chat_event_reminder_notification", new_callable=AsyncMock) as mock_send, \
         patch("app.services.reminder_scheduler.redis_client.lock") as mock_lock:
        mock_lock.return_value.acquire = AsyncMock(return_value=True)
        mock_lock.return_value.release = AsyncMock()
        await _check_due_reminders()
        mock_send.assert_called_once()

    # _check_due_reminders DB error
    with patch("app.services.reminder_scheduler.fetch_due_event_reminders", side_effect=DatabaseAccessError("DB fail")), \
         patch("sentry_sdk.capture_exception"), \
         patch("app.services.reminder_scheduler.redis_client.lock") as mock_lock:
        mock_lock.return_value.acquire = AsyncMock(return_value=True)
        mock_lock.return_value.release = AsyncMock()
        await _check_due_reminders()

    # _check_upcoming_safety_reminders success
    mock_safety_events = [{"id": EVENT_1, "conversation_id": "c1", "created_by": USER_1}]
    with patch("app.services.reminder_scheduler.fetch_due_safety_reminders", return_value=mock_safety_events), \
         patch("app.services.reminder_scheduler.mark_safety_reminder_sent", return_value=True), \
         patch("app.services.reminder_scheduler.fetch_conversation_participants", return_value=mock_conv), \
         patch("app.services.reminder_scheduler.send_meetup_safety_reminder_notification", new_callable=AsyncMock) as mock_safety_send, \
         patch("app.services.reminder_scheduler.redis_client.lock") as mock_lock:
        mock_lock.return_value.acquire = AsyncMock(return_value=True)
        mock_lock.return_value.release = AsyncMock()
        await _check_upcoming_safety_reminders()
        mock_safety_send.assert_called_once()


# ==============================================================================
# 3. SAFETY ESCALATIONS
# ==============================================================================

async def test_safety_escalation_flow():
    now = datetime.now(timezone.utc)

    # _next_escalation_due
    assert _next_escalation_due({"escalations_sent": 0}, now) is True
    assert _next_escalation_due({"escalations_sent": 1, "last_escalated_at": None}, now) is False
    assert _next_escalation_due({
        "escalations_sent": 1,
        "last_escalated_at": (now - timedelta(minutes=20)).isoformat(),
        "interval_seconds": 900,
    }, now) is True

    # _acquire_escalation_idempotency
    with patch("app.services.reminder_scheduler.redis_client.set", new_callable=AsyncMock, return_value=True):
        assert await _acquire_escalation_idempotency(SESSION_1, 1) is True

    with patch("app.services.reminder_scheduler.redis_client.set", new_callable=AsyncMock, side_effect=Exception("Redis fail")), \
         patch("sentry_sdk.capture_exception"):
        assert await _acquire_escalation_idempotency(SESSION_1, 1) is False

    # _compose_session_unreachable_message
    msg = _compose_session_unreachable_message(
        session={"battery_percent": 75, "connection_type": "wifi", "label": "Coffee"},
        session_id=SESSION_1,
        escalation_number=1,
        user_name="Alice",
    )
    assert "Alice" in msg

    # _dispatch_escalation_sms_and_record
    contacts = [{"id": "c1", "phone": "+15551234567"}]
    with patch("app.services.reminder_scheduler.record_safety_escalation_sent", return_value=True), \
         patch("app.services.reminder_scheduler.fetch_contact_facing_profile_summary", return_value={"name": "Alice"}), \
         patch("app.services.reminder_scheduler.send_sms", new_callable=AsyncMock, return_value=MagicMock(success=True)):
        await _dispatch_escalation_sms_and_record(
            contacts=contacts,
            session={"user_id": USER_1},
            session_id=SESSION_1,
            escalation_number=1,
            idempotency_key="k1",
        )

    # _escalate_safety_session
    with patch("app.services.reminder_scheduler.fetch_safety_contacts_with_id", return_value=contacts), \
         patch("app.services.reminder_scheduler._acquire_escalation_idempotency", new_callable=AsyncMock, return_value=True), \
         patch("app.services.reminder_scheduler._dispatch_escalation_sms_and_record", new_callable=AsyncMock) as mock_dispatch:
        await _escalate_safety_session({"id": SESSION_1, "user_id": USER_1, "escalations_sent": 0})
        mock_dispatch.assert_called_once()

    # _check_overdue_safety_sessions
    overdue_sessions = [{"id": SESSION_1, "user_id": USER_1, "escalations_sent": 0}]
    with patch("app.services.reminder_scheduler.fetch_overdue_safety_sessions", return_value=overdue_sessions), \
         patch("app.services.reminder_scheduler._escalate_safety_session", new_callable=AsyncMock) as mock_esc, \
         patch("app.services.reminder_scheduler.redis_client.lock") as mock_lock:
        mock_lock.return_value.acquire = AsyncMock(return_value=True)
        mock_lock.return_value.release = AsyncMock()
        await _check_overdue_safety_sessions()
        mock_esc.assert_called_once()


# ==============================================================================
# 4. MAINTENANCE EXECUTOR & LIFECYCLE
# ==============================================================================

async def test_maintenance_purges_and_lifecycle():
    # get_maintenance_executor & _run_in_maintenance_executor
    exec_inst = get_maintenance_executor()
    assert exec_inst is not None

    def sample_sync_task(x: int) -> int:
        return x * 2

    res = await _run_in_maintenance_executor(sample_sync_task, 21)
    assert res == 42

    # Purge wrappers
    with patch("app.services.reminder_scheduler._run_in_maintenance_executor", new_callable=AsyncMock) as mock_run, \
         patch("app.services.reminder_scheduler.redis_client.lock") as mock_lock:
        mock_lock.return_value.acquire = AsyncMock(return_value=True)
        mock_lock.return_value.release = AsyncMock()

        await _run_account_deletion_purge()
        await _run_blocklist_expiry()
        await _run_account_deletion_long_tail_purge()
        await _run_safety_evidence_retention_purge()
        await _run_safety_data_legal_hold_purge()
        assert mock_run.call_count == 5

    # Lifecycle start & stop
    with patch.object(AsyncIOScheduler, "start") as mock_start, \
         patch.object(AsyncIOScheduler, "shutdown") as mock_shutdown, \
         patch.object(AsyncIOScheduler, "running", return_value=True):
        sched = start_reminder_scheduler()
        assert sched is not None
        mock_start.assert_called_once()

        stop_reminder_scheduler()
        mock_shutdown.assert_called_once()
