from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from postgrest.exceptions import APIError

from app.core.security.crypto import DecryptFailedError
from app.db.client import DatabaseAccessError

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
SESSION_1 = "00000000-0000-0000-0000-000000000010"
ALERT_1 = "00000000-0000-0000-0000-000000000020"


# =============================================================================
# 1. DB SAFETY ALERTS & SESSIONS TESTS
# =============================================================================

def test_db_safety_alerts_deep():
    from app.db.safety.alerts import (
        fetch_alerts_for_session,
        fetch_contact_facing_profile_summary,
        fetch_recent_safety_alert,
        fetch_safety_alert,
        purge_expired_safety_evidence,
        purge_safety_data_for_purged_accounts,
        record_safety_alert,
        update_alert_contacts_notified,
    )

    # fetch_contact_facing_profile_summary: res is None, APIError, DecryptFailedError
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=None)
        assert fetch_contact_facing_profile_summary(USER_1) is None

        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_contact_facing_profile_summary(USER_1)

        mock_sb.table().select().eq().maybe_single().execute.side_effect = None
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data={"name": "enc"})
        with patch("app.db.safety.alerts.decrypt_profile_record", side_effect=DecryptFailedError("fail")):
            assert fetch_contact_facing_profile_summary(USER_1) is None

    # record_safety_alert: rows empty & APIError
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().insert().select().execute.return_value = MagicMock(data=[])
        with pytest.raises(DatabaseAccessError, match="Safety alert insert returned no row"):
            record_safety_alert(USER_1, "emergency", {"lat": 1.0, "lng": 2.0}, session_id=SESSION_1)

        mock_sb.table().insert().select().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            record_safety_alert(USER_1, "emergency", None)

    # fetch_safety_alert: res is None & APIError
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=None)
        assert fetch_safety_alert(ALERT_1) is None

        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_safety_alert(ALERT_1)

    # fetch_recent_safety_alert: session_id provided & Exception
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().gte().order().limit().eq().execute.return_value = MagicMock(data=[{"id": ALERT_1}])
        res = fetch_recent_safety_alert(USER_1, "emergency", session_id=SESSION_1)
        assert res == {"id": ALERT_1}

        mock_sb.table().select().eq().eq().gte().order().limit().eq().execute.side_effect = Exception("DB error")
        assert fetch_recent_safety_alert(USER_1, "emergency", session_id=SESSION_1) is None

    # update_alert_contacts_notified: APIError
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().update().eq().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            update_alert_contacts_notified(ALERT_1, 3)

    # fetch_alerts_for_session: stale location & APIError
    now = datetime.now(timezone.utc)
    old_time = (now - timedelta(hours=2)).isoformat()
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().eq().order().execute.return_value = MagicMock(
            data=[{"current_location": "enc_loc", "created_at": old_time}],
        )
        alerts = fetch_alerts_for_session(SESSION_1, decrypt_locations=True, max_location_age=timedelta(minutes=30))
        assert alerts[0]["current_location"] is None

        mock_sb.table().select().eq().order().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_alerts_for_session(SESSION_1)

    # purge_expired_safety_evidence: fetch APIError, empty rows, delete APIError, storage remove Exception
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().lt().execute.side_effect = APIError({"message": "fail"})
        purge_expired_safety_evidence()

        mock_sb.table().select().lt().execute.side_effect = None
        mock_sb.table().select().lt().execute.return_value = MagicMock(data=[])
        purge_expired_safety_evidence()

        mock_sb.table().select().lt().execute.return_value = MagicMock(data=[{"id": "ev1", "storage_path": "path1"}])
        mock_sb.table().delete().in_().execute.side_effect = APIError({"message": "fail"})
        purge_expired_safety_evidence()

        mock_sb.table().delete().in_().execute.side_effect = None
        mock_sb.storage.from_().remove.side_effect = Exception("Storage fail")
        purge_expired_safety_evidence()

    # purge_safety_data_for_purged_accounts: fetch APIError, empty user_ids, evidence APIError, safety_alerts APIError
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().not_.is_().lte().execute.side_effect = APIError({"message": "fail"})
        purge_safety_data_for_purged_accounts()

        mock_sb.table().select().not_.is_().lte().execute.side_effect = None
        mock_sb.table().select().not_.is_().lte().execute.return_value = MagicMock(data=[])
        purge_safety_data_for_purged_accounts()

        mock_sb.table().select().not_.is_().lte().execute.return_value = MagicMock(data=[{"id": USER_1}])
        mock_sb.table().select().in_().execute.side_effect = APIError({"message": "fail"})
        mock_sb.table().delete().in_().execute.side_effect = APIError({"message": "fail"})
        purge_safety_data_for_purged_accounts()


