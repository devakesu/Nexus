"""Unit tests for optional JWT authentication error handling and background presence queue throttling."""

import asyncio
from unittest.mock import AsyncMock, patch

import jwt
import pytest
from fastapi import HTTPException, status

from app.api.dependencies import (
    _MAX_BACKGROUND_TASKS,
    _background_tasks,
    get_authenticated_user_id,
    get_optional_authenticated_user_id,
)
from app.core.config import settings


@pytest.mark.anyio
async def test_get_optional_authenticated_user_id_none_returns_none() -> None:
    """When no Bearer token is provided, returns None."""
    result = await get_optional_authenticated_user_id(None)
    assert result is None


@pytest.mark.anyio
async def test_get_optional_authenticated_user_id_valid_token() -> None:
    """When valid Bearer token is provided, returns user_id."""
    secret = str(settings.supabase_jwt_secret)
    token = jwt.encode(
        {"sub": "user-123", "aud": "authenticated"},
        secret,
        algorithm="HS256",
    )
    with patch("app.core.config.Settings.is_jwks", new_callable=lambda: property(lambda _self: False)):
        result = await get_optional_authenticated_user_id(token)
        assert result == "user-123"


@pytest.mark.anyio
async def test_get_optional_authenticated_user_id_malformed_token_raises_401() -> None:
    """When tampered or malformed token is provided, raises 401 Unauthorized."""
    with pytest.raises(HTTPException) as exc_info:
        await get_optional_authenticated_user_id("tampered.token.here")

    assert exc_info.value.status_code == status.HTTP_401_UNAUTHORIZED
    assert exc_info.value.detail == "Cryptographic signature verification failed."


@pytest.mark.anyio
async def test_get_optional_authenticated_user_id_expired_token_raises_401() -> None:
    """When expired token is provided, raises 401 Unauthorized."""
    secret = str(settings.supabase_jwt_secret)
    token = jwt.encode(
        {"sub": "user-123", "aud": "authenticated", "exp": 1000000000},
        secret,
        algorithm="HS256",
    )
    with patch("app.core.config.Settings.is_jwks", new_callable=lambda: property(lambda _self: False)):
        with pytest.raises(HTTPException) as exc_info:
            await get_optional_authenticated_user_id(token)

        assert exc_info.value.status_code == status.HTTP_401_UNAUTHORIZED
        assert exc_info.value.detail == "Authentication session expired."


@pytest.mark.anyio
async def test_get_optional_authenticated_user_id_missing_sub_raises_401() -> None:
    """When token missing sub claim is provided, raises 401 Unauthorized."""
    secret = str(settings.supabase_jwt_secret)
    token = jwt.encode(
        {"aud": "authenticated"},
        secret,
        algorithm="HS256",
    )
    with patch("app.core.config.Settings.is_jwks", new_callable=lambda: property(lambda _self: False)):
        with pytest.raises(HTTPException) as exc_info:
            await get_optional_authenticated_user_id(token)

        assert exc_info.value.status_code == status.HTTP_401_UNAUTHORIZED
        assert exc_info.value.detail == "Invalid token: sub claim missing."


@pytest.mark.anyio
async def test_presence_background_task_creation_and_queue_capping() -> None:
    """Verify presence task is queued normally, but skipped when queue reaches _MAX_BACKGROUND_TASKS."""
    payload = {"sub": "user-presence-test"}

    # 1. Normal queue under limit
    _background_tasks.clear()
    with patch("app.api.dependencies._update_presence_if_needed", AsyncMock()) as mock_presence:
        user_id = await get_authenticated_user_id(payload)
        assert user_id == "user-presence-test"
        # Yield to event loop to let task run
        await asyncio.sleep(0.01)
        mock_presence.assert_called_once_with("user-presence-test")

    # 2. Queue at capacity
    _background_tasks.clear()
    dummy_tasks = [asyncio.create_task(asyncio.sleep(10)) for _ in range(_MAX_BACKGROUND_TASKS)]
    for dt in dummy_tasks:
        _background_tasks.add(dt)

    try:
        with patch("app.api.dependencies._update_presence_if_needed", AsyncMock()) as mock_presence:
            user_id = await get_authenticated_user_id(payload)
            assert user_id == "user-presence-test"
            await asyncio.sleep(0.01)
            # Should have skipped creating a new presence task
            mock_presence.assert_not_called()
    finally:
        for dt in dummy_tasks:
            dt.cancel()
        _background_tasks.clear()
