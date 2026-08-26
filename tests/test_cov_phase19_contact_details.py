"""Phase 19 Coverage Suite: Comprehensive coverage for app/api/feedback/contact.py and app/api/user/profile/details.py."""

from __future__ import annotations

import io
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import BackgroundTasks, HTTPException, UploadFile
from PIL import Image
from postgrest.exceptions import APIError
from redis.exceptions import RedisError

from app.api.feedback.models import ContactOtpRequest, ContactSubmitRequest, ErrorSessionCreateRequest

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"


# =============================================================================
# 1. API FEEDBACK CONTACT TESTS
# =============================================================================

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
    with patch("app.api.feedback.contact._list_storage_attachments", return_value=[{"name": f"f{i}"} for i in range(10)]):
        with pytest.raises(HTTPException, match="Maximum attachment limit"):
            await _check_session_upload_quota("sess1")

    with patch("app.api.feedback.contact._list_storage_attachments", side_effect=Exception("quota check fail")):
        # Should catch and log warning without raising
        await _check_session_upload_quota("sess1")

    # upload_contact_attachment: turnstile fail, invalid clean_session, storage upload exception
    mock_req = MagicMock()
    mock_req.client.host = "127.0.0.1"

    with patch("app.api.feedback.contact.verify_turnstile_token", AsyncMock(return_value=False)):
        with pytest.raises(HTTPException, match="Security verification failed"):
            await upload_contact_attachment(mock_req, f, "sess1", "token")

    with patch("app.api.feedback.contact.verify_turnstile_token", AsyncMock(return_value=True)), \
         patch("app.api.feedback.contact._read_bounded_upload_file", AsyncMock(return_value=valid_png_bytes)), \
         patch("app.api.feedback.contact._validate_uploaded_image", return_value=".png"), \
         patch("app.api.feedback.contact._check_session_upload_quota", AsyncMock()):
        with pytest.raises(HTTPException, match="Invalid session_id"):
            await upload_contact_attachment(mock_req, f, "???!!!", "token")

        with patch("app.api.feedback.contact.feedback_module.supabase_client") as mock_sb:
            mock_sb.storage.from_().upload.side_effect = Exception("Upload fail")
            with pytest.raises(HTTPException, match="Failed to store attachment file"):
                await upload_contact_attachment(mock_req, f, "valid-sess-1", "token")

    # delete_contact_attachments: turnstile fail, invalid session_id, no safe paths, remove exception
    with patch("app.api.feedback.contact.verify_turnstile_token", AsyncMock(return_value=False)):
        with pytest.raises(HTTPException, match="Security verification failed"):
            await delete_contact_attachments(mock_req, "sess1", ["path1"], "token")

    with patch("app.api.feedback.contact.verify_turnstile_token", AsyncMock(return_value=True)):
        with pytest.raises(HTTPException, match="Invalid session_id"):
            await delete_contact_attachments(mock_req, "???", ["path1"], "token")

        # No safe paths
        res_del = await delete_contact_attachments(mock_req, "sess1", ["unsafe/path"], "token")
        assert res_del == {"success": True}

        # Safe paths with remove exception
        with patch("app.api.feedback.contact.feedback_module.supabase_client") as mock_sb:
            mock_sb.storage.from_().remove.side_effect = APIError({"message": "fail"})
            res_del = await delete_contact_attachments(mock_req, "sess1", ["web_contact/sess1/file.png"], "token")
            assert res_del == {"success": True}

    # send_contact_otp: turnstile fail, invalid email, redis set exception, email send failure
    with patch("app.api.feedback.contact.verify_turnstile_token", AsyncMock(return_value=False)):
        with pytest.raises(HTTPException, match="Security verification failed"):
            await send_contact_otp(mock_req, ContactOtpRequest(email="a@b.com", turnstile_token="t"))

    with patch("app.api.feedback.contact.verify_turnstile_token", AsyncMock(return_value=True)):
        with pytest.raises(HTTPException, match="valid email is required"):
            await send_contact_otp(mock_req, ContactOtpRequest(email="invalidemail", turnstile_token="t"))

        with patch("app.api.feedback.contact.feedback_module.redis_client") as mock_redis:
            mock_redis.set = AsyncMock(side_effect=RedisError("Redis down"))
            with pytest.raises(HTTPException, match="Support service temporarily unavailable"):
                await send_contact_otp(mock_req, ContactOtpRequest(email="test@example.com", turnstile_token="t"))

            mock_redis.set = AsyncMock()
            mock_redis.delete = AsyncMock()
            with patch("app.api.feedback.contact.feedback_module.send_support_appeal_otp_email", AsyncMock(return_value=MagicMock(success=False))):
                with pytest.raises(HTTPException, match="Failed to send verification email"):
                    await send_contact_otp(mock_req, ContactOtpRequest(email="test@example.com", turnstile_token="t"))

    # _verify_and_consume_otp: RedisError -> 503
    with patch("app.api.feedback.contact.verify_and_consume_raw_otp", AsyncMock(side_effect=RedisError("fail"))):
        with pytest.raises(HTTPException, match="Support service temporarily unavailable"):
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
    with patch("app.api.feedback.contact._list_storage_attachments", return_value=[{"name": "found.png"}]):
        with pytest.raises(HTTPException, match="Attachment file not found"):
            await _verify_session_storage_files("sess1", ["notfound.png"])

    with patch("app.api.feedback.contact._list_storage_attachments", side_effect=Exception("list fail")):
        with pytest.raises(HTTPException, match="Attachment verification failed"):
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

    with patch("app.api.feedback.contact._validate_contact_attachments", AsyncMock()), \
         patch("app.api.feedback.contact._verify_and_consume_otp", AsyncMock()), \
         patch("app.api.feedback.contact._get_user_id_by_email", AsyncMock(return_value=USER_1)), \
         patch("app.api.feedback.contact.feedback_module.record_feedback_submission", side_effect=APIError({"message": "fail"})), \
         patch("app.api.feedback.contact._cleanup_attachments_on_failure", AsyncMock()):
        with pytest.raises(HTTPException, match="Failed to submit support ticket"):
            await submit_contact_ticket(mock_req, bg, ContactSubmitRequest(
                email="test@example.com",
                otp_code="123456",
                turnstile_token="t_tok",
                subject="Help",
                message="Message here",
                attachment_paths=["web_contact/sess1/img.png"],
                query_type="unknown_type",
                name="John Doe",
                account_id_or_phone="+1234567890",
            ))

    # create_error_session & get_error_session
    with patch("app.api.feedback.contact.feedback_module.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(side_effect=RedisError("fail"))
        with pytest.raises(HTTPException, match="Failed to store error session"):
            await create_error_session(mock_req, ErrorSessionCreateRequest(
                query_type="bug_report",
                subject="Error",
                message="Details",
            ))

        # get_error_session 404 & 500
        mock_redis.get = AsyncMock(return_value=None)
        with pytest.raises(HTTPException, match="Error session expired"):
            await get_error_session(mock_req, "nonexistent")

        mock_redis.get = AsyncMock(side_effect=RedisError("fail"))
        with pytest.raises(HTTPException, match="Failed to retrieve error session"):
            await get_error_session(mock_req, "sess-1")


# =============================================================================
# 2. API USER PROFILE DETAILS TESTS
# =============================================================================

def test_user_profile_details_deep_branches():
    from app.api.user.profile.details import get_profile_details, update_profile_details
    from app.models import ProfileDetailsUpdate

    mock_req = MagicMock()
    bg = BackgroundTasks()

    # get_profile_details: 404 not found, 500 invalid structure, 500 generic exception
    with patch("app.api.user.profile.details.supabase_client") as mock_sb, \
         patch("app.api.user.profile.details._rolling_change_window_status", return_value=(0, True, None)):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=None)
        with pytest.raises(HTTPException, match="Profile not found"):
            get_profile_details(mock_req, _device=None, user_id=USER_1)

        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data="not-a-dict")
        with pytest.raises(HTTPException, match="Invalid profile data structure"):
            get_profile_details(mock_req, _device=None, user_id=USER_1)

        mock_sb.table().select().eq().maybe_single().execute.side_effect = RuntimeError("Fatal DB error")
        with pytest.raises(HTTPException, match="Internal server error"):
            get_profile_details(mock_req, _device=None, user_id=USER_1)

    # update_profile_details: age change limit reached, profile not found, generic error
    mock_profile_row = {"name": "Alice", "age": 20, "campus_name": "MIT", "campus_year": 2024}
    with patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb, \
         patch("app.api.user.profile.helpers.supabase_client"), \
         patch("app.api.user.profile.details._rolling_change_window_status", return_value=(0, True, None)), \
         patch("app.api.user.profile.details.fetch_public_user", return_value={"id": USER_1, "is_active": True}), \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value=mock_profile_row), \
         patch("app.api.user.profile.details._assert_no_decryption_failures"):
        
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=mock_profile_row)

        # apply_age_change age_change_limit_reached
        err_age_limit = APIError({"message": "age_change_limit_reached"})
        err_age_limit.message = "age_change_limit_reached"
        mock_sb.rpc.return_value.execute.side_effect = err_age_limit
        with pytest.raises(HTTPException, match="You've used both age changes allowed this year"):
            update_profile_details(mock_req, bg, ProfileDetailsUpdate(age=25), user_id=USER_1, _device=None)

        # apply_age_change profile_not_found
        err_not_found = APIError({"message": "profile_not_found"})
        err_not_found.message = "profile_not_found"
        mock_sb.rpc.return_value.execute.side_effect = err_not_found
        with pytest.raises(HTTPException, match="Profile not found"):
            update_profile_details(mock_req, bg, ProfileDetailsUpdate(age=25), user_id=USER_1, _device=None)

        # apply_age_change generic APIError
        mock_sb.rpc.return_value.execute.side_effect = APIError({"message": "db_crash"})
        with pytest.raises(HTTPException, match="Internal server error"):
            update_profile_details(mock_req, bg, ProfileDetailsUpdate(age=25), user_id=USER_1, _device=None)

        # apply_name_change name_change_limit_reached
        err_name_limit = APIError({"message": "name_change_limit_reached"})
        err_name_limit.message = "name_change_limit_reached"
        mock_sb.rpc.return_value.execute.side_effect = err_name_limit
        with pytest.raises(HTTPException, match="You've used both name changes allowed this year"):
            update_profile_details(mock_req, bg, ProfileDetailsUpdate(name="Bobby"), user_id=USER_1, _device=None)

        # apply_name_change profile_not_found
        mock_sb.rpc.return_value.execute.side_effect = err_not_found
        with pytest.raises(HTTPException, match="Profile not found"):
            update_profile_details(mock_req, bg, ProfileDetailsUpdate(name="Bobby"), user_id=USER_1, _device=None)

        # apply_name_change generic APIError
        mock_sb.rpc.return_value.execute.side_effect = APIError({"message": "db_crash"})
        with pytest.raises(HTTPException, match="Internal server error"):
            update_profile_details(mock_req, bg, ProfileDetailsUpdate(name="Bobby"), user_id=USER_1, _device=None)

        # update_data execute returns empty without conditional check -> 404
        mock_sb.rpc.return_value.execute.side_effect = None
        mock_sb.rpc.return_value.execute.return_value = MagicMock()
        mock_sb.table().update().eq().execute.return_value = MagicMock(data=[])
        with pytest.raises(HTTPException, match="Profile not found"):
            update_profile_details(mock_req, bg, ProfileDetailsUpdate(bio="New bio"), user_id=USER_1, _device=None)
