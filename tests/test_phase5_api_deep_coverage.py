"""Phase 5 Test Suite: Deep Branch Coverage for API Layer Endpoints & Dependencies.

Covers:
- app/api/user/profile/details.py & app/api/user/profile/helpers.py
- app/api/feedback/contact.py
- app/api/user/auth_otp.py
- app/api/safety/endpoints.py
- app/api/feedback/tickets.py
- app/api/dependencies.py
- app/api/safety/portal/endpoints.py
"""

from __future__ import annotations

import io
from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, UploadFile
from fastapi.security import HTTPAuthorizationCredentials
from PIL import Image
from starlette.datastructures import Headers

from app.api.dependencies import (
    assert_account_active,
    assert_safety_consent,
    assert_special_category_consent,
    get_authenticated_user_id,
    get_bearer_token,
    get_optional_authenticated_user_id,
    get_optional_bearer_token,
    require_safety_consent,
)
from app.api.feedback.contact import (
    _read_bounded_upload_file,
    _strip_exif_metadata,
    _validate_uploaded_image,
    send_contact_otp,
    submit_contact_ticket,
    upload_contact_attachment,
    verify_turnstile_token,
)
from app.api.feedback.models import ContactOtpRequest, ContactSubmitRequest
from app.api.feedback.tickets import (
    add_feedback_comment,
    close_feedback_ticket,
    get_feedback_ticket,
    list_my_feedback_tickets,
    submit_feedback,
)
from app.api.safety.endpoints import (
    cancel_escalation,
    checkin_session,
    end_session,
    start_session,
)
from app.api.safety.portal.endpoints import (
    contact_portal_page,
    portal_page,
)
from app.api.user.auth_otp import (
    accept_terms,
    auth_bootstrap,
    request_account_phone_otp,
    verify_account_phone_otp,
)
from app.api.user.profile.details import (
    get_profile_derived_signals,
    get_profile_details,
    update_profile_details,
)
from app.api.user.profile.helpers import (
    _assert_no_decryption_failures,
    _build_ordered_images,
    _sets_special_category_data,
    _validate_common_activation,
    _validate_dating_activation,
    _validate_friends_activation,
    _validate_professional_activation,
)
from app.core.config import settings
from app.core.security.crypto import encrypt_to_hex
from app.models import (
    AccountPhoneOtpRequestRequest,
    AccountPhoneOtpVerifyRequest,
    ConsentUpdateRequest,
    FeedbackCloseRequest,
    FeedbackCommentRequest,
    FeedbackSubmitRequest,
    FeedbackTicketDetail,
    ProfileDetailsUpdate,
    SafetySessionCheckinRequest,
    SafetySessionEndRequest,
    SafetySessionStartRequest,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
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
        import copy
        return MagicMock(data=copy.deepcopy(data))  # pyright: ignore[reportUnknownArgumentType,reportUnknownMemberType]

    def _single() -> MagicMock:
        import copy
        if isinstance(data, list) and data:
            return MagicMock(data=copy.deepcopy(data[0]))  # pyright: ignore[reportUnknownArgumentType,reportUnknownMemberType]
        return MagicMock(data=copy.deepcopy(data))  # pyright: ignore[reportUnknownArgumentType,reportUnknownMemberType]

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    return mock


# ==============================================================================
# 1. API DEPENDENCIES
# ==============================================================================

async def test_api_dependencies() -> None:
    # Bearer tokens
    creds_valid = HTTPAuthorizationCredentials(scheme="Bearer", credentials="jwt-token-xyz")
    creds_invalid = HTTPAuthorizationCredentials(scheme="Basic", credentials="xyz")
    assert get_bearer_token(creds_valid) == "jwt-token-xyz"
    assert get_optional_bearer_token(creds_valid) == "jwt-token-xyz"
    assert get_optional_bearer_token(None) is None
    assert get_optional_bearer_token(creds_invalid) is None
    with pytest.raises(HTTPException):
        get_bearer_token(None)
    with pytest.raises(HTTPException):
        get_bearer_token(creds_invalid)

    # User identity & status checks
    assert await get_authenticated_user_id(payload={"sub": USER_1}) == USER_1
    assert await get_optional_authenticated_user_id(token=None) is None

    # assert_account_active
    active_u = {"id": USER_1, "is_active": True, "is_suspended": False, "deletion_requested_at": None, "purged_at": None}
    assert_account_active(active_u)

    with pytest.raises(HTTPException):
        assert_account_active({**active_u, "is_active": False})
    with pytest.raises(HTTPException):
        assert_account_active({**active_u, "is_suspended": True})
    with pytest.raises(HTTPException):
        assert_account_active({**active_u, "deletion_requested_at": "2026-08-25T00:00:00Z"})

    # Special category & safety consent
    now = datetime.now(timezone.utc)
    u_consent = {
        "id": USER_1,
        "special_category_consent_version": "2.0.0",
        "special_category_consent_at": now.isoformat(),
        "safety_data_consent_version": "2.0.0",
        "safety_data_consent_at": now.isoformat(),
    }
    with patch("app.api.dependencies.settings.current_terms_version", "2.0.0"), \
         patch("app.api.dependencies.get_cached_public_user", AsyncMock(return_value=u_consent)):
        assert_special_category_consent(u_consent)
        assert_safety_consent(u_consent)
        assert await require_safety_consent(user_id=USER_1) == USER_1


# ==============================================================================
# 2. PROFILE DETAILS & HELPERS
# ==============================================================================

def test_api_profile_details_and_helpers() -> None:
    # Helper validators
    _assert_no_decryption_failures({"name": "Alice"})
    with pytest.raises(HTTPException):
        _assert_no_decryption_failures({"name": "__DECRYPTION_FAILED__"})

    assert _sets_special_category_data(ProfileDetailsUpdate(religious_beliefs="Agnostic")) is True
    assert _sets_special_category_data(ProfileDetailsUpdate(bio="Hello")) is False

    imgs = _build_ordered_images({"profile_pic": "p1.jpg", "normal_pics": ["p2.jpg"]})
    assert len(imgs) == 2

    # Activations
    valid_common = {
        "name": "Alice",
        "age": 22,
        "sub_interests": {"tech": ["python", "fastapi"]},
        "profile_pic": "p1.jpg",
        "normal_pics": ["p2.jpg"],
        "bio": "Hello",
    }
    missing_list: list[str] = []
    _validate_common_activation(valid_common, ProfileDetailsUpdate(), missing_list)
    assert len(missing_list) == 0

    _validate_dating_activation({**valid_common, "dating_target_buckets": ["men"]}, ProfileDetailsUpdate(), missing_list)
    _validate_friends_activation({**valid_common, "friends_target_buckets": ["all"]}, ProfileDetailsUpdate(), missing_list)
    _validate_professional_activation({**valid_common, "professional_target_buckets": ["tech"], "role_at": "Nexus", "role_type": "Eng"}, ProfileDetailsUpdate(), missing_list)

    # GET profile details
    mock_table = _make_chaining_mock({
        "id": USER_1,
        "name": encrypt_to_hex("Alice"),
        "age": 22,
        "is_dating_active": True,
    })
    mock_request = MagicMock()
    with patch("app.api.user.profile.details.supabase_client.table", return_value=mock_table), \
         patch("app.api.user.profile.details._rolling_change_window_status", return_value=(0, True, None)):
        det = get_profile_details(mock_request, _device=None, user_id=USER_1)
        assert det is not None

    # GET derived signals
    with patch("app.api.user.profile.details.supabase_client.table", return_value=mock_table):
        sig = get_profile_derived_signals(mock_request, _device=None, user_id=USER_1)
        assert sig is not None

    # PATCH profile details
    patch_req = ProfileDetailsUpdate(bio="New bio", drinking="Socially")
    bg = MagicMock()
    with patch("app.api.user.profile.details.supabase_client.table", return_value=mock_table), \
         patch("app.api.user.profile.details.fetch_public_user", return_value={"id": USER_1, "is_active": True}), \
         patch("app.api.user.profile.details.sync_redis_client"):
        up_res = update_profile_details(
            request=mock_request,
            background_tasks=bg,
            payload=patch_req,
            user_id=USER_1,
            _device=None,
        )
        assert up_res is not None


# ==============================================================================
# 3. FEEDBACK CONTACT FORM & ATTACHMENTS
# ==============================================================================

async def test_api_feedback_contact() -> None:
    # Turnstile
    with patch("app.api.feedback.contact.settings.turnstile_secret_key", ""):
        assert await verify_turnstile_token("token") is True

    # Image sanitize
    img = Image.new("RGB", (100, 100), color="red")
    img_byte_arr = io.BytesIO()
    img.save(img_byte_arr, format="JPEG")
    content = img_byte_arr.getvalue()

    mock_file = UploadFile(file=io.BytesIO(content), filename="shot.jpg", headers=Headers({"content-type": "image/jpeg"}))
    ext = _validate_uploaded_image(mock_file, content)
    assert ext in (".jpg", "jpg")
    clean_bytes = _strip_exif_metadata(content, ext)
    assert len(clean_bytes) > 0

    # Bounded upload
    mock_upload = UploadFile(file=io.BytesIO(b"Hello Nexus Feedback"), size=20, filename="note.txt")
    read_bytes = await _read_bounded_upload_file(mock_upload)
    assert read_bytes == b"Hello Nexus Feedback"

    # Upload attachment
    mock_request = MagicMock()
    mock_storage = MagicMock()
    mock_storage.upload.return_value = None
    mock_storage.list.return_value = []
    with patch("app.api.feedback.contact.feedback_module.supabase_client.storage.from_", return_value=mock_storage), \
         patch("app.api.feedback.contact.verify_turnstile_token", return_value=True), \
         patch("app.api.feedback.contact.feedback_module.redis_client", AsyncMock()):
        up_res = await upload_contact_attachment(
            mock_request,
            file=UploadFile(file=io.BytesIO(img_byte_arr.getvalue()), filename="shot.jpg", headers=Headers({"content-type": "image/jpeg"})),
            session_id="sess-1",
            turnstile_token="valid-token",
        )
        assert "storage_path" in up_res

    # Send OTP & Submit Form
    bg = MagicMock()
    with patch("app.api.feedback.contact.verify_turnstile_token", return_value=True), \
         patch("app.api.feedback.contact.feedback_module.redis_client", AsyncMock()), \
         patch("app.api.feedback.contact.feedback_module.send_support_appeal_otp_email", AsyncMock(return_value=MagicMock(success=True))):
        otp_resp = await send_contact_otp(
            mock_request,
            ContactOtpRequest(email="tester@berkeley.edu", turnstile_token="t-tok"),
        )
        assert otp_resp.get("success") is True

        with patch("app.api.feedback.contact._verify_and_consume_otp", AsyncMock()), \
             patch("app.api.feedback.contact._verify_session_storage_files", AsyncMock()), \
             patch("app.api.feedback.contact._get_user_id_by_email", AsyncMock(return_value=USER_1)), \
             patch("app.api.feedback.contact.feedback_module.record_feedback_submission", return_value={"id": 1}):
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


# ==============================================================================
# 4. USER AUTH & OTP ENDPOINTS
# ==============================================================================

async def test_api_user_auth_otp() -> None:
    mock_request = MagicMock()
    mock_table = _make_chaining_mock([{"id": USER_1, "is_active": True, "accepted_terms_version": settings.current_terms_version}])
    now = datetime.now(timezone.utc)

    # Auth bootstrap
    with patch("app.api.user.auth_otp.supabase_client.table", return_value=mock_table), \
         patch("app.api.user.auth_otp.redis_client", AsyncMock()), \
         patch("app.api.user.auth_otp.get_user_email_by_id", return_value="student@berkeley.edu"), \
         patch("app.api.user.auth_otp.is_allowed_email", return_value=True):
        boot = await auth_bootstrap(mock_request, _device=None, auth_user={"id": USER_1, "email": "student@berkeley.edu"})
        assert boot is not None

    # Account phone OTP request & verify
    with patch("app.api.user.auth_otp.redis_client", AsyncMock()), \
         patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=False), \
         patch("app.api.user.auth_otp.find_user_id_by_phone", return_value=None), \
         patch("app.api.user.auth_otp.send_sms", AsyncMock(return_value=True)):
        p_req = await request_account_phone_otp(
            mock_request,
            AccountPhoneOtpRequestRequest(phone="+14155552671"),
            _device=None,
            user_id=USER_1,
        )
        assert p_req.sent is True

        with patch("app.api.user.auth_otp.verify_and_consume_hashed_otp", AsyncMock(return_value=True)), \
             patch("app.api.user.auth_otp.set_verified_mobile"):
            p_ver = await verify_account_phone_otp(
                mock_request,
                AccountPhoneOtpVerifyRequest(phone="+14155552671", code="123456"),
                _device=None,
                user_id=USER_1,
            )
            assert p_ver.verified is True

    # Accept terms
    with patch("app.api.user.auth_otp.supabase_client.table", return_value=mock_table), \
         patch("app.api.user.auth_otp.update_user_terms", return_value=(settings.current_terms_version, now)), \
         patch("app.api.user.auth_otp.update_community_guidelines_consent", return_value=(settings.current_terms_version, now)), \
         patch("app.api.user.auth_otp.update_special_category_consent", return_value=(settings.current_terms_version, now)), \
         patch("app.api.user.auth_otp.update_safety_data_consent", return_value=(settings.current_terms_version, now)), \
         patch("app.api.user.auth_otp.fetch_public_user", return_value={"id": USER_1, "is_active": True, "accepted_terms_version": settings.current_terms_version}):
        t_res = await accept_terms(
            mock_request,
            ConsentUpdateRequest(
                terms_version=settings.current_terms_version,
                general_accepted=True,
                community_guidelines_accepted=True,
                special_category_accepted=True,
                safety_data_accepted=True,
            ),
            _device=None,
            auth_user={"id": USER_1, "email": "student@berkeley.edu"},
        )
        assert t_res.user_id == USER_1


