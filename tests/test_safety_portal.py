import asyncio
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

    mock_fetch_session.return_value = {"id": "session-123", "user_id": "user-456"}
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
    # Ensure setex was called for OTP storage
    assert mock_redis.setex.call_count == 1
    call_args = mock_redis.setex.call_args[0]
    assert call_args[0] == "safety_portal:otp:session-123:+15551112233"
    assert not call_args[2].startswith("sentinel:")


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

