from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import Request

from app.api.discovery.likes import record_like_back_action
from app.models import LikeActionRequest


@pytest.mark.anyio
@patch("app.api.discovery.likes.record_user_report")
@patch("app.api.discovery.likes.invalidate_block_cache")
@patch("app.api.discovery.likes.close_conversation_for_match_action")
async def test_record_like_back_action_report_closes_convo(
    mock_close_convo: MagicMock,
    mock_invalidate_cache: AsyncMock,
    mock_record_report: MagicMock,
) -> None:
    # 1. Mock parameters
    payload = LikeActionRequest(
        target_id="11111111-1111-1111-1111-111111111111",
        action="report",
        tab="Dating",
        reason="other",
        reason_detail="Inappropriate behavior",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    # 2. Call endpoint
    res = await record_like_back_action(
        request=request,
        payload=payload,
        user_id="22222222-2222-2222-2222-222222222222",
    )

    # 3. Assertions
    assert res.matched is False
    mock_record_report.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        "other",
        "Inappropriate behavior",
        "Dating",
    )
    mock_invalidate_cache.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    )
    mock_close_convo.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        "Dating",
        "report",
    )


@pytest.mark.anyio
@patch("app.api.discovery.likes.record_discovery_action")
@patch("app.api.discovery.likes.invalidate_block_cache")
@patch("app.api.discovery.likes.revoke_incoming_like")
@patch("app.api.discovery.likes.close_conversation_for_match_action")
async def test_record_like_back_action_block_closes_convo(
    mock_close_convo: MagicMock,
    mock_revoke: MagicMock,
    mock_invalidate_cache: AsyncMock,
    mock_record_action: MagicMock,
) -> None:
    # 1. Mock parameters
    payload = LikeActionRequest(
        target_id="11111111-1111-1111-1111-111111111111",
        action="block",
        tab="Dating",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    mock_revoke.return_value = True
    # 2. Call endpoint
    res = await record_like_back_action(
        request=request,
        payload=payload,
        user_id="22222222-2222-2222-2222-222222222222",
    )

    # 3. Assertions
    assert res.matched is False
    mock_record_action.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        "block",
        None,
        None,
    )
    mock_invalidate_cache.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    )
    mock_revoke.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    )
    mock_close_convo.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        "Dating",
        "block",
    )


@pytest.mark.anyio
@patch("app.api.discovery.likes.supabase_client")
@patch("app.api.discovery.likes.record_discovery_action")
@patch("app.api.discovery.likes.record_match")
@patch("app.api.discovery.likes.revoke_incoming_like")
@patch("app.api.discovery.likes.send_match_notification")
async def test_record_like_back_action_concurrent_revocation_cleans_up_and_fails(
    mock_send_notif: MagicMock,
    mock_revoke: MagicMock,
    mock_record_match: MagicMock,
    mock_record_discovery: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    from fastapi import HTTPException

    # 1. Setup mock
    mock_record_match.return_value = "match-123"
    mock_revoke.return_value = False  # Like is concurrently revoked!

    # Mock supabase client table matches delete
    mock_delete = MagicMock()
    mock_supabase.table.return_value.delete.return_value.eq.return_value = mock_delete

    payload = LikeActionRequest(
        target_id="11111111-1111-1111-1111-111111111111",
        action="like",
        tab="Dating",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    # 2. Call handler and assert HTTPException
    with pytest.raises(HTTPException) as exc_info:
        await record_like_back_action(
            request=request,
            payload=payload,
            user_id="22222222-2222-2222-2222-222222222222",
        )

    # 3. Assertions
    assert exc_info.value.status_code == 400
    assert "No active incoming like found" in exc_info.value.detail
    mock_record_match.assert_called_once()
    mock_supabase.table.assert_called_with("matches")
    mock_supabase.table.return_value.delete.assert_called_once()
    mock_delete.execute.assert_called_once()

