"""Test Suite for Test Spotify Sync.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
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


async def test_spotify_sync():
    from app.services.spotify_sync import (
        blend_artist_affinity,
        compute_artist_frequency,
        compute_genre_affinity,
        top_display_names,
    )

    # 1. blend and top display names
    native_ranked: dict[str, float] = {"queen": 1.0, "david bowie": 0.8}
    playlist_freq: dict[str, float] = {"Queen": 5.0, "The Beatles": 3.0}
    blended, casing = blend_artist_affinity(native_ranked, playlist_freq)
    assert len(blended) > 0
    assert "queen" in casing

    names = top_display_names(blended, casing, n=2)
    assert len(names) <= 2

    # 2. compute genre affinity
    genre_w = {"rock": 2.0, "pop": 1.0}
    g_aff = compute_genre_affinity(genre_w)
    assert "rock" in g_aff

    # 3. compute artist frequency
    tracks = [
        {"artists": ["Queen"]},
        {"artists": ["Queen", "David Bowie"]},
    ]
    freq = compute_artist_frequency(tracks)
    assert freq["Queen"] == 1.0
    assert freq["David Bowie"] == 0.5


async def test_services_spotify_sync_deep():
    from app.services.spotify_sync import (
        TopArtistsResult,
        _auth_header,
        _get_with_retry,
        _parse_retry_after,
        _post_with_retry,
        blend_artist_affinity,
        compute_artist_frequency,
        compute_genre_affinity,
        compute_playlist_artist_ids_frequency,
        exchange_code,
        fetch_artist_genres_batch,
        fetch_owned_or_collaborative_playlists,
        fetch_playlist_tracks,
        fetch_spotify_user_id,
        refresh_access_token,
        revoke_refresh_token,
        run_full_sync,
        top_display_names,
    )

    # _auth_header & _parse_retry_after
    assert _auth_header("tok-123") == {"Authorization": "Bearer tok-123"}
    resp_hdr = httpx.Response(429, headers={"Retry-After": "5"})
    assert _parse_retry_after(resp_hdr) == 5.0

    resp_no_hdr = httpx.Response(429)
    assert _parse_retry_after(resp_no_hdr) == 1.0

    # _get_with_retry & _post_with_retry: 200 vs 429 retry
    dummy_req = httpx.Request("GET", "https://api.spotify.com/v1/me")
    dummy_post_req = httpx.Request("POST", "https://api.spotify.com/v1/token")

    async with httpx.AsyncClient() as client:
        with (
            patch.object(
                client,
                "get",
                side_effect=[
                    httpx.Response(
                        429, headers={"Retry-After": "0"}, request=dummy_req,
                    ),
                    httpx.Response(200, json={"ok": True}, request=dummy_req),
                ],
            ),
            patch("asyncio.sleep", new_callable=AsyncMock),
        ):
            res = await _get_with_retry(
                client,
                "https://api.spotify.com/v1/me",
                headers={"Authorization": "Bearer tok"},
            )
            assert res.status_code == 200

        with (
            patch.object(
                client,
                "post",
                side_effect=[
                    httpx.Response(
                        429, headers={"Retry-After": "0"}, request=dummy_post_req,
                    ),
                    httpx.Response(200, json={"ok": True}, request=dummy_post_req),
                ],
            ),
            patch("asyncio.sleep", new_callable=AsyncMock),
        ):
            res_post = await _post_with_retry(
                client,
                "https://api.spotify.com/v1/token",
                data={},
                auth=("id", "sec"),
                headers={},
            )
            assert res_post.status_code == 200

    # exchange_code, refresh_access_token, revoke_refresh_token, fetch_spotify_user_id
    with patch(
        "app.services.spotify_sync._post_with_retry",
        return_value=httpx.Response(
            200,
            json={
                "access_token": "new-tok",
                "refresh_token": "new-ref",
                "expires_in": 3600,
            },
            request=dummy_post_req,
        ),
    ):
        bundle = await exchange_code("auth_code", "https://nexus.test/callback")
        assert bundle.access_token == "new-tok"

        bundle_ref = await refresh_access_token("my-refresh-token")
        assert bundle_ref.access_token == "new-tok"

    with patch(
        "httpx.AsyncClient.post",
        return_value=httpx.Response(200, request=dummy_post_req),
    ):
        assert await revoke_refresh_token("my-refresh-token") is True

    with patch(
        "app.services.spotify_sync._get_with_retry",
        return_value=httpx.Response(
            200, json={"id": "spotify-user-999"}, request=dummy_req,
        ),
    ):
        assert await fetch_spotify_user_id("tok") == "spotify-user-999"

    # Math affinity calculation functions
    tracks = [
        {"artists": ["Queen", "Bowie"]},
        {"artists": ["Queen"]},
    ]
    freq = compute_artist_frequency(tracks)
    assert "Queen" in freq
    assert freq["Queen"] > freq["Bowie"]

    genre_map = compute_genre_affinity({"rock": 10.0, "pop": 5.0})
    assert "rock" in genre_map
    assert genre_map["rock"] == 1.0
    assert genre_map["pop"] == 0.5

    blended, casing = blend_artist_affinity(
        native_ranked={"Queen": 1.0, "Bowie": 0.5},
        playlist_freq={"Queen": 0.5, "Beatles": 0.8},
    )
    assert "queen" in blended
    assert casing["queen"] == "Queen"

    top_names = top_display_names(blended, casing, n=2)
    assert len(top_names) == 2

    freq_ids = compute_playlist_artist_ids_frequency(
        [
            {"artists": ["Queen"], "artist_ids": ["art-1"]},
        ],
        limit=50,
    )
    assert len(freq_ids) == 1
    assert freq_ids[0][0] == "art-1"

    # fetch_artist_genres_batch
    async with httpx.AsyncClient() as client:
        with patch(
            "app.services.spotify_sync._get_with_retry",
            return_value=httpx.Response(
                200,
                json={
                    "artists": [{"id": "art-1", "name": "Queen", "genres": ["rock"]}],
                },
                request=dummy_req,
            ),
        ):
            genres_map = await fetch_artist_genres_batch(client, "tok", ["art-1"])
            assert "art-1" in genres_map

    # fetch_owned_or_collaborative_playlists & fetch_playlist_tracks
    async with httpx.AsyncClient() as client:
        with patch(
            "app.services.spotify_sync._get_with_retry",
            return_value=httpx.Response(
                200,
                json={
                    "items": [
                        {
                            "id": "pl-1",
                            "name": "Favorites",
                            "owner": {"id": "spot-1"},
                            "collaborative": False,
                        },
                    ],
                    "next": None,
                },
                request=dummy_req,
            ),
        ):
            pls = await fetch_owned_or_collaborative_playlists(client, "tok", "spot-1")
            assert len(pls) == 1

        with patch(
            "app.services.spotify_sync._get_with_retry",
            return_value=httpx.Response(
                200,
                json={
                    "items": [
                        {
                            "track": {
                                "id": "tr-1",
                                "name": "Bohemian Rhapsody",
                                "artists": [{"id": "a1", "name": "Queen"}],
                            },
                        },
                    ],
                    "next": None,
                },
                request=dummy_req,
            ),
        ):
            pl_tracks = await fetch_playlist_tracks(client, "pl-1", "tok")
            assert len(pl_tracks) == 1

    # Full integration run_full_sync
    with (
        patch(
            "app.services.spotify_sync.fetch_top_artists_ranked",
            return_value=TopArtistsResult(
                ranked={"Queen": 1.0}, genre_weights={"rock": 1.0},
            ),
        ),
        patch("app.services.spotify_sync._sync_playlist_tracks", return_value=([], [])),
        patch("app.services.spotify_sync.persist_artist_signals"),
        patch("app.services.spotify_sync.replace_playlists"),
        patch("app.services.spotify_sync.mark_sync_result"),
    ):
        await run_full_sync(USER_1, "tok-123", "spot-1")
