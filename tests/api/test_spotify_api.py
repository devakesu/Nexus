"""Test Suite for Test Spotify Api.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
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


async def test_api_spotify_auth_deep():
    from app.api.spotify.auth import (
        _consume_state,
        _NativeExchangeRequest,
        _seed_and_queue_sync,
        _store_state,
        spotify_connect,
        spotify_native_exchange,
    )

    mock_req = MagicMock()
    mock_bg = MagicMock()

    with (
        patch("app.api.spotify.auth.redis_client") as mock_r,
        patch("app.api.spotify.auth.settings.spotify_client_id", "client_123"),
        patch(
            "app.api.spotify.auth.settings.spotify_redirect_uri",
            "https://app.nexus.com/callback",
        ),
        patch(
            "app.api.spotify.auth.settings.spotify_allowed_redirect_uris",
            ["https://app.nexus.com/callback"],
        ),
        patch(
            "app.api.spotify.auth.exchange_code",
            AsyncMock(
                return_value=MagicMock(
                    access_token="acc_tok",
                    refresh_token="ref_tok",
                    scope="user-top-read",
                ),
            ),
        ),
        patch(
            "app.api.spotify.auth._seed_and_queue_sync",
            AsyncMock(return_value=["Taylor Swift"]),
        ),
        patch(
            "app.api.spotify.auth.fetch_spotify_user_id",
            AsyncMock(return_value="sp_user_1"),
        ),
        patch("app.api.spotify.auth.upsert_connection"),
        patch("app.api.spotify.auth.invalidate_viewer_discovery_sessions"),
        patch(
            "app.api.spotify.auth.fetch_top_artists_ranked",
            AsyncMock(
                return_value=MagicMock(
                    ranked={"Taylor Swift": 1.0}, genre_weights={"pop": 1.0},
                ),
            ),
        ),
        patch("app.api.spotify.auth.persist_artist_signals"),
    ):
        mock_r.setex = AsyncMock()
        mock_r.getdel = AsyncMock(return_value=USER_1)

        await _store_state("state123", USER_1)
        res_state = await _consume_state("state123")
        assert res_state == USER_1

        req_body = _NativeExchangeRequest(
            code="auth_code_123", redirect_uri="https://app.nexus.com/callback",
        )
        res_exchange = await spotify_native_exchange(
            mock_req, req_body, mock_bg, _device=None, user_id=USER_1,
        )
        assert res_exchange["syncing"] is True

        conn_url = await spotify_connect(mock_req, _device=None, user_id=USER_1)
        assert "auth_url" in conn_url

        seeded = await _seed_and_queue_sync(
            mock_bg, USER_1, "acc_tok", "ref_tok", "user-top-read",
        )
        assert len(seeded) > 0


async def test_api_spotify_auth_deep_p21():
    from app.api.spotify.auth import (
        _fallback_playlist_sync,
        _NativeExchangeRequest,
        _seed_and_queue_sync,
        spotify_callback,
        spotify_native_exchange,
    )

    # _fallback_playlist_sync exception
    with patch("httpx.AsyncClient.get", side_effect=Exception("network fail")):
        blended, display_names = await _fallback_playlist_sync(
            "token",
            "spot_u1",
            {"Artist1": 1.0},
            USER_1,
        )
        assert "artist1" in blended
        assert "Artist1" in display_names

    # _seed_and_queue_sync with discovery session invalidation exception
    bg = MagicMock()
    with (
        patch(
            "app.api.spotify.auth.fetch_spotify_user_id",
            AsyncMock(return_value="spot_u1"),
        ),
        patch("app.api.spotify.auth.upsert_connection"),
        patch(
            "app.api.spotify.auth.invalidate_viewer_discovery_sessions",
            side_effect=Exception("cache error"),
        ),
        patch(
            "app.api.spotify.auth.fetch_top_artists_ranked",
            AsyncMock(
                return_value=MagicMock(ranked={"A1": 1.0}, genre_weights={"pop": 1.0}),
            ),
        ),
        patch("app.api.spotify.auth.persist_artist_signals"),
    ):
        names = await _seed_and_queue_sync(
            bg, USER_1, "acc_token", None, "user-top-read",
        )
        assert len(names) > 0

    # spotify_native_exchange errors
    mock_req = MagicMock()
    with patch(
        "app.api.spotify.auth.settings.spotify_redirect_uri",
        "https://app.nexus.test/spotify/callback",
    ):
        # invalid redirect_uri
        with pytest.raises(HTTPException, match="Invalid redirect_uri"):
            await spotify_native_exchange(
                mock_req,
                _NativeExchangeRequest(
                    code="c", redirect_uri="https://attacker.test/cb",
                ),
                bg,
                _device=None,
                user_id=USER_1,
            )

        # exchange_code Exception -> 502
        with patch(
            "app.api.spotify.auth.exchange_code",
            AsyncMock(side_effect=Exception("bad code")),
        ), pytest.raises(
            HTTPException, match="Failed to exchange Spotify authorization code",
        ):
            await spotify_native_exchange(
                mock_req,
                _NativeExchangeRequest(
                    code="c", redirect_uri="https://app.nexus.test/spotify/callback",
                ),
                bg,
                _device=None,
                user_id=USER_1,
            )

        # empty access_token -> 502
        with patch(
            "app.api.spotify.auth.exchange_code",
            AsyncMock(return_value=MagicMock(access_token="")),
        ), pytest.raises(
            HTTPException, match="Spotify did not return a valid access token",
        ):
            await spotify_native_exchange(
                mock_req,
                _NativeExchangeRequest(
                    code="c", redirect_uri="https://app.nexus.test/spotify/callback",
                ),
                bg,
                _device=None,
                user_id=USER_1,
            )

        # seed_and_queue_sync failure -> 502
        with (
            patch(
                "app.api.spotify.auth.exchange_code",
                AsyncMock(
                    return_value=MagicMock(
                        access_token="tok", refresh_token="ref", scope="s",
                    ),
                ),
            ),
            patch(
                "app.api.spotify.auth._seed_and_queue_sync",
                AsyncMock(side_effect=Exception("sync fail")),
            ),pytest.raises(
            HTTPException, match="Failed to fetch data from Spotify",
        ),
        ):
            await spotify_native_exchange(
                mock_req,
                _NativeExchangeRequest(
                    code="c", redirect_uri="https://app.nexus.test/spotify/callback",
                ),
                bg,
                _device=None,
                user_id=USER_1,
            )

    # spotify_callback HTML responses for token exchange fail, missing access_token, sync setup exception
    with (
        patch(
            "app.api.spotify.auth.settings.spotify_redirect_uri",
            "https://app.nexus.test/spotify/callback",
        ),
        patch(
            "app.api.spotify.auth.redis_client.getdel", AsyncMock(return_value=USER_1),
        ),
        patch("app.api.spotify.auth.redis_client.delete", AsyncMock()),
    ):
        # Token exchange exception
        with patch(
            "app.api.spotify.auth.exchange_code",
            AsyncMock(side_effect=Exception("fail")),
        ):
            resp = await spotify_callback(mock_req, bg, code="c", state="s")
            assert resp.status_code == 500

        # Missing access_token
        with patch(
            "app.api.spotify.auth.exchange_code",
            AsyncMock(return_value=MagicMock(access_token="")),
        ):
            resp = await spotify_callback(mock_req, bg, code="c", state="s")
            assert resp.status_code == 502

        # Sync setup exception
        with (
            patch(
                "app.api.spotify.auth.exchange_code",
                AsyncMock(
                    return_value=MagicMock(
                        access_token="t", refresh_token="r", scope="s",
                    ),
                ),
            ),
            patch(
                "app.api.spotify.auth._seed_and_queue_sync",
                AsyncMock(side_effect=Exception("sync error")),
            ),
        ):
            resp = await spotify_callback(mock_req, bg, code="c", state="s")
            assert resp.status_code == 500
