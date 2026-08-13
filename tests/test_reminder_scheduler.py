"""Unit tests for reminder scheduler distributed leader locking."""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from app.services.reminder_scheduler import (
    _check_due_reminders,
    _check_overdue_safety_sessions,
    _check_upcoming_safety_reminders,
    _run_account_deletion_long_tail_purge,
    _run_account_deletion_purge,
    _run_blocklist_expiry,
    _run_safety_data_legal_hold_purge,
    _run_safety_evidence_retention_purge,
    with_distributed_lock,
)


@pytest.mark.anyio
async def test_with_distributed_lock_executes_when_acquired():
    mock_lock = MagicMock()
    mock_lock.acquire = AsyncMock(return_value=True)
    mock_lock.release = AsyncMock()

    called = False

    @with_distributed_lock("test_job", ttl_seconds=60)
    async def sample_job():
        nonlocal called
        called = True

    with patch("app.services.reminder_scheduler.redis_client.lock", return_value=mock_lock):
        await sample_job()

    assert called is True
    mock_lock.acquire.assert_called_once_with(blocking=False)
    mock_lock.release.assert_called_once()


@pytest.mark.anyio
async def test_with_distributed_lock_skips_when_not_acquired():
    mock_lock = MagicMock()
    mock_lock.acquire = AsyncMock(return_value=False)
    mock_lock.release = AsyncMock()

    called = False

    @with_distributed_lock("test_job", ttl_seconds=60)
    async def sample_job():
        nonlocal called
        called = True

    with patch("app.services.reminder_scheduler.redis_client.lock", return_value=mock_lock):
        await sample_job()

    assert called is False
    mock_lock.acquire.assert_called_once_with(blocking=False)
    mock_lock.release.assert_not_called()


@pytest.mark.anyio
async def test_with_distributed_lock_handles_redis_communication_error():
    mock_lock = MagicMock()
    mock_lock.acquire = AsyncMock(side_effect=Exception("Redis connection refused"))

    called = False

    @with_distributed_lock("test_job", ttl_seconds=60)
    async def sample_job():
        nonlocal called
        called = True

    with patch("app.services.reminder_scheduler.redis_client.lock", return_value=mock_lock):
        await sample_job()

    # Falls back to executing the function
    assert called is True


@pytest.mark.anyio
async def test_with_distributed_lock_releases_on_exception():
    mock_lock = MagicMock()
    mock_lock.acquire = AsyncMock(return_value=True)
    mock_lock.release = AsyncMock()

    @with_distributed_lock("test_job", ttl_seconds=60)
    async def failing_job():
        raise ValueError("Job processing failed")

    with patch("app.services.reminder_scheduler.redis_client.lock", return_value=mock_lock):
        with pytest.raises(ValueError, match="Job processing failed"):
            await failing_job()

    mock_lock.release.assert_called_once()


@pytest.mark.anyio
async def test_all_scheduler_jobs_are_decorated():
    jobs = [
        _check_due_reminders,
        _check_upcoming_safety_reminders,
        _check_overdue_safety_sessions,
        _run_account_deletion_purge,
        _run_blocklist_expiry,
        _run_account_deletion_long_tail_purge,
        _run_safety_evidence_retention_purge,
        _run_safety_data_legal_hold_purge,
    ]

    for job in jobs:
        assert hasattr(job, "__wrapped__"), f"{job.__name__} is missing @with_distributed_lock decorator"


def test_fetch_due_event_reminders_applies_limit():
    from app.db.chat import fetch_due_event_reminders

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.is_.return_value = mock_builder
    mock_builder.neq.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])

    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_builder):
        fetch_due_event_reminders(window_minutes=60)

    mock_builder.limit.assert_called_once_with(500)


def test_fetch_due_safety_reminders_applies_limit():
    from app.db.chat import fetch_due_safety_reminders

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.is_.return_value = mock_builder
    mock_builder.neq.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])

    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_builder):
        fetch_due_safety_reminders(window_minutes=35)

    mock_builder.limit.assert_called_once_with(500)


