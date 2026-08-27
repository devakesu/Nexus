from io import BytesIO
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
    mock_redis.incr = AsyncMock(return_value=6)
    mock_redis.get = AsyncMock(return_value="111222")

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

    async def fake_set(key: str, val: str, ex: int = 600) -> None:
        nonlocal stored_json
        stored_json = val

    async def fake_get(key: str) -> str | None:
        return stored_json

    async def fake_delete(key: str) -> None:
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


def _create_valid_png_bytes() -> bytes:
    from PIL import Image
    buf = BytesIO()
    img = Image.new("RGB", (2, 2), color=(255, 0, 0))
    img.save(buf, format="PNG")
    return buf.getvalue()


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
async def test_upload_contact_attachment_success(mock_supabase: MagicMock) -> None:
    from fastapi import UploadFile

    from app.api.feedback.contact import upload_contact_attachment

    # Mock storage list returning 2 existing objects (under the limit of 5)
    mock_storage = MagicMock()
    mock_storage.list.return_value = [{"name": "file1.png"}, {"name": "file2.png"}]
    mock_storage.upload.return_value = {"Key": "feedback_attachments/web_contact/sess123/abc.png"}
    mock_supabase.storage.from_.return_value = mock_storage

    file = UploadFile(filename="test.png", file=BytesIO(_create_valid_png_bytes()))
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
    from fastapi import UploadFile

    from app.api.feedback.contact import upload_contact_attachment

    # Mock storage list returning 5 existing objects (limit reached)
    mock_storage = MagicMock()
    mock_storage.list.return_value = [{"name": f"file{i}.png"} for i in range(5)]
    mock_supabase.storage.from_.return_value = mock_storage

    file = UploadFile(filename="overflow.png", file=BytesIO(_create_valid_png_bytes()))
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
@patch("app.api.feedback.supabase_client")
async def test_upload_contact_attachment_rejects_fake_image_magic_bytes(
    mock_supabase: MagicMock,
) -> None:
    from fastapi import UploadFile

    from app.api.feedback.contact import upload_contact_attachment

    mock_storage = MagicMock()
    mock_storage.list.return_value = []
    mock_supabase.storage.from_.return_value = mock_storage

    # Fake PHP/executable script disguised as .jpg
    fake_file = UploadFile(
        filename="exploit.jpg",
        file=BytesIO(b"<?php echo 'malicious code'; ?>"),
    )
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
            file=fake_file,
            session_id="sess123",
            turnstile_token=None,
        )

    assert exc_info.value.status_code == 400
    assert "File signature does not match permitted image formats" in exc_info.value.detail
    mock_storage.upload.assert_not_called()


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
async def test_upload_contact_attachment_rejects_corrupted_image_header(
    mock_supabase: MagicMock,
) -> None:
    from fastapi import UploadFile

    from app.api.feedback.contact import upload_contact_attachment

    mock_storage = MagicMock()
    mock_storage.list.return_value = []
    mock_supabase.storage.from_.return_value = mock_storage

    # PNG magic bytes followed by garbage payload
    corrupted_file = UploadFile(
        filename="corrupted.png",
        file=BytesIO(b"\x89PNG\r\n\x1a\n\x00\x00\x00\x00randomjunknotavalidpng"),
    )
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
            file=corrupted_file,
            session_id="sess123",
            turnstile_token=None,
        )

    assert exc_info.value.status_code == 400
    assert "Corrupted or invalid image file" in exc_info.value.detail
    mock_storage.upload.assert_not_called()


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
async def test_upload_contact_attachment_strips_exif_gps_metadata(
    mock_supabase: MagicMock,
) -> None:
    from fastapi import UploadFile
    from PIL import Image

    from app.api.feedback.contact import upload_contact_attachment

    mock_storage = MagicMock()
    mock_storage.list.return_value = []
    mock_supabase.storage.from_.return_value = mock_storage

    # Create JPEG image with GPS EXIF metadata
    img = Image.new("RGB", (10, 10), color=(100, 150, 200))
    exif = img.getexif()
    gps_ifd = exif.get_ifd(0x8825)
    gps_ifd[1] = "N"
    gps_ifd[3] = "W"
    exif[0x8825] = gps_ifd
    exif[0x010F] = "CameraModel123"

    raw_buf = BytesIO()
    img.save(raw_buf, format="JPEG", exif=exif)
    raw_bytes = raw_buf.getvalue()

    # Verify raw_bytes indeed has GPS EXIF metadata
    with Image.open(BytesIO(raw_bytes)) as raw_img:
        assert 0x8825 in raw_img.getexif()

    file = UploadFile(
        filename="photo_with_gps.jpg",
        file=BytesIO(raw_bytes),
    )
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
    mock_storage.upload.assert_called_once()

    # Inspect the uploaded file payload passed to storage
    upload_kwargs = mock_storage.upload.call_args[1]
    uploaded_bytes = upload_kwargs["file"]
    with Image.open(BytesIO(uploaded_bytes)) as stored_img:
        stored_exif = stored_img.getexif()
        assert 0x8825 not in stored_exif


