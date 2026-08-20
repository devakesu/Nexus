import time
from unittest.mock import AsyncMock, patch

import pytest
from fastapi import HTTPException

from app.api.dependencies import verify_app_check_with_replay_protection


@pytest.mark.anyio
async def test_app_check_fails_open_on_redis_error():
    future_exp = int(time.time()) + 3600
    with (
        patch("app.api.dependencies.settings.enforce_app_check", True),
        patch("app.api.dependencies.settings.enable_replay_protection", True),
        patch("app.api.dependencies.app_check.verify_token", return_value={"exp": future_exp}),
        patch("app.api.dependencies.redis_client.set", new_callable=AsyncMock) as mock_redis_set,
    ):
        mock_redis_set.side_effect = ConnectionError("Redis connection lost")

        # Must not raise HTTPException(503); should fail open
        await verify_app_check_with_replay_protection("valid-app-check-token")


@pytest.mark.anyio
async def test_app_check_blocks_replay_when_redis_returns_false():
    future_exp = int(time.time()) + 3600
    with (
        patch("app.api.dependencies.settings.enforce_app_check", True),
        patch("app.api.dependencies.settings.enable_replay_protection", True),
        patch("app.api.dependencies.app_check.verify_token", return_value={"exp": future_exp}),
        patch("app.api.dependencies.redis_client.set", new_callable=AsyncMock) as mock_redis_set,
    ):
        mock_redis_set.return_value = False

        with pytest.raises(HTTPException) as exc_info:
            await verify_app_check_with_replay_protection("replayed-token")
        assert exc_info.value.status_code == 403
        assert "already consumed" in exc_info.value.detail


@pytest.mark.anyio
async def test_app_check_allows_fresh_token_when_redis_returns_true():
    future_exp = int(time.time()) + 3600
    with (
        patch("app.api.dependencies.settings.enforce_app_check", True),
        patch("app.api.dependencies.settings.enable_replay_protection", True),
        patch("app.api.dependencies.app_check.verify_token", return_value={"exp": future_exp}),
        patch("app.api.dependencies.redis_client.set", new_callable=AsyncMock) as mock_redis_set,
    ):
        mock_redis_set.return_value = True

        await verify_app_check_with_replay_protection("fresh-token")
        mock_redis_set.assert_called_once()


@pytest.mark.anyio
async def test_strict_app_check_fails_closed_on_redis_error():
    from app.api.dependencies import verify_app_check_with_strict_replay_protection

    future_exp = int(time.time()) + 3600
    with (
        patch("app.api.dependencies.settings.enforce_app_check", True),
        patch("app.api.dependencies.settings.enable_replay_protection", True),
        patch("app.api.dependencies.app_check.verify_token", return_value={"exp": future_exp}),
        patch("app.api.dependencies.redis_client.set", new_callable=AsyncMock) as mock_redis_set,
    ):
        mock_redis_set.side_effect = ConnectionError("Redis connection lost")

        # Must raise HTTPException(503) because critical endpoints fail closed
        with pytest.raises(HTTPException) as exc_info:
            await verify_app_check_with_strict_replay_protection("valid-app-check-token")
        assert exc_info.value.status_code == 503
        assert "Service temporarily unavailable" in exc_info.value.detail


@pytest.mark.anyio
async def test_strict_app_check_allows_fresh_token_when_redis_returns_true():
    from app.api.dependencies import verify_app_check_with_strict_replay_protection

    future_exp = int(time.time()) + 3600
    with (
        patch("app.api.dependencies.settings.enforce_app_check", True),
        patch("app.api.dependencies.settings.enable_replay_protection", True),
        patch("app.api.dependencies.app_check.verify_token", return_value={"exp": future_exp}),
        patch("app.api.dependencies.redis_client.set", new_callable=AsyncMock) as mock_redis_set,
    ):
        mock_redis_set.return_value = True

        await verify_app_check_with_strict_replay_protection("fresh-token")
        mock_redis_set.assert_called_once()