@pytest.mark.anyio
@patch("app.services.reminder_scheduler.fetch_safety_contacts")
@patch("app.services.reminder_scheduler.send_sms")
@patch("app.services.reminder_scheduler.record_safety_escalation_sent")
async def test_escalate_safety_session_idempotency_new(
    mock_record: AsyncMock,
    mock_send_sms: AsyncMock,
    mock_fetch_contacts: AsyncMock,
):
    from app.services.reminder_scheduler import _escalate_safety_session

    session = {
        "id": "session-123",
        "escalations_sent": 1,
        "user_id": "user-456",
        "label": "Test User",
        "battery_percent": 80,
        "connection_type": "wifi",
    }
    mock_fetch_contacts.return_value = [{"phone": "+1234567890"}]
    mock_send_sms.return_value = MagicMock(success=True)

    mock_set = AsyncMock(return_value=True)

    with patch("app.services.reminder_scheduler.redis_client.set", mock_set):
        await _escalate_safety_session(session)

    mock_set.assert_called_once_with("safety:escalation:sent:session-123:2", "1", ex=86400, nx=True)
    mock_send_sms.assert_called_once()
    mock_record.assert_called_once_with("session-123", 2)


@pytest.mark.anyio
@patch("app.services.reminder_scheduler.fetch_safety_contacts")
@patch("app.services.reminder_scheduler.send_sms")
@patch("app.services.reminder_scheduler.record_safety_escalation_sent")
async def test_escalate_safety_session_idempotency_duplicate(
    mock_record: AsyncMock,
    mock_send_sms: AsyncMock,
    mock_fetch_contacts: AsyncMock,
):
    from app.services.reminder_scheduler import _escalate_safety_session

    session = {
        "id": "session-123",
        "escalations_sent": 1,
        "user_id": "user-456",
        "label": "Test User",
    }
    mock_fetch_contacts.return_value = [{"phone": "+1234567890"}]

    mock_set = AsyncMock(return_value=False)

    with patch("app.services.reminder_scheduler.redis_client.set", mock_set):
        await _escalate_safety_session(session)

    mock_set.assert_called_once_with("safety:escalation:sent:session-123:2", "1", ex=86400, nx=True)
    mock_send_sms.assert_not_called()
    mock_record.assert_not_called()


@pytest.mark.anyio
@patch("app.services.reminder_scheduler.fetch_safety_contacts")
@patch("app.services.reminder_scheduler.send_sms")
@patch("app.services.reminder_scheduler.record_safety_escalation_sent")
async def test_escalate_safety_session_idempotency_failed_sms(
    mock_record: AsyncMock,
    mock_send_sms: AsyncMock,
    mock_fetch_contacts: AsyncMock,
):
    from app.services.reminder_scheduler import _escalate_safety_session

    session = {
        "id": "session-123",
        "escalations_sent": 1,
        "user_id": "user-456",
        "label": "Test User",
    }
    mock_fetch_contacts.return_value = [{"phone": "+1234567890"}]
    mock_send_sms.return_value = MagicMock(success=False)

    mock_set = AsyncMock(return_value=True)
    mock_delete = AsyncMock()

    with patch("app.services.reminder_scheduler.redis_client.set", mock_set), \
         patch("app.services.reminder_scheduler.redis_client.delete", mock_delete):
        await _escalate_safety_session(session)

    mock_send_sms.assert_called_once()
    mock_delete.assert_called_once_with("safety:escalation:sent:session-123:2")
    mock_record.assert_not_called()


def test_fetch_accounts_due_for_purge_applies_limit():
    from app.db.users.account_deletion import _fetch_accounts_due_for_purge

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.not_.return_value = mock_builder
    mock_builder.is_.return_value = mock_builder
    mock_builder.lte.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])

    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_builder):
        _fetch_accounts_due_for_purge()

    mock_builder.limit.assert_called_once_with(500)


