import asyncio
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException

from app.api.safety.portal.endpoints import (
    get_contact_portal_details,
    remove_trusted_contact,
    request_contact_portal_otp,
    request_portal_otp,
    verify_contact_portal_otp,
    verify_portal_otp,
)
from app.models import (
    SafetyContactPortalOtpRequestRequest,
    SafetyContactPortalOtpVerifyRequest,
    SafetyPortalOtpRequestRequest,
    SafetyPortalOtpVerifyRequest,
)


@pytest.fixture(autouse=True)
def mock_verify_contact_portal_token():
    with patch("app.api.safety.portal.endpoints.verify_contact_portal_token") as mock:
        def mock_verify(token: str) -> str:
            return token
        mock.side_effect = mock_verify
        yield mock


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
@patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id")
@patch("app.api.safety.portal.endpoints.send_sms")
async def test_request_contact_portal_otp_success(
    mock_send_sms: MagicMock,
    mock_fetch: MagicMock,
    mock_redis: MagicMock,
):
    mock_redis.exists = AsyncMock(return_value=False)
    mock_redis.set = AsyncMock()
    mock_redis.setex = AsyncMock()

    mock_fetch.return_value = {"id": "contact-123", "phone": "+14155552671", "user_id": "user-456"}
    mock_send_sms.return_value = MagicMock(success=True)

    payload = SafetyContactPortalOtpRequestRequest(phone="+14155552671")
    res = await request_contact_portal_otp(
        request=MagicMock(),
        contact_id="contact-123",
        payload=payload,
    )

    assert res.sent is True
    mock_send_sms.assert_called_once()


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
@patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id")
async def test_request_contact_portal_otp_cooldown(
    mock_fetch: MagicMock,
    mock_redis: MagicMock,
):
    mock_redis.exists = AsyncMock(return_value=True)

    payload = SafetyContactPortalOtpRequestRequest(phone="+14155552671")
    with pytest.raises(HTTPException) as exc_info:
        await request_contact_portal_otp(
            request=MagicMock(),
            contact_id="contact-123",
            payload=payload,
        )

    assert exc_info.value.status_code == 429
    mock_fetch.assert_not_called()


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
@patch("app.api.safety.portal.endpoints.verify_otp_hash")
async def test_verify_contact_portal_otp_success(
    mock_verify: MagicMock,
    mock_redis: MagicMock,
):
    mock_redis.get = AsyncMock(side_effect=[None, "hashed-code"])
    mock_redis.delete = AsyncMock()
    mock_verify.return_value = True

    payload = SafetyContactPortalOtpVerifyRequest(phone="+14155552671", code="123456")
    res = await verify_contact_portal_otp(
        request=MagicMock(),
        contact_id="contact-123",
        payload=payload,
    )

    assert res.token is not None
    assert res.expires_in == 1800


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
@patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id")
@patch("app.api.safety.portal.endpoints.fetch_contact_facing_profile_summary")
@patch("app.api.safety.portal.endpoints.verify_portal_access_token")
async def test_get_contact_portal_details_success(
    mock_verify_token: MagicMock,
    mock_fetch_profile: MagicMock,
    mock_fetch_contact: MagicMock,
    _mock_redis: MagicMock,
):
    from app.core.security.portal_auth import hash_phone_identifier

    phone_id = hash_phone_identifier("+14155552671")
    mock_verify_token.return_value = phone_id
    mock_fetch_contact.return_value = {"id": "contact-123", "user_id": "user-456", "phone": "+14155552671"}
    mock_fetch_profile.return_value = {"name": "User Alice", "profile_pic": None, "hometown": "Chicago"}

    res = await get_contact_portal_details(
        request=MagicMock(),
        contact_id="contact-123",
        authorization="Bearer session-valid",
    )

    assert res.user_name == "User Alice"
    assert res.hometown == "Chicago"


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
@patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id")
@patch("app.api.safety.portal.endpoints.fetch_contact_facing_profile_summary")
@patch("app.api.safety.portal.endpoints.verify_portal_access_token")
async def test_get_contact_portal_details_stale_phone_rejected(
    mock_verify_token: MagicMock,
    mock_fetch_profile: MagicMock,
    mock_fetch_contact: MagicMock,
    _mock_redis: MagicMock,
):
    from app.core.security.portal_auth import hash_phone_identifier

    # Token issued for old phone
    old_phone_id = hash_phone_identifier("+15551111111")
    mock_verify_token.return_value = old_phone_id
    # Stored contact has updated phone
    mock_fetch_contact.return_value = {"id": "contact-123", "user_id": "user-456", "phone": "+15552222222"}

    with pytest.raises(HTTPException) as exc_info:
        await get_contact_portal_details(
            request=MagicMock(),
            contact_id="contact-123",
            authorization="Bearer session-valid",
        )

    assert exc_info.value.status_code == 401
    assert "Invalid or expired portal session" in exc_info.value.detail
    mock_fetch_profile.assert_not_called()


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
@patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id")
@patch("app.api.safety.portal.endpoints.remove_safety_contact_self_service")
@patch("app.api.safety.portal.endpoints.verify_portal_access_token")
@patch("app.api.safety.portal.endpoints.fetch_public_user")
@patch("app.api.safety.portal.endpoints.fetch_contact_facing_profile_summary")
@patch("app.api.safety.portal.endpoints.get_user_email_by_id")
@patch("app.api.safety.portal.endpoints.send_sms")
@patch("app.api.safety.portal.endpoints.send_trusted_contact_removed_email")
async def test_remove_trusted_contact_success(
    mock_send_email: MagicMock,
    mock_send_sms: MagicMock,
    mock_email: MagicMock,
    mock_profile: MagicMock,
    mock_user: MagicMock,
    mock_verify_token: MagicMock,
    mock_remove: MagicMock,
    mock_fetch_contact: MagicMock,
    _mock_redis: MagicMock,
):
    from app.core.security.portal_auth import hash_phone_identifier

    phone_id = hash_phone_identifier("+14155552671")
    mock_verify_token.return_value = phone_id
    mock_fetch_contact.return_value = {"id": "contact-123", "name": "Alice", "user_id": "user-456", "phone": "+14155552671"}
    mock_remove.return_value = {"id": "contact-123", "name": "Alice", "user_id": "user-456"}
    mock_user.return_value = {"mobile": "+1987654321"}
    mock_profile.return_value = {"name": "Bob"}
    mock_email.return_value = "bob@example.com"

    res = await remove_trusted_contact(
        request=MagicMock(),
        contact_id="contact-123",
        authorization="Bearer session-valid",
    )

    assert res.removed is True
    # wait for background task notification to finish
    await asyncio.sleep(0.1)
    mock_send_sms.assert_called_once()
    mock_send_email.assert_called_once()


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
@patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id")
@patch("app.api.safety.portal.endpoints.remove_safety_contact_self_service")
@patch("app.api.safety.portal.endpoints.verify_portal_access_token")
async def test_remove_trusted_contact_stale_phone_rejected(
    mock_verify_token: MagicMock,
    mock_remove: MagicMock,
    mock_fetch_contact: MagicMock,
    _mock_redis: MagicMock,
):
    from app.core.security.portal_auth import hash_phone_identifier

    # Token issued for old phone
    old_phone_id = hash_phone_identifier("+15551111111")
    mock_verify_token.return_value = old_phone_id
    # Stored contact has updated new phone
    mock_fetch_contact.return_value = {"id": "contact-123", "name": "Alice", "user_id": "user-456", "phone": "+15552222222"}

    with pytest.raises(HTTPException) as exc_info:
        await remove_trusted_contact(
            request=MagicMock(),
            contact_id="contact-123",
            authorization="Bearer session-valid",
        )

    assert exc_info.value.status_code == 401
    assert "Invalid or expired portal session" in exc_info.value.detail
    mock_remove.assert_not_called()



