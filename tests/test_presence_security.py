from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import Request

from app.api.chat.presence import batch_get_presence
from app.models import BatchPresenceRequest


@pytest.mark.anyio
@patch("app.api.chat.presence.has_active_match")
@patch("app.db.discovery.get_cached_active_block_ids")
@patch("app.api.chat.presence.fetch_user_share_flags")
@patch("app.api.chat.presence.fetch_presence")
async def test_presence_not_blocked(
    mock_fetch_presence: MagicMock,
    mock_fetch_flags: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_has_match: MagicMock,
) -> None:
    mock_has_match.return_value = True

    # We mock get_cached_active_block_ids returning empty sets
    def get_blocks_side_effect(uid: str) -> set[str]:
        return set()
    mock_get_blocks.side_effect = get_blocks_side_effect

    mock_fetch_flags.return_value = {"share_active_status": True}
    now_str = datetime.now(timezone.utc).isoformat()
    mock_fetch_presence.return_value = {
        "is_online": True,
        "last_active_at": now_str,
    }

    payload = BatchPresenceRequest(user_ids=["target-1"])
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await batch_get_presence(
        request=request,
        payload=payload,
        user_id="viewer-1",
    )

    assert "target-1" in res
    assert res["target-1"].is_online is True
    assert res["target-1"].last_active_at is not None


@pytest.mark.anyio
@patch("app.api.chat.presence.has_active_match")
@patch("app.db.discovery.get_cached_active_block_ids")
@patch("app.api.chat.presence.fetch_user_share_flags")
@patch("app.api.chat.presence.fetch_presence")
async def test_presence_blocked_by_viewer(
    mock_fetch_presence: MagicMock,
    mock_fetch_flags: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_has_match: MagicMock,
) -> None:
    mock_has_match.return_value = True

    # Viewer blocks target
    def side_effect(uid: str) -> set[str]:
        return {"target-1"} if uid == "viewer-1" else set()
    mock_get_blocks.side_effect = side_effect

    payload = BatchPresenceRequest(user_ids=["target-1"])
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await batch_get_presence(
        request=request,
        payload=payload,
        user_id="viewer-1",
    )

    assert "target-1" in res
    assert res["target-1"].is_online is None
    assert res["target-1"].last_active_at is None
    mock_fetch_presence.assert_not_called()
    mock_fetch_flags.assert_not_called()


@pytest.mark.anyio
@patch("app.api.chat.presence.has_active_match")
@patch("app.db.discovery.get_cached_active_block_ids")
@patch("app.api.chat.presence.fetch_user_share_flags")
@patch("app.api.chat.presence.fetch_presence")
async def test_presence_blocked_by_target(
    mock_fetch_presence: MagicMock,
    mock_fetch_flags: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_has_match: MagicMock,
) -> None:
    mock_has_match.return_value = True

    # Target blocks viewer
    def side_effect(uid: str) -> set[str]:
        return {"viewer-1"} if uid == "target-1" else set()
    mock_get_blocks.side_effect = side_effect

    payload = BatchPresenceRequest(user_ids=["target-1"])
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await batch_get_presence(
        request=request,
        payload=payload,
        user_id="viewer-1",
    )

    assert "target-1" in res
    assert res["target-1"].is_online is None
    assert res["target-1"].last_active_at is None
    mock_fetch_presence.assert_not_called()
    mock_fetch_flags.assert_not_called()