def test_fetch_accounts_due_for_long_tail_purge_applies_limit():
    from app.db.users.account_deletion import _fetch_accounts_due_for_long_tail_purge

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.not_.return_value = mock_builder
    mock_builder.is_.return_value = mock_builder
    mock_builder.lte.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])

    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_builder):
        _fetch_accounts_due_for_long_tail_purge()

    mock_builder.limit.assert_called_once_with(500)


@patch("app.db.users.account_deletion._fetch_accounts_due_for_purge")
@patch("app.db.users.account_deletion._permanently_unmatch_all")
@patch("app.db.users.account_deletion._anonymize_profile_and_user")
@patch("app.db.users.account_deletion._delete_no_retention_rows")
@patch("app.db.users.account_deletion._delete_user_media_objects")
@patch("app.db.users.account_deletion._ban_and_scrub_auth_user")
@patch("app.db.users.account_deletion.time.sleep")
def test_purge_due_accounts_batches_and_sleeps(
    mock_sleep: MagicMock,
    mock_ban: MagicMock,
    mock_media: MagicMock,
    mock_del_rows: MagicMock,
    mock_anonymize: MagicMock,
    mock_unmatch: MagicMock,
    mock_fetch: MagicMock,
):
    from app.db.users.account_deletion import purge_due_accounts

    # Simulate 120 accounts (3 batches: 50, 50, 20)
    mock_fetch.return_value = [{"id": f"user-{i}"} for i in range(120)]

    purge_due_accounts()

    assert mock_unmatch.call_count == 120
    assert mock_sleep.call_count == 2  # Sleep called twice between the 3 batches
    mock_sleep.assert_any_call(1.0)


@patch("app.db.users.account_deletion.supabase_client.auth.admin.update_user_by_id")
def test_ban_and_scrub_auth_user_appends_random_token(mock_update_user: MagicMock):
    from app.db.users.account_deletion import _ban_and_scrub_auth_user
    from app.core.config import settings

    _ban_and_scrub_auth_user("user-xyz")

    mock_update_user.assert_called_once()
    args, _ = mock_update_user.call_args
    assert args[0] == "user-xyz"
    update_payload = args[1]
    assert update_payload["ban_duration"] == "876000h"
    email = update_payload["email"]
    assert email.startswith("deleted-user-xyz-")
    assert email.endswith(f"@deleted.{settings.email_domain}")
    # Verify hex token length in email
    token_part = email.split("@")[0].replace("deleted-user-xyz-", "")
    assert len(token_part) == 16  # token_hex(8) produces 16 hex chars



@patch("app.db.users.account_deletion._fetch_accounts_due_for_long_tail_purge")
@patch("app.db.users.account_deletion._archive_account_history")
@patch("app.db.users.account_deletion.supabase_client.auth.admin.delete_user")
@patch("app.db.users.account_deletion.time.sleep")
def test_hard_purge_long_tail_accounts_batches_and_sleeps(
    mock_sleep: MagicMock,
    mock_delete: MagicMock,
    mock_archive: MagicMock,
    mock_fetch: MagicMock,
):
    from app.db.users.account_deletion import hard_purge_long_tail_accounts

    # Simulate 75 accounts (2 batches: 50, 25)
    mock_fetch.return_value = [f"user-{i}" for i in range(75)]
    mock_archive.return_value = []

    hard_purge_long_tail_accounts()

    assert mock_delete.call_count == 75
    assert mock_sleep.call_count == 1  # Sleep called once between the 2 batches
    mock_sleep.assert_any_call(1.0)


@patch("app.db.users.account_deletion._fetch_accounts_due_for_long_tail_purge")
@patch("app.db.users.account_deletion._archive_account_history")
@patch("app.db.users.account_deletion.supabase_client.auth.admin.delete_user")
@patch("app.db.users.account_deletion.time.sleep")
def test_hard_purge_long_tail_accounts_aborts_on_archive_failure(
    mock_sleep: MagicMock,
    mock_delete: MagicMock,
    mock_archive: MagicMock,
    mock_fetch: MagicMock,
):
    from app.db.users.account_deletion import hard_purge_long_tail_accounts

    def _mock_archive_side_effect(uid: str) -> list[str]:
        return ["user_reports"] if uid == "user-fail" else []

    mock_archive.side_effect = _mock_archive_side_effect

    hard_purge_long_tail_accounts()

    # delete_user should only be called for user-ok, skipping user-fail
    assert mock_delete.call_count == 1
    mock_delete.assert_called_once_with("user-ok")


