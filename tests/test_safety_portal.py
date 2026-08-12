import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException

from app.api.safety.portal.endpoints import (
    get_contact_portal_details,
    remove_trusted_contact,
    request_contact_portal_otp,
    verify_contact_portal_otp,
)
from app.models import (
    SafetyContactPortalOtpRequestRequest,
    SafetyContactPortalOtpVerifyRequest,
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
    mock_redis.set = MagicMock()
    mock_redis.setex = MagicMock()

    mock_fetch.return_value = {"id": "contact-123", "phone": "+1234567890", "user_id": "user-456"}
    mock_send_sms.return_value = MagicMock(success=True)

    payload = SafetyContactPortalOtpRequestRequest(phone="+1234567890")
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

    payload = SafetyContactPortalOtpRequestRequest(phone="+1234567890")
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

    payload = SafetyContactPortalOtpVerifyRequest(phone="+1234567890", code="123456")
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
    mock_redis: MagicMock,
):
    mock_verify_token.return_value = "session-valid"
    mock_fetch_contact.return_value = {"id": "contact-123", "user_id": "user-456"}
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
    mock_redis: MagicMock,
):
    mock_verify_token.return_value = "session-valid"
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
