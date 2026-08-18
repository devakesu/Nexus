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
)
from app.models import LoginByPhoneRequestRequest


def _build_request(client_ip: str) -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/auth/login-by-phone/request",
        "headers": [],
        "client": (client_ip, 12345),
    }
    return Request(scope)


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
        assert resp.sent is False

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
            assert resp.sent is False

    # 4th request from a brand new IP is blocked by Tier 2 phone cap
    req_4 = _build_request("198.51.100.99")
    with patch("app.api.user.auth_otp.redis_client.exists", side_effect=mock_exists), \
         patch("app.api.user.auth_otp.redis_client.get", side_effect=mock_get), \
         pytest.raises(HTTPException) as exc_info:
        await request_login_by_phone(req_4, payload, _device=None)

    assert exc_info.value.status_code == 429
    assert "Too many login attempts for this phone number" in exc_info.value.detail
