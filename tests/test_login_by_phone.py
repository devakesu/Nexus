"""Unit tests for login-by-phone multi-tier rate limiting (per-IP cooldown & per-phone sliding window)."""

from typing import Any
from unittest.mock import patch

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from app.api.user.auth_otp import (
    _LOGIN_BY_PHONE_MAX_PHONE_ATTEMPTS,
    _login_by_phone_ip_resend_key,
    _login_by_phone_phone_limit_key,
    _login_by_phone_resend_key,
    request_login_by_phone,
    verify_login_by_phone,
)
from app.models import LoginByPhoneRequestRequest, LoginByPhoneVerifyRequest


def _build_request(client_ip: str) -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/auth/login-by-phone/request",
        "headers": [],
        "client": (client_ip, 12345),
    }
    return Request(scope)


@pytest.fixture(autouse=True)
def mock_phone_not_blocklisted():
    """Default fixture ensuring is_phone_blocklisted is mocked to False unless overridden."""
    with patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=False):
        yield


@pytest.mark.anyio
async def test_login_by_phone_tier1_ip_cooldown_and_tier2_phone_increment():
    """Verifies that login-by-phone sets Tier 1 IP cooldown and increments Tier 2 phone attempt counter."""
    redis_store: dict[str, str] = {}
    redis_ttls: dict[str, int] = {}

    async def mock_exists(key: str) -> bool:
        return key in redis_store

    async def mock_get(key: str) -> str | None:
        return redis_store.get(key)

    async def mock_set(key: str, val: str, *args: Any, **kwargs: Any) -> bool:
        _ = args, kwargs
        redis_store[key] = val
        return True

    async def mock_incr(key: str) -> int:
        val = int(redis_store.get(key, "0")) + 1
        redis_store[key] = str(val)
        return val

    async def mock_expire(key: str, seconds: int) -> bool:
        redis_ttls[key] = seconds
        return True

    req = _build_request("198.51.100.1")
    payload = LoginByPhoneRequestRequest(phone="+14155552671")

    with patch("app.api.user.auth_otp.redis_client.exists", side_effect=mock_exists), \
         patch("app.api.user.auth_otp.redis_client.get", side_effect=mock_get), \
         patch("app.api.user.auth_otp.redis_client.set", side_effect=mock_set), \
         patch("app.api.user.auth_otp.redis_client.incr", side_effect=mock_incr), \
         patch("app.api.user.auth_otp.redis_client.expire", side_effect=mock_expire), \
         patch("app.api.user.auth_otp.find_user_id_by_phone", return_value=None):
        resp = await request_login_by_phone(req, payload, _device=None)
        assert resp.sent is True
        assert not hasattr(resp, "exists")

    assert _login_by_phone_ip_resend_key("198.51.100.1") in redis_store
    assert _login_by_phone_resend_key("198.51.100.1", "+14155552671") in redis_store
    phone_key = _login_by_phone_phone_limit_key("+14155552671")
    assert redis_store.get(phone_key) == "1"
    assert redis_ttls.get(phone_key) == 1800  # 30 minutes


@pytest.mark.anyio
async def test_login_by_phone_tier1_rejects_same_ip_during_cooldown():
    """Verifies that requests from the same IP during 60s cooldown are rejected with HTTP 429."""
    redis_store = {
        _login_by_phone_ip_resend_key("198.51.100.1"): "1",
    }

    async def mock_exists(key: str) -> bool:
        return key in redis_store

    async def mock_get(key: str) -> str | None:
        return redis_store.get(key)

    req = _build_request("198.51.100.1")
    payload = LoginByPhoneRequestRequest(phone="+14155552671")

    with patch("app.api.user.auth_otp.redis_client.exists", side_effect=mock_exists), \
         patch("app.api.user.auth_otp.redis_client.get", side_effect=mock_get), \
         pytest.raises(HTTPException) as exc_info:
        await request_login_by_phone(req, payload, _device=None)

    assert exc_info.value.status_code == 429
    assert "wait a bit" in exc_info.value.detail


