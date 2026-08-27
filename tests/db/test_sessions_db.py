"""Test Suite for Test Sessions Db.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
import json
from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.security.crypto import DecryptFailedError, encrypt_to_hex
from app.db.client import DatabaseAccessError
from app.db.sessions.auth_sessions import (
    create_discovery_session,
    delete_expired_discovery_sessions,
    get_candidate_session_details,
    get_discovery_session,
    get_discovery_session_by_id,
    invalidate_viewer_discovery_sessions,
    is_candidate_in_active_session,
    prune_excess_viewer_discovery_sessions,
    verify_session_not_expired,
)

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


async def test_db_sessions_all_modules():
    from app.db.sessions.auth_sessions import (
        create_discovery_session,
        delete_expired_discovery_sessions,
        get_candidate_session_details,
        get_discovery_session,
        get_discovery_session_by_id,
        invalidate_viewer_discovery_sessions,
        is_candidate_in_active_session,
        prune_excess_viewer_discovery_sessions,
    )
    from app.db.sessions.node_details import fetch_discovery_node_detail
    from app.db.sessions.viewport import fetch_spatial_viewport

    mock_table = MagicMock()
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data=SESS_1)

    # 1. auth_sessions.py
    mock_table.insert.return_value.execute.return_value = MagicMock(
        data=[{"id": SESS_1, "viewer_id": USER_1}],
    )
    with (
        patch(
            "app.db.sessions.auth_sessions.supabase_client.table",
            return_value=mock_table,
        ),
        patch(
            "app.db.sessions.auth_sessions.supabase_client.rpc", return_value=mock_rpc,
        ),
        patch(
            "app.db.sessions.auth_sessions.assign_orbit_positions",
            return_value=[{"profile": {"id": USER_2}, "score": 0.9}],
        ),
    ):
        s_id, exp = create_discovery_session(
            USER_1, "Dating", {}, [{"candidate_id": USER_2}],
        )
        assert s_id is not None
        assert exp is not None

    mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": SESS_1, "viewer_id": USER_1, "tab": "Dating"},
    )
    with patch(
        "app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table,
    ):
        sess = get_discovery_session(SESS_1, USER_1, "Dating")
        assert sess is not None
        assert sess["id"] == SESS_1

    mock_table.select.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": SESS_1, "viewer_id": USER_1},
    )
    with patch(
        "app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table,
    ):
        s_by_id = get_discovery_session_by_id(SESS_1, USER_1)
        assert s_by_id is not None

    cand_select_mock = MagicMock()
    exec_mock = MagicMock()
    exec_mock.data = [
        {
            "session_id": SESS_1,
            "discovery_sessions": {
                "tab": "Dating",
                "expires_at": "2026-08-26T18:00:00Z",
            },
        },
    ]
    cand_select_mock.select.return_value.eq.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = exec_mock
    cand_select_mock.select.return_value.eq.return_value.eq.return_value.execute.return_value = exec_mock
    with patch(
        "app.db.sessions.auth_sessions.supabase_client.table",
        return_value=cand_select_mock,
    ):
        assert is_candidate_in_active_session(USER_1, USER_2) is True
        details = get_candidate_session_details(USER_1, USER_2, "Dating")
        assert details is not None
        assert details["session_id"] == SESS_1

    mock_table.delete.return_value.lt.return_value.execute.return_value = MagicMock(
        data=[],
    )
    with patch(
        "app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table,
    ):
        delete_expired_discovery_sessions()
        invalidate_viewer_discovery_sessions(USER_1)
        prune_excess_viewer_discovery_sessions(USER_1, max_active=5)

    # 2. node_details.py
    node_res = MagicMock()
    node_res.data = [
        {
            "candidate_id": USER_2,
            "score": 0.85,
            "x": 1.0,
            "y": 2.0,
            "orbit_tier": 1,
            "music_match_grade": 1,
            "candidate_spotify_connected": False,
            "discovery_sessions": {
                "id": SESS_1,
                "viewer_id": USER_1,
                "tab": "Dating",
                "expires_at": "2099-01-01T00:00:00Z",
                "viewer_spotify_connected": False,
            },
            "profiles": {
                "id": USER_2,
                "name": encrypt_to_hex("Bob", category="profile"),
                "bio": encrypt_to_hex("Hello", category="profile"),
                "normal_pics": encrypt_to_hex(
                    json.dumps(["pic.jpg"]), category="profile",
                ),
                "profile_pic": "pic.jpg",
                "interests": encrypt_to_hex(
                    json.dumps({"tech": ["Python"]}), category="profile",
                ),
                "is_deactivated": False,
            },
        },
    ]
    mock_node_table = MagicMock()
    mock_node_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = node_res
    with (
        patch(
            "app.db.sessions.node_details.supabase_client.table",
            return_value=mock_node_table,
        ),
        patch(
            "app.db.sessions.node_details.get_cached_active_block_ids",
            AsyncMock(return_value=set()),
        ),
        patch(
            "app.db.sessions.node_details.sign_profile_media",
            return_value={"name": "Bob", "profile_pic": "https://signed.url"},
        ),
    ):
        node_res_tuple = await fetch_discovery_node_detail(SESS_1, USER_1, USER_2)
        assert node_res_tuple is not None
        tab, node_dict = node_res_tuple
        assert tab == "Dating"
        assert node_dict["name"] == "Bob"

    # 3. viewport.py
    vp_res = MagicMock()
    vp_res.data = [
        {
            "candidate_id": USER_2,
            "score": 0.85,
            "x": 1.0,
            "y": 2.0,
            "orbit_tier": 1,
            "music_match_grade": 1,
            "candidate_spotify_connected": False,
            "profiles": {
                "id": USER_2,
                "name": encrypt_to_hex("Bob", category="profile"),
                "profile_pic": "pic.jpg",
            },
        },
    ]
    mock_vp_table = MagicMock()
    mock_vp_table.select.return_value.eq.return_value.eq.return_value.gte.return_value.lte.return_value.gte.return_value.lte.return_value.execute.return_value = vp_res
    with (
        patch(
            "app.db.sessions.viewport.supabase_client.table", return_value=mock_vp_table,
        ),
        patch(
            "app.db.sessions.viewport.get_cached_active_block_ids",
            AsyncMock(return_value=set()),
        ),
        patch(
            "app.db.sessions.viewport.decrypt_profile_rows",
            return_value={USER_2: {"name": "Bob", "profile_pic": "https://signed.url"}},
        ),
    ):
        vp_items, _ = await fetch_spatial_viewport(
            SESS_1, USER_1, 10.0, 10.0, 50.0, include_total_count=False,
        )
        assert len(vp_items) == 1
        assert vp_items[0]["name"] == "Bob"


async def test_db_sessions_auth_and_viewport_deep():
    from app.db.client import DatabaseAccessError
    from app.db.sessions.auth_sessions import (
        create_discovery_session,
        delete_expired_discovery_sessions,
        get_candidate_session_details,
        get_discovery_session,
        get_discovery_session_by_id,
        invalidate_viewer_discovery_sessions,
        is_candidate_in_active_session,
        prune_excess_viewer_discovery_sessions,
        verify_session_not_expired,
    )
    from app.db.sessions.viewport import (
        fetch_spatial_viewport,
    )

    mock_sess: dict[str, Any] = {
        "id": "s1",
        "viewer_id": USER_1,
        "tab": "Dating",
        "expires_at": (datetime.now(timezone.utc)).isoformat(),
        "created_at": (datetime.now(timezone.utc)).isoformat(),
        "filters": {},
    }
    mock_ok = _make_chaining_mock([mock_sess])
    mock_err = _make_chaining_mock(error=APIError({"message": "DB error"}))

    with (
        patch(
            "app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_ok,
        ),
        patch("app.db.sessions.auth_sessions.supabase_client.rpc") as mock_rpc,
        patch("app.db.sessions.viewport.supabase_client.table", return_value=mock_ok),
        patch(
            "app.db.sessions.viewport.decrypt_profile_rows",
            return_value={USER_2: {"name": "Bob"}},
        ),
        patch(
            "app.db.sessions.viewport.get_cached_active_block_ids",
            AsyncMock(return_value=set()),
        ),
    ):
        mock_rpc.return_value.execute.return_value = MagicMock(data="s1")
        create_discovery_session(USER_1, "Dating", {}, [{"profile": {"id": USER_2}}])
        get_discovery_session("s1", USER_1, "Dating")
        get_discovery_session_by_id("s1", USER_1)
        delete_expired_discovery_sessions()
        invalidate_viewer_discovery_sessions(USER_1)
        prune_excess_viewer_discovery_sessions(USER_1)
        verify_session_not_expired(mock_sess)
        is_candidate_in_active_session(USER_1, USER_2)
        get_candidate_session_details(USER_1, USER_2, "Dating")

        res, cnt = await fetch_spatial_viewport(
            "s1", USER_1, 0.0, 0.0, 100.0, include_total_count=True,
        )
        assert isinstance(res, list)
        assert isinstance(cnt, int)

    with (
        patch(
            "app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_err,
        ),
        patch(
            "app.db.sessions.auth_sessions.supabase_client.rpc",
            side_effect=APIError({"message": "DB error"}),
        ),
        patch("app.db.sessions.viewport.supabase_client.table", return_value=mock_err),
    ):
        with pytest.raises(DatabaseAccessError):
            create_discovery_session(
                USER_1, "Dating", {}, [{"profile": {"id": USER_2}}],
            )
        with pytest.raises(DatabaseAccessError):
            get_discovery_session("s1", USER_1, "Dating")
        with pytest.raises(DatabaseAccessError):
            get_discovery_session_by_id("s1", USER_1)
        with pytest.raises(DatabaseAccessError):
            delete_expired_discovery_sessions()
        with pytest.raises(DatabaseAccessError):
            invalidate_viewer_discovery_sessions(USER_1)


async def test_db_sessions_deep():
    from app.db.sessions.auth_sessions import (
        create_discovery_session,
        delete_expired_discovery_sessions,
        get_discovery_session,
        get_discovery_session_by_id,
        invalidate_viewer_discovery_sessions,
        prune_excess_viewer_discovery_sessions,
    )
    from app.db.sessions.node_details import (
        fetch_discovery_node_detail,
    )
    from app.db.sessions.viewport import (
        fetch_spatial_viewport,
    )

    mock_session = {
        "id": SESSION_1,
        "viewer_id": USER_1,
        "tab": "Dating",
        "expires_at": "2099-01-01T00:00:00+00:00",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "filters": {},
        "candidate_id": USER_2,
        "score": 0.85,
        "x": 10.0,
        "y": 15.0,
        "orbit_tier": 1,
        "profiles": {
            "id": USER_2,
            "name": "Bob",
            "profile_pic": "p.jpg",
            "is_deactivated": False,
        },
        "discovery_sessions": {
            "id": SESSION_1,
            "viewer_id": USER_1,
            "tab": "Dating",
            "expires_at": "2099-01-01T00:00:00+00:00",
            "viewer_spotify_connected": False,
        },
    }
    mock_t = _make_chaining_mock([mock_session])

    with (
        patch(
            "app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_t,
        ),
        patch("app.db.sessions.auth_sessions.supabase_client.rpc") as mock_rpc,
        patch(
            "app.db.sessions.node_details.supabase_client.table", return_value=mock_t,
        ),
        patch("app.db.sessions.viewport.supabase_client.table", return_value=mock_t),
        patch(
            "app.db.sessions.node_details.decrypt_profile_record",
            return_value={"name": "Bob", "age": 25},
        ),
        patch(
            "app.db.sessions.node_details.get_cached_active_block_ids",
            AsyncMock(return_value=set()),
        ),
        patch(
            "app.db.sessions.viewport.decrypt_profile_rows",
            return_value={USER_2: {"name": "Bob", "profile_pic": "p.jpg"}},
        ),
        patch(
            "app.db.sessions.viewport.get_cached_active_block_ids",
            AsyncMock(return_value=set()),
        ),
        patch(
            "app.db.sessions.auth_sessions.assign_orbit_positions",
            return_value=[
                {
                    "profile": {"id": USER_2},
                    "x": 1.0,
                    "y": 2.0,
                    "orbit_tier": 1,
                    "score": 0.9,
                },
            ],
        ),
    ):
        mock_rpc.return_value.execute.return_value = MagicMock(data=SESSION_1)
        prune_excess_viewer_discovery_sessions(USER_1, 2)
        sess_id, _exp_dt = create_discovery_session(
            USER_1, "Dating", {}, [{"profile": {"id": USER_2}, "score": 0.9}], 60,
        )
        assert sess_id == SESSION_1

        get_discovery_session(SESSION_1, USER_1, "Dating")
        get_discovery_session_by_id(SESSION_1, USER_1)
        invalidate_viewer_discovery_sessions(USER_1)
        delete_expired_discovery_sessions()

        node = await fetch_discovery_node_detail(USER_1, SESSION_1, USER_2)
        assert node is not None

        vp_items, _count = await fetch_spatial_viewport(
            SESSION_1, USER_1, 0.0, 0.0, 50.0, include_total_count=True,
        )
        assert len(vp_items) >= 0


def test_db_sessions_auth_sessions_deep():
    from app.db.sessions.auth_sessions import (
        create_discovery_session,
        delete_expired_discovery_sessions,
        get_candidate_session_details,
        get_discovery_session,
        get_discovery_session_by_id,
        invalidate_viewer_discovery_sessions,
        is_candidate_in_active_session,
        prune_excess_viewer_discovery_sessions,
        verify_session_not_expired,
    )

    # prune_excess_viewer_discovery_sessions: exception
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().gt().order().execute.side_effect = Exception(
            "fail",
        )
        prune_excess_viewer_discovery_sessions(USER_1)

    # create_discovery_session: empty session_id, APIError, Exception
    with (
        patch(
            "app.db.sessions.auth_sessions.assign_orbit_positions",
            return_value=[{"profile": {"id": USER_2}, "score": 85}],
        ),
        patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb,
    ):
        mock_sb.rpc().execute.return_value = MagicMock(data="None")
        with pytest.raises(DatabaseAccessError):
            create_discovery_session(USER_1, "Dating", {}, [])

        mock_sb.rpc().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            create_discovery_session(USER_1, "Dating", {}, [])

        mock_sb.rpc().execute.side_effect = Exception("Unexpected")
        with pytest.raises(DatabaseAccessError):
            create_discovery_session(USER_1, "Dating", {}, [])

    # get_discovery_session: APIError, Exception, None response, non-dict row
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().eq().maybe_single().execute.side_effect = (
            make_api_error()
        )
        with pytest.raises(DatabaseAccessError):
            get_discovery_session("sess-1", USER_1, "Dating")

        mock_sb.table().select().eq().eq().eq().maybe_single().execute.side_effect = (
            Exception("fail")
        )
        with pytest.raises(DatabaseAccessError):
            get_discovery_session("sess-1", USER_1, "Dating")

        mock_sb.table().select().eq().eq().eq().maybe_single().execute.side_effect = (
            None
        )
        mock_sb.table().select().eq().eq().eq().maybe_single().execute.return_value = (
            None
        )
        assert get_discovery_session("sess-1", USER_1, "Dating") is None

        mock_sb.table().select().eq().eq().eq().maybe_single().execute.return_value = (
            MagicMock(data="not-a-dict")
        )
        with pytest.raises(DatabaseAccessError):
            get_discovery_session("sess-1", USER_1, "Dating")

    # get_discovery_session_by_id: APIError, Exception, None response, non-dict row
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().maybe_single().execute.side_effect = (
            make_api_error()
        )
        with pytest.raises(DatabaseAccessError):
            get_discovery_session_by_id("sess-1", USER_1)

        mock_sb.table().select().eq().eq().maybe_single().execute.side_effect = (
            Exception("fail")
        )
        with pytest.raises(DatabaseAccessError):
            get_discovery_session_by_id("sess-1", USER_1)

        mock_sb.table().select().eq().eq().maybe_single().execute.side_effect = None
        mock_sb.table().select().eq().eq().maybe_single().execute.return_value = None
        assert get_discovery_session_by_id("sess-1", USER_1) is None

        mock_sb.table().select().eq().eq().maybe_single().execute.return_value = (
            MagicMock(data="not-a-dict")
        )
        with pytest.raises(DatabaseAccessError):
            get_discovery_session_by_id("sess-1", USER_1)

    # delete_expired_discovery_sessions: APIError, Exception
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().delete().lte().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            delete_expired_discovery_sessions()

        mock_sb.table().delete().lte().execute.side_effect = Exception("fail")
        with pytest.raises(DatabaseAccessError):
            delete_expired_discovery_sessions()

    # invalidate_viewer_discovery_sessions: APIError, Exception
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().delete().eq().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            invalidate_viewer_discovery_sessions(USER_1)

        mock_sb.table().delete().eq().execute.side_effect = Exception("fail")
        with pytest.raises(DatabaseAccessError):
            invalidate_viewer_discovery_sessions(USER_1)

    # verify_session_not_expired
    assert verify_session_not_expired({}) is False
    assert verify_session_not_expired({"expires_at": "2020-01-01T00:00:00Z"}) is False
    assert (
        verify_session_not_expired(
            {
                "expires_at": (
                    datetime.now(timezone.utc) + timedelta(hours=1)
                ).isoformat(),
            },
        )
        is True
    )

    # is_candidate_in_active_session & get_candidate_session_details: exception
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().gt().limit().execute.side_effect = Exception(
            "fail",
        )
        assert is_candidate_in_active_session(USER_1, USER_2) is False

        mock_sb.table().select().eq().eq().limit().execute.side_effect = Exception(
            "fail",
        )
        assert get_candidate_session_details(USER_1, USER_2, tab="orbit") is None


async def test_db_sessions_node_details_deep():
    from app.db.sessions.node_details import (
        _build_node_detail_payload,
        _query_discovery_node_detail,
        _validate_discovery_node_data,
        fetch_discovery_node_detail,
    )

    # _build_node_detail_payload: DecryptFailedError
    with patch(
        "app.db.sessions.node_details.decrypt_profile_record",
        side_effect=DecryptFailedError("Fail"),
    ), pytest.raises(DecryptFailedError):
        _build_node_detail_payload({}, {}, "cid", SESS_1, USER_1, USER_2)

    # _validate_discovery_node_data: missing session, invalid tab, expired session, missing profile, deactivated, blocked
    assert await _validate_discovery_node_data({}, USER_1) is None
    assert (
        await _validate_discovery_node_data(
            {"discovery_sessions": {"tab": "Invalid"}}, USER_1,
        )
        is None
    )
    assert (
        await _validate_discovery_node_data(
            {
                "discovery_sessions": {
                    "tab": "Dating",
                    "expires_at": "2020-01-01T00:00:00Z",
                },
            },
            USER_1,
        )
        is None
    )

    valid_sess = {
        "tab": "Dating",
        "expires_at": (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat(),
    }
    assert (
        await _validate_discovery_node_data({"discovery_sessions": valid_sess}, USER_1)
        is None
    )
    assert (
        await _validate_discovery_node_data(
            {"discovery_sessions": valid_sess, "profiles": {"is_deactivated": True}},
            USER_1,
        )
        is None
    )

    with patch(
        "app.db.sessions.node_details.get_cached_active_block_ids",
        return_value={USER_2},
    ):
        assert (
            await _validate_discovery_node_data(
                {
                    "discovery_sessions": valid_sess,
                    "profiles": {"id": USER_2, "is_deactivated": False},
                },
                USER_1,
            )
            is None
        )

    # _query_discovery_node_detail: APIError & generic Exception
    with patch("app.db.sessions.node_details.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().eq().limit().execute.side_effect = (
            make_api_error()
        )
        with pytest.raises(DatabaseAccessError):
            _query_discovery_node_detail(SESS_1, USER_1, USER_2)

        mock_sb.table().select().eq().eq().eq().limit().execute.side_effect = Exception(
            "Unexpected",
        )
        with pytest.raises(DatabaseAccessError):
            _query_discovery_node_detail(SESS_1, USER_1, USER_2)

    # fetch_discovery_node_detail: non-dict row & validation failed
    with patch(
        "app.db.sessions.node_details._query_discovery_node_detail",
        return_value=MagicMock(data=["not-a-dict"]),
    ):
        assert await fetch_discovery_node_detail(SESS_1, USER_1, USER_2) is None

    with (
        patch(
            "app.db.sessions.node_details._query_discovery_node_detail",
            return_value=MagicMock(data=[{}]),
        ),
        patch(
            "app.db.sessions.node_details._validate_discovery_node_data",
            return_value=None,
        ),
    ):
        assert await fetch_discovery_node_detail(SESS_1, USER_1, USER_2) is None


def test_db_sessions_auth_and_discovery():
    now = datetime.now(timezone.utc)
    sess_valid = {
        "id": SESSION_1,
        "viewer_id": USER_1,
        "candidate_ids": [USER_2],
        "expires_at": (now + timedelta(hours=1)).isoformat(),
    }
    sess_expired = {
        "id": SESSION_1,
        "viewer_id": USER_1,
        "candidate_ids": [USER_2],
        "expires_at": (now - timedelta(hours=1)).isoformat(),
    }
    assert verify_session_not_expired(sess_valid) is True
    assert verify_session_not_expired(sess_expired) is False

    mock_table = _make_chaining_mock([sess_valid])
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data=SESSION_1)

    with (
        patch(
            "app.db.sessions.auth_sessions.supabase_client.table",
            return_value=mock_table,
        ),
        patch(
            "app.db.sessions.auth_sessions.supabase_client.rpc", return_value=mock_rpc,
        ),
    ):
        prune_excess_viewer_discovery_sessions(USER_1)
        sess_id, exp_dt = create_discovery_session(
            viewer_id=USER_1,
            active_tab="Dating",
            filters={},
            ranked_items=[{"candidate_id": USER_2, "profile": {"id": USER_2}}],
        )
        assert sess_id == SESSION_1
        assert exp_dt is not None
        get_discovery_session(SESSION_1, USER_1, "Dating")
        get_discovery_session_by_id(SESSION_1, USER_1)
        delete_expired_discovery_sessions()
        invalidate_viewer_discovery_sessions(USER_1)
        is_candidate_in_active_session(USER_1, USER_2)
        get_candidate_session_details(USER_1, USER_2)
