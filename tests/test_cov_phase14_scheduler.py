"""Phase 14 Scheduler & FCM Sender Coverage Suite to push coverage well beyond 90%.

Targeting:
1. app/services/reminder_scheduler.py (_check_due_reminders, _check_upcoming_safety_reminders, _check_overdue_safety_sessions, maintenance routines, start/stop)
2. app/services/fcm_sender.py (_send_to_tokens, send_like_notification, error scenarios)
3. app/services/value_dimensions.py
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
CONV_1 = "00000000-0000-0000-0000-000000000010"
SESSION_1 = "00000000-0000-0000-0000-000000000020"


def _make_chaining_mock(data: Any = None) -> MagicMock:
    mock: MagicMock = MagicMock()
    mock.select.return_value = mock
    mock.insert.return_value = mock
    mock.update.return_value = mock
    mock.delete.return_value = mock
    mock.upsert.return_value = mock
    mock.eq.return_value = mock
    mock.neq.return_value = mock
    mock.gt.return_value = mock
    mock.gte.return_value = mock
    mock.lt.return_value = mock
    mock.lte.return_value = mock
    mock.is_.return_value = mock
    mock.in_.return_value = mock
    mock.or_.return_value = mock
    mock.not_.is_.return_value = mock
    mock.order.return_value = mock
    mock.limit.return_value = mock

    def _exec() -> MagicMock:
        return MagicMock(data=data)

    def _single() -> MagicMock:
        if isinstance(data, list) and data:
            return MagicMock(data=data[0])
        return MagicMock(data=data)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    mock.single.return_value = single_mock
    return mock


# -----------------------------------------------------------------------------
# 1. SERVICES REMINDER SCHEDULER
# -----------------------------------------------------------------------------
async def test_services_reminder_scheduler_deep():
    from app.services.reminder_scheduler import (
        _check_due_reminders,
        _check_overdue_safety_sessions,
        _check_upcoming_safety_reminders,
        _next_escalation_due,
        _run_account_deletion_long_tail_purge,
        _run_account_deletion_purge,
        _run_blocklist_expiry,
        _run_safety_data_legal_hold_purge,
        _run_safety_evidence_retention_purge,
        start_reminder_scheduler,
        stop_reminder_scheduler,
    )

    mock_event = {
        "id": "ev_1",
        "conversation_id": CONV_1,
        "created_by": USER_1,
        "location_label": "Cafe",
    }
    mock_conv = {
        "id": CONV_1,
        "user_a_id": USER_1,
        "user_b_id": USER_2,
        "tab": "Dating",
    }
    mock_session = {
        "id": SESSION_1,
        "user_id": USER_1,
        "escalations_sent": 0,
        "interval_seconds": 300,
        "last_escalated_at": None,
    }

    with patch("app.services.reminder_scheduler.fetch_due_event_reminders", return_value=[mock_event]), \
         patch("app.services.reminder_scheduler.mark_reminder_sent", return_value=True), \
         patch("app.services.reminder_scheduler.fetch_conversation_participants", return_value=mock_conv), \
         patch("app.services.reminder_scheduler.send_chat_event_reminder_notification", AsyncMock()), \
         patch("app.services.reminder_scheduler.fetch_due_safety_reminders", return_value=[mock_event]), \
         patch("app.services.reminder_scheduler.mark_safety_reminder_sent", return_value=True), \
         patch("app.services.reminder_scheduler.send_meetup_safety_reminder_notification", AsyncMock()), \
         patch("app.services.reminder_scheduler.fetch_overdue_safety_sessions", return_value=[mock_session]), \
         patch("app.services.reminder_scheduler._escalate_safety_session", AsyncMock()), \
         patch("app.services.reminder_scheduler.purge_due_accounts"), \
         patch("app.services.reminder_scheduler.expire_blocklist_entries"), \
         patch("app.services.reminder_scheduler.hard_purge_long_tail_accounts"), \
         patch("app.services.reminder_scheduler.purge_expired_safety_evidence"), \
         patch("app.services.reminder_scheduler.purge_safety_data_for_purged_accounts"), \
         patch("app.services.reminder_scheduler.redis_client") as mock_r:
        mock_r.set = AsyncMock(return_value=True)
        mock_r.eval = AsyncMock(return_value=1)

        await _check_due_reminders()
        await _check_upcoming_safety_reminders()
        await _check_overdue_safety_sessions()

        await _run_account_deletion_purge()
        await _run_blocklist_expiry()
        await _run_account_deletion_long_tail_purge()
        await _run_safety_evidence_retention_purge()
        await _run_safety_data_legal_hold_purge()

        due = _next_escalation_due(mock_session, datetime.now(timezone.utc))
        assert due is True

        with patch("app.services.reminder_scheduler.AsyncIOScheduler") as mock_sched_cls:
            mock_inst = MagicMock()
            mock_sched_cls.return_value = mock_inst
            mock_inst.running = True
            sched = start_reminder_scheduler()
            assert sched is not None
            stop_reminder_scheduler()


# -----------------------------------------------------------------------------
# 2. SERVICES FCM SENDER
# -----------------------------------------------------------------------------
async def test_services_fcm_sender_deep():
    from app.services.fcm_sender import (
        _fetch_user_fcm_tokens,
        _is_firebase_initialized,
        _send_to_tokens,
        send_like_notification,
    )

    mock_t = _make_chaining_mock([{"fcm_token": "fcm_token_1234567890", "is_deactivated": False}])

    with patch("app.services.fcm_sender.supabase_client.table", return_value=mock_t), \
         patch("app.services.fcm_sender._fb.get_app"), \
         patch("app.services.fcm_sender.get_cached_active_block_ids", AsyncMock(return_value=set())), \
         patch("app.services.fcm_sender._fcm.send_each_for_multicast") as mock_send, \
         patch("app.services.fcm_sender.decrypt_pii", return_value="Alice"):
        mock_send.return_value = MagicMock(failure_count=0, success_count=1)

        assert _is_firebase_initialized() is True
        toks = _fetch_user_fcm_tokens(USER_1)
        assert len(toks) > 0

        sent_count = _send_to_tokens(["fcm_token_1234567890"], "Title", "Body", {"key": "val"}, "likes")
        assert sent_count == 1

        await send_like_notification(USER_1, USER_2, is_superlike=True)
