from unittest.mock import AsyncMock, patch

import pytest
from fastapi import HTTPException

from app.api.discovery.likes import _verify_peer_access_and_infer_tab


@pytest.mark.anyio
async def test_verify_peer_access_self_access_denied() -> None:
    """Verify that attempting to access one's own profile via peer endpoint raises 403."""
    with pytest.raises(HTTPException) as exc_info:
        await _verify_peer_access_and_infer_tab(
            "user-123", "user-123", "Dating",
        )

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "Access denied. Viewer not permitted."


@pytest.mark.anyio
@patch("app.api.discovery.likes.get_cached_active_block_ids")
async def test_verify_peer_access_blocked_by_viewer(mock_get_blocks: AsyncMock) -> None:
    def _mock_blocks(uid: str) -> set[str]:
        return {"target-id"} if uid == "viewer-id" else set()

    mock_get_blocks.side_effect = _mock_blocks

    with pytest.raises(HTTPException) as exc_info:
        await _verify_peer_access_and_infer_tab(
            "target-id", "viewer-id", "Dating",
        )

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "Access denied. Viewer not permitted."


@pytest.mark.anyio
@patch("app.api.discovery.likes.get_cached_active_block_ids")
async def test_verify_peer_access_blocked_by_target(mock_get_blocks: AsyncMock) -> None:
    def _mock_blocks(uid: str) -> set[str]:
        return {"viewer-id"} if uid == "target-id" else set()

    mock_get_blocks.side_effect = _mock_blocks

    with pytest.raises(HTTPException) as exc_info:
        await _verify_peer_access_and_infer_tab(
            "target-id", "viewer-id", "Dating",
        )

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "Access denied. Viewer not permitted."


@pytest.mark.anyio
@patch("app.api.discovery.likes.get_cached_active_block_ids")
@patch("app.api.discovery.likes._find_peer_like")
async def test_verify_peer_access_not_blocked_with_like(
    mock_find_like: AsyncMock,
    mock_get_blocks: AsyncMock,
) -> None:
    mock_get_blocks.return_value = set()  # No blocks in either direction
    mock_find_like.return_value = {"id": "like-123", "tab": "Dating"}

    tab = await _verify_peer_access_and_infer_tab(
        "target-id", "viewer-id", "Dating",
    )

    assert tab == "Dating"
    assert mock_get_blocks.call_count == 2
    mock_find_like.assert_called_once_with("target-id", "viewer-id")


@pytest.mark.anyio
@patch("app.api.discovery.likes.get_cached_active_block_ids")
@patch("app.api.discovery.likes._find_peer_like")
@patch("app.api.discovery.likes._find_peer_match")
async def test_verify_peer_access_with_match(
    mock_find_match: AsyncMock,
    mock_find_like: AsyncMock,
    mock_get_blocks: AsyncMock,
) -> None:
    mock_get_blocks.return_value = set()
    mock_find_like.return_value = None
    mock_find_match.return_value = {"id": "match-123", "tab": "Friends"}

    target_uuid = "00000000-0000-0000-0000-000000000001"
    viewer_uuid = "00000000-0000-0000-0000-000000000002"
    tab = await _verify_peer_access_and_infer_tab(
        target_uuid, viewer_uuid, "Dating",
    )

    assert tab == "Friends"
    assert mock_get_blocks.call_count == 2
    mock_find_like.assert_called_once_with(target_uuid, viewer_uuid)
    mock_find_match.assert_called_once_with(target_uuid, viewer_uuid)

