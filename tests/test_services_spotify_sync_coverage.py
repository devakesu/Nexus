"""Test coverage suite for Spotify Sync service.

Covers:
- app/services/spotify_sync.py
"""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from app.services.spotify_sync import (
    TopArtistsResult,
    _auth_header,
    _blend_playlist_genres_affinity,
    _get_with_retry,
    _parse_retry_after,
    _persist_native_fallback_signals,
    _post_with_retry,
    _sync_playlist_tracks,
    blend_artist_affinity,
    compute_artist_frequency,
    compute_genre_affinity,
    compute_playlist_artist_ids_frequency,
    exchange_code,
    fetch_artist_genres_batch,
    fetch_owned_or_collaborative_playlists,
    fetch_playlist_tracks,
    fetch_spotify_user_id,
    fetch_top_artists_ranked,
    refresh_access_token,
    revoke_refresh_token,
    run_full_sync,
    top_display_names,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
SPOTIFY_USER = "spotify_user_123"


# ==============================================================================
# 1. HTTP HELPERS & TOKEN FLOWS
# ==============================================================================

async def test_spotify_http_helpers_and_token_exchange():
    assert _auth_header("token123") == {"Authorization": "Bearer token123"}

    # _parse_retry_after
    resp_hdr = httpx.Response(429, headers={"Retry-After": "3.5"})
    assert _parse_retry_after(resp_hdr) == 3.5

    resp_hdr_invalid = httpx.Response(429, headers={"Retry-After": "abc"})
    assert _parse_retry_after(resp_hdr_invalid) == 1.0

    # _get_with_retry
    client = AsyncMock()
    mock_ok_resp = MagicMock(status_code=200)
    mock_ok_resp.raise_for_status.return_value = None
    client.get.return_value = mock_ok_resp

    res = await _get_with_retry(client, "https://api.spotify.com/v1/me")
    assert res.status_code == 200

    # _post_with_retry
    client.post.return_value = mock_ok_resp
    post_res = await _post_with_retry(
        client,
        "https://accounts.spotify.com/api/token",
        data={"grant_type": "code"},
        auth=("id", "secret"),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    assert post_res.status_code == 200

    # exchange_code
    token_json = {
        "access_token": "acc_123",
        "refresh_token": "ref_456",
        "scope": "user-read-email",
        "expires_in": 3600,
    }
    with patch("app.services.spotify_sync._post_with_retry", return_value=MagicMock(json=lambda: token_json)):
        bundle = await exchange_code("auth_code_xyz", "https://nexus.app/callback")
        assert bundle.access_token == "acc_123"
        assert bundle.refresh_token == "ref_456"

    # refresh_access_token
    with patch("app.services.spotify_sync._post_with_retry", return_value=MagicMock(json=lambda: token_json)):
        refreshed = await refresh_access_token("ref_456")
        assert refreshed.access_token == "acc_123"

    # revoke_refresh_token
    assert await revoke_refresh_token("") is False
    with patch("httpx.AsyncClient.post", return_value=MagicMock(is_success=True)):
        assert await revoke_refresh_token("ref_456") is True

    with patch("httpx.AsyncClient.post", side_effect=Exception("Revoke failed")):
        assert await revoke_refresh_token("ref_456") is False

    # fetch_spotify_user_id
    with patch("app.services.spotify_sync._get_with_retry", return_value=MagicMock(json=lambda: {"id": SPOTIFY_USER})):
        sp_id = await fetch_spotify_user_id("acc_123")
        assert sp_id == SPOTIFY_USER


# ==============================================================================
# 2. TOP ARTISTS & PLAYLISTS FETCHING
# ==============================================================================

async def test_fetch_top_artists_and_playlists():
    # fetch_top_artists_ranked with empty items
    mock_resp_empty = MagicMock()
    mock_resp_empty.json.return_value = {"items": []}
    with patch("app.services.spotify_sync._get_with_retry", return_value=mock_resp_empty):
        res_empty = await fetch_top_artists_ranked("acc_123")
        assert res_empty.ranked == {}
        assert res_empty.genre_weights == {}

    # fetch_top_artists_ranked with valid artists
    artists_payload = {
        "items": [
            {"name": "Radiohead", "genres": ["art rock", "alternative rock"]},
            {"name": "Daft Punk", "genres": ["electronic", "synthpop"]},
            None,
            {"name": ""},
        ],
    }
    mock_resp_artists = MagicMock()
    mock_resp_artists.json.return_value = artists_payload
    with patch("app.services.spotify_sync._get_with_retry", return_value=mock_resp_artists):
        res = await fetch_top_artists_ranked("acc_123")
        assert "Radiohead" in res.ranked
        assert "Daft Punk" in res.ranked
        assert res.ranked["Radiohead"] == 1.0
        assert res.ranked["Daft Punk"] == 0.5
        assert "art rock" in res.genre_weights

    # fetch_owned_or_collaborative_playlists
    playlists_payload = {
        "items": [
            {
                "id": "pl1",
                "name": "My Favs",
                "owner": {"id": SPOTIFY_USER},
                "collaborative": False,
                "tracks": {"total": 25},
            },
            {
                "id": "pl2",
                "name": "Collab Mix",
                "owner": {"id": "other_user"},
                "collaborative": True,
                "items": {"total": 10},
            },
            {
                "id": "pl3",
                "name": "Followed Playlist",
                "owner": {"id": "other_user"},
                "collaborative": False,
            },
        ],
        "next": None,
    }
    mock_client = AsyncMock()
    with patch("app.services.spotify_sync._get_with_retry", return_value=MagicMock(json=lambda: playlists_payload)):
        pls = await fetch_owned_or_collaborative_playlists(mock_client, "acc_123", SPOTIFY_USER)
        assert len(pls) == 2
        assert pls[0]["spotify_playlist_id"] == "pl1"
        assert pls[1]["spotify_playlist_id"] == "pl2"

    # fetch_playlist_tracks
    tracks_payload = {
        "items": [
            {
                "track": {
                    "id": "tr1",
                    "name": "Karma Police",
                    "artists": [{"id": "art1", "name": "Radiohead"}],
                },
            },
            {
                "item": {
                    "id": "tr2",
                    "name": "One More Time",
                    "artists": [{"id": "art2", "name": "Daft Punk"}],
                },
            },
            None,
            {"track": None},
        ],
        "next": None,
    }
    with patch("app.services.spotify_sync._get_with_retry", return_value=MagicMock(json=lambda: tracks_payload)):
        tracks = await fetch_playlist_tracks(mock_client, "acc_123", "pl1")
        assert len(tracks) == 2
        assert tracks[0]["name"] == "Karma Police"
        assert tracks[0]["artists"] == ["Radiohead"]

    # 403 on playlist tracks -> returns empty list gracefully
    err_resp = httpx.Response(403)
    with patch("app.services.spotify_sync._get_with_retry", side_effect=httpx.HTTPStatusError("Forbidden", request=MagicMock(), response=err_resp)):
        tracks_403 = await fetch_playlist_tracks(mock_client, "acc_123", "pl1")
        assert tracks_403 == []


# ==============================================================================
# 3. FREQUENCY, AFFINITY BLENDING & DISPLAY NAMES
# ==============================================================================

async def test_affinity_math_and_genres_batch():
    mock_tracks = [
        {"spotify_track_id": "t1", "artists": ["Radiohead", "Thom Yorke"], "artist_ids": ["a1", "a2"]},
        {"spotify_track_id": "t2", "artists": ["Radiohead"], "artist_ids": ["a1"]},
        {"spotify_track_id": "t3", "artists": ["Daft Punk"], "artist_ids": ["a3"]},
    ]

    # compute_playlist_artist_ids_frequency
    freq_ids = compute_playlist_artist_ids_frequency(mock_tracks, limit=10)
    assert len(freq_ids) == 3
    assert freq_ids[0][0] == "a1"  # Radiohead has 2 occurrences -> 1.0 weight
    assert freq_ids[0][2] == 1.0

    assert compute_playlist_artist_ids_frequency([]) == []

    # fetch_artist_genres_batch
    mock_client = AsyncMock()
    artists_batch_res = {
        "artists": [
            {"id": "a1", "genres": ["art rock", "post-rock"]},
            {"id": "a3", "genres": ["electronic"]},
        ],
    }
    with patch("app.services.spotify_sync._get_with_retry", return_value=MagicMock(json=lambda: artists_batch_res)):
        genres_map = await fetch_artist_genres_batch(mock_client, "acc_123", ["a1", "a3"])
        assert "a1" in genres_map
        assert genres_map["a1"] == ["art rock", "post-rock"]

    assert await fetch_artist_genres_batch(mock_client, "acc_123", []) == {}

    # compute_artist_frequency
    freq_names = compute_artist_frequency(mock_tracks)
    assert freq_names["Radiohead"] == 1.0
    assert freq_names["Daft Punk"] == 0.5
    assert compute_artist_frequency([]) == {}

    # compute_genre_affinity
    genre_weights = {"art rock": 2.0, "electronic": 1.0, "obscure": 0.01}
    gen_aff = compute_genre_affinity(genre_weights)
    assert gen_aff["art rock"] == 1.0
    assert gen_aff["electronic"] == 0.5
    assert "obscure" not in gen_aff  # below _GENRE_AFFINITY_MIN_WEIGHT
    assert compute_genre_affinity({}) == {}
    assert compute_genre_affinity({"none": 0.0}) == {}

    # blend_artist_affinity
    native_ranked = {"Radiohead": 1.0, "The Beatles": 0.8}
    playlist_freq = {"Radiohead": 1.0, "Daft Punk": 0.9}
    blended, casing_map = blend_artist_affinity(native_ranked, playlist_freq)
    assert "radiohead" in blended
    assert casing_map["radiohead"] == "Radiohead"
    assert casing_map["the beatles"] == "The Beatles"

    assert blend_artist_affinity({}, {}) == ({}, {})

    # top_display_names
    display_list = top_display_names(blended, casing_map, n=2)
    assert len(display_list) == 2
    assert "Radiohead" in display_list


# ==============================================================================
# 4. FULL SYNC ORCHESTRATION
# ==============================================================================

async def test_full_sync_pipeline():
    mock_client = AsyncMock()

    # _blend_playlist_genres_affinity
    genre_acc: dict[str, float] = {}
    mock_tracks = [{"artists": ["Radiohead"], "artist_ids": ["a1"]}]
    with patch("app.services.spotify_sync.fetch_artist_genres_batch", return_value={"a1": ["rock"]}):
        await _blend_playlist_genres_affinity(mock_client, "acc_123", mock_tracks, genre_acc)
        assert "rock" in genre_acc

    # _sync_playlist_tracks
    import time
    with patch("app.services.spotify_sync.fetch_owned_or_collaborative_playlists", return_value=[{"spotify_playlist_id": "p1"}]), \
         patch("app.services.spotify_sync.fetch_playlist_tracks", return_value=[{"name": "Song 1", "artists": ["Artist A"]}]):
        pls, all_tr = await _sync_playlist_tracks(mock_client, "acc_123", SPOTIFY_USER, USER_1, start=time.monotonic())
        assert len(pls) == 1
        assert len(all_tr) == 1

    # _persist_native_fallback_signals
    with patch("app.services.spotify_sync.persist_artist_signals") as mock_persist:
        await _persist_native_fallback_signals(USER_1, {"Radiohead": 1.0}, {"rock": 1.0})
        mock_persist.assert_called_once()

    # run_full_sync success path
    top_res = TopArtistsResult(
        ranked={"Radiohead": 1.0},
        genre_weights={"art rock": 1.0},
    )
    with patch("app.services.spotify_sync.fetch_top_artists_ranked", return_value=top_res), \
         patch("app.services.spotify_sync._sync_playlist_tracks", return_value=([{"spotify_playlist_id": "p1", "tracks": []}], [])), \
         patch("app.services.spotify_sync._blend_playlist_genres_affinity"), \
         patch("app.services.spotify_sync.persist_artist_signals") as mock_persist, \
         patch("app.services.spotify_sync.replace_playlists") as mock_replace, \
         patch("app.services.spotify_sync.mark_sync_result") as mock_mark:
        await run_full_sync(USER_1, "acc_123", SPOTIFY_USER)
        mock_persist.assert_called_once()
        mock_replace.assert_called_once()
        mock_mark.assert_called_once_with(USER_1, "ok")

    # run_full_sync playlist failure path -> fallback to native signals
    with patch("app.services.spotify_sync.fetch_top_artists_ranked", return_value=top_res), \
         patch("app.services.spotify_sync._sync_playlist_tracks", side_effect=Exception("Spotify connection lost")), \
         patch("app.services.spotify_sync._persist_native_fallback_signals") as mock_fallback, \
         patch("app.services.spotify_sync.mark_sync_result") as mock_mark:
        await run_full_sync(USER_1, "acc_123", SPOTIFY_USER)
        mock_fallback.assert_called_once()
        mock_mark.assert_called_once_with(USER_1, "error", "Spotify connection lost")