def test_archive_account_history_tracks_failures():
    from app.db.users.account_deletion import _archive_account_history
    from postgrest.exceptions import APIError

    builder = MagicMock()
    builder.select.return_value = builder
    builder.or_.return_value = builder
    builder.eq.return_value = builder
    builder.execute.side_effect = APIError({"message": "DB error"})

    with patch("app.db.users.account_deletion.supabase_client.table", return_value=builder):
        failed_tables = _archive_account_history("user-123")

    assert "user_reports" in failed_tables
    assert len(failed_tables) == 3


def test_make_and_verify_escalation_cancel_token():
    from app.core.utils.sms import make_escalation_cancel_token, verify_escalation_cancel_token

    session_id = "session-test-token"
    token = make_escalation_cancel_token(session_id, escalation_number=2)

    # Valid token verification returns the escalation number
    val = verify_escalation_cancel_token(session_id, token)
    assert val == 2

    # Verification returns None if session_id does not match
    val_diff_session = verify_escalation_cancel_token("session-other", token)
    assert val_diff_session is None

    # Verification returns None for expired or malformed token
    assert verify_escalation_cancel_token(session_id, "malformed-token") is None


def test_start_safety_session_no_escalation():
    from app.db.safety.sessions import start_safety_session

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.insert.return_value = mock_builder
    mock_builder.update.return_value = mock_builder
    # Return empty active session list or session with escalations_sent = 0
    mock_builder.execute.side_effect = [
        MagicMock(data=[]), # select active sessions
        MagicMock(data=[]), # update status ended
        MagicMock(data=[{"id": "new-session"}]), # insert new session
    ]

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_builder):
        res = start_safety_session(
            user_id="user-123",
            label="meetup",
            interval_seconds=1800,
            next_checkin_at="2026-08-12T20:00:00Z",
            event_context=None,
            battery_percent=90,
            connection_type="cellular",
        )

    assert res["id"] == "new-session"


def test_start_safety_session_with_active_escalation():
    from app.db.safety.sessions import start_safety_session, EscalationInProgressError

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    # Return active session with escalations_sent > 0
    mock_builder.execute.return_value = MagicMock(data=[{"id": "session-1", "escalations_sent": 1}])

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_builder):
        with pytest.raises(EscalationInProgressError, match="Cannot start session: escalation already in progress"):
            start_safety_session(
                user_id="user-123",
                label="meetup",
                interval_seconds=1800,
                next_checkin_at="2026-08-12T20:00:00Z",
                event_context=None,
                battery_percent=90,
                connection_type="cellular",
            )


@pytest.mark.anyio
@patch("app.api.safety.endpoints.redis_client")
@patch("app.api.safety.endpoints.fetch_safety_contacts")
@patch("app.api.safety.endpoints.send_sms")
@patch("app.api.safety.endpoints.record_safety_alert")
@patch("app.api.safety.endpoints.update_alert_contacts_notified")
async def test_send_safety_alert_idempotency_new(
    mock_update: MagicMock,
    mock_record: MagicMock,
    mock_send_sms: MagicMock,
    mock_fetch_contacts: MagicMock,
    mock_redis: MagicMock,
):
    from app.api.safety.endpoints import send_safety_alert
    from app.models.safety import SafetyAlertRequest

    mock_redis.get = AsyncMock(return_value=None)
    mock_redis.set = AsyncMock()

    mock_fetch_contacts.return_value = [{"phone": "+1234567890"}]
    mock_send_sms.return_value = MagicMock(success=True)
    mock_record.return_value = {"id": "alert-789"}

    payload = SafetyAlertRequest(
        alert_type="sos_loud",
        session_id="00000000-0000-0000-0000-000000000000",
        session_label="test session",
        event_label=None,
        current_location=None,
    )

    res = await send_safety_alert(request=MagicMock(), payload=payload, user_id="user-123")

    assert res.id == "alert-789"
    assert res.contacts_notified == 1
    mock_redis.get.assert_called_once_with("safety:sos:idempotency:user-123:00000000-0000-0000-0000-000000000000")
    mock_redis.set.assert_called_once()