@pytest.mark.anyio
async def test_login_by_phone_tier2_caps_attempts_across_multiple_ips_at_limit():
    """Verifies that requests across distinct IPs are capped at max 3 attempts per 30 minutes per phone."""
    redis_store: dict[str, str] = {}
    redis_ttls: dict[str, int] = {}

    async def mock_exists(key: str) -> bool:
        return key in redis_store

    async def mock_get(key: str) -> str | None:
        return redis_store.get(key)

    async def mock_set(key: str, val: str, *args: Any, **kwargs: Any) -> bool:
        _ = args, kwargs
        redis_store[key] = val
        return True

    async def mock_incr(key: str) -> int:
        val = int(redis_store.get(key, "0")) + 1
        redis_store[key] = str(val)
        return val

    async def mock_expire(key: str, seconds: int) -> bool:
        redis_ttls[key] = seconds
        return True

    payload = LoginByPhoneRequestRequest(phone="+14155552671")

    # 3 distinct IPs can execute up to the 3 attempt limit
    for i in range(1, _LOGIN_BY_PHONE_MAX_PHONE_ATTEMPTS + 1):
        req = _build_request(f"198.51.100.{i}")
        with patch("app.api.user.auth_otp.redis_client.exists", side_effect=mock_exists), \
             patch("app.api.user.auth_otp.redis_client.get", side_effect=mock_get), \
             patch("app.api.user.auth_otp.redis_client.set", side_effect=mock_set), \
             patch("app.api.user.auth_otp.redis_client.incr", side_effect=mock_incr), \
             patch("app.api.user.auth_otp.redis_client.expire", side_effect=mock_expire), \
             patch("app.api.user.auth_otp.find_user_id_by_phone", return_value=None):
            resp = await request_login_by_phone(req, payload, _device=None)
            assert resp.sent is True

    # 4th request from a brand new IP is blocked by Tier 2 phone cap
    req_4 = _build_request("198.51.100.99")
    with patch("app.api.user.auth_otp.redis_client.exists", side_effect=mock_exists), \
         patch("app.api.user.auth_otp.redis_client.get", side_effect=mock_get), \
         pytest.raises(HTTPException) as exc_info:
        await request_login_by_phone(req_4, payload, _device=None)

    assert exc_info.value.status_code == 429
    assert "Too many login attempts for this phone number" in exc_info.value.detail


@pytest.mark.anyio
async def test_login_by_phone_anti_enumeration_identical_response():
    """Verifies registered vs unregistered numbers return identical responses without exists field."""
    redis_store: dict[str, str] = {}

    async def mock_exists(key: str) -> bool:
        return key in redis_store

    async def mock_get(key: str) -> str | None:
        return redis_store.get(key)

    async def mock_set(key: str, val: str, *args: Any, **kwargs: Any) -> bool:
        _ = args, kwargs
        redis_store[key] = val
        return True

    async def mock_incr(key: str) -> int:
        val = int(redis_store.get(key, "0")) + 1
        redis_store[key] = str(val)
        return val

    async def mock_expire(key: str, seconds: int) -> bool:
        _ = key, seconds
        return True

    payload = LoginByPhoneRequestRequest(phone="+14155552671")

    # 1. Unregistered number
    req1 = _build_request("198.51.100.10")
    with patch("app.api.user.auth_otp.redis_client.exists", side_effect=mock_exists), \
         patch("app.api.user.auth_otp.redis_client.get", side_effect=mock_get), \
         patch("app.api.user.auth_otp.redis_client.set", side_effect=mock_set), \
         patch("app.api.user.auth_otp.redis_client.incr", side_effect=mock_incr), \
         patch("app.api.user.auth_otp.redis_client.expire", side_effect=mock_expire), \
         patch("app.api.user.auth_otp.find_user_id_by_phone", return_value=None), \
         patch("app.api.user.auth_otp.send_login_email_otp") as mock_send_unreg:
        resp_unreg = await request_login_by_phone(req1, payload, _device=None)
        assert resp_unreg.model_dump() == {"sent": True}
        mock_send_unreg.assert_not_called()

    # 2. Registered number
    req2 = _build_request("198.51.100.20")
    with patch("app.api.user.auth_otp.redis_client.exists", side_effect=mock_exists), \
         patch("app.api.user.auth_otp.redis_client.get", side_effect=mock_get), \
         patch("app.api.user.auth_otp.redis_client.set", side_effect=mock_set), \
         patch("app.api.user.auth_otp.redis_client.incr", side_effect=mock_incr), \
         patch("app.api.user.auth_otp.redis_client.expire", side_effect=mock_expire), \
         patch("app.api.user.auth_otp.find_user_id_by_phone", return_value="uuid-user-123"), \
         patch("app.api.user.auth_otp.get_user_email_by_id", return_value="user@example.com"), \
         patch("app.api.user.auth_otp.send_login_email_otp") as mock_send_reg:
        resp_reg = await request_login_by_phone(req2, payload, _device=None)
        assert resp_reg.model_dump() == {"sent": True}
        mock_send_reg.assert_called_once_with("user@example.com")


