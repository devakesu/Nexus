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
    def get_blocks_side_effect(_uid: str) -> set[str]:
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


def test_batch_presence_request_max_ids_validation_error() -> None:
    from pydantic import ValidationError

    # 51 user IDs should fail Pydantic max_length validation
    too_many_ids = [f"user-{i}" for i in range(51)]
    with pytest.raises(ValidationError):
        BatchPresenceRequest(user_ids=too_many_ids)


@pytest.mark.anyio
async def test_batch_presence_endpoint_caps_at_50() -> None:
    from fastapi import HTTPException

    payload = BatchPresenceRequest(user_ids=[f"user-{i}" for i in range(50)])
    # Artificially expand list to simulate raw model bypass
    payload.user_ids.append("user-51")

    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await batch_get_presence(
            request=request,
            payload=payload,
            user_id="viewer-1",
        )

    assert exc_info.value.status_code == 400
    assert "Too many user IDs." in exc_info.value.detail


def test_coarsen_last_active_timestamp() -> None:
    from app.api.chat.presence import _coarsen_last_active_timestamp

    dt = datetime(2026, 8, 24, 14, 43, 27, 856123, tzinfo=timezone.utc)
    coarsened = _coarsen_last_active_timestamp(dt, interval_minutes=30)
    assert coarsened == datetime(2026, 8, 24, 14, 30, 0, 0, tzinfo=timezone.utc)

    dt2 = datetime(2026, 8, 24, 14, 12, 5, 0, tzinfo=timezone.utc)
    coarsened2 = _coarsen_last_active_timestamp(dt2, interval_minutes=30)
    assert coarsened2 == datetime(2026, 8, 24, 14, 0, 0, 0, tzinfo=timezone.utc)