@pytest.mark.anyio
@patch("app.api.safety.endpoints.redis_client")
@patch("app.api.safety.endpoints.fetch_safety_contacts")
async def test_send_safety_alert_idempotency_cached(
    mock_fetch_contacts: MagicMock,
    mock_redis: MagicMock,
):
    from app.api.safety.endpoints import send_safety_alert
    from app.models.safety import SafetyAlertRequest
    import json

    cached_response = {
        "id": "alert-cached",
        "contacts_notified": 2,
        "contacts_total": 2,
    }
    mock_redis.get = AsyncMock(return_value=json.dumps(cached_response))

    payload = SafetyAlertRequest(
        alert_type="sos_loud",
        session_id="00000000-0000-0000-0000-000000000000",
        session_label="test session",
        event_label=None,
        current_location=None,
    )

    res = await send_safety_alert(request=MagicMock(), payload=payload, user_id="user-123")

    assert res.id == "alert-cached"
    assert res.contacts_notified == 2
    assert res.contacts_total == 2
    mock_fetch_contacts.assert_not_called()


@pytest.mark.anyio
@patch("app.api.safety.endpoints.redis_client")
@patch("app.api.safety.endpoints.fetch_safety_contacts")
@patch("app.api.safety.endpoints.send_sms")
@patch("app.api.safety.endpoints.record_safety_alert")
@patch("app.api.safety.endpoints.sentry_sdk.capture_exception")
async def test_send_safety_alert_db_error_with_sms(
    mock_sentry: MagicMock,
    mock_record: MagicMock,
    mock_send_sms: MagicMock,
    mock_fetch_contacts: MagicMock,
    mock_redis: MagicMock,
):
    from app.api.safety.endpoints import send_safety_alert
    from app.models.safety import SafetyAlertRequest
    from app.db.client import DatabaseAccessError

    mock_redis.get = AsyncMock(return_value=None)
    mock_redis.set = AsyncMock()

    mock_fetch_contacts.return_value = [{"phone": "+1234567890"}]
    mock_send_sms.return_value = MagicMock(success=True)
    mock_record.side_effect = DatabaseAccessError("Mock DB error")

    payload = SafetyAlertRequest(
        alert_type="sos_loud",
        session_id="00000000-0000-0000-0000-000000000000",
        session_label="test session",
        event_label=None,
        current_location=None,
    )

    res = await send_safety_alert(request=MagicMock(), payload=payload, user_id="user-123")

    assert res.id.startswith("temp-")
    assert res.contacts_notified == 1
    mock_sentry.assert_called_once()


@pytest.mark.anyio
@patch("app.api.safety.endpoints.redis_client")
@patch("app.api.safety.endpoints.fetch_safety_contacts")
@patch("app.api.safety.endpoints.send_sms")
@patch("app.api.safety.endpoints.record_safety_alert")
@patch("app.api.safety.endpoints.sentry_sdk.capture_exception")
async def test_send_safety_alert_db_error_no_sms(
    mock_sentry: MagicMock,
    mock_record: MagicMock,
    mock_send_sms: MagicMock,
    mock_fetch_contacts: MagicMock,
    mock_redis: MagicMock,
):
    from app.api.safety.endpoints import send_safety_alert
    from app.models.safety import SafetyAlertRequest
    from app.db.client import DatabaseAccessError
    from fastapi import HTTPException

    mock_redis.get = AsyncMock(return_value=None)

    mock_fetch_contacts.return_value = [{"phone": "+1234567890"}]
    mock_send_sms.return_value = MagicMock(success=False)
    mock_record.side_effect = DatabaseAccessError("Mock DB error")

    payload = SafetyAlertRequest(
        alert_type="sos_loud",
        session_id="00000000-0000-0000-0000-000000000000",
        session_label="test session",
        event_label=None,
        current_location=None,
    )

    with pytest.raises(HTTPException) as exc_info:
        await send_safety_alert(request=MagicMock(), payload=payload, user_id="user-123")

    assert exc_info.value.status_code == 503
    mock_sentry.assert_called_once()


