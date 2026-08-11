from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException

from app.api.discovery.likes import _verify_peer_access_and_infer_tab


@pytest.mark.anyio
@patch("app.api.discovery.likes.get_cached_active_block_ids")
async def test_verify_peer_access_blocked(mock_get_blocks: AsyncMock) -> None:
    mock_get_blocks.return_value = {"target-id"}  # Blocked!

    with pytest.raises(HTTPException) as exc_info:
        await _verify_peer_access_and_infer_tab(
            "target-id", "viewer-id", "Dating"
        )

    assert exc_info.value.status_code == 403
    assert exc_info.value.detail == "Access denied. Viewer not permitted."
    mock_get_blocks.assert_called_once_with("viewer-id")


@pytest.mark.anyio
@patch("app.api.discovery.likes.get_cached_active_block_ids")
@patch("app.api.discovery.likes.supabase_client")
async def test_verify_peer_access_not_blocked_with_like(
    mock_supabase: MagicMock,
    mock_get_blocks: AsyncMock,
) -> None:
    mock_get_blocks.return_value = set()  # No blocks

    # Mock like query to return a like row
    mock_exec = MagicMock()
    mock_exec.execute.return_value.data = [{"id": "like-123", "tab": "Dating"}]
    # Chain matching target table/select query builders
    (
        mock_supabase.table.return_value
        .select.return_value
        .eq.return_value
        .eq.return_value
        .in_.return_value
        .is_.return_value
    ) = mock_exec

    tab = await _verify_peer_access_and_infer_tab(
        "target-id", "viewer-id", "Dating"
    )

    assert tab == "Dating"
    mock_get_blocks.assert_called_once_with("viewer-id")