@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
@patch("app.api.safety.portal.endpoints.fetch_safety_session")
@patch("app.api.safety.portal.endpoints.fetch_safety_contacts")
@patch("app.api.safety.portal.endpoints.send_sms")
async def test_request_portal_otp_matched_stores_hash_and_sends_sms(
    mock_send_sms: MagicMock,
    mock_fetch_contacts: MagicMock,
    mock_fetch_session: MagicMock,
    mock_redis: MagicMock,
):
    mock_redis.exists = AsyncMock(return_value=False)
    mock_redis.set = AsyncMock()
    mock_redis.setex = AsyncMock()

    mock_fetch_session.return_value = {"id": "session-123", "user_id": "user-456", "status": "active"}
    mock_fetch_contacts.return_value = [{"id": "c-1", "phone": "+15551112233"}]
    mock_send_sms.return_value = MagicMock(success=True)

    payload = SafetyPortalOtpRequestRequest(phone="+15551112233")
    res = await request_portal_otp(
        request=MagicMock(),
        session_id="session-123",
        payload=payload,
    )

    assert res.sent is True
    mock_send_sms.assert_called_once()


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
@patch("app.api.safety.portal.endpoints.fetch_safety_session")
@patch("app.api.safety.portal.endpoints.fetch_safety_contacts")
@patch("app.api.safety.portal.endpoints.send_sms")
async def test_request_portal_otp_ended_stale_session_stores_sentinel_no_sms(
    mock_send_sms: MagicMock,
    mock_fetch_contacts: MagicMock,
    mock_fetch_session: MagicMock,
    mock_redis: MagicMock,
):
    mock_redis.exists = AsyncMock(return_value=False)
    mock_redis.set = AsyncMock()
    mock_redis.setex = AsyncMock()

    # Session ended months ago
    mock_fetch_session.return_value = {
        "id": "session-123",
        "user_id": "user-456",
        "status": "ended",
        "next_checkin_at": "2020-01-01T00:00:00Z",
    }
    mock_fetch_contacts.return_value = [{"id": "c-1", "phone": "+15551112233"}]

    payload = SafetyPortalOtpRequestRequest(phone="+15551112233")
    res = await request_portal_otp(
        request=MagicMock(),
        session_id="session-123",
        payload=payload,
    )

    assert res.sent is True
    mock_send_sms.assert_not_called()
    assert mock_redis.setex.call_count == 1
    call_args = mock_redis.setex.call_args[0]
    assert call_args[2].startswith("sentinel:")


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
@patch("app.api.safety.portal.endpoints.fetch_safety_session")
@patch("app.api.safety.portal.endpoints.fetch_safety_contacts")
@patch("app.api.safety.portal.endpoints.send_sms")
async def test_request_portal_otp_unmatched_stores_sentinel_no_sms(
    mock_send_sms: MagicMock,
    mock_fetch_contacts: MagicMock,
    mock_fetch_session: MagicMock,
    mock_redis: MagicMock,
):
    mock_redis.exists = AsyncMock(return_value=False)
    mock_redis.set = AsyncMock()
    mock_redis.setex = AsyncMock()

    mock_fetch_session.return_value = {"id": "session-123", "user_id": "user-456"}
    mock_fetch_contacts.return_value = [{"id": "c-1", "phone": "+15559998877"}]

    payload = SafetyPortalOtpRequestRequest(phone="+15550000000")
    res = await request_portal_otp(
        request=MagicMock(),
        session_id="session-123",
        payload=payload,
    )

    assert res.sent is True
    mock_send_sms.assert_not_called()
    # Verify sentinel was stored to prevent enumeration
    assert mock_redis.setex.call_count == 1
    call_args = mock_redis.setex.call_args[0]
    assert call_args[0] == "safety_portal:otp:session-123:+15550000000"
    assert call_args[2].startswith("sentinel:")


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
@patch("app.api.safety.portal.endpoints.fetch_safety_contact_by_id")
@patch("app.api.safety.portal.endpoints.send_sms")
async def test_request_contact_portal_otp_unmatched_stores_sentinel_no_sms(
    mock_send_sms: MagicMock,
    mock_fetch: MagicMock,
    mock_redis: MagicMock,
):
    mock_redis.exists = AsyncMock(return_value=False)
    mock_redis.set = AsyncMock()
    mock_redis.setex = AsyncMock()

    mock_fetch.return_value = {"id": "contact-123", "phone": "+15559998877", "user_id": "user-456"}

    payload = SafetyContactPortalOtpRequestRequest(phone="+15550000000")
    res = await request_contact_portal_otp(
        request=MagicMock(),
        contact_id="contact-123",
        payload=payload,
    )

    assert res.sent is True
    mock_send_sms.assert_not_called()
    assert mock_redis.setex.call_count == 1
    call_args = mock_redis.setex.call_args[0]
    assert call_args[0] == "safety_contact_portal:otp:contact-123:+15550000000"
    assert call_args[2].startswith("sentinel:")


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
async def test_verify_portal_otp_sentinel_returns_incorrect_code(
    mock_redis: MagicMock,
):
    """When a sentinel OTP exists (unmatched phone was requested), verify returns 'Incorrect code.'."""
    mock_redis.get = AsyncMock(side_effect=[None, "sentinel:abcdef1234567890"])
    mock_redis.incr = AsyncMock()
    mock_redis.expire = AsyncMock()

    payload = SafetyPortalOtpVerifyRequest(phone="+15550000000", code="000000")
    with pytest.raises(HTTPException) as exc_info:
        await verify_portal_otp(
            request=MagicMock(),
            session_id="session-123",
            payload=payload,
        )

    assert exc_info.value.status_code == 400
    assert exc_info.value.detail == "Incorrect code."


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.redis_client")
async def test_verify_portal_otp_never_requested_returns_expired_or_never_requested(
    mock_redis: MagicMock,
):
    """When no OTP was ever requested (key absent), returns 'expired or was never requested'."""
    mock_redis.get = AsyncMock(side_effect=[None, None])

    payload = SafetyPortalOtpVerifyRequest(phone="+15550000000", code="000000")
    with pytest.raises(HTTPException) as exc_info:
        await verify_portal_otp(
            request=MagicMock(),
            session_id="session-123",
            payload=payload,
        )

    assert exc_info.value.status_code == 400
    assert "expired or was never requested" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.verify_portal_access_token")