@pytest.mark.anyio
async def test_register_evidence_path_traversal():
    from app.api.safety.endpoints import register_evidence
    from app.models.safety import SafetyEvidenceRegisterRequest
    from fastapi import HTTPException

    payload_wrong_user = SafetyEvidenceRegisterRequest(
        alert_id="alert-123",
        storage_path="other_user/file.mp4",
        media_key_base64="key",
        content_type="video",
        duration_seconds=10.0,
    )

    with pytest.raises(HTTPException) as exc_info:
        await register_evidence(request=MagicMock(), payload=payload_wrong_user, user_id="user-123")
    assert exc_info.value.status_code == 422

    payload_traversal = SafetyEvidenceRegisterRequest(
        alert_id="alert-123",
        storage_path="user-123/../other_user/file.mp4",
        media_key_base64="key",
        content_type="video",
        duration_seconds=10.0,
    )

    with pytest.raises(HTTPException) as exc_info:
        await register_evidence(request=MagicMock(), payload=payload_traversal, user_id="user-123")
    assert exc_info.value.status_code == 422


def test_make_and_verify_contact_portal_token():
    from app.core.utils.sms import make_contact_portal_token, verify_contact_portal_token

    contact_id = "contact-uuid-123"
    token = make_contact_portal_token(contact_id)

    # Valid token verification returns the contact_id UUID
    val = verify_contact_portal_token(token)
    assert val == contact_id

    # Verification returns None for expired or malformed token
    assert verify_contact_portal_token("malformed-token") is None


@pytest.mark.anyio
async def test_contact_portal_page_invalid_token():
    from app.api.safety.portal.endpoints import contact_portal_page
    from fastapi import HTTPException

    with pytest.raises(HTTPException) as exc_info:
        await contact_portal_page(request=MagicMock(), contact_id="invalid-token")

    assert exc_info.value.status_code == 400


@pytest.mark.anyio
@patch("app.api.chat.events.fetch_conversation_participants")
@patch("app.api.chat.events.fetch_event")
async def test_update_chat_event_non_participant(
    mock_fetch_event: MagicMock,
    mock_fetch_participants: MagicMock,
):
    from app.api.chat.events import update_chat_event
    from app.models.chat import UpdateEventStatusRequest
    from fastapi import HTTPException

    # Set conversation participants to users other than "user-123"
    mock_fetch_participants.return_value = {
        "user_a_id": "user-aaa",
        "user_b_id": "user-bbb",
    }

    payload = UpdateEventStatusRequest(status="confirmed")

    # A non-participant should raise 403 Forbidden immediately
    with pytest.raises(HTTPException) as exc_info:
        await update_chat_event(
            request=MagicMock(),
            conversation_id="conv-123",
            event_id="event-789",
            payload=payload,
            user_id="user-123",
        )

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "Not a participant of this conversation."
    # fetch_event should NOT be called (meaning state of the event is not checked/leaked)
    mock_fetch_event.assert_not_called()


def test_create_event_request_validation():
    from app.models.chat import CreateEventRequest
    from datetime import datetime, timezone
    from pydantic import ValidationError

    # Valid with safety disabled and interval omitted
    req = CreateEventRequest(
        event_time=datetime.now(timezone.utc),
        ciphertext="AAAA",
        safety_enabled=False,
        safety_interval_seconds=None,
    )
    assert req.safety_enabled is False

    # Invalid with safety enabled and interval omitted
    with pytest.raises(ValidationError) as exc_info:
        CreateEventRequest(
            event_time=datetime.now(timezone.utc),
            ciphertext="AAAA",
            safety_enabled=True,
            safety_interval_seconds=None,
        )
    assert "safety_interval_seconds is required when safety_enabled is set" in str(exc_info.value)


