from typing import Any, cast
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request

from app.api.discovery.endpoints import handle_discovery_action
from app.models import DiscoveryActionRequest


@pytest.mark.anyio
@patch("app.db.sessions.get_candidate_session_details")
async def test_discovery_action_like_requires_session_failure(
    mock_get_details: MagicMock,
) -> None:
    mock_get_details.return_value = None  # Not in session!

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
    mock_get_details.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    )


@pytest.mark.anyio
@patch("app.db.sessions.get_candidate_session_details")
async def test_discovery_action_like_session_expired(
    mock_get_details: MagicMock,
) -> None:
    from datetime import timedelta

    from app.db.client import utcnow

    # Session expired 6 minutes ago (past 5-minute grace window)
    expired_time = utcnow() - timedelta(minutes=6)
    mock_get_details.return_value = {
        "session_id": "session-123",
        "expires_at": expired_time,
    }

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

    assert exc_info.value.status_code == 410
    assert isinstance(exc_info.value.detail, dict)
    detail_dict = cast(dict[str, Any], exc_info.value.detail)
    assert detail_dict["code"] == "SESSION_EXPIRED"
    mock_get_details.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    )


@pytest.mark.anyio
@patch("app.db.profiles.is_active_profile", return_value=True)
@patch("app.db.sessions.is_candidate_in_active_session")
@patch("app.api.discovery.endpoints.record_discovery_action")
@patch("app.api.discovery.endpoints.invalidate_block_cache")
@patch("app.api.discovery.endpoints.set_match_unmatched")
@patch("app.api.discovery.endpoints.close_conversation_for_match_action")
async def test_discovery_action_block_skips_session_check(
    mock_close_convo: MagicMock,
    mock_set_unmatched: MagicMock,
    mock_invalidate: AsyncMock,
    mock_record: MagicMock,
    mock_in_session: MagicMock,
    _mock_is_active: MagicMock,
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
    mock_set_unmatched.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        None,
    )
    mock_close_convo.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        None,
        "block",
    )


@pytest.mark.anyio
@patch("app.db.profiles.is_active_profile", return_value=True)
@patch("app.db.sessions.is_candidate_in_active_session")
@patch("app.api.discovery.endpoints.record_user_report")
@patch("app.api.discovery.endpoints.invalidate_block_cache")
@patch("app.api.discovery.endpoints.set_match_unmatched")
@patch("app.api.discovery.endpoints.close_conversation_for_match_action")
async def test_discovery_action_report_skips_session_check(
    mock_close_convo: MagicMock,
    mock_set_unmatched: MagicMock,
    mock_invalidate: AsyncMock,
    mock_record_report: MagicMock,
    mock_in_session: MagicMock,
    _mock_is_active: MagicMock,
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
    mock_set_unmatched.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        None,
    )
    mock_close_convo.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        None,
        "report",
    )


@pytest.mark.anyio
@patch("app.db.profiles.is_active_profile", return_value=False)
async def test_discovery_action_block_inactive_target_returns_400(
    _mock_is_active: MagicMock,
) -> None:
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

    with pytest.raises(HTTPException) as exc_info:
        await handle_discovery_action(
            request=request,
            payload=payload,
            user_id="22222222-2222-2222-2222-222222222222",
        )

    assert exc_info.value.status_code == 400
    assert "Target user not found or is inactive" in exc_info.value.detail


