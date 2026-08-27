"""Test Suite for Test Feedback Api.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
import io
from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import BackgroundTasks, HTTPException, UploadFile
from PIL import Image
from postgrest.exceptions import APIError
from redis.exceptions import RedisError
from starlette.datastructures import Headers
from starlette.requests import Request

from app.api.feedback.contact import (
    _read_bounded_upload_file,
    _strip_exif_metadata,
    _validate_uploaded_image,
    send_contact_otp,
    submit_contact_ticket,
    upload_contact_attachment,
    verify_turnstile_token,
)
from app.api.feedback.models import (
    ContactOtpRequest,
    ContactSubmitRequest,
    ErrorSessionCreateRequest,
)
from app.api.feedback.tickets import (
    add_feedback_comment,
    close_feedback_ticket,
    get_feedback_ticket,
    list_my_feedback_tickets,
    submit_feedback,
)
from app.db.client import DatabaseAccessError
from app.models import (
    FeedbackCloseRequest,
    FeedbackCommentRequest,
    FeedbackSubmitRequest,
    FeedbackTicketDetail,
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


async def test_api_feedback_contact():
    from app.api.feedback.contact import (
        _read_bounded_upload_file,
        submit_contact_ticket,
    )
    from app.api.feedback.models import ContactSubmitRequest

    # 1. _read_bounded_upload_file
    uf = UploadFile(file=MagicMock(), filename="test.png")
    uf.read = AsyncMock(side_effect=[b"chunk1", b"chunk2", b""])
    data = await _read_bounded_upload_file(uf, max_size=1024)
    assert data == b"chunk1chunk2"

    uf_overflow = UploadFile(file=MagicMock(), filename="test.png")
    uf_overflow.read = AsyncMock(side_effect=[b"x" * 2000, b""])
    with pytest.raises(HTTPException):
        await _read_bounded_upload_file(uf_overflow, max_size=1024)

    # 2. submit_contact_ticket error cases
    req = _make_mock_request()
    bg = BackgroundTasks()
    payload = ContactSubmitRequest(
        email="alice@example.com",
        otp_code="123456",
        subject="Test sub",
        message="This is a valid test message for submission.",
        query_type="bug_report",
    )
    with patch(
        "app.api.feedback.contact._verify_and_consume_otp",
        AsyncMock(side_effect=HTTPException(status_code=400, detail="Invalid OTP")),
    ), pytest.raises(HTTPException):
        await submit_contact_ticket(
            request=req,
            background_tasks=bg,
            payload=payload,
        )


async def test_api_feedback_tickets_deep():
    from app.api.feedback.tickets import (
        add_feedback_comment,
        close_feedback_ticket,
        get_feedback_ticket,
        list_my_feedback_tickets,
        submit_feedback,
    )
    from app.models import (
        FeedbackCloseRequest,
        FeedbackCommentRequest,
        FeedbackSubmitRequest,
    )

    mock_req = MagicMock()
    bg = MagicMock()

    now_iso = datetime.now(timezone.utc).isoformat()
    mock_report: dict[str, Any] = {
        "id": "1",
        "user_id": USER_1,
        "query_type": "bug_report",
        "subject": "Bug",
        "message": "App crashed",
        "status": "open",
        "attachment_paths": [],
        "created_at": now_iso,
        "updated_at": now_iso,
    }

    with (
        patch(
            "app.api.feedback.tickets.feedback_module.record_feedback_submission",
            return_value={"id": "1", "created_at": now_iso, "status": "open"},
        ),
        patch("app.api.feedback.tickets.fetch_user_tickets", return_value=[]),
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
            return_value=mock_report,
        ),
        patch("app.api.feedback.tickets.fetch_ticket_comments", return_value=[]),
        patch("app.api.feedback.tickets.fetch_ticket_status_history", return_value=[]),
        patch(
            "app.api.feedback.tickets.feedback_module.add_ticket_comment",
            return_value={
                "id": "1",
                "report_id": "1",
                "author_id": USER_1,
                "body": "more",
                "created_at": now_iso,
            },
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.close_ticket",
            return_value=mock_report,
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_user_email",
            return_value="alice@berkeley.edu",
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.send_feedback_confirmation_email",
            AsyncMock(),
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.send_feedback_admin_notification_email",
            AsyncMock(),
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.send_feedback_comment_admin_notification_email",
            AsyncMock(),
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.send_feedback_closed_admin_notification_email",
            AsyncMock(),
        ),
    ):
        # Submit
        sub = await submit_feedback(
            request=mock_req,
            background_tasks=bg,
            payload=FeedbackSubmitRequest(
                query_type="bug_report",
                subject="Bug sub",
                message="Detailed bug report message",
            ),
            user_id=USER_1,
            _device=None,
        )
        assert sub is not None

        # List
        lst = await list_my_feedback_tickets(mock_req, _device=None, user_id=USER_1)
        assert len(lst) >= 0

        # Get
        t = await get_feedback_ticket(
            mock_req, report_id="1", _device=None, user_id=USER_1,
        )
        assert t is not None

        # Add comment
        c = await add_feedback_comment(
            request=mock_req,
            report_id="1",
            background_tasks=bg,
            payload=FeedbackCommentRequest(body="Here is more info"),
            _device=None,
            user_id=USER_1,
        )
        assert c is not None

        # Close
        cl = await close_feedback_ticket(
            mock_req,
            report_id="1",
            background_tasks=bg,
            payload=FeedbackCloseRequest(reason="resolved"),
            _device=None,
            user_id=USER_1,
        )
        assert cl is not None


async def test_api_feedback_tickets_deep_p10():
    from app.api.feedback.tickets import (
        add_feedback_comment,
        assemble_ticket_detail,
        close_feedback_ticket,
        get_feedback_ticket,
        list_my_feedback_tickets,
        submit_feedback,
    )
    from app.models import (
        FeedbackCloseRequest,
        FeedbackCommentRequest,
        FeedbackSubmitRequest,
    )

    mock_req = MagicMock()
    bg = MagicMock()
    now_iso = datetime.now(timezone.utc).isoformat()

    mock_report: dict[str, Any] = {
        "id": REPORT_1,
        "user_id": USER_1,
        "query_type": "help",
        "subject": "Need assistance",
        "status": "open",
        "created_at": now_iso,
        "updated_at": now_iso,
        "message": "Message body here",
        "attachment_paths": [],
    }

    mock_history = [
        {
            "id": "h1",
            "report_id": REPORT_1,
            "status": "open",
            "changed_by": USER_1,
            "created_at": now_iso,
        },
    ]
    mock_comments = [
        {
            "id": "c1",
            "report_id": REPORT_1,
            "author_id": USER_1,
            "body": "Comment body",
            "created_at": now_iso,
        },
    ]

    with (
        patch(
            "app.api.feedback.tickets.feedback_module.record_feedback_submission",
            return_value=mock_report,
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_user_email",
            return_value="a@b.com",
        ),
        patch(
            "app.api.feedback.tickets.fetch_user_tickets", return_value=[mock_report],
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
            return_value=mock_report,
        ),
        patch(
            "app.api.feedback.tickets.fetch_ticket_status_history",
            return_value=mock_history,
        ),
        patch(
            "app.api.feedback.tickets.fetch_ticket_comments", return_value=mock_comments,
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.add_ticket_comment",
            return_value=mock_comments[0],
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.close_ticket",
            return_value=mock_report,
        ),
        patch(
            "app.api.feedback.tickets.feedback_module._assemble_ticket_detail",
            AsyncMock(return_value=MagicMock()),
        ),
    ):
        # submit
        sub_req = FeedbackSubmitRequest(
            query_type="help", subject="Help", message="Help message long enough",
        )
        sub_res = await submit_feedback(
            mock_req, bg, sub_req, _device=None, user_id=USER_1,
        )
        assert sub_res.id == REPORT_1

        # list & get
        my_t = await list_my_feedback_tickets(
            mock_req, 10, 0, _device=None, user_id=USER_1,
        )
        assert len(my_t) == 1

        await get_feedback_ticket(mock_req, REPORT_1, _device=None, user_id=USER_1)

        # comment & close
        await add_feedback_comment(
            mock_req,
            REPORT_1,
            bg,
            FeedbackCommentRequest(body="Comment text"),
            _device=None,
            user_id=USER_1,
        )
        await close_feedback_ticket(
            mock_req,
            REPORT_1,
            bg,
            FeedbackCloseRequest(reason="Resolved"),
            _device=None,
            user_id=USER_1,
        )

        # assemble detail
        detail = await assemble_ticket_detail(USER_1, mock_report)
        assert detail.id == REPORT_1


async def test_api_feedback_contact_exhaustive():
    from app.api.feedback.contact import (
        _parse_attachment_path,
        _strip_exif_metadata,
        _validate_uploaded_image,
        create_error_session,
        delete_contact_attachments,
        get_error_session,
        send_contact_otp,
        submit_contact_ticket,
        upload_contact_attachment,
        verify_turnstile_token,
    )
    from app.api.feedback.models import (
        ContactOtpRequest,
        ContactSubmitRequest,
        ErrorSessionCreateRequest,
    )

    mock_req = MagicMock()
    mock_req.client.host = "127.0.0.1"
    bg = MagicMock()

    # Image validation
    img_buf = io.BytesIO()
    Image.new("RGB", (100, 100)).save(img_buf, format="JPEG")
    valid_bytes = img_buf.getvalue()
    valid_upload = UploadFile(filename="pic.jpg", file=io.BytesIO(valid_bytes))

    ext = _validate_uploaded_image(valid_upload, valid_bytes)
    assert ext == ".jpg"
    stripped = _strip_exif_metadata(valid_bytes, ".jpg")
    assert len(stripped) > 0

    assert _parse_attachment_path("web_contact/sess1/pic.jpg") == ("sess1", "pic.jpg")
    with pytest.raises(HTTPException):
        _parse_attachment_path("invalid/path")

    with patch("app.api.feedback.contact.settings.turnstile_secret_key", ""):
        assert await verify_turnstile_token("tok", "127.0.0.1") is True

    # Contact OTP & Sessions
    with (
        patch("app.api.feedback.contact.feedback_module.redis_client") as mock_r,
        patch(
            "app.api.feedback.contact.feedback_module.send_support_appeal_otp_email",
            AsyncMock(return_value=MagicMock(success=True)),
        ),
        patch(
            "app.api.feedback.contact.feedback_module.supabase_client.storage.from_",
        ) as mock_storage,
        patch(
            "app.api.feedback.contact.feedback_module.record_feedback_submission",
            return_value={"id": "1", "status": "open"},
        ),
        patch("app.api.feedback.contact._verify_and_consume_otp", AsyncMock()),
        patch("app.api.feedback.contact._validate_contact_attachments", AsyncMock()),
        patch(
            "app.api.feedback.contact._get_user_id_by_email",
            AsyncMock(return_value=USER_1),
        ),
    ):
        mock_r.get = AsyncMock(return_value='{"query_type":"help","subject":"hi"}')
        mock_r.set = AsyncMock(return_value=True)
        mock_r.delete = AsyncMock(return_value=True)
        mock_storage.return_value.list.return_value = []
        mock_storage.return_value.upload.return_value = None
        mock_storage.return_value.remove.return_value = None

        # send otp
        otp_res = await send_contact_otp(mock_req, ContactOtpRequest(email="a@b.com"))
        assert otp_res["success"] is True

        # submit ticket
        sub_res = await submit_contact_ticket(
            mock_req,
            bg,
            ContactSubmitRequest(
                email="a@b.com",
                otp_code="123456",
                query_type="bug_report",
                subject="Crash",
                message="Detailed crash message here",
            ),
        )
        assert sub_res["success"] is True

        # upload & delete attachment
        up_res = await upload_contact_attachment(
            mock_req, valid_upload, session_id="sess1",
        )
        assert "storage_path" in up_res

        del_res = await delete_contact_attachments(
            mock_req, session_id="sess1", paths=["web_contact/sess1/pic.jpg"],
        )
        assert del_res["success"] is True

        # error sessions
        err_res = await create_error_session(
            mock_req,
            ErrorSessionCreateRequest(
                query_type="bug_report",
                subject="Error",
                message="Error details",
            ),
        )
        assert "session_id" in err_res

        get_err = await get_error_session(mock_req, err_res["session_id"])
        assert get_err["query_type"] == "help"


async def test_feedback_contact_internals_and_validations():
    from app.api.feedback.contact import (
        _check_session_upload_quota,
        _cleanup_attachments_on_failure,
        _get_user_id_by_email,
        _parse_attachment_path,
        _read_bounded_upload_file,
        _strip_exif_metadata,
        _validate_contact_attachments,
        _validate_uploaded_image,
        _verify_and_consume_otp,
        _verify_session_storage_files,
        create_error_session,
        delete_contact_attachments,
        get_error_session,
        send_contact_otp,
        submit_contact_ticket,
        upload_contact_attachment,
        verify_turnstile_token,
    )

    # _read_bounded_upload_file max size exceeded
    mock_file = AsyncMock(spec=UploadFile)
    mock_file.read.side_effect = [b"a" * 100, b"b" * 100, b""]
    with pytest.raises(HTTPException) as exc:
        await _read_bounded_upload_file(mock_file, max_size=150)
    assert exc.value.status_code == 400

    # verify_turnstile_token with secret set
    with patch("app.api.feedback.contact.settings.turnstile_secret_key", "secret123"):
        # No token provided
        assert await verify_turnstile_token(None) is False

        # Success response False
        with patch("httpx.AsyncClient.post") as mock_post:
            mock_post.return_value = MagicMock(json=lambda: {"success": False})
            assert await verify_turnstile_token("token-val", "127.0.0.1") is False

            # Exception
            mock_post.side_effect = Exception("network fail")
            assert await verify_turnstile_token("token-val", "127.0.0.1") is False

    # _validate_uploaded_image errors
    f = MagicMock(spec=UploadFile)
    f.filename = None
    with pytest.raises(HTTPException, match="Invalid file uploaded"):
        _validate_uploaded_image(f, b"")

    f.filename = "test.png"
    with pytest.raises(HTTPException, match="Invalid file payload"):
        _validate_uploaded_image(f, b"short")

    with pytest.raises(HTTPException, match="File size exceeds maximum limit"):
        _validate_uploaded_image(f, b"x" * (6 * 1024 * 1024))

    with pytest.raises(HTTPException, match="File signature does not match"):
        _validate_uploaded_image(f, b"0123456789012345")

    # Valid PNG magic bytes but corrupted payload
    corrupted_png = b"\x89PNG\r\n\x1a\n12345678"
    with pytest.raises(HTTPException, match="Corrupted or invalid image file"):
        _validate_uploaded_image(f, corrupted_png)

    # Valid PIL image but invalid extension
    img_buf = io.BytesIO()
    Image.new("RGB", (10, 10), color="blue").save(img_buf, format="PNG")
    valid_png_bytes = img_buf.getvalue()

    f.filename = "test.exe"
    with pytest.raises(HTTPException, match="Only image files"):
        _validate_uploaded_image(f, valid_png_bytes)

    # Unsupported format (e.g. GIF)
    gif_buf = io.BytesIO()
    Image.new("RGB", (10, 10), color="red").save(gif_buf, format="GIF")
    f.filename = "test.gif"
    with pytest.raises(HTTPException):
        _validate_uploaded_image(f, gif_buf.getvalue())

    # _strip_exif_metadata RGBA to JPEG conversion & Exception fallback
    rgba_img = Image.new("RGBA", (10, 10), color=(255, 0, 0, 128))
    rgba_buf = io.BytesIO()
    rgba_img.save(rgba_buf, format="PNG")
    stripped_jpeg = _strip_exif_metadata(rgba_buf.getvalue(), ".jpg")
    assert len(stripped_jpeg) > 0

    with patch("PIL.Image.open", side_effect=Exception("strip error")):
        assert _strip_exif_metadata(b"raw-data", ".png") == b"raw-data"

    # _check_session_upload_quota quota exceeded & warning log
    with patch(
        "app.api.feedback.contact._list_storage_attachments",
        return_value=[{"name": f"f{i}"} for i in range(10)],
    ), pytest.raises(HTTPException, match="Maximum attachment limit"):
        await _check_session_upload_quota("sess1")

    with patch(
        "app.api.feedback.contact._list_storage_attachments",
        side_effect=Exception("quota check fail"),
    ):
        # Should catch and log warning without raising
        await _check_session_upload_quota("sess1")

    # upload_contact_attachment: turnstile fail, invalid clean_session, storage upload exception
    mock_req = MagicMock()
    mock_req.client.host = "127.0.0.1"

    with patch(
        "app.api.feedback.contact.verify_turnstile_token", AsyncMock(return_value=False),
    ), pytest.raises(HTTPException, match="Security verification failed"):
        await upload_contact_attachment(mock_req, f, "sess1", "token")

    with (
        patch(
            "app.api.feedback.contact.verify_turnstile_token",
            AsyncMock(return_value=True),
        ),
        patch(
            "app.api.feedback.contact._read_bounded_upload_file",
            AsyncMock(return_value=valid_png_bytes),
        ),
        patch("app.api.feedback.contact._validate_uploaded_image", return_value=".png"),
        patch("app.api.feedback.contact._check_session_upload_quota", AsyncMock()),
    ):
        with pytest.raises(HTTPException, match="Invalid session_id"):
            await upload_contact_attachment(mock_req, f, "???!!!", "token")

        with patch(
            "app.api.feedback.contact.feedback_module.supabase_client",
        ) as mock_sb:
            mock_sb.storage.from_().upload.side_effect = Exception("Upload fail")
            with pytest.raises(HTTPException, match="Failed to store attachment file"):
                await upload_contact_attachment(mock_req, f, "valid-sess-1", "token")

    # delete_contact_attachments: turnstile fail, invalid session_id, no safe paths, remove exception
    with patch(
        "app.api.feedback.contact.verify_turnstile_token", AsyncMock(return_value=False),
    ), pytest.raises(HTTPException, match="Security verification failed"):
        await delete_contact_attachments(mock_req, "sess1", ["path1"], "token")

    with patch(
        "app.api.feedback.contact.verify_turnstile_token", AsyncMock(return_value=True),
    ):
        with pytest.raises(HTTPException, match="Invalid session_id"):
            await delete_contact_attachments(mock_req, "???", ["path1"], "token")

        # No safe paths
        res_del = await delete_contact_attachments(
            mock_req, "sess1", ["unsafe/path"], "token",
        )
        assert res_del == {"success": True}

        # Safe paths with remove exception
        with patch(
            "app.api.feedback.contact.feedback_module.supabase_client",
        ) as mock_sb:
            mock_sb.storage.from_().remove.side_effect = APIError({"message": "fail"})
            res_del = await delete_contact_attachments(
                mock_req, "sess1", ["web_contact/sess1/file.png"], "token",
            )
            assert res_del == {"success": True}

    # send_contact_otp: turnstile fail, invalid email, redis set exception, email send failure
    with patch(
        "app.api.feedback.contact.verify_turnstile_token", AsyncMock(return_value=False),
    ), pytest.raises(HTTPException, match="Security verification failed"):
        await send_contact_otp(
            mock_req, ContactOtpRequest(email="a@b.com", turnstile_token="t"),
        )

    with patch(
        "app.api.feedback.contact.verify_turnstile_token", AsyncMock(return_value=True),
    ):
        with pytest.raises(HTTPException, match="valid email is required"):
            await send_contact_otp(
                mock_req, ContactOtpRequest(email="invalidemail", turnstile_token="t"),
            )

        with patch(
            "app.api.feedback.contact.feedback_module.redis_client",
        ) as mock_redis:
            mock_redis.set = AsyncMock(side_effect=RedisError("Redis down"))
            with pytest.raises(
                HTTPException, match="Support service temporarily unavailable",
            ):
                await send_contact_otp(
                    mock_req,
                    ContactOtpRequest(email="test@example.com", turnstile_token="t"),
                )

            mock_redis.set = AsyncMock()
            mock_redis.delete = AsyncMock()
            with patch(
                "app.api.feedback.contact.feedback_module.send_support_appeal_otp_email",
                AsyncMock(return_value=MagicMock(success=False)),
            ):
                with pytest.raises(
                    HTTPException, match="Failed to send verification email",
                ):
                    await send_contact_otp(
                        mock_req,
                        ContactOtpRequest(
                            email="test@example.com", turnstile_token="t",
                        ),
                    )

    # _verify_and_consume_otp: RedisError -> 503
    with patch(
        "app.api.feedback.contact.verify_and_consume_raw_otp",
        AsyncMock(side_effect=RedisError("fail")),
    ), pytest.raises(
        HTTPException, match="Support service temporarily unavailable",
    ):
        await _verify_and_consume_otp("test@example.com", "123456")

    # _get_user_id_by_email: APIError -> returns None
    with patch("app.api.feedback.contact.feedback_module.supabase_client") as mock_sb:
        mock_sb.rpc().execute.side_effect = APIError({"message": "fail"})
        assert await _get_user_id_by_email("test@example.com") is None

    # _cleanup_attachments_on_failure: empty and APIError
    await _cleanup_attachments_on_failure([])
    with patch("app.api.feedback.contact.feedback_module.supabase_client") as mock_sb:
        mock_sb.storage.from_().remove.side_effect = APIError({"message": "fail"})
        await _cleanup_attachments_on_failure(["web_contact/sess1/img.png"])

    # _parse_attachment_path error cases
    with pytest.raises(HTTPException, match="Invalid attachment path"):
        _parse_attachment_path("other_prefix/sess/img.png")
    with pytest.raises(HTTPException, match="Invalid attachment path format"):
        _parse_attachment_path("web_contact/sess/img/sub.png")
    with pytest.raises(HTTPException, match="Invalid attachment path format"):
        _parse_attachment_path("web_contact//img.png")
    with pytest.raises(HTTPException, match="Invalid session identifier"):
        _parse_attachment_path("web_contact/sess!@#/img.png")

    # _verify_session_storage_files & _validate_contact_attachments
    with patch(
        "app.api.feedback.contact._list_storage_attachments",
        return_value=[{"name": "found.png"}],
    ), pytest.raises(HTTPException, match="Attachment file not found"):
        await _verify_session_storage_files("sess1", ["notfound.png"])

    with patch(
        "app.api.feedback.contact._list_storage_attachments",
        side_effect=Exception("list fail"),
    ), pytest.raises(HTTPException, match="Attachment verification failed"):
        await _verify_session_storage_files("sess1", ["found.png"])

    with pytest.raises(HTTPException, match="Cannot submit more than"):
        await _validate_contact_attachments(["web_contact/sess/f.png"] * 10)

    # submit_contact_ticket: security fail & DB insert fail
    bg = BackgroundTasks()
    fake_sub_payload = MagicMock()
    fake_sub_payload.turnstile_token = None
    fake_sub_payload.otp_code = ""
    fake_sub_payload.email = "test@example.com"
    fake_sub_payload.attachment_paths = []
    with pytest.raises(HTTPException, match="Security verification failed"):
        await submit_contact_ticket(mock_req, bg, fake_sub_payload)

    with (
        patch("app.api.feedback.contact._validate_contact_attachments", AsyncMock()),
        patch("app.api.feedback.contact._verify_and_consume_otp", AsyncMock()),
        patch(
            "app.api.feedback.contact._get_user_id_by_email",
            AsyncMock(return_value=USER_1),
        ),
        patch(
            "app.api.feedback.contact.feedback_module.record_feedback_submission",
            side_effect=APIError({"message": "fail"}),
        ),
        patch("app.api.feedback.contact._cleanup_attachments_on_failure", AsyncMock()),
    ):
        with pytest.raises(HTTPException, match="Failed to submit support ticket"):
            await submit_contact_ticket(
                mock_req,
                bg,
                ContactSubmitRequest(
                    email="test@example.com",
                    otp_code="123456",
                    turnstile_token="t_tok",
                    subject="Help",
                    message="Message here",
                    attachment_paths=["web_contact/sess1/img.png"],
                    query_type="unknown_type",
                    name="John Doe",
                    account_id_or_phone="+1234567890",
                ),
            )

    # create_error_session & get_error_session
    with patch("app.api.feedback.contact.feedback_module.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(side_effect=RedisError("fail"))
        with pytest.raises(HTTPException, match="Failed to store error session"):
            await create_error_session(
                mock_req,
                ErrorSessionCreateRequest(
                    query_type="bug_report",
                    subject="Error",
                    message="Details",
                ),
            )

        # get_error_session 404 & 500
        mock_redis.get = AsyncMock(return_value=None)
        with pytest.raises(HTTPException, match="Error session expired"):
            await get_error_session(mock_req, "nonexistent")

        mock_redis.get = AsyncMock(side_effect=RedisError("fail"))
        with pytest.raises(HTTPException, match="Failed to retrieve error session"):
            await get_error_session(mock_req, "sess-1")


async def test_feedback_tickets_deep():
    from app.api.feedback.tickets import (
        _is_valid_attachment_path,
        _verify_user_storage_files,
        add_feedback_comment,
        close_feedback_ticket,
        get_feedback_ticket,
        list_my_feedback_tickets,
        submit_feedback,
    )

    req = make_dummy_request()
    bg = MagicMock()

    # _is_valid_attachment_path
    assert _is_valid_attachment_path(f"{USER_1}/file.png", f"{USER_1}/") is True
    assert _is_valid_attachment_path(f"{USER_1}/../file.png", f"{USER_1}/") is False
    assert _is_valid_attachment_path("other/file.png", f"{USER_1}/") is False

    # _verify_user_storage_files: missing files, storage failure
    with patch("app.api.feedback.tickets.feedback_module.supabase_client") as mock_sb:
        mock_sb.storage.from_().list.return_value = [{"name": "image.png"}]
        with pytest.raises(HTTPException) as exc:
            await _verify_user_storage_files(USER_1, [f"{USER_1}/missing.png"])
        assert exc.value.status_code == 400

        mock_sb.storage.from_().list.side_effect = Exception("Storage down")
        with pytest.raises(HTTPException) as exc:
            await _verify_user_storage_files(USER_1, [f"{USER_1}/image.png"])
        assert exc.value.status_code == 400

    # submit_feedback: DB error, no email, success
    sub_req = FeedbackSubmitRequest(
        query_type="bug_report",
        subject="Crash on startup",
        message="Application crashes immediately upon clicking login button",
        attachment_paths=[],
    )
    with patch(
        "app.api.feedback.tickets.feedback_module.record_feedback_submission",
        side_effect=DatabaseAccessError("fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await submit_feedback(req, bg, sub_req, None, USER_1)
        assert exc.value.status_code == 503

    with (
        patch(
            "app.api.feedback.tickets.feedback_module.record_feedback_submission",
            return_value={"id": "rep-1", "created_at": datetime.now(timezone.utc)},
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_user_email",
            return_value=None,
        ),
    ):
        res = await submit_feedback(req, bg, sub_req, None, USER_1)
        assert res.id == "rep-1"

    # list_my_feedback_tickets: DB error vs success
    with patch(
        "app.api.feedback.tickets.fetch_user_tickets",
        side_effect=DatabaseAccessError("fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await list_my_feedback_tickets(req, None, 0, None, USER_1)
        assert exc.value.status_code == 503

    # get_feedback_ticket: DB error fetching, not found, DB error assembling, success
    with patch(
        "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
        side_effect=DatabaseAccessError("fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await get_feedback_ticket(req, "rep-1", None, USER_1)
        assert exc.value.status_code == 503

    with patch(
        "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
        return_value=None,
    ):
        with pytest.raises(HTTPException) as exc:
            await get_feedback_ticket(req, "rep-1", None, USER_1)
        assert exc.value.status_code == 404

    with (
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
            return_value={"id": "rep-1"},
        ),
        patch(
            "app.api.feedback.tickets.feedback_module._assemble_ticket_detail",
            side_effect=DatabaseAccessError("fail"),
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await get_feedback_ticket(req, "rep-1", None, USER_1)
        assert exc.value.status_code == 503

    # add_feedback_comment: DB error fetching, not found, closed, DB error adding, success
    cmt_req = FeedbackCommentRequest(body="More details here")
    with patch(
        "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
        side_effect=DatabaseAccessError("fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await add_feedback_comment(req, "rep-1", bg, cmt_req, None, USER_1)
        assert exc.value.status_code == 503

    with patch(
        "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
        return_value=None,
    ):
        with pytest.raises(HTTPException) as exc:
            await add_feedback_comment(req, "rep-1", bg, cmt_req, None, USER_1)
        assert exc.value.status_code == 404

    with patch(
        "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
        return_value={"id": "rep-1", "status": "closed"},
    ):
        with pytest.raises(HTTPException) as exc:
            await add_feedback_comment(req, "rep-1", bg, cmt_req, None, USER_1)
        assert exc.value.status_code == 400

    with (
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
            return_value={"id": "rep-1", "status": "open"},
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.add_ticket_comment",
            side_effect=DatabaseAccessError("fail"),
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await add_feedback_comment(req, "rep-1", bg, cmt_req, None, USER_1)
        assert exc.value.status_code == 503

    with (
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
            return_value={"id": "rep-1", "status": "open"},
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.add_ticket_comment",
            return_value={
                "id": "cmt-1",
                "report_id": "rep-1",
                "author_id": USER_1,
                "body": "More details",
                "created_at": datetime.now(timezone.utc),
            },
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_user_email",
            return_value="alice@nexus.test",
        ),
    ):
        res_cmt = await add_feedback_comment(req, "rep-1", bg, cmt_req, None, USER_1)
        assert res_cmt.id == "cmt-1"

    # close_feedback_ticket: DB error closing, report None and existing None, report None and existing closed, DB error assembling, success
    cls_req = FeedbackCloseRequest(reason="resolved")
    with patch(
        "app.api.feedback.tickets.feedback_module.close_ticket",
        side_effect=DatabaseAccessError("fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await close_feedback_ticket(req, "rep-1", bg, cls_req, None, USER_1)
        assert exc.value.status_code == 503

    with (
        patch(
            "app.api.feedback.tickets.feedback_module.close_ticket", return_value=None,
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
            return_value=None,
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await close_feedback_ticket(req, "rep-1", bg, cls_req, None, USER_1)
        assert exc.value.status_code == 404

    with (
        patch(
            "app.api.feedback.tickets.feedback_module.close_ticket", return_value=None,
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
            return_value={"id": "rep-1", "status": "closed"},
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await close_feedback_ticket(req, "rep-1", bg, cls_req, None, USER_1)
        assert exc.value.status_code == 400

    with (
        patch(
            "app.api.feedback.tickets.feedback_module.close_ticket",
            return_value={"id": "rep-1", "status": "closed"},
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_user_email",
            return_value="alice@nexus.test",
        ),
        patch(
            "app.api.feedback.tickets.feedback_module._assemble_ticket_detail",
            side_effect=DatabaseAccessError("fail"),
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await close_feedback_ticket(req, "rep-1", bg, cls_req, None, USER_1)
        assert exc.value.status_code == 503


async def test_api_feedback_contact_p5() -> None:
    # Turnstile
    with patch("app.api.feedback.contact.settings.turnstile_secret_key", ""):
        assert await verify_turnstile_token("token") is True

    # Image sanitize
    img = Image.new("RGB", (100, 100), color="red")
    img_byte_arr = io.BytesIO()
    img.save(img_byte_arr, format="JPEG")
    content = img_byte_arr.getvalue()

    mock_file = UploadFile(
        file=io.BytesIO(content),
        filename="shot.jpg",
        headers=Headers({"content-type": "image/jpeg"}),
    )
    ext = _validate_uploaded_image(mock_file, content)
    assert ext in (".jpg", "jpg")
    clean_bytes = _strip_exif_metadata(content, ext)
    assert len(clean_bytes) > 0

    # Bounded upload
    mock_upload = UploadFile(
        file=io.BytesIO(b"Hello Nexus Feedback"), size=20, filename="note.txt",
    )
    read_bytes = await _read_bounded_upload_file(mock_upload)
    assert read_bytes == b"Hello Nexus Feedback"

    # Upload attachment
    mock_request = MagicMock()
    mock_storage = MagicMock()
    mock_storage.upload.return_value = None
    mock_storage.list.return_value = []
    with (
        patch(
            "app.api.feedback.contact.feedback_module.supabase_client.storage.from_",
            return_value=mock_storage,
        ),
        patch("app.api.feedback.contact.verify_turnstile_token", return_value=True),
        patch("app.api.feedback.contact.feedback_module.redis_client", AsyncMock()),
    ):
        up_res = await upload_contact_attachment(
            mock_request,
            file=UploadFile(
                file=io.BytesIO(img_byte_arr.getvalue()),
                filename="shot.jpg",
                headers=Headers({"content-type": "image/jpeg"}),
            ),
            session_id="sess-1",
            turnstile_token="valid-token",
        )
        assert "storage_path" in up_res

    # Send OTP & Submit Form
    bg = MagicMock()
    with (
        patch("app.api.feedback.contact.verify_turnstile_token", return_value=True),
        patch("app.api.feedback.contact.feedback_module.redis_client", AsyncMock()),
        patch(
            "app.api.feedback.contact.feedback_module.send_support_appeal_otp_email",
            AsyncMock(return_value=MagicMock(success=True)),
        ),
    ):
        otp_resp = await send_contact_otp(
            mock_request,
            ContactOtpRequest(email="tester@berkeley.edu", turnstile_token="t-tok"),
        )
        assert otp_resp.get("success") is True

        with (
            patch("app.api.feedback.contact._verify_and_consume_otp", AsyncMock()),
            patch(
                "app.api.feedback.contact._verify_session_storage_files", AsyncMock(),
            ),
            patch(
                "app.api.feedback.contact._get_user_id_by_email",
                AsyncMock(return_value=USER_1),
            ),
            patch(
                "app.api.feedback.contact.feedback_module.record_feedback_submission",
                return_value={"id": 1},
            ),
        ):
            submit_resp = await submit_contact_ticket(
                mock_request,
                bg,
                ContactSubmitRequest(
                    email="tester@berkeley.edu",
                    name="Tester",
                    query_type="bug_report",
                    subject="App Bug",
                    message="Something broke in the app details",
                    otp_code="123456",
                    turnstile_token="t-tok",
                ),
            )
            assert isinstance(submit_resp, dict)


async def test_api_feedback_tickets() -> None:
    mock_request = MagicMock()
    bg = MagicMock()
    now_dt = datetime.now(timezone.utc)
    now_iso = now_dt.isoformat()

    mock_ticket_detail = FeedbackTicketDetail(
        id="ticket-1",
        status="open",
        query_type="bug_report",
        subject="Help",
        message="msg",
        created_at=now_dt,
        updated_at=now_dt,
        attachment_paths=[],
        comments=[],
        status_history=[],
    )

    with (
        patch(
            "app.api.feedback.tickets.feedback_module.record_feedback_submission",
            return_value={"id": "ticket-1", "created_at": now_iso},
        ),
        patch(
            "app.api.feedback.tickets.feedback_module.fetch_user_email",
            return_value="student@berkeley.edu",
        ),
        patch(
            "app.api.feedback.tickets.fetch_user_tickets",
            return_value=[
                {
                    "id": "ticket-1",
                    "user_id": USER_1,
                    "status": "open",
                    "query_type": "bug_report",
                    "subject": "Help",
                    "created_at": now_iso,
                    "updated_at": now_iso,
                },
            ],
        ),
        patch("app.api.feedback.tickets.fetch_ticket_status_history", return_value=[]),
        patch("app.api.feedback.tickets.fetch_ticket_comments", return_value=[]),
        patch("app.api.feedback.tickets._verify_user_storage_files", AsyncMock()),
    ):
        # Submit ticket
        t_sub = await submit_feedback(
            mock_request,
            bg,
            FeedbackSubmitRequest(
                query_type="bug_report",
                subject="Bug Title",
                message="Message details about bug",
            ),
            _device=None,
            user_id=USER_1,
        )
        assert t_sub.status == "open"

        # List & Detail
        t_list = await list_my_feedback_tickets(
            mock_request, limit=None, offset=0, _device=None, user_id=USER_1,
        )
        assert len(t_list) >= 1

        mock_report = {
            "id": "ticket-1",
            "user_id": USER_1,
            "status": "open",
            "query_type": "bug_report",
            "subject": "Help",
            "message": "msg",
            "created_at": now_iso,
            "updated_at": now_iso,
        }
        with (
            patch(
                "app.api.feedback.tickets.feedback_module.fetch_ticket_report",
                return_value=mock_report,
            ),
            patch(
                "app.api.feedback.tickets.feedback_module._assemble_ticket_detail",
                AsyncMock(return_value=mock_ticket_detail),
            ),
        ):
            t_det = await get_feedback_ticket(
                mock_request, report_id="ticket-1", _device=None, user_id=USER_1,
            )
            assert t_det.id == "ticket-1"

            # Comment & Close
            comment_row = {
                "id": "comment-1",
                "report_id": "ticket-1",
                "author_id": USER_1,
                "body": "Added info",
                "author_role": "user",
                "created_at": now_iso,
            }
            with patch(
                "app.api.feedback.tickets.feedback_module.add_ticket_comment",
                return_value=comment_row,
            ):
                c_res = await add_feedback_comment(
                    mock_request,
                    report_id="ticket-1",
                    background_tasks=bg,
                    payload=FeedbackCommentRequest(body="Added info"),
                    _device=None,
                    user_id=USER_1,
                )
                assert c_res.id == "comment-1"

            with patch(
                "app.api.feedback.tickets.feedback_module.close_ticket",
                return_value=mock_report,
            ):
                cl_res = await close_feedback_ticket(
                    mock_request,
                    report_id="ticket-1",
                    background_tasks=bg,
                    payload=FeedbackCloseRequest(reason="resolved"),
                    _device=None,
                    user_id=USER_1,
                )
                assert cl_res.id == "ticket-1"