@pytest.mark.anyio
@patch("app.services.reminder_scheduler.fetch_due_event_reminders")
@patch("app.services.reminder_scheduler.fetch_conversation_participants")
@patch("app.services.reminder_scheduler.send_chat_event_reminder_notification")
@patch("app.services.reminder_scheduler.mark_reminder_sent")
async def test_check_due_reminders_notification_success(
    mock_mark_sent: MagicMock,
    mock_send_notif: MagicMock,
    mock_fetch_convo: MagicMock,
    mock_fetch_due: MagicMock,
):
    from app.services.reminder_scheduler import _check_due_reminders

    mock_fetch_due.return_value = [{"id": "event-123", "conversation_id": "conv-456", "location_label": "Café"}]
    mock_fetch_convo.return_value = {"user_a_id": "user-a", "user_b_id": "user-b", "tab": "Dating"}
    mock_send_notif.return_value = True # Successful notification

    await _check_due_reminders()

    mock_send_notif.assert_called_once()
    mock_mark_sent.assert_called_once_with("event-123")


@pytest.mark.anyio
@patch("app.services.reminder_scheduler.fetch_due_event_reminders")
@patch("app.services.reminder_scheduler.fetch_conversation_participants")
@patch("app.services.reminder_scheduler.send_chat_event_reminder_notification")
@patch("app.services.reminder_scheduler.mark_reminder_sent")
async def test_check_due_reminders_notification_failure(
    mock_mark_sent: MagicMock,
    mock_send_notif: MagicMock,
    mock_fetch_convo: MagicMock,
    mock_fetch_due: MagicMock,
):
    from app.services.reminder_scheduler import _check_due_reminders

    mock_fetch_due.return_value = [{"id": "event-123", "conversation_id": "conv-456", "location_label": "Café"}]
    mock_fetch_convo.return_value = {"user_a_id": "user-a", "user_b_id": "user-b", "tab": "Dating"}
    mock_send_notif.return_value = False # Failed notification

    await _check_due_reminders()

    mock_send_notif.assert_called_once()
    mock_mark_sent.assert_not_called()


def test_fetch_key_bundle_prekey_used_true():
    from app.db.chat.keys import fetch_key_bundle

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder
    mock_builder.rpc.return_value = mock_builder

    # Returns identity prekey, signed prekey, and one-time prekey
    mock_builder.execute.side_effect = [
        MagicMock(data={"identity_public_key": "\\x01\\x02", "registration_id": 123}), # identity_public_key
        MagicMock(data={"key_id": 1, "public_key": "\\x03\\x04", "signature": "\\x05\\x06"}), # signed_prekey
        MagicMock(data=[{"key_id": 99, "public_key": "\\x07\\x08"}]), # claim_one_time_prekey
    ]

    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_builder), \
         patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_builder):
        res = fetch_key_bundle("user-123")

    assert res is not None
    assert res["one_time_prekey_used"] is True
    assert res["one_time_prekey_id"] == 99


def test_fetch_key_bundle_prekey_used_false():
    from app.db.chat.keys import fetch_key_bundle

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder
    mock_builder.rpc.return_value = mock_builder

    # Returns identity prekey, signed prekey, and empty list for one-time prekey
    mock_builder.execute.side_effect = [
        MagicMock(data={"identity_public_key": "\\x01\\x02", "registration_id": 123}),
        MagicMock(data={"key_id": 1, "public_key": "\\x03\\x04", "signature": "\\x05\\x06"}),
        MagicMock(data=[]), # claim_one_time_prekey empty (exhausted)
    ]

    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_builder), \
         patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_builder):
        res = fetch_key_bundle("user-123")

    assert res is not None
    assert res["one_time_prekey_used"] is False
    assert res["one_time_prekey_id"] is None