# ==============================================================================
# 5. SAFETY ENDPOINTS & PORTAL
# ==============================================================================

async def test_api_safety_endpoints_and_portal() -> None:
    mock_request = MagicMock()
    now = datetime.now(timezone.utc)

    with patch("app.api.safety.endpoints.start_safety_session", return_value={"id": SESSION_1, "status": "active"}), \
         patch("app.api.safety.endpoints.heartbeat_safety_session", return_value={"id": SESSION_1, "status": "active"}), \
         patch("app.api.safety.endpoints.end_safety_session", return_value={"id": SESSION_1, "status": "ended"}), \
         patch("app.api.safety.endpoints.cancel_safety_escalation", return_value={"id": SESSION_1}), \
         patch("app.api.safety.endpoints.sync_safety_contacts"), \
         patch("app.api.safety.endpoints.fetch_safety_contacts", return_value=[]), \
         patch("app.api.safety.endpoints.fetch_contact_facing_profile_summary", return_value={"display_name": "Alice"}), \
         patch("app.api.safety.endpoints.send_sms", AsyncMock(return_value=True)):

        # Start session
        st = await start_session(
            mock_request,
            SafetySessionStartRequest(interval_seconds=3600, label="Cafe", next_checkin_at=now + timedelta(hours=1)),
            user_id=USER_1,
        )
        assert st.id == SESSION_1

        # Checkin & Active
        ck = await checkin_session(
            mock_request,
            SafetySessionCheckinRequest(session_id=SESSION_1, next_checkin_at=now + timedelta(minutes=15)),
            user_id=USER_1,
        )
        assert ck.get("ok") is True

        # End & Cancel Escalation
        stp = await end_session(
            mock_request,
            SafetySessionEndRequest(session_id=SESSION_1),
            user_id=USER_1,
        )
        assert stp.get("ok") is True

        mock_sess = {"id": SESSION_1, "status": "active", "escalations_sent": 1, "user_id": USER_1, "escalation_cancelled_at": None}
        with patch("app.api.safety.endpoints.verify_escalation_cancel_token", return_value=1), \
             patch("app.api.safety.endpoints.fetch_safety_session", return_value=mock_sess), \
             patch("app.api.safety.endpoints.redis_client", AsyncMock()):
            c_esc = await cancel_escalation(mock_request, session_id=SESSION_1, token="tok", reason="safe", note=None)
            assert c_esc.status_code == 200

    # Safety Portal HTML
    html_page = await portal_page(mock_request, SESSION_1)
    assert "<!doctype html>" in bytes(html_page.body).decode("utf-8").lower()

    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value="contact-1"):
        c_html_page = await contact_portal_page(mock_request, "contact-1")
        assert "<!doctype html>" in bytes(c_html_page.body).decode("utf-8").lower()