class _MockSession:
    access_token = "mock-access-token"
    refresh_token = "mock-refresh-token"
    expires_in = 3600


class _MockAuthResponse:
    session = _MockSession()


@pytest.mark.anyio
async def test_verify_login_by_phone_active_user_success():
    """Active user with correct code successfully verifies and obtains session tokens."""
    req = _build_request("198.51.100.1")
    payload = LoginByPhoneVerifyRequest(phone="+14155552671", code="123456")

    user_row = {
        "id": "uuid-user-123",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": None,
    }

    with patch("app.api.user.auth_otp.find_user_id_by_phone", return_value="uuid-user-123"), \
         patch("app.api.user.auth_otp.get_user_email_by_id", return_value="user@example.com"), \
         patch("app.api.user.auth_otp.fetch_public_user", return_value=user_row), \
         patch("app.api.user.auth_otp.verify_login_email_otp", return_value=_MockAuthResponse()):
        resp = await verify_login_by_phone(req, payload, _device=None)
        assert resp.refresh_token == "mock-refresh-token"


@pytest.mark.anyio
async def test_verify_login_by_phone_suspended_user_raises_403():
    """Suspended user is blocked from obtaining tokens via phone login verification."""
    req = _build_request("198.51.100.1")
    payload = LoginByPhoneVerifyRequest(phone="+14155552671", code="123456")

    user_row = {
        "id": "uuid-user-123",
        "is_active": True,
        "is_suspended": True,
        "deletion_requested_at": None,
        "moderation_reason_code": "harassment",
    }

    with patch("app.api.user.auth_otp.find_user_id_by_phone", return_value="uuid-user-123"), \
         patch("app.api.user.auth_otp.get_user_email_by_id", return_value="user@example.com"), \
         patch("app.api.user.auth_otp.fetch_public_user", return_value=user_row), \
         patch("app.api.user.auth_otp.verify_login_email_otp") as mock_verify_otp:
        with pytest.raises(HTTPException) as exc_info:
            await verify_login_by_phone(req, payload, _device=None)
        assert exc_info.value.status_code == 403
        assert "suspended" in exc_info.value.detail.lower()
        mock_verify_otp.assert_not_called()


@pytest.mark.anyio
async def test_verify_login_by_phone_deletion_pending_raises_403():
    """Deletion-pending user is blocked with 403 upon phone login verification."""
    req = _build_request("198.51.100.1")
    payload = LoginByPhoneVerifyRequest(phone="+14155552671", code="123456")

    user_row = {
        "id": "uuid-user-123",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": "2026-08-15T12:00:00Z",
    }

    with patch("app.api.user.auth_otp.find_user_id_by_phone", return_value="uuid-user-123"), \
         patch("app.api.user.auth_otp.get_user_email_by_id", return_value="user@example.com"), \
         patch("app.api.user.auth_otp.fetch_public_user", return_value=user_row), \
         patch("app.api.user.auth_otp.verify_login_email_otp") as mock_verify_otp:
        with pytest.raises(HTTPException) as exc_info:
            await verify_login_by_phone(req, payload, _device=None)
        assert exc_info.value.status_code == 403
        assert "Account is pending deletion." in exc_info.value.detail
        mock_verify_otp.assert_not_called()


