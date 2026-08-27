"""Test coverage suite for Safety and Feedback API layers.

Covers:
- app/api/safety/endpoints.py
- app/api/safety/portal/endpoints.py
- app/api/safety/portal/html.py
- app/api/feedback/tickets.py
- app/api/feedback/contact.py
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import BackgroundTasks, HTTPException, Request

from app.api.feedback.contact import (
    _parse_attachment_path,
    create_error_session,
    get_error_session,
    send_contact_otp,
    submit_contact_ticket,
)
from app.api.feedback.models import (
    ContactOtpRequest,
    ContactSubmitRequest,
    ErrorSessionCreateRequest,
)
from app.api.feedback.tickets import (
    _is_valid_attachment_path,
    add_feedback_comment,
    close_feedback_ticket,
    get_feedback_ticket,
    list_my_feedback_tickets,
    submit_feedback,
)
from app.api.safety.endpoints import (
    _escalation_page,
    cancel_escalation,
    cancel_escalation_post,
    checkin_session,
    end_session,
    put_safety_contacts,
    register_evidence,
    send_safety_alert,
    start_session,
)
from app.api.safety.portal.endpoints import (
    contact_portal_page,
    get_contact_portal_details,
    get_portal_details,
    portal_page,
    remove_trusted_contact,
    request_contact_portal_otp,
    request_portal_otp,
    verify_contact_portal_otp,
    verify_portal_otp,
)
from app.db.client import DatabaseAccessError
from app.db.safety import EscalationInProgressError
from app.models import (
    EscalationCancelRequest,
    FeedbackCloseRequest,
    FeedbackCommentRequest,
    FeedbackSubmitRequest,
    FeedbackTicketDetail,
    SafetyAlertRequest,
    SafetyAlertResponse,
    SafetyContactIn,
    SafetyContactPortalOtpRequestRequest,
    SafetyContactPortalOtpVerifyRequest,
    SafetyContactsSyncRequest,
    SafetyEvidenceRegisterRequest,
    SafetyLocation,
    SafetyPortalOtpRequestRequest,
    SafetyPortalOtpVerifyRequest,
    SafetySessionCheckinRequest,
    SafetySessionEndRequest,
    SafetySessionStartRequest,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
ALERT_ID = "00000000-0000-0000-0000-000000000010"
SESSION_ID = "00000000-0000-0000-0000-000000000020"
CONTACT_ID = "00000000-0000-0000-0000-000000000030"
TICKET_ID = "00000000-0000-0000-0000-000000000040"


def make_mock_request(headers: dict[str, str] | None = None) -> Request:
    raw_headers = [(k.lower().encode(), v.encode()) for k, v in (headers or {}).items()]
    scope = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/test",
        "headers": raw_headers,
        "client": ("127.0.0.1", 12345),
        "app": MagicMock(),
    }
    req = Request(scope)
    req.state.view_rate_limit = None
    return req


# ==============================================================================
# 1. SAFETY API ENDPOINTS TESTS
# ==============================================================================

async def test_put_safety_contacts():
    req = make_mock_request()
    payload = SafetyContactsSyncRequest(
        contacts=[
            SafetyContactIn(name="Contact 1", phone="+15551234567"),
        ],
    )

    # 1. DB Error -> 503
    with patch("app.api.safety.endpoints.sync_safety_contacts", side_effect=DatabaseAccessError("DB error")):
        with pytest.raises(HTTPException) as exc_db:
            await put_safety_contacts(request=req, payload=payload, user_id=USER_1)
        assert exc_db.value.status_code == 503

    # 2. Success sync
    with patch("app.api.safety.endpoints.sync_safety_contacts", return_value=([], [{"id": CONTACT_ID, "name": "Contact 1"}])), \
         patch("app.api.safety.endpoints.safe_create_task"):
        res = await put_safety_contacts(request=req, payload=payload, user_id=USER_1)
        assert res.count == 1
        assert len(res.blocked) == 0


async def test_send_safety_alert():
    req = make_mock_request()
    payload_sos = SafetyAlertRequest(
        alert_type="sos_silent",
        event_label="Dinner",
        current_location=SafetyLocation(lat=37.7749, lng=-122.4194),
    )

    # 1. Quota exceeded -> 429
    with patch("app.api.safety.endpoints.redis_client.incr", new_callable=AsyncMock, return_value=50), \
         patch("app.api.safety.endpoints.redis_client.expire", new_callable=AsyncMock):
        with pytest.raises(HTTPException) as exc_quota:
            await send_safety_alert(request=req, payload=payload_sos, user_id=USER_1)
        assert exc_quota.value.status_code == 429

    # 2. No contacts on file -> 400
    with patch("app.api.safety.endpoints.redis_client.incr", new_callable=AsyncMock, return_value=1), \
         patch("app.api.safety.endpoints.redis_client.expire", new_callable=AsyncMock), \
         patch("app.api.safety.endpoints._check_cached_sos_alert", return_value=None), \
         patch("app.api.safety.endpoints.fetch_safety_contacts", return_value=[]):
        with pytest.raises(HTTPException) as exc_no_c:
            await send_safety_alert(request=req, payload=payload_sos, user_id=USER_1)
        assert exc_no_c.value.status_code == 400

    # 3. Successful SOS alert dispatch
    mock_contacts = [{"id": CONTACT_ID, "name": "Alice", "phone": "+15551234567"}]
    mock_alert_resp = SafetyAlertResponse(
        id=ALERT_ID,
        contacts_notified=1,
        contacts_total=1,
    )
    with patch("app.api.safety.endpoints.redis_client.incr", new_callable=AsyncMock, return_value=1), \
         patch("app.api.safety.endpoints.redis_client.expire", new_callable=AsyncMock), \
         patch("app.api.safety.endpoints._check_cached_sos_alert", return_value=None), \
         patch("app.api.safety.endpoints.fetch_safety_contacts", return_value=mock_contacts), \
         patch("app.api.safety.endpoints.fetch_contact_facing_profile_summary", return_value={"name": "Bob"}), \
         patch("app.api.safety.endpoints._send_alert_sms_to_contacts", return_value=1), \
         patch("app.api.safety.endpoints._record_safety_alert_response", return_value=mock_alert_resp), \
         patch("app.api.safety.endpoints._cache_sos_alert"):
        res = await send_safety_alert(request=req, payload=payload_sos, user_id=USER_1)
        assert res.id == ALERT_ID
        assert res.contacts_notified == 1


async def test_register_evidence():
    req = make_mock_request()

    # 1. Invalid path traversal / unowned path -> 422
    bad_payload = SafetyEvidenceRegisterRequest(
        alert_id=ALERT_ID,
        storage_path=f"{USER_2}/evidence.mp4",
        media_key_base64="dGVzdA==",
        content_type="video",
        duration_seconds=10,
    )
    with pytest.raises(HTTPException) as exc_trav:
        await register_evidence(request=req, payload=bad_payload, user_id=USER_1)
    assert exc_trav.value.status_code == 422

    # 2. Alert not found -> 404
    valid_payload = SafetyEvidenceRegisterRequest(
        alert_id=ALERT_ID,
        storage_path=f"{USER_1}/evidence.mp4",
        media_key_base64="dGVzdA==",
        content_type="video",
        duration_seconds=10,
    )
    with patch("app.api.safety.endpoints.fetch_safety_alert", return_value=None):
        with pytest.raises(HTTPException) as exc_404:
            await register_evidence(request=req, payload=valid_payload, user_id=USER_1)
        assert exc_404.value.status_code == 404

    # 3. Successful evidence registration
    with patch("app.api.safety.endpoints.fetch_safety_alert", return_value={"id": ALERT_ID, "user_id": USER_1}), \
         patch("app.api.safety.endpoints.register_safety_evidence", return_value={"id": "evid-1"}):
        res = await register_evidence(request=req, payload=valid_payload, user_id=USER_1)
        assert res.id == "evid-1"


async def test_safety_session_lifecycle():
    req = make_mock_request()
    now = datetime.now(timezone.utc)

    # 1. Start session with past next_checkin_at -> 400
    past_start = SafetySessionStartRequest(
        label="Meetup",
        interval_seconds=900,
        next_checkin_at=now - timedelta(minutes=5),
    )
    with pytest.raises(HTTPException) as exc_past:
        await start_session(request=req, payload=past_start, user_id=USER_1)
    assert exc_past.value.status_code == 400

    # 2. Start session with escalation in progress -> 400
    future_start = SafetySessionStartRequest(
        label="Meetup",
        interval_seconds=900,
        next_checkin_at=now + timedelta(minutes=15),
    )
    with patch("app.api.safety.endpoints.start_safety_session", side_effect=EscalationInProgressError("In progress")):
        with pytest.raises(HTTPException) as exc_esc:
            await start_session(request=req, payload=future_start, user_id=USER_1)
        assert exc_esc.value.status_code == 400

    # 3. Successful start session
    with patch("app.api.safety.endpoints.start_safety_session", return_value={"id": SESSION_ID}):
        start_res = await start_session(request=req, payload=future_start, user_id=USER_1)
        assert start_res.id == SESSION_ID

    # 4. Checkin session
    checkin_payload = SafetySessionCheckinRequest(
        session_id=SESSION_ID,
        next_checkin_at=now + timedelta(minutes=15),
    )
    with patch("app.api.safety.endpoints.heartbeat_safety_session", return_value={"ok": True}):
        chk_res = await checkin_session(request=req, payload=checkin_payload, user_id=USER_1)
        assert chk_res["ok"] is True

    # 5. End session
    end_payload = SafetySessionEndRequest(session_id=SESSION_ID)
    with patch("app.api.safety.endpoints.end_safety_session", return_value=True):
        end_res = await end_session(request=req, payload=end_payload, user_id=USER_1)
        assert end_res["ok"] is True


async def test_escalation_cancellation_and_page():
    req = make_mock_request()

    # 1. Escalation cancellation GET
    with patch("app.api.safety.endpoints.verify_escalation_cancel_token", return_value=1), \
         patch("app.api.safety.endpoints.redis_client.set", new_callable=AsyncMock, return_value=True), \
         patch("app.api.safety.endpoints.fetch_safety_session", return_value={"id": SESSION_ID, "user_id": USER_1, "status": "active", "escalations_sent": 1}), \
         patch("app.api.safety.endpoints.cancel_safety_escalation"):
        resp_html = await cancel_escalation(request=req, session_id=SESSION_ID, token="valid_token", reason="safe", note=None)
        assert resp_html.status_code == 200

    # 2. Escalation cancellation POST
    post_payload = EscalationCancelRequest(token="valid_token", reason="safe")
    with patch("app.api.safety.endpoints.verify_escalation_cancel_token", return_value=1), \
         patch("app.api.safety.endpoints.redis_client.set", new_callable=AsyncMock, return_value=True), \
         patch("app.api.safety.endpoints.fetch_safety_session", return_value={"id": SESSION_ID, "user_id": USER_1, "status": "active", "escalations_sent": 1}), \
         patch("app.api.safety.endpoints.cancel_safety_escalation"):
        resp_post = await cancel_escalation_post(request=req, session_id=SESSION_ID, payload=post_payload)
        assert resp_post.status_code == 200

    # 3. Escalation page helper
    html = _escalation_page("Escalation Cancelled")
    assert "Escalation Cancelled" in html


# ==============================================================================
# 2. SAFETY PORTAL ENDPOINTS TESTS
# ==============================================================================

async def test_safety_portal_otp_and_details():
    req = make_mock_request()
    otp_req = SafetyPortalOtpRequestRequest(phone="+15551234567")

    # 1. Request OTP - rate limit cooldown -> 429
    with patch("app.api.safety.portal.endpoints.redis_client.set", new_callable=AsyncMock, return_value=False):
        with pytest.raises(HTTPException) as exc_cd:
            await request_portal_otp(request=req, session_id=SESSION_ID, payload=otp_req)
        assert exc_cd.value.status_code == 429

    # 2. Request OTP - session active, matched contact
    session_row = {"id": SESSION_ID, "user_id": USER_1, "status": "active"}
    contacts = [{"id": CONTACT_ID, "phone": "+15551234567", "name": "Alice"}]
    with patch("app.api.safety.portal.endpoints.redis_client.set", new_callable=AsyncMock, return_value=True), \
         patch("app.api.safety.portal.endpoints.fetch_safety_session", return_value=session_row), \
         patch("app.api.safety.portal.endpoints.fetch_safety_contacts", return_value=contacts), \
         patch("app.api.safety.portal.endpoints.redis_client.setex", new_callable=AsyncMock), \
         patch("app.api.safety.portal.endpoints.safe_create_task"):
        req_res = await request_portal_otp(request=req, session_id=SESSION_ID, payload=otp_req)
        assert req_res.sent is True

    # 3. Verify OTP
    v_req = SafetyPortalOtpVerifyRequest(phone="+15551234567", code="123456")
    with patch("app.api.safety.portal.endpoints.verify_and_consume_hashed_otp"), \
         patch("app.api.safety.portal.endpoints.make_portal_access_token", return_value="portal_token_123"):
        v_res = await verify_portal_otp(request=req, session_id=SESSION_ID, payload=v_req)
        assert v_res.token == "portal_token_123"

    # 4. Get portal details - missing token -> 401
    with pytest.raises(HTTPException) as exc_401:
        await get_portal_details(request=req, session_id=SESSION_ID, authorization=None)
    assert exc_401.value.status_code == 401

    # 5. Get portal details - valid token
    with patch("app.api.safety.portal.endpoints._extract_bearer_token", return_value="portal_token_123"), \
         patch("app.api.safety.portal.endpoints.verify_portal_access_token", return_value="c_phone_id_123"), \
         patch("app.api.safety.portal.endpoints.fetch_safety_session", return_value=session_row), \
         patch("app.api.safety.portal.endpoints.fetch_safety_contacts", return_value=contacts), \
         patch("app.api.safety.portal.endpoints.hash_phone_identifier", return_value="c_phone_id_123"), \
         patch("app.api.safety.portal.endpoints.fetch_alerts_for_session", return_value=[]), \
         patch("app.api.safety.portal.endpoints.fetch_evidence_for_alert_ids", return_value=[]):
        det_res = await get_portal_details(request=req, session_id=SESSION_ID, authorization="Bearer portal_token_123")
        assert det_res.status == "active"


async def test_contact_portal_otp_and_removal():
    req = make_mock_request()
    c_otp_req = SafetyContactPortalOtpRequestRequest(phone="+15551234567")

    # 1. Request contact OTP
    contact_row = {"id": CONTACT_ID, "phone": "+15551234567", "user_id": USER_1, "name": "Alice"}
    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value=CONTACT_ID), \
         patch("app.api.safety.portal.endpoints.redis_client.set", new_callable=AsyncMock, return_value=True), \
         patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id", return_value=contact_row), \
         patch("app.api.safety.portal.endpoints.redis_client.setex", new_callable=AsyncMock), \
         patch("app.api.safety.portal.endpoints.safe_create_task"):
        res_c_otp = await request_contact_portal_otp(request=req, contact_id=CONTACT_ID, payload=c_otp_req)
        assert res_c_otp.sent is True

    # 2. Verify contact OTP
    v_c_req = SafetyContactPortalOtpVerifyRequest(phone="+15551234567", code="123456")
    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value=CONTACT_ID), \
         patch("app.api.safety.portal.endpoints.verify_and_consume_hashed_otp"), \
         patch("app.api.safety.portal.endpoints.make_portal_access_token", return_value="c_token_123"):
        v_c_res = await verify_contact_portal_otp(request=req, contact_id=CONTACT_ID, payload=v_c_req)
        assert v_c_res.token == "c_token_123"

    # 3. Get contact portal details
    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value=CONTACT_ID), \
         patch("app.api.safety.portal.endpoints.verify_portal_access_token", return_value="c_phone_id_123"), \
         patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id", return_value=contact_row), \
         patch("app.api.safety.portal.endpoints.hash_phone_identifier", return_value="c_phone_id_123"), \
         patch("app.api.safety.portal.endpoints.fetch_contact_facing_profile_summary", return_value={"name": "Bob", "profile_pic": "b.jpg"}):
        det = await get_contact_portal_details(request=req, contact_id=CONTACT_ID, authorization="Bearer c_token_123")
        assert det.user_name == "Bob"

    # 4. Remove trusted contact
    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value=CONTACT_ID), \
         patch("app.api.safety.portal.endpoints.verify_portal_access_token", return_value="c_phone_id_123"), \
         patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id", return_value=contact_row), \
         patch("app.api.safety.portal.endpoints.hash_phone_identifier", return_value="c_phone_id_123"), \
         patch("app.api.safety.portal.endpoints._enforce_contact_remove_rate_limit"), \
         patch("app.api.safety.portal.endpoints.remove_safety_contact_self_service", return_value=contact_row), \
         patch("app.api.safety.portal.endpoints._notify_user_of_contact_self_removal"):
        rem_res = await remove_trusted_contact(request=req, contact_id=CONTACT_ID, authorization="Bearer c_token_123")
        assert rem_res.removed is True

    # 5. HTML Portal Pages
    session_row = {"id": SESSION_ID, "user_id": USER_1, "status": "active"}
    with patch("app.api.safety.portal.endpoints.fetch_safety_session", return_value=session_row):
        h1 = await portal_page(request=req, session_id=SESSION_ID)
        assert h1.status_code == 200

    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value=CONTACT_ID), \
         patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id", return_value=contact_row):
        h2 = await contact_portal_page(request=req, contact_id=CONTACT_ID)
        assert h2.status_code == 200


# ==============================================================================
# 3. FEEDBACK TICKETS API TESTS
# ==============================================================================

async def test_feedback_tickets_flow():
    req = make_mock_request()
    bg = BackgroundTasks()

    # 1. Attachment path validator
    assert _is_valid_attachment_path(f"{USER_1}/image.png", f"{USER_1}/") is True
    assert _is_valid_attachment_path(f"{USER_2}/image.png", f"{USER_1}/") is False
    assert _is_valid_attachment_path(f"{USER_1}/../etc/passwd", f"{USER_1}/") is False

    # 2. Submit feedback
    payload_ticket = FeedbackSubmitRequest(
        query_type="bug_report",
        subject="Camera crash on launch",
        message="The camera screen freezes when tapping capture button",
        attachment_paths=[],
    )
    mock_ticket_row = {
        "id": TICKET_ID,
        "query_type": "bug_report",
        "subject": "Camera crash on launch",
        "github_issue_url": "https://github.com/issues/1",
        "app_version": "1.2.0",
        "platform": "android",
        "status": "open",
        "created_at": datetime.now(timezone.utc),
        "updated_at": datetime.now(timezone.utc),
        "unread_user_comments": 0,
    }
    with patch("app.api.feedback.tickets.feedback_module.record_feedback_submission", return_value=mock_ticket_row), \
         patch("app.api.feedback.tickets.feedback_module.fetch_user_email", return_value="user@example.com"):
        res = await submit_feedback(request=req, background_tasks=bg, payload=payload_ticket, user_id=USER_1)
        assert res.id == TICKET_ID

    # 3. List my feedback tickets
    with patch("app.api.feedback.tickets.fetch_user_tickets", return_value=[mock_ticket_row]):
        my_tickets = await list_my_feedback_tickets(request=req, user_id=USER_1)
        assert len(my_tickets) == 1
        assert my_tickets[0].id == TICKET_ID

    # 4. Get feedback ticket
    detail_data: dict[str, Any] = {
        **mock_ticket_row,
        "message": "Camera crashes",
        "comments": [],
        "status_history": [],
        "attachment_paths": [],
    }
    detail_res = FeedbackTicketDetail.model_validate(detail_data)
    with patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value=mock_ticket_row), \
         patch("app.api.feedback.tickets.feedback_module._assemble_ticket_detail", return_value=detail_res):
        det_ticket = await get_feedback_ticket(request=req, report_id=TICKET_ID, user_id=USER_1)
        assert det_ticket.id == TICKET_ID

    comm_payload = FeedbackCommentRequest(body="Additional logs attached")
    with patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value=mock_ticket_row), \
         patch("app.api.feedback.tickets.feedback_module.add_ticket_comment", return_value={"id": "comm-1", "created_at": datetime.now(timezone.utc), "author_id": USER_1, "body": "Additional logs attached"}), \
         patch("app.api.feedback.tickets.feedback_module.fetch_user_email", return_value="user@example.com"):
        comm_res = await add_feedback_comment(request=req, background_tasks=bg, report_id=TICKET_ID, payload=comm_payload, user_id=USER_1)
        assert comm_res.id == "comm-1"

    # 6. Close feedback ticket
    close_payload = FeedbackCloseRequest(reason="Resolved on my own")
    with patch("app.api.feedback.tickets.feedback_module.close_ticket", return_value=mock_ticket_row), \
         patch("app.api.feedback.tickets.feedback_module.fetch_user_email", return_value="user@example.com"), \
         patch("app.api.feedback.tickets.feedback_module._assemble_ticket_detail", return_value=detail_res):
        close_res = await close_feedback_ticket(request=req, report_id=TICKET_ID, background_tasks=bg, payload=close_payload, user_id=USER_1)
        assert close_res.id == TICKET_ID


# ==============================================================================
# 4. CONTACT API & ERROR SESSIONS TESTS
# ==============================================================================

async def test_contact_api_and_sessions():
    req = make_mock_request()
    bg = BackgroundTasks()

    # 1. Attachment path parsing
    s_id, f_name = _parse_attachment_path("web_contact/contact_sess123/screenshot.png")
    assert s_id == "contact_sess123"
    assert f_name == "screenshot.png"
    with pytest.raises(HTTPException) as exc_bad_path:
        _parse_attachment_path("invalid/path/traversal")
    assert exc_bad_path.value.status_code == 400

    # 2. Send contact OTP
    otp_payload = ContactOtpRequest(email="support@example.com")
    with patch("app.api.feedback.contact.verify_turnstile_token", return_value=True), \
         patch("app.api.feedback.contact.feedback_module.redis_client.set", new_callable=AsyncMock), \
         patch("app.api.feedback.contact.feedback_module.redis_client.delete", new_callable=AsyncMock), \
         patch("app.api.feedback.contact.feedback_module.send_support_appeal_otp_email", return_value=MagicMock(success=True)):
        otp_res = await send_contact_otp(request=req, payload=otp_payload)
        assert otp_res["success"] is True

    # 3. Submit contact ticket
    ticket_payload = ContactSubmitRequest(
        email="support@example.com",
        otp_code="123456",
        query_type="help",
        subject="Login problem",
        message="Cannot login to app",
    )
    with patch("app.api.feedback.contact._verify_and_consume_otp"), \
         patch("app.api.feedback.contact._get_user_id_by_email", return_value=USER_1), \
         patch("app.api.feedback.contact.feedback_module.record_feedback_submission", return_value={"id": TICKET_ID, "status": "open"}):
        t_res = await submit_contact_ticket(request=req, background_tasks=bg, payload=ticket_payload)
        assert t_res["success"] is True
        assert t_res["ticket_id"] == TICKET_ID

    # 4. Create and retrieve error session
    err_req = ErrorSessionCreateRequest(
        query_type="bug_report",
        subject="App Crash",
        message="Stack trace log",
        email="test@example.com",
    )
    with patch("app.api.feedback.contact.feedback_module.redis_client.set", new_callable=AsyncMock):
        sess_create = await create_error_session(request=req, payload=err_req)
        assert "session_id" in sess_create

    session_id_created = sess_create["session_id"]
    with patch("app.api.feedback.contact.feedback_module.redis_client.get", new_callable=AsyncMock, return_value=json.dumps({"query_type": "bug_report", "subject": "App Crash"})), \
         patch("app.api.feedback.contact.feedback_module.redis_client.delete", new_callable=AsyncMock):
        sess_get = await get_error_session(request=req, session_id=session_id_created)
        assert sess_get["subject"] == "App Crash"