@pytest.mark.anyio
async def test_discovery_action_self_target_returns_400() -> None:
    payload = DiscoveryActionRequest(
        target_id="22222222-2222-2222-2222-222222222222",
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

    with pytest.raises(HTTPException) as exc_info:
        await handle_discovery_action(
            request=request,
            payload=payload,
            user_id="22222222-2222-2222-2222-222222222222",
        )

    assert exc_info.value.status_code == 400
    assert "Cannot perform discovery actions on yourself" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.db.discovery.has_active_discovery_action")
@patch("app.api.discovery.endpoints.record_discovery_action")
async def test_discovery_action_reversal_unpass_success(
    mock_record: MagicMock,
    mock_has_action: MagicMock,
) -> None:
    mock_has_action.return_value = True

    payload = DiscoveryActionRequest(
        target_id="11111111-1111-1111-1111-111111111111",
        action="unpass",
        tab="Dating",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await handle_discovery_action(
        request=request,
        payload=payload,
        user_id="22222222-2222-2222-2222-222222222222",
    )

    assert res.success is True
    mock_has_action.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        "pass",
        "Dating",
    )
    mock_record.assert_called_once_with(
        actor_id="22222222-2222-2222-2222-222222222222",
        target_id="11111111-1111-1111-1111-111111111111",
        action="unpass",
        tab="Dating",
    )


@pytest.mark.anyio
@patch("app.db.discovery.has_active_discovery_action")
async def test_discovery_action_reversal_unpass_no_active_action_fails(
    mock_has_action: MagicMock,
) -> None:
    mock_has_action.return_value = False

    payload = DiscoveryActionRequest(
        target_id="11111111-1111-1111-1111-111111111111",
        action="unpass",
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
    assert "No active 'pass' action found" in exc_info.value.detail


def test_discovery_action_request_rejects_unlike_and_unsuperlike() -> None:
    from pydantic import ValidationError

    with pytest.raises(ValidationError):
        DiscoveryActionRequest(
            target_id="11111111-1111-1111-1111-111111111111",
            action="unlike",  # type: ignore[arg-type]
            tab="Dating",
        )

    with pytest.raises(ValidationError):
        DiscoveryActionRequest(
            target_id="11111111-1111-1111-1111-111111111111",
            action="unsuperlike",  # type: ignore[arg-type]
            tab="Dating",
        )


def test_prune_excess_viewer_discovery_sessions() -> None:
    from app.db.sessions.auth_sessions import prune_excess_viewer_discovery_sessions

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.gt.return_value = mock_builder
    mock_builder.order.return_value = mock_builder
    mock_builder.delete.return_value = mock_builder
    mock_builder.in_.return_value = mock_builder

    # 6 active sessions returned, max_active=5 -> should delete oldest 2 sessions
    mock_builder.execute.side_effect = [
        MagicMock(
            data=[
                {"id": f"s-{i}", "created_at": f"2026-08-15T0{i}:00:00Z"}
                for i in range(6, 0, -1)
            ],
        ),
        MagicMock(data=[]),
    ]

    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_builder):
        prune_excess_viewer_discovery_sessions("viewer-1", max_active=5)

    mock_builder.delete.assert_called_once()
    mock_builder.in_.assert_called_once_with("id", ["s-2", "s-1"])


@pytest.mark.anyio
@patch("app.db.chat.fetch_conversation_participants")
@patch("app.api.discovery.endpoints.record_discovery_action")
async def test_discovery_action_valid_conversation_id_succeeds(
    mock_record: MagicMock,
    mock_fetch_conv: MagicMock,
) -> None:
    conv_id = "33333333-3333-3333-3333-333333333333"
    actor_id = "11111111-1111-1111-1111-111111111111"
    target_id = "22222222-2222-2222-2222-222222222222"

    mock_fetch_conv.return_value = {
        "user_a_id": actor_id,
        "user_b_id": target_id,
        "tab": "Dating",
    }

    payload = DiscoveryActionRequest(
        target_id=target_id,
        action="block",
        conversation_id=conv_id,
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    with patch("app.api.discovery.endpoints.invalidate_block_cache"), \
         patch("app.api.discovery.endpoints.set_match_unmatched"), \
         patch("app.api.discovery.endpoints.close_conversation_for_match_action"):
        res = await handle_discovery_action(request=request, payload=payload, user_id=actor_id)
        assert res.success is True
        mock_record.assert_called_once()


@pytest.mark.anyio
@patch("app.db.chat.fetch_conversation_participants")
async def test_discovery_action_nonexistent_conversation_id_returns_404(
    mock_fetch_conv: MagicMock,
) -> None:
    mock_fetch_conv.return_value = None

    payload = DiscoveryActionRequest(
        target_id="22222222-2222-2222-2222-222222222222",
        action="block",
        conversation_id="33333333-3333-3333-3333-333333333333",
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
            user_id="11111111-1111-1111-1111-111111111111",
        )

    assert exc_info.value.status_code == 404
    assert "Referenced conversation not found" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.db.chat.fetch_conversation_participants")
async def test_discovery_action_unauthorized_conversation_actor_returns_403(
    mock_fetch_conv: MagicMock,
) -> None:
    # Conversation between strangers X and Y
    mock_fetch_conv.return_value = {
        "user_a_id": "88888888-8888-8888-8888-888888888888",
        "user_b_id": "99999999-9999-9999-9999-999999999999",
    }

    payload = DiscoveryActionRequest(
        target_id="22222222-2222-2222-2222-222222222222",
        action="block",
        conversation_id="33333333-3333-3333-3333-333333333333",
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
            user_id="11111111-1111-1111-1111-111111111111",
        )

    assert exc_info.value.status_code == 403
    assert "Actor is not a participant" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.db.chat.fetch_conversation_participants")
async def test_discovery_action_mismatched_conversation_target_returns_400(
    mock_fetch_conv: MagicMock,
) -> None:
    actor_id = "11111111-1111-1111-1111-111111111111"
    # Conversation between actor and other_user
    mock_fetch_conv.return_value = {
        "user_a_id": actor_id,
        "user_b_id": "88888888-8888-8888-8888-888888888888",
    }

    # Action targeting victim who is NOT in this conversation
    payload = DiscoveryActionRequest(
        target_id="22222222-2222-2222-2222-222222222222",
        action="block",
        conversation_id="33333333-3333-3333-3333-333333333333",
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
            user_id=actor_id,
        )

    assert exc_info.value.status_code == 400
    assert "Target user is not a participant" in exc_info.value.detail

