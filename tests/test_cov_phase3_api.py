"""Phase 3 API Layer Coverage Expansion.

Targets:
- app/api/feedback/contact.py
- app/api/safety/endpoints.py
- app/api/user/settings.py
- app/api/chat/keys.py
- app/api/chat/presence.py
- app/api/spotify/auth.py
- app/api/discovery/likes.py
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import BackgroundTasks, HTTPException, UploadFile
from starlette.requests import Request

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
SESS_1 = "00000000-0000-0000-0000-000000000011"
ALERT_1 = "00000000-0000-0000-0000-000000000022"


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


# -----------------------------------------------------------------------------
# 1. API FEEDBACK CONTACT & MODELS
# -----------------------------------------------------------------------------
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
    with patch("app.api.feedback.contact._verify_and_consume_otp", AsyncMock(side_effect=HTTPException(status_code=400, detail="Invalid OTP"))):
        with pytest.raises(HTTPException):
            await submit_contact_ticket(
                request=req,
                background_tasks=bg,
                payload=payload,
            )


# -----------------------------------------------------------------------------
# 2. API SAFETY ENDPOINTS
# -----------------------------------------------------------------------------
async def test_api_safety_endpoints():
    from app.api.safety.endpoints import (
        cancel_escalation,
        checkin_session,
        end_session,
        put_safety_contacts,
        send_safety_alert,
        start_session,
    )
    from app.models import (
        SafetyAlertRequest,
        SafetyAlertResponse,
        SafetyContactIn,
        SafetyContactsSyncRequest,
        SafetyLocation,
        SafetySessionCheckinRequest,
        SafetySessionEndRequest,
        SafetySessionStartRequest,
    )

    req = _make_mock_request()

    # 1. put_safety_contacts
    payload = SafetyContactsSyncRequest(contacts=[SafetyContactIn(name="Bob", phone="+15555555555")])
    with patch("app.api.safety.endpoints.sync_safety_contacts", return_value=([], [])):
        res = await put_safety_contacts(req, payload, _device=None, user_id=USER_1)
        assert res.count == 1

    # 2. start_session
    sess_in = SafetySessionStartRequest(
        label="Date",
        interval_seconds=900,
        next_checkin_at=datetime.fromtimestamp(datetime.now(timezone.utc).timestamp() + 300, tz=timezone.utc),
    )
    with patch("app.api.safety.endpoints.start_safety_session", return_value={"id": SESS_1, "interval_seconds": 900}):
        sess = await start_session(req, sess_in, _device=None, user_id=USER_1)
        assert sess is not None

    # 3. checkin_session
    hb_in = SafetySessionCheckinRequest(
        session_id=SESS_1,
        next_checkin_at=datetime.fromtimestamp(datetime.now(timezone.utc).timestamp() + 600, tz=timezone.utc),
    )
    with patch("app.api.safety.endpoints.heartbeat_safety_session", return_value={"id": SESS_1, "status": "active"}):
        hb = await checkin_session(req, hb_in, _device=None, user_id=USER_1)
        assert hb is not None

    # 4. end_session
    end_in = SafetySessionEndRequest(session_id=SESS_1)
    with patch("app.api.safety.endpoints.end_safety_session"):
        ended = await end_session(req, end_in, _device=None, user_id=USER_1)
        assert ended is not None

    # 5. send_safety_alert
    alert_in = SafetyAlertRequest(alert_type="sos_loud", current_location=SafetyLocation(lat=37.7749, lng=-122.4194))
    with patch("app.api.safety.endpoints.fetch_safety_contacts", return_value=[{"phone": "+15555555555"}]), \
         patch("app.api.safety.endpoints._send_alert_sms_to_contacts", AsyncMock(return_value=1)), \
         patch("app.api.safety.endpoints._record_safety_alert_response", AsyncMock(return_value=SafetyAlertResponse(id=ALERT_1, contacts_notified=1, contacts_total=1))), \
         patch("app.api.safety.endpoints._cache_sos_alert", AsyncMock()):
        alt = await send_safety_alert(req, alert_in, _device=None, user_id=USER_1)
        assert alt.id == ALERT_1

    # 6. cancel_escalation
    with patch("app.api.safety.endpoints.verify_escalation_cancel_token", return_value=1), \
         patch("app.api.safety.endpoints.fetch_safety_session", return_value={"id": SESS_1, "user_id": USER_1, "status": "active", "escalations_sent": 1}), \
         patch("app.api.safety.endpoints.cancel_safety_escalation", return_value={"id": SESS_1}), \
         patch("app.api.safety.endpoints.redis_client") as mock_r:
        mock_r.set.return_value = True
        canc = await cancel_escalation(req, SESS_1, token="valid_tok", reason="safe", note=None)
        assert canc.status_code == 200


# -----------------------------------------------------------------------------
# 3. API USER SETTINGS & PRIVACY
# -----------------------------------------------------------------------------
async def test_api_user_settings():
    from app.api.user.settings import (
        get_email_notification_settings,
        get_privacy_settings,
        update_email_notification_settings,
        update_privacy_settings,
    )
    from app.models import (
        EmailNotificationSettingsUpdate,
        PrivacySettingsUpdate,
    )

    req = _make_mock_request()
    mock_row = {
        "id": USER_1,
        "hidden_profile_fields": ["pronouns"],
        "share_active_status": True,
        "share_read_receipts": True,
        "email_notify_matches": True,
        "email_notify_messages": True,
        "email_notify_digest": False,
        "email_notify_product_updates": True,
        "email_notify_promotions": False,
    }
    mock_t = MagicMock()
    mock_t.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(data=mock_row)
    mock_t.update.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(data=[mock_row])

    with patch("app.api.user.settings.supabase_client.table", return_value=mock_t):
        priv = get_privacy_settings(req, _device=None, user_id=USER_1)
        assert priv.share_active_status is True

        up_priv = update_privacy_settings(
            req,
            payload=PrivacySettingsUpdate(hidden_fields=["pronouns"], share_active_status=False),
            _device=None,
            user_id=USER_1,
        )
        assert up_priv is not None

        email_s = get_email_notification_settings(req, _device=None, user_id=USER_1)
        assert email_s.email_notify_matches is True

        up_email = update_email_notification_settings(
            req,
            payload=EmailNotificationSettingsUpdate(email_notify_digest=True),
            _device=None,
            user_id=USER_1,
        )
        assert up_email is not None


# -----------------------------------------------------------------------------
# 4. API CHAT KEYS, PRESENCE, SPOTIFY & DISCOVERY LIKES
# -----------------------------------------------------------------------------
async def test_api_chat_presence_spotify_likes():
    from app.api.chat.keys import (
        get_key_bundle,
        get_one_time_prekey_count,
        upload_identity_key,
        upload_one_time_prekeys,
    )
    from app.api.chat.presence import (
        get_presence,
        send_presence_heartbeat,
    )
    from app.api.discovery.likes import (
        get_likes_inbox,
        mark_likes_as_seen,
        record_like_back_action,
    )
    from app.api.spotify.auth import spotify_connect
    from app.models import (
        LikeActionRequest,
        MarkLikesSeenRequest,
        OneTimePrekeyItem,
        PresenceHeartbeatRequest,
        UploadIdentityKeyRequest,
        UploadOneTimePrekeysRequest,
    )

    req = _make_mock_request()

    # 1. chat keys
    dummy_bundle = {
        "user_id": USER_2,
        "identity_public_key": b"\x00" * 32,
        "registration_id": 1234,
        "signed_prekey_id": 1,
        "signed_prekey_public": b"\x11" * 32,
        "signed_prekey_signature": b"\x22" * 64,
        "one_time_prekey_id": None,
        "one_time_prekey_public": None,
        "one_time_prekey_used": False,
    }
    with patch("app.api.chat.keys.fetch_x3dh_key_bundle_unified", return_value=(dummy_bundle, None)):
        bundle = await get_key_bundle(req, target_user_id=USER_2, _device=None, user_id=USER_1)
        assert bundle is not None

    with patch("app.api.chat.keys.count_unused_one_time_prekeys", return_value=42):
        cnt = await get_one_time_prekey_count(req, _device=None, user_id=USER_1)
        assert cnt.count == 42

    with patch("app.api.chat.keys.upsert_identity_key"):
        up_id = UploadIdentityKeyRequest(
            identity_public_key=b"\x00" * 32,
            registration_id=100,
        )
        res_id = await upload_identity_key(req, up_id, _device=None, user_id=USER_1)
        assert res_id["success"] is True

    with patch("app.api.chat.keys.bulk_insert_one_time_prekeys"):
        otk = UploadOneTimePrekeysRequest(prekeys=[OneTimePrekeyItem(key_id=1, public_key=b"\x33" * 32)])
        res_otk = await upload_one_time_prekeys(req, otk, _device=None, user_id=USER_1)
        assert res_otk["success"] is True

    # 2. presence
    with patch("app.api.chat.presence.upsert_presence_heartbeat"):
        await send_presence_heartbeat(req, PresenceHeartbeatRequest(is_online=True), _device=None, user_id=USER_1)

    with patch("app.api.chat.presence._resolve_single_presence", return_value=MagicMock(is_online=True)):
        pres = await get_presence(req, target_user_id=USER_2, _device=None, user_id=USER_1)
        assert pres.is_online is True

    # 3. spotify auth
    with patch("app.api.spotify.auth._store_state", AsyncMock()), \
         patch("app.api.spotify.auth.settings.spotify_client_id", "client_123"), \
         patch("app.api.spotify.auth.settings.spotify_redirect_uri", "https://app.nexus.com/callback"):
        url_res = await spotify_connect(req, _device=None, user_id=USER_1)
        assert "auth_url" in url_res

    # 4. discovery likes inbox & actions
    with patch("app.api.discovery.likes.fetch_likes_for_user", return_value=[]):
        inbox = await get_likes_inbox(req, tab="Dating", _device=None, user_id=USER_1)
        assert inbox.likes == []

    with patch("app.api.discovery.likes.mark_likes_seen"):
        seen_res = await mark_likes_as_seen(req, MarkLikesSeenRequest(mark_all=True, tab="Dating"), _device=None, user_id=USER_1)
        assert seen_res["success"] is True

    act_payload = LikeActionRequest(target_id=USER_2, action="pass", tab="Dating")
    with patch("app.api.discovery.likes._validate_conversation_membership", AsyncMock()), \
         patch("app.api.discovery.likes.revoke_incoming_like", return_value=True), \
         patch("app.api.discovery.likes.record_discovery_action"):
        act_res = await record_like_back_action(req, act_payload, _device=None, user_id=USER_1)
        assert act_res is not None