@pytest.mark.anyio
async def test_verify_login_by_phone_inactive_user_raises_403():
    """Inactive user is blocked with 403 upon phone login verification."""
    req = _build_request("198.51.100.1")
    payload = LoginByPhoneVerifyRequest(phone="+14155552671", code="123456")

    user_row = {
        "id": "uuid-user-123",
        "is_active": False,
        "is_suspended": False,
        "deletion_requested_at": None,
    }

    with patch("app.api.user.auth_otp.find_user_id_by_phone", return_value="uuid-user-123"), \
         patch("app.api.user.auth_otp.get_user_email_by_id", return_value="user@example.com"), \
         patch("app.api.user.auth_otp.fetch_public_user", return_value=user_row), \
         patch("app.api.user.auth_otp.verify_login_email_otp") as mock_verify_otp:
        with pytest.raises(HTTPException) as exc_info:
            await verify_login_by_phone(req, payload, _device=None)
        assert exc_info.value.status_code == 403
        assert "Account is inactive" in exc_info.value.detail
        mock_verify_otp.assert_not_called()


@pytest.mark.anyio
async def test_verify_login_by_phone_unregistered_raises_400():
    """Unregistered phone number returns 400 Bad Request."""
    req = _build_request("198.51.100.1")
    payload = LoginByPhoneVerifyRequest(phone="+14155552671", code="123456")

    with patch("app.api.user.auth_otp.find_user_id_by_phone", return_value=None):
        with pytest.raises(HTTPException) as exc_info:
            await verify_login_by_phone(req, payload, _device=None)
        assert exc_info.value.status_code == 400
        assert "Invalid or expired code." in exc_info.value.detail


@pytest.mark.anyio
async def test_request_login_by_phone_blocklisted_number_triggers_dummy_delay_without_sending_email():
    """Blocklisted phone numbers trigger dummy delay and return neutral sent=True without email dispatch."""
    from unittest.mock import AsyncMock
    req = _build_request("198.51.100.1")
    payload = LoginByPhoneRequestRequest(phone="+14155552671")

    with patch("app.api.user.auth_otp.redis_client.exists", AsyncMock(return_value=False)), \
         patch("app.api.user.auth_otp.redis_client.get", AsyncMock(return_value=None)), \
         patch("app.api.user.auth_otp.redis_client.set", AsyncMock(return_value=True)), \
         patch("app.api.user.auth_otp.redis_client.incr", AsyncMock(return_value=1)), \
         patch("app.api.user.auth_otp.redis_client.expire", AsyncMock(return_value=True)), \
         patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=True), \
         patch("app.api.user.auth_otp.dummy_email_send_delay", AsyncMock()) as mock_delay, \
         patch("app.api.user.auth_otp.send_login_email_otp") as mock_send_email, \
         patch("app.api.user.auth_otp.find_user_id_by_phone") as mock_find_user:
        resp = await request_login_by_phone(req, payload, _device=None)
        assert resp.sent is True
        mock_delay.assert_called_once()
        mock_send_email.assert_not_called()
        mock_find_user.assert_not_called()


@pytest.mark.anyio
async def test_verify_login_by_phone_blocklisted_number_raises_400():
    """Blocklisted phone numbers are rejected with 400 upon verify attempt."""
    req = _build_request("198.51.100.1")
    payload = LoginByPhoneVerifyRequest(phone="+14155552671", code="123456")

    with patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=True), \
         patch("app.api.user.auth_otp.verify_login_email_otp") as mock_verify_otp, \
         patch("app.api.user.auth_otp.find_user_id_by_phone") as mock_find_user:
        with pytest.raises(HTTPException) as exc_info:
            await verify_login_by_phone(req, payload, _device=None)
        assert exc_info.value.status_code == 400
        assert "Invalid or expired code." in exc_info.value.detail
        mock_verify_otp.assert_not_called()
        mock_find_user.assert_not_called()

