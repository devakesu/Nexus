"""Phase 25 Coverage Suite: Comprehensive coverage for safety endpoints, safety portal, user auth OTP, and feedback tickets."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.db.client import DatabaseAccessError
from app.db.safety import EscalationInProgressError
from app.models import (
    AccountPhoneOtpRequestRequest,
    AccountPhoneOtpVerifyRequest,
    ConsentUpdateRequest,
    EscalationCancelRequest,
    FeedbackCloseRequest,
    FeedbackCommentRequest,
    FeedbackSubmitRequest,
    LoginByPhoneRequestRequest,
    LoginByPhoneVerifyRequest,
    MECOnboardingRequest,
    NexusOnboardingRequest,
    SafetyAlertRequest,
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
PHONE_VALID = "+14155552671"


def make_dummy_request(client_ip: str = "127.0.0.1") -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/test",
        "headers": [],
        "client": (client_ip, 12345),
        "app": MagicMock(),
    }
    return Request(scope)


# =============================================================================
# 1. SAFETY ENDPOINTS TESTS
# =============================================================================

async def test_safety_endpoints_deep():
    from app.api.safety.endpoints import (
        _check_cached_sos_alert,
        _handle_cancel_escalation,
        _notify_newly_added_contacts,
        cancel_escalation,
        cancel_escalation_post,
        checkin_session,
        end_session,
        put_safety_contacts,
        register_evidence,
        send_safety_alert,
        start_session,
    )

    req = make_dummy_request()

    # _notify_newly_added_contacts: empty, DB error, redis throttle, success
    await _notify_newly_added_contacts(USER_1, [])

    with patch("app.api.safety.endpoints.fetch_contact_facing_profile_summary", side_effect=DatabaseAccessError("fail")):
        await _notify_newly_added_contacts(USER_1, [{"phone": PHONE_VALID}])

    with patch("app.api.safety.endpoints.fetch_contact_facing_profile_summary", return_value={"name": "Alice"}), \
         patch("app.api.safety.endpoints.fetch_safety_contacts_with_id", return_value=[{"id": "cnt-1", "phone": PHONE_VALID}]), \
         patch("app.api.safety.endpoints.redis_client") as mock_redis, \
         patch("app.api.safety.endpoints.send_sms", return_value=MagicMock(success=False, error="SMS fail", error_code="400")):
        mock_redis.incr = AsyncMock(return_value=1)
        mock_redis.expire = AsyncMock()
        await _notify_newly_added_contacts(USER_1, [{"phone": PHONE_VALID}])

        # Over throttle limit
        mock_redis.incr = AsyncMock(return_value=10)
        await _notify_newly_added_contacts(USER_1, [{"phone": PHONE_VALID}])

        # Redis exception
        mock_redis.incr = AsyncMock(side_effect=Exception("Redis down"))
        await _notify_newly_added_contacts(USER_1, [{"phone": PHONE_VALID}])

    # put_safety_contacts: DB error vs success
    sync_req = SafetyContactsSyncRequest(contacts=[SafetyContactIn(name="Bob", phone=PHONE_VALID)])
    with patch("app.api.safety.endpoints.sync_safety_contacts", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await put_safety_contacts(req, sync_req, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.safety.endpoints.sync_safety_contacts", return_value=([], [{"phone": PHONE_VALID}])), \
         patch("app.api.safety.endpoints.safe_create_task"):
        res = await put_safety_contacts(req, sync_req, None, USER_1)
        assert res.count == 1

    # _check_cached_sos_alert: redis hit, malformed json, db hit, db error
    with patch("app.api.safety.endpoints.redis_client") as mock_redis:
        mock_redis.get = AsyncMock(return_value='{"id": "alert-1", "contacts_notified": 2, "contacts_total": 2}')
        hit = await _check_cached_sos_alert("key", USER_1, "sess-1", "sos_loud")
        assert hit is not None
        assert hit.id == "alert-1"

        mock_redis.get = AsyncMock(side_effect=Exception("Redis down"))
        with patch("app.api.safety.endpoints.fetch_recent_safety_alert", return_value={"id": "alert-db", "contacts_notified": 1}):
            db_hit = await _check_cached_sos_alert("key", USER_1, "sess-1", "sos_loud")
            assert db_hit is not None
            assert db_hit.id == "alert-db"

        with patch("app.api.safety.endpoints.fetch_recent_safety_alert", side_effect=Exception("DB fail")):
            assert await _check_cached_sos_alert("key", USER_1, "sess-1", "sos_loud") is None

    # send_safety_alert: DB error, no contacts, inform vs sos
    alert_req = SafetyAlertRequest(alert_type="inform", session_id=USER_1, event_label="Coffee", current_location=SafetyLocation(lat=40.0, lng=-73.0))
    with patch("app.api.safety.endpoints._check_cached_sos_alert", return_value=None), \
         patch("app.api.safety.endpoints.fetch_safety_contacts", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await send_safety_alert(req, alert_req, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.safety.endpoints._check_cached_sos_alert", return_value=None), \
         patch("app.api.safety.endpoints.fetch_safety_contacts", return_value=[]):
        with pytest.raises(HTTPException) as exc:
            await send_safety_alert(req, alert_req, None, USER_1)
        assert exc.value.status_code == 400

    with patch("app.api.safety.endpoints._check_cached_sos_alert", return_value=None), \
         patch("app.api.safety.endpoints.fetch_safety_contacts", return_value=[{"phone": PHONE_VALID}]), \
         patch("app.api.safety.endpoints.fetch_contact_facing_profile_summary", side_effect=Exception("fail")), \
         patch("app.api.safety.endpoints._send_alert_sms_to_contacts", return_value=1), \
         patch("app.api.safety.endpoints._record_safety_alert_response", return_value=MagicMock(id="alert-rec")), \
         patch("app.api.safety.endpoints._cache_sos_alert"):
        res = await send_safety_alert(req, alert_req, None, USER_1)
        assert res.id == "alert-rec"

    # register_evidence: path traversal, prefix mismatch, alert lookup error, alert not found, DB error, success
    ev_req_bad = SafetyEvidenceRegisterRequest(alert_id="00000000-0000-0000-0000-000000000009", storage_path=f"{USER_2}/file.enc", media_key_base64="key", content_type="audio", duration_seconds=10)
    with pytest.raises(HTTPException) as exc:
        await register_evidence(req, ev_req_bad, None, USER_1)
    assert exc.value.status_code == 422

    ev_req_good = SafetyEvidenceRegisterRequest(alert_id="00000000-0000-0000-0000-000000000009", storage_path=f"{USER_1}/audio.enc", media_key_base64="key", content_type="audio", duration_seconds=10)
    with patch("app.api.safety.endpoints.fetch_safety_alert", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await register_evidence(req, ev_req_good, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.safety.endpoints.fetch_safety_alert", return_value={"user_id": USER_2}):
        with pytest.raises(HTTPException) as exc:
            await register_evidence(req, ev_req_good, None, USER_1)
        assert exc.value.status_code == 404

    with patch("app.api.safety.endpoints.fetch_safety_alert", return_value={"user_id": USER_1}), \
         patch("app.api.safety.endpoints.register_safety_evidence", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await register_evidence(req, ev_req_good, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.safety.endpoints.fetch_safety_alert", return_value={"user_id": USER_1}), \
         patch("app.api.safety.endpoints.register_safety_evidence", return_value={"id": "ev-1"}):
        res = await register_evidence(req, ev_req_good, None, USER_1)
        assert res.id == "ev-1"

    # start_session: past time, window exceeded, escalation in progress, DB error, success
    now = datetime.now(timezone.utc)
    start_req_past = SafetySessionStartRequest(label="Dinner", interval_seconds=300, next_checkin_at=now - timedelta(minutes=5))
    with pytest.raises(HTTPException) as exc:
        await start_session(req, start_req_past, None, USER_1)
    assert exc.value.status_code == 400

    start_req_far = SafetySessionStartRequest(label="Dinner", interval_seconds=300, next_checkin_at=now + timedelta(days=10))
    with pytest.raises(HTTPException) as exc:
        await start_session(req, start_req_far, None, USER_1)
    assert exc.value.status_code == 400

    start_req_ok = SafetySessionStartRequest(label="Dinner", interval_seconds=300, next_checkin_at=now + timedelta(minutes=10), event_label="Date")
    with patch("app.api.safety.endpoints.start_safety_session", side_effect=EscalationInProgressError("busy")):
        with pytest.raises(HTTPException) as exc:
            await start_session(req, start_req_ok, None, USER_1)
        assert exc.value.status_code == 400

    with patch("app.api.safety.endpoints.start_safety_session", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await start_session(req, start_req_ok, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.safety.endpoints.start_safety_session", return_value={"id": "sess-start"}):
        res = await start_session(req, start_req_ok, None, USER_1)
        assert res.id == "sess-start"

    # checkin_session: past time, far window, DB error, not found, success
    checkin_past = SafetySessionCheckinRequest(session_id="00000000-0000-0000-0000-000000000001", next_checkin_at=now - timedelta(minutes=1))
    with pytest.raises(HTTPException) as exc:
        await checkin_session(req, checkin_past, None, USER_1)
    assert exc.value.status_code == 400

    checkin_far = SafetySessionCheckinRequest(session_id="00000000-0000-0000-0000-000000000001", next_checkin_at=now + timedelta(days=5))
    with pytest.raises(HTTPException) as exc:
        await checkin_session(req, checkin_far, None, USER_1)
    assert exc.value.status_code == 400

    checkin_ok = SafetySessionCheckinRequest(session_id="00000000-0000-0000-0000-000000000001", next_checkin_at=now + timedelta(minutes=15))
    with patch("app.api.safety.endpoints.heartbeat_safety_session", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await checkin_session(req, checkin_ok, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.safety.endpoints.heartbeat_safety_session", return_value=None):
        with pytest.raises(HTTPException) as exc:
            await checkin_session(req, checkin_ok, None, USER_1)
        assert exc.value.status_code == 404

    with patch("app.api.safety.endpoints.heartbeat_safety_session", return_value={"id": "sess-1"}):
        assert await checkin_session(req, checkin_ok, None, USER_1) == {"ok": True}

    # end_session: DB error vs success
    end_req = SafetySessionEndRequest(session_id="00000000-0000-0000-0000-000000000001")
    with patch("app.api.safety.endpoints.end_safety_session", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await end_session(req, end_req, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.safety.endpoints.end_safety_session"):
        assert await end_session(req, end_req, None, USER_1) == {"ok": True}

    # _handle_cancel_escalation: invalid reason, bad token, replay token, session not found, session ended, already cancelled, escalation mismatch, DB error, success
    res_bad_reason = await _handle_cancel_escalation("sess-1", "tok", "invalid", None)
    assert res_bad_reason.status_code == 400

    with patch("app.api.safety.endpoints.verify_escalation_cancel_token", return_value=None):
        assert (await _handle_cancel_escalation("sess-1", "tok", "safe", None)).status_code == 403

    with patch("app.api.safety.endpoints.verify_escalation_cancel_token", return_value=1), \
         patch("app.api.safety.endpoints.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(return_value=False)
        assert (await _handle_cancel_escalation("sess-1", "tok", "safe", None)).status_code == 400

        mock_redis.set = AsyncMock(return_value=True)
        with patch("app.api.safety.endpoints.fetch_safety_session", return_value=None):
            assert (await _handle_cancel_escalation("sess-1", "tok", "safe", None)).status_code == 404

        with patch("app.api.safety.endpoints.fetch_safety_session", return_value={"status": "ended"}):
            assert (await _handle_cancel_escalation("sess-1", "tok", "safe", None)).status_code == 200

        with patch("app.api.safety.endpoints.fetch_safety_session", return_value={"status": "active", "escalation_cancelled_at": "2026-08-26T00:00:00Z"}):
            assert (await _handle_cancel_escalation("sess-1", "tok", "safe", None)).status_code == 200

        with patch("app.api.safety.endpoints.fetch_safety_session", return_value={"status": "active", "escalation_cancelled_at": None, "escalations_sent": 2}):
            assert (await _handle_cancel_escalation("sess-1", "tok", "safe", None)).status_code == 400

        with patch("app.api.safety.endpoints.fetch_safety_session", return_value={"status": "active", "escalation_cancelled_at": None, "escalations_sent": 1, "user_id": USER_1}), \
             patch("app.api.safety.endpoints.cancel_safety_escalation", side_effect=DatabaseAccessError("fail")):
            with pytest.raises(HTTPException) as exc:
                await _handle_cancel_escalation("sess-1", "tok", "safe", "note")
            assert exc.value.status_code == 503

        with patch("app.api.safety.endpoints.fetch_safety_session", return_value={"status": "active", "escalation_cancelled_at": None, "escalations_sent": 1, "user_id": USER_1}), \
             patch("app.api.safety.endpoints.cancel_safety_escalation"):
            res_ok = await _handle_cancel_escalation("sess-1", "tok", "safe", "all good")
            assert res_ok.status_code == 200

    # cancel_escalation & cancel_escalation_post
    with patch("app.api.safety.endpoints._handle_cancel_escalation", return_value=MagicMock()):
        await cancel_escalation(req, "sess-1", "tok", "safe", "note")
        await cancel_escalation_post(req, "sess-1", EscalationCancelRequest(token="tok", reason="safe", note="note"))


# =============================================================================
# 2. SAFETY PORTAL ENDPOINTS TESTS
# =============================================================================

async def test_safety_portal_endpoints_deep():
    from app.api.safety.portal.endpoints import (
        _enforce_contact_remove_rate_limit,
        _notify_user_of_contact_self_removal,
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

    req = make_dummy_request()

    # request_portal_otp: resend cooldown, session not found vs ended stale, DB error, sentinel OTP
    with patch("app.api.safety.portal.endpoints.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(return_value=False)
        with pytest.raises(HTTPException) as exc:
            await request_portal_otp(req, "sess-1", SafetyPortalOtpRequestRequest(phone=PHONE_VALID))
        assert exc.value.status_code == 429

        mock_redis.set = AsyncMock(return_value=True)
        with patch("app.api.safety.portal.endpoints.fetch_safety_session", side_effect=DatabaseAccessError("fail")):
            with pytest.raises(HTTPException) as exc:
                await request_portal_otp(req, "sess-1", SafetyPortalOtpRequestRequest(phone=PHONE_VALID))
            assert exc.value.status_code == 503

        # Stale session
        with patch("app.api.safety.portal.endpoints.fetch_safety_session", return_value={"status": "ended", "last_escalated_at": "2020-01-01T00:00:00Z"}), \
             patch("app.api.safety.portal.endpoints.redis_client.setex", new_callable=AsyncMock):
            res_stale = await request_portal_otp(req, "sess-1", SafetyPortalOtpRequestRequest(phone=PHONE_VALID))
            assert res_stale.sent is True

    # verify_portal_otp
    with patch("app.api.safety.portal.endpoints.verify_and_consume_hashed_otp", new_callable=AsyncMock), \
         patch("app.api.safety.portal.endpoints.make_portal_access_token", return_value="tok-portal"):
        v_res = await verify_portal_otp(req, "sess-1", SafetyPortalOtpVerifyRequest(phone=PHONE_VALID, code="123456"))
        assert v_res.token == "tok-portal"

    # get_portal_details: unauth, session not found, DB error, active location, download url
    with pytest.raises(HTTPException) as exc:
        await get_portal_details(req, "sess-1", authorization=None)
    assert exc.value.status_code == 401

    with patch("app.api.safety.portal.endpoints.verify_portal_access_token", return_value="phone-hash"), \
         patch("app.api.safety.portal.endpoints.hash_phone_identifier", return_value="phone-hash"):
        with patch("app.api.safety.portal.endpoints.fetch_safety_session", return_value=None):
            with pytest.raises(HTTPException) as exc:
                await get_portal_details(req, "sess-1", authorization="Bearer tok")
            assert exc.value.status_code == 404

        with patch("app.api.safety.portal.endpoints.fetch_safety_session", return_value={"id": "sess-1", "user_id": USER_1, "status": "active"}), \
             patch("app.api.safety.portal.endpoints.fetch_safety_contacts", return_value=[{"phone": PHONE_VALID}]), \
             patch("app.api.safety.portal.endpoints.fetch_alerts_for_session", side_effect=DatabaseAccessError("fail")):
            with pytest.raises(HTTPException) as exc:
                await get_portal_details(req, "sess-1", authorization="Bearer tok")
            assert exc.value.status_code == 503

        with patch("app.api.safety.portal.endpoints.fetch_safety_session", return_value={"id": "sess-1", "user_id": USER_1, "status": "active", "event_context": {"label": "Meet"}}), \
             patch("app.api.safety.portal.endpoints.fetch_safety_contacts", return_value=[{"phone": PHONE_VALID}]), \
             patch("app.api.safety.portal.endpoints.fetch_alerts_for_session", return_value=[{"id": "a-1", "current_location": {"lat": 40.0, "lng": -73.0}, "created_at": "2026-08-26T00:00:00Z"}]), \
             patch("app.api.safety.portal.endpoints.fetch_evidence_for_alert_ids", return_value=[{"id": "ev-1", "storage_path": "path", "content_type": "audio", "media_key_base64": "key", "created_at": "2026-08-26T00:00:00Z"}]), \
             patch("app.api.safety.portal.endpoints.create_evidence_download_url", return_value="https://download.test/ev"):
            det = await get_portal_details(req, "sess-1", authorization="Bearer tok")
            assert det.event_label == "Meet"
            assert det.last_location is not None
            assert len(det.evidence) == 1

    # request_contact_portal_otp & verify_contact_portal_otp: bad token, cooldown, DB error
    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value=None):
        with pytest.raises(HTTPException) as exc:
            await request_contact_portal_otp(req, "bad-tok", SafetyContactPortalOtpRequestRequest(phone=PHONE_VALID))
        assert exc.value.status_code == 400

        with pytest.raises(HTTPException) as exc:
            await verify_contact_portal_otp(req, "bad-tok", SafetyContactPortalOtpVerifyRequest(phone=PHONE_VALID, code="123456"))
        assert exc.value.status_code == 400

    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value="cnt-1"), \
         patch("app.api.safety.portal.endpoints.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(return_value=False)
        with pytest.raises(HTTPException) as exc:
            await request_contact_portal_otp(req, "cnt-1", SafetyContactPortalOtpRequestRequest(phone=PHONE_VALID))
        assert exc.value.status_code == 429

        mock_redis.set = AsyncMock(return_value=True)
        with patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id", side_effect=DatabaseAccessError("fail")):
            with pytest.raises(HTTPException) as exc:
                await request_contact_portal_otp(req, "cnt-1", SafetyContactPortalOtpRequestRequest(phone=PHONE_VALID))
            assert exc.value.status_code == 503

    # get_contact_portal_details: bad token, unauth, contact not found, phone mismatch, DB error, profile not found, success
    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value=None):
        with pytest.raises(HTTPException) as exc:
            await get_contact_portal_details(req, "bad-tok")
        assert exc.value.status_code == 400

    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value="cnt-1"), \
         patch("app.api.safety.portal.endpoints.verify_portal_access_token", return_value=None):
        with pytest.raises(HTTPException) as exc:
            await get_contact_portal_details(req, "cnt-1", authorization="Bearer tok")
        assert exc.value.status_code == 401

    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value="cnt-1"), \
         patch("app.api.safety.portal.endpoints.verify_portal_access_token", return_value="bad-hash"), \
         patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id", return_value=None):
        with pytest.raises(HTTPException) as exc:
            await get_contact_portal_details(req, "cnt-1", authorization="Bearer tok")
        assert exc.value.status_code == 404

    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value="cnt-1"), \
         patch("app.api.safety.portal.endpoints.verify_portal_access_token", return_value="different-hash"), \
         patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id", return_value={"id": "cnt-1", "user_id": USER_1, "phone": PHONE_VALID}):
        with pytest.raises(HTTPException) as exc:
            await get_contact_portal_details(req, "cnt-1", authorization="Bearer tok")
        assert exc.value.status_code == 401

    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value="cnt-1"), \
         patch("app.api.safety.portal.endpoints.hash_phone_identifier", return_value="matching-hash"), \
         patch("app.api.safety.portal.endpoints.verify_portal_access_token", return_value="matching-hash"), \
         patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id", return_value={"id": "cnt-1", "user_id": USER_1, "phone": PHONE_VALID}), \
         patch("app.api.safety.portal.endpoints.fetch_contact_facing_profile_summary", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await get_contact_portal_details(req, "cnt-1", authorization="Bearer tok")
        assert exc.value.status_code == 503

    # _notify_user_of_contact_self_removal: DB error vs success
    with patch("app.api.safety.portal.endpoints.fetch_public_user", side_effect=DatabaseAccessError("fail")):
        await _notify_user_of_contact_self_removal(USER_1, "Bob")

    with patch("app.api.safety.portal.endpoints.fetch_public_user", return_value={"mobile": PHONE_VALID}), \
         patch("app.api.safety.portal.endpoints.fetch_contact_facing_profile_summary", return_value={"name": "Alice"}), \
         patch("app.api.safety.portal.endpoints.get_user_email_by_id", return_value="alice@nexus.test"), \
         patch("app.api.safety.portal.endpoints.send_trusted_contact_removed_notification"), \
         patch("app.api.safety.portal.endpoints.send_sms", return_value=MagicMock(success=True)), \
         patch("app.api.safety.portal.endpoints.send_trusted_contact_removed_email"):
        await _notify_user_of_contact_self_removal(USER_1, "Bob")

    # _enforce_contact_remove_rate_limit: under vs over limit
    with patch("app.api.safety.portal.endpoints.redis_client") as mock_redis:
        mock_redis.incr = AsyncMock(return_value=1)
        mock_redis.expire = AsyncMock()
        await _enforce_contact_remove_rate_limit("token-1")

        mock_redis.incr = AsyncMock(return_value=10)
        with pytest.raises(HTTPException) as exc:
            await _enforce_contact_remove_rate_limit("token-1")
        assert exc.value.status_code == 429

    # remove_trusted_contact & pages
    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value="cnt-1"), \
         patch("app.api.safety.portal.endpoints.hash_phone_identifier", return_value="matching-hash"), \
         patch("app.api.safety.portal.endpoints.verify_portal_access_token", return_value="matching-hash"), \
         patch("app.api.safety.portal.endpoints._enforce_contact_remove_rate_limit"), \
         patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id", return_value={"id": "cnt-1", "user_id": USER_1, "phone": PHONE_VALID}), \
         patch("app.api.safety.portal.endpoints.remove_safety_contact_self_service", return_value={"user_id": USER_1, "name": "Bob"}), \
         patch("app.api.safety.portal.endpoints.safe_create_task"):
        res = await remove_trusted_contact(req, "cnt-1", authorization="Bearer tok")
        assert res.removed is True

    await portal_page(req, "sess-1")
    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token", return_value="cnt-1"):
        await contact_portal_page(req, "cnt-1")


# =============================================================================
# 3. USER AUTH OTP ENDPOINTS TESTS
# =============================================================================

async def test_user_auth_otp_deep():
    from app.api.user.auth_otp import (
        _resolve_onboarding_profile_fields,
        _unhide_special_category_fields,
        _validate_auth_user_allowed,
        accept_terms,
        auth_bootstrap,
        complete_onboarding,
        get_attestation_status,
        request_account_phone_otp,
        request_login_by_phone,
        revoke_all_sessions,
        verify_account_phone_otp,
        verify_login_by_phone,
    )

    req = make_dummy_request()

    # _validate_auth_user_allowed: disposable email, unauthorized domain
    with patch("app.api.user.auth_otp.is_disposable_email", return_value=True):
        with pytest.raises(HTTPException) as exc:
            await _validate_auth_user_allowed("temp@trash.com", {})
        assert exc.value.status_code == 400

    with patch("app.api.user.auth_otp.is_disposable_email", return_value=False), \
         patch("app.api.user.auth_otp.is_allowed_email", return_value=False):
        with pytest.raises(HTTPException) as exc:
            await _validate_auth_user_allowed("user@outside.edu", {})
        assert exc.value.status_code == 400

    # auth_bootstrap: incomplete payload, welcome email send failure
    with pytest.raises(HTTPException) as exc:
        await auth_bootstrap(req, None, {})
    assert exc.value.status_code == 401

    with patch("app.api.user.auth_otp._validate_auth_user_allowed"), \
         patch("app.api.user.auth_otp.fetch_public_user", return_value=None), \
         patch("app.api.user.auth_otp.upsert_public_user", return_value=({"id": USER_1, "is_active": True}, True)), \
         patch("app.api.user.auth_otp.fetch_profile", return_value=None), \
         patch("app.api.user.auth_otp.redis_client") as mock_redis, \
         patch("app.api.user.auth_otp.send_bootstrap_welcome_email", side_effect=Exception("SMTP fail")):
        mock_redis.set = AsyncMock(return_value=True)
        res = await auth_bootstrap(req, None, {"id": USER_1, "email": "test@nexus.test"})
        assert res.user_id == USER_1

    # _resolve_onboarding_profile_fields MEC branch
    mec_payload = MECOnboardingRequest(
        app_variant="nexus_mec",
        age=20,
        campus_branch="CS",
        campus_year=3,
        campus_name="Model Engineering College",
    )
    with pytest.raises(HTTPException) as exc:
        _resolve_onboarding_profile_fields(mec_payload, None, {})
    assert exc.value.status_code == 400

    # complete_onboarding: variant mismatch & success
    nexus_payload = NexusOnboardingRequest(
        app_variant="nexus",
        age=25,
        name="User",
        demographic_bucket="M",
    )
    with patch("app.api.user.auth_otp.fetch_public_user", return_value={"id": USER_1, "app_variant": "nexus_mec", "accepted_terms_version": "1.0", "is_active": True}), \
         patch("app.api.user.auth_otp.fetch_profile", return_value=None):
        with pytest.raises(HTTPException) as exc:
            await complete_onboarding(req, nexus_payload, None, {"id": USER_1, "email": "test@mec.ac.in"})
        assert exc.value.status_code == 400

    with patch("app.api.user.auth_otp.fetch_public_user", return_value={"id": USER_1, "app_variant": "nexus", "accepted_terms_version": "1.0", "is_active": True}), \
         patch("app.api.user.auth_otp.fetch_profile", return_value=None), \
         patch("app.api.user.auth_otp.upsert_profile_variant", return_value=({"id": USER_1, "name": "User"}, True)):
        onboard_res = await complete_onboarding(req, nexus_payload, None, {"id": USER_1, "email": "test@nexus.test"})
        assert onboard_res.user_id == USER_1

    # request_account_phone_otp & verify_account_phone_otp
    with patch("app.api.user.auth_otp.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(return_value=False)
        with pytest.raises(HTTPException) as exc:
            await request_account_phone_otp(req, AccountPhoneOtpRequestRequest(phone=PHONE_VALID), None, USER_1)
        assert exc.value.status_code == 429

    with patch("app.api.user.auth_otp.verify_and_consume_hashed_otp", new_callable=AsyncMock), \
         patch("app.api.user.auth_otp.set_verified_mobile"):
        ver_res = await verify_account_phone_otp(req, AccountPhoneOtpVerifyRequest(phone=PHONE_VALID, code="123456"), None, USER_1)
        assert ver_res.verified is True

    # request_login_by_phone: rate limits, blocklisted, no user
    with patch("app.api.user.auth_otp.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(return_value=True)
        mock_redis.get = AsyncMock(return_value="5")
        with pytest.raises(HTTPException) as exc:
            await request_login_by_phone(req, LoginByPhoneRequestRequest(phone=PHONE_VALID), None)
        assert exc.value.status_code == 429

        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.incr = AsyncMock(return_value=1)
        mock_redis.expire = AsyncMock()
        with patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=True), \
             patch("app.api.user.auth_otp.dummy_email_send_delay"):
            assert (await request_login_by_phone(req, LoginByPhoneRequestRequest(phone=PHONE_VALID), None)).sent is True

    # verify_login_by_phone: blocklisted, user not found, auth session None
    with patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=True):
        with pytest.raises(HTTPException) as exc:
            await verify_login_by_phone(req, LoginByPhoneVerifyRequest(phone=PHONE_VALID, code="123456"), None)
        assert exc.value.status_code == 400

    with patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=False), \
         patch("app.api.user.auth_otp.find_user_id_by_phone", return_value=None):
        with pytest.raises(HTTPException) as exc:
            await verify_login_by_phone(req, LoginByPhoneVerifyRequest(phone=PHONE_VALID, code="123456"), None)
        assert exc.value.status_code == 400

    with patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=False), \
         patch("app.api.user.auth_otp.find_user_id_by_phone", return_value=USER_1), \
         patch("app.api.user.auth_otp.get_user_email_by_id", return_value="alice@nexus.test"), \
         patch("app.api.user.auth_otp.fetch_public_user", return_value={"id": USER_1, "is_active": True}), \
         patch("app.api.user.auth_otp.verify_login_email_otp", return_value=MagicMock(session=None)):
        with pytest.raises(HTTPException) as exc:
            await verify_login_by_phone(req, LoginByPhoneVerifyRequest(phone=PHONE_VALID, code="123456"), None)
        assert exc.value.status_code == 400

    # _unhide_special_category_fields
    with patch("app.api.user.auth_otp.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data={"hidden_profile_fields": ["display_sexuality", "hometown"]})
        mock_sb.table().update().eq().execute.return_value = MagicMock()
        _unhide_special_category_fields(USER_1)

    # accept_terms: declined general, declined guidelines, success
    from app.core.config import settings
    tv = settings.current_terms_version
    consent_req_general_declined = ConsentUpdateRequest(terms_version=tv, general_accepted=False, community_guidelines_accepted=True)
    with patch("app.api.user.auth_otp.fetch_public_user", return_value={"id": USER_1, "is_active": True}), \
         patch("app.api.user.auth_otp.update_user_terms"), \
         patch("app.api.user.auth_otp.update_community_guidelines_consent"):
        with pytest.raises(HTTPException) as exc:
            await accept_terms(req, consent_req_general_declined, None, {"id": USER_1, "email": "alice@nexus.test"})
        assert exc.value.status_code == 400

    consent_req_guidelines_declined = ConsentUpdateRequest(terms_version=tv, general_accepted=True, community_guidelines_accepted=False)
    with patch("app.api.user.auth_otp.fetch_public_user", return_value={"id": USER_1, "is_active": True}), \
         patch("app.api.user.auth_otp.update_user_terms"), \
         patch("app.api.user.auth_otp.update_community_guidelines_consent"):
        with pytest.raises(HTTPException) as exc:
            await accept_terms(req, consent_req_guidelines_declined, None, {"id": USER_1, "email": "alice@nexus.test"})
        assert exc.value.status_code == 400

    consent_req_ok = ConsentUpdateRequest(terms_version=tv, general_accepted=True, community_guidelines_accepted=True, special_category_accepted=True, safety_data_accepted=True)
    with patch("app.api.user.auth_otp.fetch_public_user", return_value={"id": USER_1, "is_active": True}), \
         patch("app.api.user.auth_otp.update_user_terms", return_value=(tv, datetime.now(timezone.utc))), \
         patch("app.api.user.auth_otp.update_community_guidelines_consent"), \
         patch("app.api.user.auth_otp.update_special_category_consent", return_value=(tv, datetime.now(timezone.utc))), \
         patch("app.api.user.auth_otp._unhide_special_category_fields"), \
         patch("app.api.user.auth_otp.update_safety_data_consent", return_value=(tv, datetime.now(timezone.utc))), \
         patch("app.api.user.auth_otp.redis_client"):
        res = await accept_terms(req, consent_req_ok, None, {"id": USER_1, "email": "alice@nexus.test"})
        assert res.user_id == USER_1

    # revoke_all_sessions & get_attestation_status
    with patch("app.api.user.auth_otp.supabase_client") as mock_sb, \
         patch("app.api.user.auth_otp.redis_client"):
        mock_sb.auth.admin.sign_out.side_effect = Exception("fail")
        mock_sb.table().update().eq().execute.side_effect = Exception("fail")
        res = await revoke_all_sessions(req, None, USER_1)
        assert res == {"success": True}

    att = await get_attestation_status(req, {"app_id": "com.nexus", "iss": "Firebase", "iat": 1234, "exp": 5678, "aud": "aud"})
    assert att.verified is True
    assert att.appCheck is True


# =============================================================================
# 4. FEEDBACK TICKETS ENDPOINTS TESTS
# =============================================================================

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
    sub_req = FeedbackSubmitRequest(query_type="bug_report", subject="Crash on startup", message="Application crashes immediately upon clicking login button", attachment_paths=[])
    with patch("app.api.feedback.tickets.feedback_module.record_feedback_submission", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await submit_feedback(req, bg, sub_req, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.feedback.tickets.feedback_module.record_feedback_submission", return_value={"id": "rep-1", "created_at": datetime.now(timezone.utc)}), \
         patch("app.api.feedback.tickets.feedback_module.fetch_user_email", return_value=None):
        res = await submit_feedback(req, bg, sub_req, None, USER_1)
        assert res.id == "rep-1"

    # list_my_feedback_tickets: DB error vs success
    with patch("app.api.feedback.tickets.fetch_user_tickets", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await list_my_feedback_tickets(req, None, 0, None, USER_1)
        assert exc.value.status_code == 503

    # get_feedback_ticket: DB error fetching, not found, DB error assembling, success
    with patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await get_feedback_ticket(req, "rep-1", None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value=None):
        with pytest.raises(HTTPException) as exc:
            await get_feedback_ticket(req, "rep-1", None, USER_1)
        assert exc.value.status_code == 404

    with patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value={"id": "rep-1"}), \
         patch("app.api.feedback.tickets.feedback_module._assemble_ticket_detail", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await get_feedback_ticket(req, "rep-1", None, USER_1)
        assert exc.value.status_code == 503

    # add_feedback_comment: DB error fetching, not found, closed, DB error adding, success
    cmt_req = FeedbackCommentRequest(body="More details here")
    with patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await add_feedback_comment(req, "rep-1", bg, cmt_req, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value=None):
        with pytest.raises(HTTPException) as exc:
            await add_feedback_comment(req, "rep-1", bg, cmt_req, None, USER_1)
        assert exc.value.status_code == 404

    with patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value={"id": "rep-1", "status": "closed"}):
        with pytest.raises(HTTPException) as exc:
            await add_feedback_comment(req, "rep-1", bg, cmt_req, None, USER_1)
        assert exc.value.status_code == 400

    with patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value={"id": "rep-1", "status": "open"}), \
         patch("app.api.feedback.tickets.feedback_module.add_ticket_comment", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await add_feedback_comment(req, "rep-1", bg, cmt_req, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value={"id": "rep-1", "status": "open"}), \
         patch("app.api.feedback.tickets.feedback_module.add_ticket_comment", return_value={"id": "cmt-1", "report_id": "rep-1", "author_id": USER_1, "body": "More details", "created_at": datetime.now(timezone.utc)}), \
         patch("app.api.feedback.tickets.feedback_module.fetch_user_email", return_value="alice@nexus.test"):
        res_cmt = await add_feedback_comment(req, "rep-1", bg, cmt_req, None, USER_1)
        assert res_cmt.id == "cmt-1"

    # close_feedback_ticket: DB error closing, report None and existing None, report None and existing closed, DB error assembling, success
    cls_req = FeedbackCloseRequest(reason="resolved")
    with patch("app.api.feedback.tickets.feedback_module.close_ticket", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await close_feedback_ticket(req, "rep-1", bg, cls_req, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.feedback.tickets.feedback_module.close_ticket", return_value=None), \
         patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value=None):
        with pytest.raises(HTTPException) as exc:
            await close_feedback_ticket(req, "rep-1", bg, cls_req, None, USER_1)
        assert exc.value.status_code == 404

    with patch("app.api.feedback.tickets.feedback_module.close_ticket", return_value=None), \
         patch("app.api.feedback.tickets.feedback_module.fetch_ticket_report", return_value={"id": "rep-1", "status": "closed"}):
        with pytest.raises(HTTPException) as exc:
            await close_feedback_ticket(req, "rep-1", bg, cls_req, None, USER_1)
        assert exc.value.status_code == 400

    with patch("app.api.feedback.tickets.feedback_module.close_ticket", return_value={"id": "rep-1", "status": "closed"}), \
         patch("app.api.feedback.tickets.feedback_module.fetch_user_email", return_value="alice@nexus.test"), \
         patch("app.api.feedback.tickets.feedback_module._assemble_ticket_detail", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc:
            await close_feedback_ticket(req, "rep-1", bg, cls_req, None, USER_1)
        assert exc.value.status_code == 503
