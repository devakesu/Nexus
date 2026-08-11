from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.api.dependencies import _update_presence_if_needed


@pytest.mark.anyio
@patch("app.api.dependencies.redis_client")
@patch("app.api.dependencies.get_cached_public_user")
@patch("app.db.chat.upsert_presence_heartbeat")
async def test_update_presence_active_user(
    mock_upsert: MagicMock,
    mock_get_cached: AsyncMock,
    mock_redis: AsyncMock,
) -> None:
    mock_redis.set.return_value = True
    mock_get_cached.return_value = {
        "is_active": True,
        "deletion_requested_at": None,
        "is_suspended": False,
    }

    await _update_presence_if_needed("user-123")

    mock_upsert.assert_called_once_with("user-123", True)


@pytest.mark.anyio
@patch("app.api.dependencies.redis_client")
@patch("app.api.dependencies.get_cached_public_user")
@patch("app.db.chat.upsert_presence_heartbeat")
async def test_update_presence_inactive_user(
    mock_upsert: MagicMock,
    mock_get_cached: AsyncMock,
    mock_redis: AsyncMock,
) -> None:
    mock_redis.set.return_value = True
    mock_get_cached.return_value = {
        "is_active": False,
        "deletion_requested_at": None,
        "is_suspended": False,
    }

    await _update_presence_if_needed("user-123")

    mock_upsert.assert_not_called()


@pytest.mark.anyio
@patch("app.api.dependencies.redis_client")
@patch("app.api.dependencies.get_cached_public_user")
@patch("app.db.chat.upsert_presence_heartbeat")
async def test_update_presence_deletion_pending_user(
    mock_upsert: MagicMock,
    mock_get_cached: AsyncMock,
    mock_redis: AsyncMock,
) -> None:
    mock_redis.set.return_value = True
    mock_get_cached.return_value = {
        "is_active": True,
        "deletion_requested_at": "2026-08-11T20:00:00",
        "is_suspended": False,
    }

    await _update_presence_if_needed("user-123")

    mock_upsert.assert_not_called()


@pytest.mark.anyio
@patch("app.api.dependencies.redis_client")
@patch("app.api.dependencies.get_cached_public_user")
@patch("app.db.chat.upsert_presence_heartbeat")
async def test_update_presence_suspended_user(
    mock_upsert: MagicMock,
    mock_get_cached: AsyncMock,
    mock_redis: AsyncMock,
) -> None:
    mock_redis.set.return_value = True
    mock_get_cached.return_value = {
        "is_active": True,
        "deletion_requested_at": None,
        "is_suspended": True,
    }

    await _update_presence_if_needed("user-123")

    mock_upsert.assert_not_called()
