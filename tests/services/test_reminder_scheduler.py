"""Test Suite for Test Reminder Scheduler.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.db.client import DatabaseAccessError
from app.services.reminder_scheduler import (
    _acquire_escalation_idempotency,
    _compose_session_unreachable_message,
    _dispatch_escalation_sms_and_record,
    _mask_id,
    _next_escalation_due,
    _run_account_deletion_long_tail_purge,
    _run_account_deletion_purge,
    _run_blocklist_expiry,
    _run_safety_data_legal_hold_purge,
    _run_safety_evidence_retention_purge,
    start_reminder_scheduler,
    stop_reminder_scheduler,
    with_distributed_lock,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
SESS_1 = "00000000-0000-0000-0000-000000000040"
SESSION_1 = "00000000-0000-0000-0000-000000000020"
ALERT_1 = "00000000-0000-0000-0000-000000000010"
CONV_1 = "00000000-0000-0000-0000-000000000020"
CONVO_1 = "00000000-0000-0000-0000-000000000020"
MATCH_1 = "00000000-0000-0000-0000-000000000010"
MSG_1 = "00000000-0000-0000-0000-000000000020"
PHONE_VALID = "+14155552671"
REPORT_1 = "00000000-0000-0000-0000-000000000050"
EVENT_1 = "00000000-0000-0000-0000-000000000033"
CONTACT_1 = "00000000-0000-0000-0000-000000000030"


def _make_chaining_mock(
    data: Any = None, error: Exception | None = None,
) -> MagicMock:
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
    mock.range.return_value = mock
    mock.contains.return_value = mock
    mock.contained_by.return_value = mock
    mock.overlaps.return_value = mock

    def _exec() -> MagicMock:
        if error:
            raise error
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    def _single() -> MagicMock:
        if error:
            raise error
        if isinstance(data, list) and data:
            return MagicMock(data=copy.deepcopy(data[0]))
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    mock.single.return_value = single_mock
    return mock


def make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/test",
        "headers": [],
        "client": ("127.0.0.1", 12345),
        "app": MagicMock(),
    }
    return Request(scope)


def _make_mock_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/test",
        "headers": [(b"host", b"localhost"), (b"user-agent", b"pytest")],
        "client": ("127.0.0.1", 12345),
        "app": {},
    }
    return Request(scope)


def make_api_error(code: str = "P0001", message: str = "DB error") -> APIError:
    return APIError(
        {"code": code, "message": message, "details": "details", "hint": "hint"},
    )


pytestmark = pytest.mark.anyio


async def test_reminder_scheduler():
    from app.services.reminder_scheduler import (
        _check_due_reminders,
        _check_overdue_safety_sessions,
        _check_upcoming_safety_reminders,
        _compose_session_unreachable_message,
        _dispatch_escalation_sms_and_record,
        _next_escalation_due,
        _run_account_deletion_long_tail_purge,
        _run_account_deletion_purge,
        _run_blocklist_expiry,
        _run_safety_data_legal_hold_purge,
        _run_safety_evidence_retention_purge,
        start_reminder_scheduler,
    )

    # 1. _check_due_reminders
    with patch(
        "app.services.reminder_scheduler.fetch_due_event_reminders", return_value=[],
    ):
        await _check_due_reminders()

    # 2. _check_upcoming_safety_reminders
    with patch(
        "app.services.reminder_scheduler.fetch_due_safety_reminders", return_value=[],
    ):
        await _check_upcoming_safety_reminders()

    # 3. message composition & escalation checks
    session_dict: dict[str, Any] = {
        "id": SESS_1,
        "user_id": USER_1,
        "escalations_sent": 0,
        "escalation_cancelled_at": None,
        "label": "Coffee date",
        "event_context": {},
    }
    assert _next_escalation_due(session_dict, datetime.now(timezone.utc)) is True
    msg = _compose_session_unreachable_message(
        session_dict, SESS_1, 1, user_name="Alice",
    )
    assert "Alice" in msg

    # 4. _dispatch_escalation_sms_and_record
    with (
        patch(
            "app.services.reminder_scheduler.record_safety_escalation_sent",
            return_value=True,
        ),
        patch(
            "app.services.reminder_scheduler.fetch_contact_facing_profile_summary",
            return_value={"name": "Alice"},
        ),
        patch(
            "app.services.reminder_scheduler.send_sms",
            AsyncMock(return_value=MagicMock(success=True)),
        ),
    ):
        await _dispatch_escalation_sms_and_record(
            [{"id": "c1", "phone": "+15555555555"}], session_dict, SESS_1, 1, "idem_key",
        )

    # 5. _check_overdue_safety_sessions
    with patch(
        "app.services.reminder_scheduler.fetch_overdue_safety_sessions", return_value=[],
    ):
        await _check_overdue_safety_sessions()

    # 6. purges
    with patch(
        "app.services.reminder_scheduler._run_in_maintenance_executor", AsyncMock(),
    ):
        await _run_account_deletion_purge()
        await _run_blocklist_expiry()
        await _run_account_deletion_long_tail_purge()
        await _run_safety_evidence_retention_purge()
        await _run_safety_data_legal_hold_purge()

    # 7. start_reminder_scheduler
    sched = start_reminder_scheduler()
    assert sched is not None


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

    with (
        patch(
            "app.services.reminder_scheduler.fetch_due_event_reminders",
            return_value=[mock_event],
        ),
        patch("app.services.reminder_scheduler.mark_reminder_sent", return_value=True),
        patch(
            "app.services.reminder_scheduler.fetch_conversation_participants",
            return_value=mock_conv,
        ),
        patch(
            "app.services.reminder_scheduler.send_chat_event_reminder_notification",
            AsyncMock(),
        ),
        patch(
            "app.services.reminder_scheduler.fetch_due_safety_reminders",
            return_value=[mock_event],
        ),
        patch(
            "app.services.reminder_scheduler.mark_safety_reminder_sent",
            return_value=True,
        ),
        patch(
            "app.services.reminder_scheduler.send_meetup_safety_reminder_notification",
            AsyncMock(),
        ),
        patch(
            "app.services.reminder_scheduler.fetch_overdue_safety_sessions",
            return_value=[mock_session],
        ),
        patch("app.services.reminder_scheduler._escalate_safety_session", AsyncMock()),
        patch("app.services.reminder_scheduler.purge_due_accounts"),
        patch("app.services.reminder_scheduler.expire_blocklist_entries"),
        patch("app.services.reminder_scheduler.hard_purge_long_tail_accounts"),
        patch("app.services.reminder_scheduler.purge_expired_safety_evidence"),
        patch("app.services.reminder_scheduler.purge_safety_data_for_purged_accounts"),
        patch("app.services.reminder_scheduler.redis_client") as mock_r,
    ):
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

        with patch(
            "app.services.reminder_scheduler.AsyncIOScheduler",
        ) as mock_sched_cls:
            mock_inst = MagicMock()
            mock_sched_cls.return_value = mock_inst
            mock_inst.running = True
            sched = start_reminder_scheduler()
            assert sched is not None
            stop_reminder_scheduler()


async def test_services_reminder_scheduler_deep_p24():
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

    # _mask_id
    assert _mask_id("00000000-0000-0000-0000-000000000001") == "0000...0001"
    assert _mask_id("short") == "***"

    # with_distributed_lock: acquired vs locked
    @with_distributed_lock("test_lock", ttl_seconds=10)
    async def sample_job() -> None:
        pass

    mock_lock = MagicMock()
    mock_lock.acquire = AsyncMock(return_value=True)
    mock_lock.release = AsyncMock()

    with patch("app.services.reminder_scheduler.redis_client") as mock_redis:
        mock_redis.lock = MagicMock(return_value=mock_lock)
        await sample_job()

        mock_lock.acquire = AsyncMock(return_value=False)
        await sample_job()

    # _next_escalation_due
    now = datetime.now(timezone.utc)
    assert _next_escalation_due({"escalations_sent": 0}, now) is True
    assert (
        _next_escalation_due({"escalations_sent": 1, "last_escalated_at": None}, now)
        is False
    )
    assert (
        _next_escalation_due(
            {
                "escalations_sent": 1,
                "last_escalated_at": (now - timedelta(minutes=20)).isoformat(),
                "interval_seconds": 300,
            },
            now,
        )
        is True
    )
    assert (
        _next_escalation_due(
            {
                "escalations_sent": 1,
                "last_escalated_at": (now - timedelta(minutes=1)).isoformat(),
                "interval_seconds": 300,
            },
            now,
        )
        is False
    )

    # _acquire_escalation_idempotency: redis set return True vs False
    with patch("app.services.reminder_scheduler.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(return_value=True)
        assert await _acquire_escalation_idempotency("sess-1", 1) is True

        mock_redis.set = AsyncMock(return_value=False)
        assert await _acquire_escalation_idempotency("sess-1", 1) is False

        mock_redis.set = AsyncMock(side_effect=Exception("redis down"))
        assert await _acquire_escalation_idempotency("sess-1", 1) is False

    # _compose_session_unreachable_message
    msg = _compose_session_unreachable_message(
        {"label": "Coffee"},
        "sess-1",
        1,
        user_name="Alice",
    )
    assert "Alice" in msg
    assert "Coffee" in msg

    # _dispatch_escalation_sms_and_record: mock SMS & log record
    contacts = [{"contact_name": "Bob", "phone": "+1234567890"}]
    session = {
        "id": "sess-1",
        "user_id": USER_1,
        "user_name": "Alice",
        "escalation_count": 0,
    }
    with (
        patch(
            "app.services.reminder_scheduler.record_safety_escalation_sent",
            return_value=True,
        ),
        patch(
            "app.services.reminder_scheduler.send_sms",
            return_value=MagicMock(success=True),
        ),
    ):
        await _dispatch_escalation_sms_and_record(
            contacts, session, "sess-1", 1, "idem-123",
        )

    # _escalate_safety_session: no contacts vs success
    with (
        patch(
            "app.services.reminder_scheduler.fetch_safety_contacts_with_id",
            return_value=[],
        ),
        patch("app.services.reminder_scheduler.record_safety_escalation_sent"),
    ):
        await _escalate_safety_session(
            {"id": "sess-1", "user_id": USER_1, "escalation_count": 0},
        )

    # _check_overdue_safety_sessions
    with (
        patch(
            "app.services.reminder_scheduler.fetch_overdue_safety_sessions",
            return_value=[
                {
                    "id": "sess-1",
                    "escalation_count": 0,
                    "session_expires_at": (now - timedelta(minutes=10)).isoformat(),
                },
            ],
        ),
        patch("app.services.reminder_scheduler._escalate_safety_session"),
    ):
        await _check_overdue_safety_sessions()

    # _check_due_reminders & _check_upcoming_safety_reminders
    with (
        patch(
            "app.services.reminder_scheduler.fetch_due_event_reminders",
            return_value=[
                {
                    "id": "ev-1",
                    "sender_id": USER_1,
                    "conversation_id": "conv-1",
                    "tab": "Dating",
                },
            ],
        ),
        patch(
            "app.services.reminder_scheduler.fetch_due_safety_reminders",
            return_value=[
                {
                    "id": "ev-2",
                    "sender_id": USER_1,
                    "conversation_id": "conv-1",
                    "tab": "Dating",
                },
            ],
        ),
        patch(
            "app.services.reminder_scheduler.fetch_conversation_participants",
            return_value={"user_a_id": USER_1, "user_b_id": USER_2},
        ),
        patch(
            "app.services.reminder_scheduler.send_chat_event_reminder_notification",
            return_value=True,
        ),
        patch(
            "app.services.reminder_scheduler.send_meetup_safety_reminder_notification",
        ),
        patch("app.services.reminder_scheduler.mark_reminder_sent"),
        patch("app.services.reminder_scheduler.mark_safety_reminder_sent"),
    ):
        await _check_due_reminders()
        await _check_upcoming_safety_reminders()

    # Maintenance purges & executor
    get_maintenance_executor()
    await _run_in_maintenance_executor(lambda: 42)

    with patch("app.services.reminder_scheduler._run_in_maintenance_executor"):
        await _run_account_deletion_purge()
        await _run_blocklist_expiry()
        await _run_account_deletion_long_tail_purge()
        await _run_safety_evidence_retention_purge()
        await _run_safety_data_legal_hold_purge()

    # start and stop scheduler
    sched = start_reminder_scheduler()
    assert sched is not None
    stop_reminder_scheduler()


async def test_services_reminder_scheduler_deep_p27():
    from app.services.reminder_scheduler import (
        _check_due_reminders,
        _check_overdue_safety_sessions,
        _check_upcoming_safety_reminders,
        _escalate_safety_session,
        _run_account_deletion_long_tail_purge,
        _run_account_deletion_purge,
        _run_blocklist_expiry,
        _run_safety_data_legal_hold_purge,
        _run_safety_evidence_retention_purge,
        start_reminder_scheduler,
    )

    # _check_due_reminders: conversation None & DatabaseAccessError
    with (
        patch(
            "app.services.reminder_scheduler.fetch_due_event_reminders",
            return_value=[{"id": "ev-1", "conversation_id": CONV_1}],
        ),
        patch("app.services.reminder_scheduler.mark_reminder_sent", return_value=True),
        patch(
            "app.services.reminder_scheduler.fetch_conversation_participants",
            return_value=None,
        ),
    ):
        await _check_due_reminders()

    with (
        patch(
            "app.services.reminder_scheduler.fetch_due_event_reminders",
            return_value=[{"id": "ev-1", "conversation_id": CONV_1}],
        ),
        patch("app.services.reminder_scheduler.mark_reminder_sent", return_value=True),
        patch(
            "app.services.reminder_scheduler.fetch_conversation_participants",
            side_effect=DatabaseAccessError("DB fail"),
        ),
    ):
        await _check_due_reminders()

    # _check_upcoming_safety_reminders: fetch error, mark False, conv None, loop error
    with patch(
        "app.services.reminder_scheduler.fetch_due_safety_reminders",
        side_effect=DatabaseAccessError("DB fail"),
    ):
        await _check_upcoming_safety_reminders()

    due_list = [
        {"id": "ev-1", "conversation_id": CONV_1, "created_by": USER_1},
        {"id": "ev-2", "conversation_id": CONV_1, "created_by": USER_1},
        {"id": "ev-3", "conversation_id": CONV_1, "created_by": USER_1},
    ]
    with (
        patch(
            "app.services.reminder_scheduler.fetch_due_safety_reminders",
            return_value=due_list,
        ),
        patch(
            "app.services.reminder_scheduler.mark_safety_reminder_sent",
            side_effect=[False, True, True],
        ),
        patch(
            "app.services.reminder_scheduler.fetch_conversation_participants",
            side_effect=[None, DatabaseAccessError("DB fail")],
        ),
    ):
        await _check_upcoming_safety_reminders()

    # _escalate_safety_session: DatabaseAccessError
    with patch(
        "app.services.reminder_scheduler.fetch_safety_contacts_with_id",
        side_effect=DatabaseAccessError("DB fail"),
    ):
        await _escalate_safety_session(
            {"id": SESS_1, "user_id": USER_1, "escalations_sent": 0},
        )

    # _check_overdue_safety_sessions: DatabaseAccessError, empty due, safe escalate error
    with patch(
        "app.services.reminder_scheduler.fetch_overdue_safety_sessions",
        side_effect=DatabaseAccessError("DB fail"),
    ):
        await _check_overdue_safety_sessions()

    with patch(
        "app.services.reminder_scheduler.fetch_overdue_safety_sessions", return_value=[],
    ):
        await _check_overdue_safety_sessions()

    overdue_sess = [{"id": SESS_1, "user_id": USER_1, "escalations_sent": 0}]
    with (
        patch(
            "app.services.reminder_scheduler.fetch_overdue_safety_sessions",
            return_value=overdue_sess,
        ),
        patch(
            "app.services.reminder_scheduler._next_escalation_due", return_value=True,
        ),
        patch(
            "app.services.reminder_scheduler._escalate_safety_session",
            side_effect=Exception("Escalate error"),
        ),
    ):
        await _check_overdue_safety_sessions()

    # Purge jobs: DatabaseAccessError handling
    with patch(
        "app.services.reminder_scheduler._run_in_maintenance_executor",
        side_effect=DatabaseAccessError("DB fail"),
    ):
        await _run_account_deletion_purge()
        await _run_blocklist_expiry()
        await _run_account_deletion_long_tail_purge()
        await _run_safety_evidence_retention_purge()
        await _run_safety_data_legal_hold_purge()

    # start_reminder_scheduler: start exception
    with (
        patch("app.services.reminder_scheduler._scheduler", None),
        patch("app.services.reminder_scheduler.AsyncIOScheduler") as mock_sched,
    ):
        mock_sched.return_value.start.side_effect = Exception("Scheduler start fail")
        with pytest.raises(Exception):
            start_reminder_scheduler()


async def test_services_reminder_scheduler() -> None:
    # _mask_id
    assert _mask_id("abcdef123456") == "abcd...3456"
    assert _mask_id("abc") == "***"

    # with_distributed_lock
    mock_lock = MagicMock()
    mock_lock.acquire = AsyncMock(return_value=True)
    mock_lock.release = AsyncMock()
    mock_redis = MagicMock()
    mock_redis.lock.return_value = mock_lock

    @with_distributed_lock("test:lock", ttl_seconds=60)
    async def locked_task() -> None:
        pass

    with patch("app.services.reminder_scheduler.redis_client", mock_redis):
        await locked_task()
        mock_lock.acquire.return_value = False
        await locked_task()  # Should skip cleanly

    # _next_escalation_due
    now = datetime.now(timezone.utc)
    sess_due = {
        "status": "escalating",
        "escalations_sent": 1,
        "interval_seconds": 60,
        "last_escalated_at": (now - timedelta(minutes=10)).isoformat(),
    }
    assert _next_escalation_due(sess_due, now) is True

    # _compose_session_unreachable_message
    msg = _compose_session_unreachable_message(
        session={"label": "Dinner"},
        session_id=SESSION_1,
        escalation_number=1,
        user_name="Alice",
    )
    assert "Alice" in msg

    # _acquire_escalation_idempotency
    mock_redis_async = AsyncMock()
    mock_redis_async.set.return_value = True
    with patch("app.services.reminder_scheduler.redis_client", mock_redis_async):
        acq = await _acquire_escalation_idempotency(SESSION_1, 1)
        assert acq is True

    # _dispatch_escalation_sms_and_record
    mock_contact = {"id": "c1", "phone": "+14155552671"}
    with (
        patch(
            "app.services.reminder_scheduler.record_safety_escalation_sent",
            return_value={"id": SESSION_1},
        ),
        patch(
            "app.services.reminder_scheduler.fetch_contact_facing_profile_summary",
            return_value={"display_name": "Alice"},
        ),
        patch(
            "app.services.reminder_scheduler.send_sms",
            AsyncMock(return_value=MagicMock(success=True)),
        ),
    ):
        await _dispatch_escalation_sms_and_record(
            contacts=[mock_contact],
            session={"label": "Dinner", "user_id": USER_1},
            session_id=SESSION_1,
            escalation_number=1,
            idempotency_key="idem-key",
        )

    # Purge wrappers
    with (
        patch(
            "app.services.reminder_scheduler.purge_due_accounts",
            return_value={"purged": 1},
        ),
        patch(
            "app.services.reminder_scheduler.expire_blocklist_entries", return_value=1,
        ),
        patch(
            "app.services.reminder_scheduler.purge_expired_safety_evidence",
            return_value=1,
        ),
        patch(
            "app.services.reminder_scheduler.purge_safety_data_for_purged_accounts",
            return_value=1,
        ),
        patch(
            "app.services.reminder_scheduler.hard_purge_long_tail_accounts",
            return_value={"orphans": 0},
        ),
    ):
        await _run_account_deletion_purge()
        await _run_blocklist_expiry()
        await _run_account_deletion_long_tail_purge()
        await _run_safety_evidence_retention_purge()
        await _run_safety_data_legal_hold_purge()

    # Scheduler start & stop
    sched = start_reminder_scheduler()
    assert sched is not None
    stop_reminder_scheduler()