def test_db_safety_sessions_deep():
    from app.db.safety.sessions import (
        _decrypt_session_row,
        cancel_safety_escalation,
        end_safety_session,
        fetch_overdue_safety_sessions,
        fetch_safety_session,
        fetch_safety_session_for_user,
        heartbeat_safety_session,
        record_safety_escalation_sent,
        start_safety_session,
    )

    # _decrypt_session_row branches
    assert _decrypt_session_row({}) == {}
    row_with_dict_ctx = {"event_context": {"foo": "bar"}}
    assert _decrypt_session_row(row_with_dict_ctx)["event_context"] == {"foo": "bar"}

    with patch("app.db.safety.sessions.decrypt_pii", side_effect=Exception("decrypt fail")):
        row_broken_enc = {"label": "enc", "event_context": "broken-enc"}
        dec = _decrypt_session_row(row_broken_enc)
        assert dec["event_context"] == {}

    # start_safety_session insert returned no row
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.rpc().execute.return_value = MagicMock(data="unexpected-string")
        with pytest.raises(DatabaseAccessError, match="Safety session insert returned no row"):
            start_safety_session(USER_1, "Label", 60, "2026-08-26T20:00:00Z", None, 90, "wifi")

    # heartbeat_safety_session: no rows, updated_rows empty, APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().eq().execute.return_value = MagicMock(data=[])
        assert heartbeat_safety_session(USER_1, SESSION_1, "2026-08-26T20:00:00Z", 80, "4g") is None

        mock_sb.table().select().eq().eq().eq().execute.return_value = MagicMock(data=[{"id": SESSION_1, "next_checkin_at": "2026-08-26T19:00:00Z"}])
        mock_sb.table().update().eq().eq().eq().select().execute.return_value = MagicMock(data=[])
        assert heartbeat_safety_session(USER_1, SESSION_1, "2026-08-26T20:00:00Z", 80, "4g") is None

        mock_sb.table().select().eq().eq().eq().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            heartbeat_safety_session(USER_1, SESSION_1, "2026-08-26T20:00:00Z", 80, "4g")

    # end_safety_session APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().update().eq().eq().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            end_safety_session(USER_1, SESSION_1)

    # fetch_overdue_safety_sessions APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().is_().eq().eq().is_().is_().lt().lt().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_overdue_safety_sessions(60)

    # record_safety_escalation_sent APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().update().eq().lt().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            record_safety_escalation_sent(SESSION_1, 2)

    # fetch_safety_session & fetch_safety_session_for_user APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_safety_session(SESSION_1)

        mock_sb.table().select().eq().eq().maybe_single().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_safety_session_for_user(USER_1, SESSION_1)

    # cancel_safety_escalation: rows empty & APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().update().eq().eq().is_().select().execute.return_value = MagicMock(data=[])
        assert cancel_safety_escalation(USER_1, SESSION_1, "false_alarm", None) is None

        mock_sb.table().update().eq().eq().is_().select().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            cancel_safety_escalation(USER_1, SESSION_1, "false_alarm", "note")


# =============================================================================
# 2. CORE INFRA TASKS TESTS
# =============================================================================

