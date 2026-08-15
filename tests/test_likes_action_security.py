from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request

from app.api.discovery.likes import record_like_back_action
from app.models import LikeActionRequest


@pytest.mark.anyio
@patch("app.api.discovery.likes.record_user_report")
@patch("app.api.discovery.likes.invalidate_block_cache")
@patch("app.api.discovery.likes.set_match_unmatched")
@patch("app.api.discovery.likes.close_conversation_for_match_action")
async def test_record_like_back_action_report_closes_convo(
    mock_close_convo: MagicMock,
    mock_set_unmatched: MagicMock,
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
    mock_set_unmatched.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        "Dating",
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
@patch("app.api.discovery.likes.set_match_unmatched")
@patch("app.api.discovery.likes.close_conversation_for_match_action")
async def test_record_like_back_action_block_closes_convo(
    mock_close_convo: MagicMock,
    mock_set_unmatched: MagicMock,
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
    mock_set_unmatched.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        "Dating",
    )
    mock_close_convo.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        "Dating",
        "block",
    )


@pytest.mark.anyio
@patch("app.api.discovery.likes.record_discovery_action")
@patch("app.api.discovery.likes.record_match")
@patch("app.api.discovery.likes.revoke_incoming_like")
@patch("app.api.discovery.likes.send_match_notification")
async def test_record_like_back_action_concurrent_revocation_fails_fast(
    mock_send_notif: MagicMock,
    mock_revoke: MagicMock,
    mock_record_match: MagicMock,
    _mock_record_discovery: MagicMock,
) -> None:
    from fastapi import HTTPException

    # 1. Setup mock: like is concurrently revoked / missing
    mock_revoke.return_value = False

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

    # 3. Assertions: Fails fast before creating match or sending notification
    assert exc_info.value.status_code == 400
    assert "No active incoming like found" in exc_info.value.detail
    mock_record_match.assert_not_called()
    mock_send_notif.assert_not_called()


@pytest.mark.anyio
@patch("app.api.discovery.likes.unrevoke_incoming_like")
@patch("app.api.discovery.likes.record_discovery_action")
@patch("app.api.discovery.likes.record_match")
@patch("app.api.discovery.likes.revoke_incoming_like")
@patch("app.api.discovery.likes.send_match_notification")
async def test_record_like_back_action_match_failure_rollbacks_revocation(
    _mock_send_notif: MagicMock,
    mock_revoke: MagicMock,
    mock_record_match: MagicMock,
    _mock_record_discovery: MagicMock,
    mock_unrevoke: MagicMock,
) -> None:
    from app.db.client import DatabaseAccessError

    mock_revoke.return_value = True
    mock_record_match.side_effect = DatabaseAccessError("DB connection error")

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

    with pytest.raises(HTTPException) as exc_info:
        await record_like_back_action(
            request=request,
            payload=payload,
            user_id="22222222-2222-2222-2222-222222222222",
        )

    assert exc_info.value.status_code == 503
    mock_unrevoke.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    )


def test_record_match_returns_existing_when_present() -> None:
    from app.db.discovery.matches import record_match

    user_a = "11111111-1111-1111-1111-111111111111"
    user_b = "22222222-2222-2222-2222-222222222222"

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.or_.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.is_.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[{"id": "existing-match-xyz"}])

    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_builder):
        res = record_match(user_a, user_b, "Dating")

    assert res == "existing-match-xyz"
    mock_builder.upsert.assert_not_called()


def test_record_match_handles_23505_conflict() -> None:
    from postgrest.exceptions import APIError

    from app.db.discovery.matches import record_match

    user_a = "11111111-1111-1111-1111-111111111111"
    user_b = "22222222-2222-2222-2222-222222222222"

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.or_.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.is_.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder
    mock_builder.upsert.return_value = mock_builder

    # First select returns empty, upsert raises 23505 (concurrent insert won), second select returns winning row
    mock_builder.execute.side_effect = [
        MagicMock(data=[]),
        APIError({"message": "duplicate key value violates unique constraint", "code": "23505"}),
        MagicMock(data=[{"id": "winning-match-123"}]),
    ]

    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_builder):
        res = record_match(user_a, user_b, "Dating")

    assert res == "winning-match-123"


def test_fetch_matches_for_user_pagination_and_warning() -> None:
    from app.db.discovery.matches import fetch_matches_for_user

    user_id = "11111111-1111-1111-1111-111111111111"
    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.or_.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.is_.return_value = mock_builder
    mock_builder.order.return_value = mock_builder
    mock_builder.lt.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder

    # Return exactly limit rows to verify warning logging
    mock_builder.execute.return_value = MagicMock(data=[
        {
            "id": f"match-{i}",
            "liker_id": user_id,
            "liked_back_id": f"peer-{i}",
            "created_at": "2026-08-11T20:00:00Z",
        }
        for i in range(5)
    ])

    with (
        patch("app.db.discovery.matches.supabase_client.table", return_value=mock_builder),
        patch("app.db.discovery.matches.logger.warning") as mock_warn,
    ):
        matches = fetch_matches_for_user(
            user_id=user_id,
            tab="Dating",
            limit=5,
            before_created_at="2026-08-12T00:00:00Z",
        )

    assert len(matches) == 5
    mock_builder.lt.assert_called_once_with("created_at", "2026-08-12T00:00:00Z")
    mock_builder.limit.assert_called_once_with(5)
    mock_warn.assert_called_once()


def test_match_action_request_validates_target_id_uuid() -> None:
    from pydantic import ValidationError

    from app.models import MatchActionRequest

    with pytest.raises(ValidationError) as exc_info:
        MatchActionRequest(
            target_id="invalid-uuid-string",
            action="unmatch",
            tab="Dating",
        )
    assert "target_id must be a valid UUID" in str(exc_info.value)


def test_set_match_unmatched_validates_uuid() -> None:
    from app.db.discovery.matches import set_match_unmatched

    with pytest.raises(ValueError):
        set_match_unmatched("invalid-user-uuid", "11111111-1111-1111-1111-111111111111")

    with pytest.raises(ValueError):
        set_match_unmatched("11111111-1111-1111-1111-111111111111", "invalid-target-uuid")


@pytest.mark.anyio
@patch("app.api.discovery.likes.record_user_report")
@patch("app.api.discovery.likes.invalidate_block_cache")
@patch("app.api.discovery.likes.set_match_unmatched")
@patch("app.api.discovery.likes.close_conversation_for_match_action")
async def test_record_like_back_action_report_dissolves_match_and_closes_conversation(
    mock_close_convo: MagicMock,
    mock_set_unmatched: MagicMock,
    mock_invalidate: AsyncMock,
    mock_record_report: MagicMock,
) -> None:
    payload = LikeActionRequest(
        target_id="11111111-1111-1111-1111-111111111111",
        action="report",
        tab="Dating",
        reason="harassment",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await record_like_back_action(
        request=request,
        payload=payload,
        user_id="22222222-2222-2222-2222-222222222222",
    )

    assert res.matched is False
    mock_record_report.assert_called_once()
    mock_invalidate.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
    )
    mock_set_unmatched.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        "Dating",
    )
    mock_close_convo.assert_called_once_with(
        "22222222-2222-2222-2222-222222222222",
        "11111111-1111-1111-1111-111111111111",
        "Dating",
        "report",
    )