@patch("app.api.safety.portal.endpoints.fetch_safety_session")
@patch("app.api.safety.portal.endpoints.fetch_alerts_for_session")
@patch("app.api.safety.portal.endpoints.fetch_evidence_for_alert_ids")
async def test_get_portal_details_active_fresh_location(
    mock_evidence: MagicMock,
    mock_alerts: MagicMock,
    mock_session: MagicMock,
    mock_verify: MagicMock,
):
    from datetime import datetime, timezone
    from app.api.safety.portal.endpoints import get_portal_details

    mock_verify.return_value = "phone-id"
    mock_session.return_value = {
        "id": "session-123",
        "status": "active",
        "label": "Coffee meetup",
    }
    mock_alerts.return_value = [
        {
            "id": "alert-1",
            "current_location": {"lat": 37.7749, "lng": -122.4194},
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
    ]
    mock_evidence.return_value = []

    res = await get_portal_details(
        request=MagicMock(),
        session_id="session-123",
        authorization="Bearer valid-token",
    )

    assert res.status == "active"
    assert res.last_location is not None
    assert res.last_location.lat == 37.7749
    assert res.last_location.lng == -122.4194
    assert res.last_location_at is not None
    # Check that is_active=True was passed to fetch_alerts_for_session
    mock_alerts.assert_called_once_with("session-123", True)


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.verify_portal_access_token")
@patch("app.api.safety.portal.endpoints.fetch_safety_session")
@patch("app.api.safety.portal.endpoints.fetch_alerts_for_session")
@patch("app.api.safety.portal.endpoints.fetch_evidence_for_alert_ids")
async def test_get_portal_details_ended_session_hides_location(
    mock_evidence: MagicMock,
    mock_alerts: MagicMock,
    mock_session: MagicMock,
    mock_verify: MagicMock,
):
    from datetime import datetime, timezone
    from app.api.safety.portal.endpoints import get_portal_details

    mock_verify.return_value = "phone-id"
    mock_session.return_value = {
        "id": "session-123",
        "status": "ended",
        "label": "Coffee meetup",
    }
    mock_alerts.return_value = [
        {
            "id": "alert-1",
            "current_location": None,
            "created_at": datetime.now(timezone.utc).isoformat(),
        },
    ]
    mock_evidence.return_value = []

    res = await get_portal_details(
        request=MagicMock(),
        session_id="session-123",
        authorization="Bearer valid-token",
    )

    assert res.status == "ended"
    assert res.last_location is None
    assert res.last_location_at is None
    # Check that is_active=False was passed to fetch_alerts_for_session
    mock_alerts.assert_called_once_with("session-123", False)


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.verify_portal_access_token")
@patch("app.api.safety.portal.endpoints.fetch_safety_session")
@patch("app.api.safety.portal.endpoints.fetch_alerts_for_session")
@patch("app.api.safety.portal.endpoints.fetch_evidence_for_alert_ids")
async def test_get_portal_details_stale_location_suppressed(
    mock_evidence: MagicMock,
    mock_alerts: MagicMock,
    mock_session: MagicMock,
    mock_verify: MagicMock,
):
    from app.api.safety.portal.endpoints import get_portal_details

    mock_verify.return_value = "phone-id"
    mock_session.return_value = {
        "id": "session-123",
        "status": "active",
        "label": "Coffee meetup",
    }
    # fetch_alerts_for_session already strips stale location
    mock_alerts.return_value = [
        {
            "id": "alert-1",
            "current_location": None,
            "created_at": "2026-08-20T10:00:00+00:00",
        },
    ]
    mock_evidence.return_value = []

    res = await get_portal_details(
        request=MagicMock(),
        session_id="session-123",
        authorization="Bearer valid-token",
    )

    assert res.status == "active"
    assert res.last_location is None
    assert res.last_location_at is None


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.verify_portal_access_token")
@patch("app.api.safety.portal.endpoints.fetch_safety_session")
@patch("app.api.safety.portal.endpoints.fetch_safety_contacts")
async def test_get_portal_details_removed_contact_rejected(
    mock_fetch_contacts: MagicMock,
    mock_session: MagicMock,
    mock_verify: MagicMock,
):
    from app.api.safety.portal.endpoints import get_portal_details
    from app.core.security.portal_auth import hash_phone_identifier

    token_phone_id = hash_phone_identifier("+15551112222")
    mock_verify.return_value = token_phone_id
    mock_session.return_value = {
        "id": "session-123",
        "user_id": "user-456",
        "status": "active",
        "label": "Coffee meetup",
    }
    # User's current contacts do NOT include +15551112222 (it was removed)
    mock_fetch_contacts.return_value = [
        {"id": "c-1", "phone": "+15559998888"},
    ]

    with pytest.raises(HTTPException) as exc_info:
        await get_portal_details(
            request=MagicMock(),
            session_id="session-123",
            authorization="Bearer valid-token",
        )

    assert exc_info.value.status_code == 401
    assert "Invalid or expired portal session" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.safety.portal.endpoints.verify_portal_access_token")
@patch("app.api.safety.portal.endpoints.fetch_safety_session")
@patch("app.api.safety.portal.endpoints.fetch_safety_contacts")
@patch("app.api.safety.portal.endpoints.fetch_alerts_for_session")
@patch("app.api.safety.portal.endpoints.fetch_evidence_for_alert_ids")
async def test_get_portal_details_active_contact_verified(
    mock_evidence: MagicMock,
    mock_alerts: MagicMock,
    mock_fetch_contacts: MagicMock,
    mock_session: MagicMock,
    mock_verify: MagicMock,
):
    from app.api.safety.portal.endpoints import get_portal_details
    from app.core.security.portal_auth import hash_phone_identifier

    token_phone_id = hash_phone_identifier("+15551112222")
    mock_verify.return_value = token_phone_id
    mock_session.return_value = {
        "id": "session-123",
        "user_id": "user-456",
        "status": "active",
        "label": "Coffee meetup",
    }
    mock_fetch_contacts.return_value = [
        {"id": "c-1", "phone": "+15551112222"},
    ]
    mock_alerts.return_value = []
    mock_evidence.return_value = []

    res = await get_portal_details(
        request=MagicMock(),
        session_id="session-123",
        authorization="Bearer valid-token",
    )
    assert res.status == "active"
    assert res.label == "Coffee meetup"


def test_fetch_alerts_for_session_staleness_and_decrypt_flag() -> None:
    import json
    from datetime import datetime, timedelta, timezone
    from unittest.mock import MagicMock, patch
    from app.core.security.crypto import encrypt_to_hex
    from app.db.safety.alerts import fetch_alerts_for_session

    fresh_time = (datetime.now(timezone.utc) - timedelta(minutes=10)).isoformat()
    stale_time = (datetime.now(timezone.utc) - timedelta(hours=5)).isoformat()
    enc_loc = encrypt_to_hex(json.dumps({"lat": 40.7128, "lng": -74.0060}))

    mock_rows = [
        {"id": "a-fresh", "alert_type": "sos", "current_location": enc_loc, "created_at": fresh_time},
        {"id": "a-stale", "alert_type": "sos", "current_location": enc_loc, "created_at": stale_time},
    ]

    with patch("app.db.safety.alerts.supabase_client") as mock_supabase:
        mock_execute = MagicMock()
        mock_execute.execute.return_value = MagicMock(data=list(mock_rows))
        mock_supabase.table.return_value.select.return_value.eq.return_value.order.return_value = mock_execute

        # 1. When decrypt_locations is True, fresh is decrypted, stale is None
        alerts = fetch_alerts_for_session("session-1", decrypt_locations=True)
        assert alerts[0]["current_location"] == {"lat": 40.7128, "lng": -74.0060}
        assert alerts[1]["current_location"] is None

        # 2. When decrypt_locations is False, both are None
        mock_execute.execute.return_value = MagicMock(data=[dict(r) for r in mock_rows])
        alerts_no_decrypt = fetch_alerts_for_session("session-1", decrypt_locations=False)
        assert alerts_no_decrypt[0]["current_location"] is None
        assert alerts_no_decrypt[1]["current_location"] is None


def test_sync_safety_contacts_atomic_rpc_and_opt_out_enforcement() -> None:
    from unittest.mock import MagicMock, patch
    from app.core.security.portal_auth import normalize_phone
    from app.core.security.crypto import compute_blind_index
    from app.db.safety.contacts import sync_safety_contacts

    user_id = "00000000-0000-0000-0000-000000000001"
    phone_blocked = "+15551112222"
    phone_new = "+15553334444"
    blind_index_blocked = compute_blind_index(normalize_phone(phone_blocked))
    blind_index_new = compute_blind_index(normalize_phone(phone_new))

    contacts = [
        {"name": "Blocked Contact", "phone": phone_blocked},
        {"name": "New Contact", "phone": phone_new},
    ]

    with patch("app.db.safety.contacts.supabase_client") as mock_supabase:
        mock_rpc = MagicMock()
        mock_rpc.execute.return_value = MagicMock(
            data={
                "blocked_indices": [blind_index_blocked],
                "newly_notified_indices": [blind_index_new],
            }
        )
        mock_supabase.rpc.return_value = mock_rpc

        blocked, newly_notified = sync_safety_contacts(user_id, contacts)

        # Verify RPC was called with p_contacts containing phone_blind_index
        mock_supabase.rpc.assert_called_once()
        rpc_call_args = mock_supabase.rpc.call_args[0]
        assert rpc_call_args[0] == "sync_safety_contacts"
        payload = rpc_call_args[1]
        assert payload["p_user_id"] == user_id
        assert len(payload["p_contacts"]) == 2
        assert any(c["phone_blind_index"] == blind_index_blocked for c in payload["p_contacts"])
        assert any(c["phone_blind_index"] == blind_index_new for c in payload["p_contacts"])

        # Verify blocked and newly_notified return partitioning
        assert len(blocked) == 1
        assert blocked[0]["name"] == "Blocked Contact"
        assert len(newly_notified) == 1
        assert newly_notified[0]["name"] == "New Contact"


def test_remove_safety_contact_self_service_sets_notice_first() -> None:
    from unittest.mock import MagicMock, patch
    from app.db.safety.contacts import remove_safety_contact_self_service

    contact_id = "00000000-0000-0000-0000-000000000099"
    contact_data = {
        "id": contact_id,
        "user_id": "00000000-0000-0000-0000-000000000001",
        "name": "Trusted Friend",
        "phone": "+15559998888",
    }

    call_order: list[str] = []

    with patch("app.db.safety.contacts.fetch_safety_contact_by_id", return_value=contact_data), \
         patch("app.db.safety.contacts.supabase_client") as mock_supabase:

        def table_side_effect(table_name: str) -> MagicMock:
            mock_table = MagicMock()
            if table_name == "safety_contact_notices":
                def upsert_fn(*_args: Any, **_kwargs: Any) -> MagicMock:
                    call_order.append("upsert_notice")
                    mock_exec = MagicMock()
                    mock_exec.execute.return_value = MagicMock()
                    return mock_exec
                mock_table.upsert = upsert_fn
            elif table_name == "safety_contacts":
                def delete_fn(*_args: Any, **_kwargs: Any) -> MagicMock:
                    mock_eq = MagicMock()
                    def eq_fn(*_a: Any, **_k: Any) -> MagicMock:
                        call_order.append("delete_contact")
                        mock_exec = MagicMock()
                        mock_exec.execute.return_value = MagicMock()
                        return mock_exec
                    mock_eq.eq = eq_fn
                    return mock_eq
                mock_table.delete = delete_fn
            return mock_table

        mock_supabase.table.side_effect = table_side_effect

        res = remove_safety_contact_self_service(contact_id)
        assert res is not None
        assert res["name"] == "Trusted Friend"

        # Notice MUST be upserted before contact deletion to prevent race condition
        assert call_order == ["upsert_notice", "delete_contact"]


def test_sync_safety_contacts_exceeding_max_limit_raises_value_error() -> None:
    from app.db.safety.contacts import sync_safety_contacts

    user_id = "00000000-0000-0000-0000-000000000001"
    contacts = [
        {"name": "C1", "phone": "+15551111111"},
        {"name": "C2", "phone": "+15552222222"},
        {"name": "C3", "phone": "+15553333333"},
        {"name": "C4", "phone": "+15554444444"},
    ]

    with pytest.raises(ValueError, match="Cannot sync more than 3 safety contacts"):
        sync_safety_contacts(user_id, contacts)



