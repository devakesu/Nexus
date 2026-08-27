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


def test_fetch_peer_profile_by_id_sanitizes_sentinels() -> None:
    """Verify that fetch_peer_profile_by_id sanitizes any __DECRYPTION_FAILED__ sentinels."""
    from unittest.mock import MagicMock

    from app.db.profiles.crud import fetch_peer_profile_by_id

    mock_row = {
        "id": "target-123",
        "name": "\\xdeadbeef",  # Corrupted ciphertext
        "bio": "\\xdeadbeef",
        "normal_pics": "\\xdeadbeef",
        "interests": "\\xdeadbeef",
        "is_deactivated": False,
        "users": {"is_active": True, "is_suspended": False, "moderation_status": "clean"},
    }

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.neq.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[mock_row])

    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_builder):
        res = fetch_peer_profile_by_id("target-123")

    assert res is not None
    # Sentinels must be stripped to safe empty values, NOT "__DECRYPTION_FAILED__"
    assert res["name"] == ""
    assert res["bio"] == ""
    assert res["normal_pics"] == []
    assert res["interests"] == {}
    assert "__DECRYPTION_FAILED__" not in str(res)


def test_fetch_peer_profile_by_id_filters_inactive_suspended_banned() -> None:
    """Verify fetch_peer_profile_by_id queries users!inner with is_active, is_suspended, and moderation_status."""
    from unittest.mock import MagicMock

    from app.db.profiles.crud import fetch_peer_profile_by_id

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.neq.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])

    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_builder) as mock_table:
        res = fetch_peer_profile_by_id("banned-user-123")

    assert res is None
    mock_table.assert_called_once_with("profiles")
    mock_builder.select.assert_called_once()
    select_arg = mock_builder.select.call_args[0][0]
    assert "users!inner(is_active, is_suspended, moderation_status)" in select_arg

    mock_builder.eq.assert_any_call("id", "banned-user-123")
    mock_builder.eq.assert_any_call("is_deactivated", False)
    mock_builder.eq.assert_any_call("users.is_active", True)
    mock_builder.eq.assert_any_call("users.is_suspended", False)
    mock_builder.neq.assert_any_call("users.moderation_status", "banned")


