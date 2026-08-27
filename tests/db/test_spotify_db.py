"""Test Suite for Test Spotify Db.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.security.crypto import DecryptFailedError
from app.db.client import DatabaseAccessError

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


def test_db_spotify_deep():
    from app.db.spotify import (
        _sanitize_sync_error,
        disconnect,
        fetch_playlists_for_owner,
        get_connection,
        get_decrypted_refresh_token,
        mark_sync_result,
        persist_artist_signals,
        replace_playlists,
        upsert_connection,
    )

    # get_connection: APIError & empty rows
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            get_connection(USER_1)

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        assert get_connection(USER_1) is None

    # get_decrypted_refresh_token: None connection, no token, DecryptFailedError
    with patch("app.db.spotify.get_connection", return_value=None):
        assert get_decrypted_refresh_token(USER_1) is None

    with patch("app.db.spotify.get_connection", return_value={"refresh_token": None}):
        assert get_decrypted_refresh_token(USER_1) is None

    with (
        patch(
            "app.db.spotify.get_connection", return_value={"refresh_token": "enc_token"},
        ),
        patch("app.db.spotify.decrypt_pii", side_effect=DecryptFailedError("fail")),
    ):
        assert get_decrypted_refresh_token(USER_1) is None

    # upsert_connection APIError
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().upsert().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            upsert_connection(USER_1, "spot_u1", "token", "scope")

    # _sanitize_sync_error
    assert _sanitize_sync_error(None) is None
    err = "Bearer 12345 secret and test@example.com for spotify:user:alice123"
    san = _sanitize_sync_error(err)
    assert san is not None
    assert "Bearer [REDACTED]" in san
    assert "[EMAIL_REDACTED]" in san
    assert "spotify:user:[REDACTED]" in san

    # mark_sync_result APIError catch
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().update().eq().execute.side_effect = APIError(
            {"message": "fail"},
        )
        # Should not raise
        mark_sync_result(USER_1, "error", "some error")

    # disconnect APIError
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().delete().eq().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            disconnect(USER_1)

    # replace_playlists APIError
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().upsert().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            replace_playlists(
                USER_1,
                [
                    {
                        "spotify_playlist_id": "p1",
                        "name": "P1",
                        "tracks": [{"artists": ["A1"], "name": "T1"}],
                    },
                ],
            )

    # fetch_playlists_for_owner: APIError, non-dict rows, DecryptFailedError, JSONDecodeError
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().select().eq().order().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_playlists_for_owner(USER_1)

        mock_sb.table().select().eq().order().execute.side_effect = None
        mock_sb.table().select().eq().order().execute.return_value = MagicMock(
            data=[
                "not-a-dict",
                {
                    "spotify_playlist_id": "p1",
                    "name": "bad_enc_name",
                    "tracks": "bad_enc_tracks",
                },
                {"spotify_playlist_id": "p2", "name": None, "tracks": None},
            ],
        )
        with patch(
            "app.db.spotify.decrypt_pii", side_effect=DecryptFailedError("fail"),
        ):
            res = fetch_playlists_for_owner(USER_1)
            assert len(res) == 2
            assert res[0]["name"] == ""
            assert res[0]["tracks"] == []

    # persist_artist_signals APIError
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().update().eq().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            persist_artist_signals(USER_1, {"A1": 1.0}, ["A1"], {"pop": 0.5})