@pytest.mark.anyio
async def test_read_bounded_upload_file_aborts_on_large_payload() -> None:
    from fastapi import UploadFile

    from app.api.feedback.contact import _read_bounded_upload_file

    mock_file = AsyncMock(spec=UploadFile)
    chunk_64k = b"A" * (64 * 1024)
    mock_file.read.side_effect = [chunk_64k] * 85  # ~5.4MB

    with pytest.raises(HTTPException) as exc_info:
        await _read_bounded_upload_file(mock_file, max_size=5 * 1024 * 1024)

    assert exc_info.value.status_code == 400
    assert "File size exceeds maximum limit of 5MB" in exc_info.value.detail
    assert mock_file.read.call_count <= 82


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
async def test_upload_contact_attachment_rejects_oversized_stream(
    mock_supabase: MagicMock,
) -> None:
    from fastapi import UploadFile

    from app.api.feedback.contact import upload_contact_attachment

    mock_storage = MagicMock()
    mock_storage.list.return_value = []
    mock_supabase.storage.from_.return_value = mock_storage

    mock_file = AsyncMock(spec=UploadFile)
    mock_file.filename = "large_image.png"
    chunk_64k = b"A" * (64 * 1024)
    mock_file.read.side_effect = [chunk_64k] * 90  # ~5.7MB

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
            file=mock_file,
            session_id="sess123",
            turnstile_token=None,
        )

    assert exc_info.value.status_code == 400
    assert "File size exceeds maximum limit of 5MB" in exc_info.value.detail
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


@pytest.mark.anyio
@patch("app.api.feedback.contact.logger")
@patch("app.api.feedback.redis_client")
async def test_verify_and_consume_otp_redis_error_redacts_email(
    mock_redis: MagicMock,
    mock_logger: MagicMock,
) -> None:
    from redis.exceptions import RedisError

    from app.api.feedback.contact import _verify_and_consume_otp

    mock_redis.get = AsyncMock(side_effect=RedisError("Redis connection lost"))

    with pytest.raises(HTTPException) as exc_info:
        await _verify_and_consume_otp("sensitive_victim@example.com", "123456")

    assert exc_info.value.status_code == 503
    mock_logger.exception.assert_called_once()
    log_args = mock_logger.exception.call_args[0]
    formatted_msg = log_args[0] % log_args[1:]
    assert "sensitive_victim@example.com" not in formatted_msg
    assert "s***m@example.com" in formatted_msg


@pytest.mark.anyio
@patch("app.api.feedback.contact.logger")
@patch("app.api.feedback.contact.httpx.AsyncClient")
@patch("app.api.feedback.contact.settings")
async def test_verify_turnstile_token_error_logs_warning_not_exception(
    mock_settings: MagicMock,
    mock_client_cls: MagicMock,
    mock_logger: MagicMock,
) -> None:
    import httpx

    from app.api.feedback.contact import verify_turnstile_token

    mock_settings.turnstile_secret_key = "dummy_secret_key"
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.post.side_effect = httpx.ConnectTimeout("Cloudflare Turnstile connection timeout")
    mock_client_cls.return_value = mock_client

    result = await verify_turnstile_token("dummy_token", "1.2.3.4")
    assert result is False

    mock_logger.warning.assert_called_once()
    assert "Failed to verify Turnstile token" in mock_logger.warning.call_args[0][0]
    mock_logger.exception.assert_not_called()

