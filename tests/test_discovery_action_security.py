from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request

from app.api.discovery.endpoints import handle_discovery_action
from app.models import DiscoveryActionRequest


@pytest.mark.anyio
@patch("app.db.sessions.is_candidate_in_active_session")
async def test_discovery_action_like_requires_session_failure(
    mock_in_session: MagicMock,
) -> None:
    mock_in_session.return_value = False  # Not in session!

    payload = DiscoveryActionRequest(
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

    with pytest.raises(HTTPException) as exc_info:
        await handle_discovery_action(
            request=request,
            payload=payload,
            user_id="22222222-2222-2222-2222-222222222222",
        )

    assert exc_info.value.status_code == 400
    assert "not in any active discovery session" in exc_info.value.detail
    mock_in_session.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    )


@pytest.mark.anyio
@patch("app.db.sessions.is_candidate_in_active_session")
@patch("app.api.discovery.endpoints.record_discovery_action")
@patch("app.api.discovery.endpoints.invalidate_block_cache")
async def test_discovery_action_block_skips_session_check(
    mock_invalidate: AsyncMock,
    mock_record: MagicMock,
    mock_in_session: MagicMock,
) -> None:
    # 1. Setup mock returning false, which would fail if called
    mock_in_session.return_value = False

    payload = DiscoveryActionRequest(
        target_id="11111111-1111-1111-1111-111111111111",
        action="block",
        tab=None,
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    # 2. Call handler
    res = await handle_discovery_action(
        request=request,
        payload=payload,
        user_id="22222222-2222-2222-2222-222222222222",
    )

    # 3. Assertions
    assert res.success is True
    mock_in_session.assert_not_called()
    mock_record.assert_called_once_with(
        actor_id="22222222-2222-2222-2222-222222222222",
        target_id="11111111-1111-1111-1111-111111111111",
        action="block",
        tab=None,
    )
    mock_invalidate.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    )


@pytest.mark.anyio
@patch("app.db.sessions.is_candidate_in_active_session")
@patch("app.api.discovery.endpoints.record_user_report")
@patch("app.api.discovery.endpoints.invalidate_block_cache")
async def test_discovery_action_report_skips_session_check(
    mock_invalidate: AsyncMock,
    mock_record_report: MagicMock,
    mock_in_session: MagicMock,
) -> None:
    # 1. Setup mock returning false, which would fail if called
    mock_in_session.return_value = False

    payload = DiscoveryActionRequest(
        target_id="11111111-1111-1111-1111-111111111111",
        action="report",
        tab=None,
        reason="other",
        reason_detail="Harassment",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    # 2. Call handler
    res = await handle_discovery_action(
        request=request,
        payload=payload,
        user_id="22222222-2222-2222-2222-222222222222",
    )

    # 3. Assertions
    assert res.success is True
    mock_in_session.assert_not_called()
    mock_record_report.assert_called_once_with(
        reporter_id="22222222-2222-2222-2222-222222222222",
        target_id="11111111-1111-1111-1111-111111111111",
        reason="other",
        reason_detail="Harassment",
        tab=None,
    )
    mock_invalidate.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    )