# ==============================================================================
# 6. FEEDBACK TICKETS
# ==============================================================================

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

    with patch("app.api.feedback.tickets.feedback_module.record_feedback_submission", return_value={"id": "ticket-1", "created_at": now_iso}), \
         patch("app.api.feedback.tickets.feedback_module.fetch_user_email", return_value="student@berkeley.edu"), \
         patch("app.api.feedback.tickets.fetch_user_tickets", return_value=[{"id": "ticket-1", "user_id": USER_1, "status": "open", "query_type": "bug_report", "subject": "Help", "created_at": now_iso, "updated_at": now_iso}]), \
         patch("app.api.feedback.tickets.fetch_ticket_status_history", return_value=[]), \
         patch("app.api.feedback.tickets.fetch_ticket_comments", return_value=[]), \
         patch("app.api.feedback.tickets._verify_user_storage_files", AsyncMock()):

        # Submit ticket
        t_sub = await submit_feedback(
            mock_request,
            bg,
            FeedbackSubmitRequest(query_type="bug_report", subject="Bug Title", message="Message details about bug"),
            _device=None,
            user_id=USER_1,
        )
        assert t_sub.status == "open"

        # List & Detail
        t_list = await list_my_feedback_tickets(mock_request, limit=None, offset=0, _device=None, user_id=USER_1)
        assert len(t_list) >= 1

        mock_report = {"id": "ticket-1", "user_id": USER_1, "status": "open", "query_type": "bug_report", "subject": "Help", "message": "msg", "created_at": now_iso, "updated_at": now_iso}
        with patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value=mock_report), \
             patch("app.api.feedback.tickets.feedback_module._assemble_ticket_detail", AsyncMock(return_value=mock_ticket_detail)):
            t_det = await get_feedback_ticket(mock_request, report_id="ticket-1", _device=None, user_id=USER_1)
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
            with patch("app.api.feedback.tickets.feedback_module.add_ticket_comment", return_value=comment_row):
                c_res = await add_feedback_comment(
                    mock_request,
                    report_id="ticket-1",
                    background_tasks=bg,
                    payload=FeedbackCommentRequest(body="Added info"),
                    _device=None,
                    user_id=USER_1,
                )
                assert c_res.id == "comment-1"

            with patch("app.api.feedback.tickets.feedback_module.close_ticket", return_value=mock_report):
                cl_res = await close_feedback_ticket(
                    mock_request,
                    report_id="ticket-1",
                    background_tasks=bg,
                    payload=FeedbackCloseRequest(reason="resolved"),
                    _device=None,
                    user_id=USER_1,
                )
                assert cl_res.id == "ticket-1"
