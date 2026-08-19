from typing import Any
from unittest.mock import ANY, AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request

from app.api.feedback import (
    ContactOtpRequest,
    ContactSubmitRequest,
    send_contact_otp,
    submit_contact_ticket,
    verify_turnstile_token,
)
from app.core.email.notifications.feedback import send_feedback_confirmation_email


@pytest.mark.anyio
@patch("app.core.email.send_email")
async def test_send_feedback_confirmation_email_props(
    mock_send_email: MagicMock,
) -> None:
    mock_send_email.return_value = MagicMock(success=True)

    res = await send_feedback_confirmation_email(
        email="testuser@example.com",
        query_type="help",
        subject="Need help with account",
        report_id="12345678-abcd-1234-abcd-1234567890ab",
    )

    assert res.success is True
    mock_send_email.assert_called_once()
    props = mock_send_email.call_args[0][0]
    assert props.to == "testuser@example.com"
    assert "We've received your help request! 💬 - Nexus Support" in props.subject
    assert "💌 TICKET RECEIVED &amp; QUEUED ✨" in props.html
    assert "We're On It! 🤝✨" in props.html
    assert "OPEN &amp; QUEUED 📥" in props.html
    assert "Helpful info while you wait:" in props.html
    assert "Hi Testuser! 👋" in props.text


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
@patch("app.api.feedback.redis_client")
@patch("app.api.feedback.send_support_appeal_otp_email")
async def test_send_contact_otp_flow(
    mock_send_email: MagicMock,
    mock_redis: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    _ = mock_supabase
    mock_redis.set = AsyncMock()
    mock_send_email.return_value.success = True

    payload = ContactOtpRequest(email="user@example.com", turnstile_token=None)
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/contact/otp/send",
        "client": ("127.0.0.1", 12345),
    }
    request = Request(scope)
    res = await send_contact_otp(request=request, payload=payload)

    assert res == {"success": True}
    mock_redis.set.assert_called_once()
    mock_send_email.assert_called_once_with("user@example.com", ANY)


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
@patch("app.api.feedback.redis_client")
@patch("app.api.feedback.record_feedback_submission")
@patch("app.api.feedback.send_feedback_confirmation_email")
@patch("app.api.feedback.send_feedback_admin_notification_email")
async def test_submit_contact_ticket_guest_flow(
    mock_admin_email: MagicMock,
    mock_conf_email: MagicMock,
    mock_record_sub: MagicMock,
    mock_redis: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    _ = mock_conf_email
    _ = mock_admin_email

    async def fake_redis_get(key: str) -> str | None:
        return "0" if "otp_attempts" in key else "654321"

    mock_redis.get = AsyncMock(side_effect=fake_redis_get)
    mock_redis.delete = AsyncMock()

    # RPC returns None (unregistered email / guest visitor)
    mock_rpc_exec = MagicMock()
    mock_rpc_exec.execute.return_value.data = None
    mock_supabase.rpc.return_value = mock_rpc_exec

    mock_record_sub.return_value = {"id": "ticket-uuid-789", "status": "open"}

    payload = ContactSubmitRequest(
        email="guest@example.com",
        otp_code="654321",
        query_type="suspended",
        subject="Account Appeal Query",
        message="I would like to request an appeal for my account.",
        name="Guest User",
        account_id_or_phone="@guest_user",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/contact/submit",
        "client": ("127.0.0.1", 12345),
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    res = await submit_contact_ticket(
        request=request,
        background_tasks=bg_tasks,
        payload=payload,
    )

    assert res["success"] is True
    assert res["ticket_id"] == "ticket-uuid-789"
    assert res["status"] == "open"

    # Verify user_id was passed as None for guest submission
    mock_record_sub.assert_called_once()
    call_kwargs = mock_record_sub.call_args.kwargs
    assert call_kwargs["user_id"] is None
    assert call_kwargs["query_type"] == "suspended"
    assert call_kwargs["contact_email"] == "guest@example.com"
    assert call_kwargs["metadata"]["submitter_name"] == "Guest User"


@pytest.mark.anyio
@patch("app.api.feedback.redis_client")
async def test_submit_contact_ticket_invalid_otp(mock_redis: MagicMock) -> None:
    async def fake_invalid_otp(key: str) -> str | None:
        return "0" if "otp_attempts" in key else "111222"

    mock_redis.get = AsyncMock(side_effect=fake_invalid_otp)

    payload = ContactSubmitRequest(
        email="user@example.com",
        otp_code="999999",
        subject="Test Subject",
        message="Test Message Details",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/contact/submit",
        "client": ("127.0.0.1", 12345),
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    with pytest.raises(HTTPException) as exc_info:
        await submit_contact_ticket(
            request=request,
            background_tasks=bg_tasks,
            payload=payload,
        )

    assert exc_info.value.status_code == 400
    assert "Invalid or expired" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.feedback.redis_client")
async def test_submit_contact_ticket_otp_attempts_lockout(mock_redis: MagicMock) -> None:
    async def fake_redis_get(key: str) -> str | None:
        if "otp_attempts" in key:
            return "5"
        return "111222"

    mock_redis.get = AsyncMock(side_effect=fake_redis_get)

    payload = ContactSubmitRequest(
        email="user@example.com",
        otp_code="111222",
        subject="Test Subject",
        message="Test Message Details",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/contact/submit",
        "client": ("127.0.0.1", 12345),
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    with pytest.raises(HTTPException) as exc_info:
        await submit_contact_ticket(
            request=request,
            background_tasks=bg_tasks,
            payload=payload,
        )

    assert exc_info.value.status_code == 429
    assert "Too many incorrect attempts" in exc_info.value.detail



@pytest.mark.anyio
async def test_feedback_submit_request_all_query_types() -> None:
    from app.models import FeedbackSubmitRequest

    categories: list[Any] = [
        "help",
        "feedback",
        "bug_report",
        "suspended",
        "security",
        "legal_grievance",
        "grievance",
        "other",
    ]
    for cat in categories:
        req = FeedbackSubmitRequest(
            query_type=cat,
            subject="Test subject for category",
            message="This is a test message long enough to pass validation.",
        )
        assert req.query_type == cat


@pytest.mark.anyio
async def test_turnstile_verification_disabled_by_default() -> None:
    # When turnstile_secret_key is None (default in config), verify returns True
    res = await verify_turnstile_token(token=None, client_ip="127.0.0.1")
    assert res is True


@pytest.mark.anyio
@patch("app.api.feedback.redis_client")
async def test_create_and_get_error_session_flow(mock_redis: MagicMock) -> None:
    from app.api.feedback.contact import create_error_session, get_error_session
    from app.api.feedback.models import ErrorSessionCreateRequest

    stored_json: str | None = None

    async def fake_set(key: str, val: str, ex: int = 600) -> None:  # noqa: ARG001
        nonlocal stored_json
        stored_json = val

    async def fake_get(key: str) -> str | None:  # noqa: ARG001
        return stored_json

    async def fake_delete(key: str) -> None:  # noqa: ARG001
        nonlocal stored_json
        stored_json = None

    mock_redis.set = AsyncMock(side_effect=fake_set)
    mock_redis.get = AsyncMock(side_effect=fake_get)
    mock_redis.delete = AsyncMock(side_effect=fake_delete)

    payload = ErrorSessionCreateRequest(
        query_type="bug_report",
        subject="Critical Error: Out of memory",
        message="--- ERROR DIAGNOSTICS ---\nDetails: Null pointer exception",
        email="testuser@example.com",
        name="Test User",
        sentry_event_id="abc123sentry",
        app_version="1.2.0",
        platform="android",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/contact/error-session",
        "client": ("127.0.0.1", 12345),
    }
    request = Request(scope)

    res_create = await create_error_session(request=request, payload=payload)
    assert "session_id" in res_create
    assert res_create["session_id"].startswith("err_sess_")

    session_id = res_create["session_id"]
    res_get = await get_error_session(request=request, session_id=session_id)

    assert res_get["subject"] == "Critical Error: Out of memory"
    assert res_get["email"] == "testuser@example.com"
    assert res_get["name"] == "Test User"
    assert res_get["sentry_event_id"] == "abc123sentry"
    assert res_get["platform"] == "android"


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
async def test_upload_contact_attachment_success(mock_supabase: MagicMock) -> None:
    from io import BytesIO

    from fastapi import UploadFile

    from app.api.feedback.contact import upload_contact_attachment

    # Mock storage list returning 2 existing objects (under the limit of 5)
    mock_storage = MagicMock()
    mock_storage.list.return_value = [{"name": "file1.png"}, {"name": "file2.png"}]
    mock_storage.upload.return_value = {"Key": "feedback_attachments/web_contact/sess123/abc.png"}
    mock_supabase.storage.from_.return_value = mock_storage

    file = UploadFile(filename="test.png", file=BytesIO(b"fake image data"))
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/contact/upload",
        "client": ("127.0.0.1", 12345),
    }
    request = Request(scope)

    res = await upload_contact_attachment(
        request=request,
        file=file,
        session_id="sess123",
        turnstile_token=None,
    )

    assert "storage_path" in res
    assert res["storage_path"].startswith("web_contact/sess123/")
    assert res["filename"] == "test.png"
    mock_storage.list.assert_called_once_with("web_contact/sess123")
    mock_storage.upload.assert_called_once()


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
async def test_upload_contact_attachment_max_limit_exceeded(mock_supabase: MagicMock) -> None:
    from io import BytesIO

    from fastapi import UploadFile

    from app.api.feedback.contact import upload_contact_attachment

    # Mock storage list returning 5 existing objects (limit reached)
    mock_storage = MagicMock()
    mock_storage.list.return_value = [{"name": f"file{i}.png"} for i in range(5)]
    mock_supabase.storage.from_.return_value = mock_storage

    file = UploadFile(filename="overflow.png", file=BytesIO(b"fake image data"))
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/contact/upload",
        "client": ("127.0.0.1", 12345),
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await upload_contact_attachment(
            request=request,
            file=file,
            session_id="sess123",
            turnstile_token=None,
        )

    assert exc_info.value.status_code == 400
    assert "Maximum attachment limit of 5 files reached" in exc_info.value.detail
    mock_storage.upload.assert_not_called()


@pytest.mark.anyio
@patch("app.api.feedback.redis_client")
async def test_submit_contact_ticket_too_many_attachments(mock_redis: MagicMock) -> None:
    _ = mock_redis
    payload = ContactSubmitRequest(
        email="user@example.com",
        otp_code="111222",
        subject="Test Subject",
        message="Test Message Details",
        attachment_paths=[f"web_contact/sess/img{i}.png" for i in range(6)],
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/contact/submit",
        "client": ("127.0.0.1", 12345),
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    with pytest.raises(HTTPException) as exc_info:
        await submit_contact_ticket(
            request=request,
            background_tasks=bg_tasks,
            payload=payload,
        )

    assert exc_info.value.status_code == 400
    assert "Cannot submit more than 5 attachments" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
@patch("app.api.feedback.redis_client")
@patch("app.api.feedback.record_feedback_submission")
@patch("app.api.feedback.send_feedback_confirmation_email")
@patch("app.api.feedback.send_feedback_admin_notification_email")
async def test_submit_contact_ticket_validates_attachments_exist(
    mock_admin_email: MagicMock,
    mock_conf_email: MagicMock,
    mock_record_sub: MagicMock,
    mock_redis: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    _ = mock_conf_email
    _ = mock_admin_email

    async def fake_redis_get(key: str) -> str | None:
        return "0" if "otp_attempts" in key else "123456"

    mock_redis.get = AsyncMock(side_effect=fake_redis_get)
    mock_redis.delete = AsyncMock()

    mock_storage = MagicMock()
    mock_storage.list.return_value = [{"name": "att1.png"}, {"name": "att2.png"}]
    mock_supabase.storage.from_.return_value = mock_storage

    mock_rpc_exec = MagicMock()
    mock_rpc_exec.execute.return_value.data = None
    mock_supabase.rpc.return_value = mock_rpc_exec

    mock_record_sub.return_value = {"id": "ticket-uuid-999", "status": "open"}

    payload = ContactSubmitRequest(
        email="user@example.com",
        otp_code="123456",
        subject="Attachment Test",
        message="Checking attachment validation in storage.",
        attachment_paths=["web_contact/sess123/att1.png", "web_contact/sess123/att2.png"],
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/contact/submit",
        "client": ("127.0.0.1", 12345),
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    res = await submit_contact_ticket(
        request=request,
        background_tasks=bg_tasks,
        payload=payload,
    )

    assert res["success"] is True
    mock_storage.list.assert_called_once_with("web_contact/sess123")


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
@patch("app.api.feedback.redis_client")
async def test_submit_contact_ticket_rejects_nonexistent_attachment(
    mock_redis: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    async def fake_redis_get(key: str) -> str | None:
        return "0" if "otp_attempts" in key else "123456"

    mock_redis.get = AsyncMock(side_effect=fake_redis_get)
    mock_storage = MagicMock()
    mock_storage.list.return_value = [{"name": "actual_file.png"}]
    mock_supabase.storage.from_.return_value = mock_storage

    payload = ContactSubmitRequest(
        email="user@example.com",
        otp_code="123456",
        subject="Attachment Test",
        message="Checking attachment validation in storage.",
        attachment_paths=["web_contact/sess123/phantom_file.png"],
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/contact/submit",
        "client": ("127.0.0.1", 12345),
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    with pytest.raises(HTTPException) as exc_info:
        await submit_contact_ticket(
            request=request,
            background_tasks=bg_tasks,
            payload=payload,
        )

    assert exc_info.value.status_code == 400
    assert "Attachment file not found: phantom_file.png" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.feedback.redis_client")
async def test_submit_contact_ticket_rejects_malformed_attachment_path(
    mock_redis: MagicMock,
) -> None:
    async def fake_redis_get(key: str) -> str | None:
        return "0" if "otp_attempts" in key else "123456"

    mock_redis.get = AsyncMock(side_effect=fake_redis_get)
    payload = ContactSubmitRequest(
        email="user@example.com",
        otp_code="123456",
        subject="Attachment Test",
        message="Checking attachment validation in storage.",
        attachment_paths=["../other_bucket/secret.png"],
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/contact/submit",
        "client": ("127.0.0.1", 12345),
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    with pytest.raises(HTTPException) as exc_info:
        await submit_contact_ticket(
            request=request,
            background_tasks=bg_tasks,
            payload=payload,
        )

    assert exc_info.value.status_code == 400
    assert "Invalid attachment path" in exc_info.value.detail