async def test_core_infra_tasks_deep():
    from app.core.infra.tasks import (
        _MAX_BACKGROUND_TASKS,
        _schedule_cross_thread,
        run_with_retries,
        safe_create_task,
    )

    async def dummy_coro():
        return 42

    async def failing_coro():
        raise ValueError("Task error")

    # safe_create_task when running loop exists
    t = safe_create_task(dummy_coro())
    assert t is not None
    await t

    # safe_create_task done_callback exception handling
    f_task = safe_create_task(failing_coro())
    assert f_task is not None
    with pytest.raises(ValueError):
        await f_task

    # safe_create_task when background task set capacity reached
    with patch("app.core.infra.tasks._background_tasks", {MagicMock() for _ in range(_MAX_BACKGROUND_TASKS)}):
        c = dummy_coro()
        dropped = safe_create_task(c)
        assert dropped is None

    # safe_create_task without running loop -> _schedule_cross_thread
    with patch("asyncio.get_running_loop", side_effect=RuntimeError("no running loop")), \
         patch("app.core.infra.tasks._schedule_cross_thread") as mock_sched:
        c = dummy_coro()
        ret = safe_create_task(c)
        assert ret is None
        mock_sched.assert_called_once()
        c.close()

    # _schedule_cross_thread error handling
    with patch("anyio.from_thread.run", side_effect=Exception("Cross thread error")):
        _schedule_cross_thread(dummy_coro())

    # run_with_retries: non-coroutine factory, sync coroutine return, max retries failure
    def _double(x: int) -> int:
        return x * 2

    assert await run_with_retries(_double, 5) == 10

    def sync_returning_coro(val: int):
        async def _inner() -> int:
            return val + 1
        return _inner()

    assert await run_with_retries(sync_returning_coro, 5) == 6

    # Retries exhausted
    call_count = 0
    async def always_fails():
        nonlocal call_count
        call_count += 1
        raise RuntimeError("always fails")

    with pytest.raises(RuntimeError, match="always fails"):
        await run_with_retries(always_fails, max_retries=2, initial_delay=0.01)
    assert call_count == 2


# =============================================================================
# 3. EMAIL NOTIFICATIONS EXCEPTION BRANCHES
# =============================================================================

async def test_email_notifications_exception_handlers():
    from app.core.email.notifications.account import (
        send_account_deletion_otp_email,
        send_account_deletion_scheduled_email,
        send_account_reactivated_email,
        send_data_export_otp_email,
        send_login_otp_email,
        send_support_appeal_otp_email,
    )
    from app.core.email.notifications.feedback import (
        send_feedback_admin_notification_email,
        send_feedback_closed_admin_notification_email,
        send_feedback_comment_admin_notification_email,
        send_feedback_confirmation_email,
    )
    from app.core.email.notifications.safety import send_trusted_contact_removed_email
    from app.core.email.notifications.welcome import send_bootstrap_welcome_email

    # Test failure results and exceptions for account emails
    with patch("app.core.email.notifications.account.email_pkg.send_email", AsyncMock(side_effect=Exception("SMTP fail"))):
        r1 = await send_login_otp_email("test@example.com", "123456")
        assert not r1.success
        assert "SMTP fail" in (r1.error or "")

        r2 = await send_account_deletion_otp_email("test@example.com", "123456")
        assert not r2.success

        r3 = await send_data_export_otp_email("test@example.com", "123456")
        assert not r3.success

        r4 = await send_support_appeal_otp_email("test@example.com", "123456")
        assert not r4.success

        r5 = await send_account_deletion_scheduled_email("test@example.com", datetime.now(timezone.utc), 14)
        assert not r5.success

        r6 = await send_account_reactivated_email("test@example.com")
        assert not r6.success

    # Feedback emails
    with patch("app.core.email.notifications.feedback.email_pkg.send_email", AsyncMock(side_effect=Exception("Feedback SMTP fail"))):
        f1 = await send_feedback_confirmation_email("test@example.com", "help", "Help sub", "rep-1")
        assert not f1.success

        f2 = await send_feedback_admin_notification_email("rep-1", "help", "Help sub", "msg", USER_1, "test@example.com")
        assert not f2.success

        f3 = await send_feedback_comment_admin_notification_email("rep-1", "help", "Help sub", "comment msg", "admin", "test@example.com")
        assert not f3.success

        f4 = await send_feedback_closed_admin_notification_email("rep-1", "help", "Help sub", "closed", USER_1, "test@example.com")
        assert not f4.success

    # Safety email exception
    with patch("app.core.email.notifications.safety.email_pkg.send_email", AsyncMock(side_effect=Exception("Safety email fail"))):
        s1 = await send_trusted_contact_removed_email("contact@example.com", "Bob", "Alice")
        assert not s1.success

    # Welcome email exception
    with patch("app.core.email.notifications.welcome.email_pkg.send_email", AsyncMock(side_effect=Exception("Welcome fail"))):
        w1 = await send_bootstrap_welcome_email("test@example.com")
        assert not w1.success
