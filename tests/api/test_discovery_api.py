"""Test Suite for Test Discovery Api.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from postgrest.exceptions import APIError
from starlette.requests import Request

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
SESS_1 = "00000000-0000-0000-0000-000000000040"
SESSION_1 = "00000000-0000-0000-0000-000000000020"
ALERT_1 = "00000000-0000-0000-0000-000000000010"
CONV_1 = "00000000-0000-0000-0000-000000000020"
CONVO_1 = "00000000-0000-0000-0000-000000000020"
MATCH_1 = "00000000-0000-0000-0000-000000000010"
MSG_1 = "00000000-0000-0000-0000-000000000020"
PHONE_VALID = "+14155552671"
REPORT_1 = "00000000-0000-0000-0000-000000000050"
EVENT_1 = "00000000-0000-0000-0000-000000000033"
CONTACT_1 = "00000000-0000-0000-0000-000000000030"


def _make_chaining_mock(
    data: Any = None, error: Exception | None = None,
) -> MagicMock:
    mock: MagicMock = MagicMock()
    mock.select.return_value = mock
    mock.insert.return_value = mock
    mock.update.return_value = mock
    mock.delete.return_value = mock
    mock.upsert.return_value = mock
    mock.eq.return_value = mock
    mock.neq.return_value = mock
    mock.gt.return_value = mock
    mock.gte.return_value = mock
    mock.lt.return_value = mock
    mock.lte.return_value = mock
    mock.is_.return_value = mock
    mock.in_.return_value = mock
    mock.or_.return_value = mock
    mock.not_.is_.return_value = mock
    mock.order.return_value = mock
    mock.limit.return_value = mock
    mock.range.return_value = mock
    mock.contains.return_value = mock
    mock.contained_by.return_value = mock
    mock.overlaps.return_value = mock

    def _exec() -> MagicMock:
        if error:
            raise error
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    def _single() -> MagicMock:
        if error:
            raise error
        if isinstance(data, list) and data:
            return MagicMock(data=copy.deepcopy(data[0]))
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    mock.single.return_value = single_mock
    return mock


def make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/test",
        "headers": [],
        "client": ("127.0.0.1", 12345),
        "app": MagicMock(),
    }
    return Request(scope)


def _make_mock_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/test",
        "headers": [(b"host", b"localhost"), (b"user-agent", b"pytest")],
        "client": ("127.0.0.1", 12345),
        "app": {},
    }
    return Request(scope)


def make_api_error(code: str = "P0001", message: str = "DB error") -> APIError:
    return APIError(
        {"code": code, "message": message, "details": "details", "hint": "hint"},
    )


pytestmark = pytest.mark.anyio


async def test_api_discovery_likes_matched_branches():
    from app.api.discovery.likes import (
        get_matches,
        record_like_back_action,
    )
    from app.models import LikeActionRequest

    mock_req = MagicMock()
    mock_match_row = {
        "match_id": "m1",
        "matched_user_id": USER_2,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    mock_prof_row = {
        "id": USER_2,
        "name": "Bob",
        "age": 24,
        "profile_pic": "p.jpg",
    }
    mock_t = _make_chaining_mock([mock_prof_row])

    with (
        patch("app.api.discovery.likes.supabase_client.table", return_value=mock_t),
        patch("app.api.discovery.likes.fetch_likes_for_user", return_value=[]),
        patch(
            "app.api.discovery.likes.fetch_matches_for_user",
            return_value=[mock_match_row],
        ),
        patch(
            "app.api.discovery.likes.get_cached_active_block_ids",
            AsyncMock(return_value=set()),
        ),
        patch(
            "app.api.discovery.likes._decrypt_profiles",
            return_value={USER_2: {"name": "Bob", "age": 24, "profile_pic": "p.jpg"}},
        ),
        patch("app.api.discovery.likes.revoke_incoming_like", return_value=True),
        patch("app.api.discovery.likes.record_match", return_value="m1"),
        patch("app.api.discovery.likes.send_match_notification", AsyncMock()),
    ):
        matches_res = await get_matches(
            mock_req, tab="Dating", _device=None, user_id=USER_1,
        )
        assert len(matches_res.matches) > 0

        req_payload = LikeActionRequest(
            action="like",
            target_id=USER_2,
            tab="Dating",
        )
        res_like = await record_like_back_action(
            mock_req, req_payload, _device=None, user_id=USER_1,
        )
        assert res_like.matched is True
        assert res_like.match_id == "m1"
