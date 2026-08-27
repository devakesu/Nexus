from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import BackgroundTasks, Request

from app.api.spotify.auth import _seed_and_queue_sync
from app.api.spotify.sync import spotify_disconnect
from app.db.sessions.auth_sessions import invalidate_viewer_discovery_sessions


def _make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/spotify/connection",
    }
    return Request(scope)


@patch("app.db.sessions.auth_sessions.supabase_client.table")
def test_invalidate_viewer_discovery_sessions(mock_table: MagicMock) -> None:
    mock_builder = MagicMock()
    mock_builder.delete.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])
    mock_table.return_value = mock_builder

    invalidate_viewer_discovery_sessions("user-456")

    mock_table.assert_called_once_with("discovery_sessions")
    mock_builder.delete.assert_called_once()
    mock_builder.eq.assert_called_once_with("viewer_id", "user-456")
    mock_builder.execute.assert_called_once()


@pytest.mark.anyio
@patch("app.api.spotify.sync.get_decrypted_refresh_token")
@patch("app.api.spotify.sync.revoke_refresh_token")
@patch("app.api.spotify.sync.invalidate_viewer_discovery_sessions")
@patch("app.api.spotify.sync.disconnect_connection")
async def test_spotify_disconnect_invalidates_discovery_sessions(
    mock_disconnect: MagicMock,
    mock_invalidate: MagicMock,
    mock_revoke: MagicMock,
    mock_get_refresh_token: MagicMock,
) -> None:
    mock_get_refresh_token.return_value = "refresh_token_to_revoke"
    bg_tasks = MagicMock()

    res = await spotify_disconnect(
        request=_make_dummy_request(),
        background_tasks=bg_tasks,
        _device=None,
        user_id="user-123",
    )

    assert res == {"disconnected": True}
    mock_disconnect.assert_called_once_with("user-123")
    mock_invalidate.assert_called_once_with("user-123")
    bg_tasks.add_task.assert_called_once_with(mock_revoke, "refresh_token_to_revoke")


@pytest.mark.anyio
@patch("app.api.spotify.auth.run_full_sync")
@patch("app.api.spotify.auth.persist_artist_signals")
@patch("app.api.spotify.auth.fetch_top_artists_ranked")
@patch("app.api.spotify.auth.invalidate_viewer_discovery_sessions")
@patch("app.api.spotify.auth.upsert_connection")
@patch("app.api.spotify.auth.fetch_spotify_user_id")
async def test_seed_and_queue_sync_invalidates_discovery_sessions(
    mock_fetch_spotify_user_id: AsyncMock,
    mock_upsert_connection: MagicMock,
    mock_invalidate: MagicMock,
    mock_fetch_top_artists: AsyncMock,
    _mock_persist_signals: MagicMock,
    _mock_run_full_sync: MagicMock,
) -> None:
    mock_fetch_spotify_user_id.return_value = "spotify-user-123"
    mock_ranked_result = MagicMock()
    mock_ranked_result.ranked = {"Artist 1": 1.0}
    mock_ranked_result.genre_weights = {}
    mock_fetch_top_artists.return_value = mock_ranked_result

    bg_tasks = BackgroundTasks()
    display_names = await _seed_and_queue_sync(
        background_tasks=bg_tasks,
        user_id="user-123",
        access_token="token-abc",
        refresh_token="refresh-xyz",
        scope="user-top-read",
    )

    assert isinstance(display_names, list)
    mock_upsert_connection.assert_called_once_with(
        "user-123", "spotify-user-123", "refresh-xyz", "user-top-read",
    )
    mock_invalidate.assert_called_once_with("user-123")


@pytest.mark.anyio
@patch("app.api.spotify.auth.run_full_sync")
@patch("app.api.spotify.auth.persist_artist_signals")
@patch("app.api.spotify.auth.fetch_top_artists_ranked")
@patch("app.api.spotify.auth.invalidate_viewer_discovery_sessions")
@patch("app.api.spotify.auth.upsert_connection")
@patch("app.api.spotify.auth.fetch_spotify_user_id")
async def test_seed_and_queue_sync_upserts_connection_without_refresh_token(
    mock_fetch_spotify_user_id: AsyncMock,
    mock_upsert_connection: MagicMock,
    _mock_invalidate: MagicMock,
    mock_fetch_top_artists: AsyncMock,
    _mock_persist_signals: MagicMock,
    _mock_run_full_sync: MagicMock,
) -> None:
    mock_fetch_spotify_user_id.return_value = "spotify-user-456"
    mock_ranked_result = MagicMock()
    mock_ranked_result.ranked = {"Artist 2": 1.0}
    mock_ranked_result.genre_weights = {}
    mock_fetch_top_artists.return_value = mock_ranked_result

    bg_tasks = BackgroundTasks()
    display_names = await _seed_and_queue_sync(
        background_tasks=bg_tasks,
        user_id="user-456",
        access_token="token-def",
        refresh_token=None,
        scope="user-top-read",
    )

    assert isinstance(display_names, list)
    mock_upsert_connection.assert_called_once_with(
        "user-456", "spotify-user-456", None, "user-top-read",
    )


@pytest.mark.anyio
@patch("app.api.spotify.auth._consume_state")
async def test_spotify_callback_returns_correct_http_status_codes(
    mock_consume_state: AsyncMock,
) -> None:
    from app.api.spotify.auth import spotify_callback

    mock_request = _make_dummy_request()
    bg_tasks = BackgroundTasks()

    # 1. Error / missing code & state -> 400
    res_err = await spotify_callback(
        request=mock_request,
        background_tasks=bg_tasks,
        error="access_denied",
    )
    assert res_err.status_code == 400

    # 2. Expired / missing state -> 400
    mock_consume_state.return_value = None
    res_expired = await spotify_callback(
        request=mock_request,
        background_tasks=bg_tasks,
        code="auth-code",
        state="invalid-state",
    )
    assert res_expired.status_code == 400


@pytest.mark.anyio
@patch("app.api.spotify.auth.exchange_code")
@patch("app.api.spotify.auth._seed_and_queue_sync")
async def test_spotify_native_exchange_redirect_uri_validation(
    mock_seed: AsyncMock,
    mock_exchange: AsyncMock,
) -> None:
    from fastapi import HTTPException

    from app.api.spotify.auth import _NativeExchangeRequest, spotify_native_exchange
    from app.core.config import settings

    mock_request = _make_dummy_request()
    bg_tasks = BackgroundTasks()

    # Disallowed redirect URI
    bad_payload = _NativeExchangeRequest(
        code="auth_code_123",
        redirect_uri="https://malicious.com/callback",
    )
    with pytest.raises(HTTPException) as exc_info:
        await spotify_native_exchange(
            request=mock_request,
            body=bad_payload,
            background_tasks=bg_tasks,
            _device=None,
            user_id="user-123",
        )
    assert exc_info.value.status_code == 400
    assert "Invalid redirect_uri" in exc_info.value.detail

    # Allowed configured redirect URI
    allowed_uri = settings.spotify_allowed_redirect_uris[0]
    good_payload = _NativeExchangeRequest(
        code="auth_code_123",
        redirect_uri=allowed_uri,
    )
    mock_tokens = MagicMock()
    mock_tokens.access_token = "access_token_123"  # noqa: S105
    mock_tokens.refresh_token = "refresh_token_123"  # noqa: S105
    mock_tokens.scope = "user-top-read"
    mock_exchange.return_value = mock_tokens
    mock_seed.return_value = ["Artist A", "Artist B"]

    res = await spotify_native_exchange(
        request=mock_request,
        body=good_payload,
        background_tasks=bg_tasks,
        _device=None,
        user_id="user-123",
    )
    assert res["syncing"] is True
    assert res["artists"] == ["Artist A", "Artist B"]


@pytest.mark.anyio
@patch("app.api.spotify.sync.get_decrypted_refresh_token")
@patch("app.api.spotify.sync.refresh_access_token")
@patch("app.api.spotify.sync.get_connection")
@patch("app.api.spotify.sync.upsert_connection")
@patch("app.api.spotify.sync.run_full_sync")
async def test_spotify_resync_persists_rotated_refresh_token(
    _mock_run_full_sync: MagicMock,
    mock_upsert_connection: MagicMock,
    mock_get_connection: MagicMock,
    mock_refresh: AsyncMock,
    mock_get_refresh_token: MagicMock,
) -> None:
    from app.api.spotify.sync import spotify_resync

    mock_get_refresh_token.return_value = "old_refresh_token"
    mock_bundle = MagicMock()
    mock_bundle.access_token = "new_access_token"  # noqa: S105
    mock_bundle.refresh_token = "rotated_refresh_token"  # noqa: S105
    mock_bundle.scope = "user-top-read"
    mock_refresh.return_value = mock_bundle

    mock_get_connection.return_value = {"spotify_user_id": "spot-user-999"}
    bg_tasks = BackgroundTasks()

    res = await spotify_resync(
        request=_make_dummy_request(),
        background_tasks=bg_tasks,
        _device=None,
        user_id="user-resync-1",
    )

    assert res == {"syncing": True}
    mock_upsert_connection.assert_called_once_with(
        "user-resync-1", "spot-user-999", "rotated_refresh_token", "user-top-read",
    )


@pytest.mark.anyio
@patch("app.services.spotify_sync._get_with_retry")
async def test_fetch_artist_genres_batch_keyed_by_id(mock_get: AsyncMock) -> None:
    import httpx

    from app.services.spotify_sync import fetch_artist_genres_batch

    mock_resp = MagicMock()
    mock_resp.json.return_value = {
        "artists": [
            {
                "id": "aid_123",
                "name": "Kendrick Lamar",
                "genres": ["conscious hip hop", "hip hop", "rap"],
            },
            {
                "id": "aid_456",
                "name": "Radiohead",
                "genres": ["art rock", "alternative rock"],
            },
        ],
    }
    mock_get.return_value = mock_resp

    async with httpx.AsyncClient() as client:
        genres_by_id = await fetch_artist_genres_batch(client, "dummy_token", ["aid_123", "aid_456"])

    assert "aid_123" in genres_by_id
    assert genres_by_id["aid_123"] == ["conscious hip hop", "hip hop", "rap"]
    assert "aid_456" in genres_by_id
    assert genres_by_id["aid_456"] == ["art rock", "alternative rock"]


@pytest.mark.anyio
@patch("app.services.spotify_sync.fetch_artist_genres_batch")
async def test_blend_playlist_genres_affinity_looks_up_by_id(mock_fetch_genres: AsyncMock) -> None:
    import httpx

    from app.services.spotify_sync import _blend_playlist_genres_affinity

    mock_fetch_genres.return_value = {
        "artist_id_1": ["indie pop", "synth-pop"],
    }
    all_tracks = [
        {
            "spotify_track_id": "track_1",
            "name": "Song 1",
            "artists": ["Different Cased Name"],
            "artist_ids": ["artist_id_1"],
        },
    ]
    genre_acc: dict[str, float] = {}

    async with httpx.AsyncClient() as client:
        await _blend_playlist_genres_affinity(client, "dummy_token", all_tracks, genre_acc)

    assert "indie pop" in genre_acc
    assert "synth-pop" in genre_acc
    assert genre_acc["indie pop"] > 0.0


@pytest.mark.anyio
@patch("asyncio.sleep", return_value=None)
async def test_post_with_retry_succeeds_after_5xx(mock_sleep: AsyncMock) -> None:
    from app.services.spotify_sync import _post_with_retry

    mock_client = MagicMock()
    mock_503 = MagicMock()
    mock_503.status_code = 503

    mock_200 = MagicMock()
    mock_200.status_code = 200
    mock_200.json.return_value = {"access_token": "ok_token"}

    mock_client.post = AsyncMock(side_effect=[mock_503, mock_200])

    resp = await _post_with_retry(
        mock_client,
        "https://accounts.spotify.com/api/token",
        data={},
        auth=("id", "secret"),
        headers={},
    )
    assert resp.status_code == 200
    assert mock_client.post.call_count == 2
    assert mock_sleep.call_count == 1


@pytest.mark.anyio
@patch("app.services.spotify_sync.fetch_artist_genres_batch")
async def test_blend_playlist_genres_affinity_respects_time_budget(mock_fetch_genres: AsyncMock) -> None:
    import httpx

    from app.services.spotify_sync import _blend_playlist_genres_affinity

    all_tracks = [
        {
            "spotify_track_id": "track_1",
            "name": "Song 1",
            "artists": ["Artist 1"],
            "artist_ids": ["aid_1"],
        },
    ]
    genre_acc: dict[str, float] = {}

    # Calling with start_time = 0.0 and budget = 10.0 (simulating expired budget)
    async with httpx.AsyncClient() as client:
        await _blend_playlist_genres_affinity(
            client,
            "dummy_token",
            all_tracks,
            genre_acc,
            start_time=0.0,
            budget_seconds=10.0,
        )

    # Should have skipped fetch completely
    mock_fetch_genres.assert_not_called()
    assert genre_acc == {}


def test_spotify_disconnect_clears_affinity_signals() -> None:
    from app.db.spotify import disconnect

    mock_table = MagicMock()
    mock_builder = MagicMock()
    mock_builder.delete.return_value = mock_builder
    mock_builder.update.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])
    mock_table.return_value = mock_builder

    with patch("app.db.spotify.supabase_client.table", mock_table):
        disconnect("user-123")

        # Verify profiles update explicitly nullifies artist_affinity, genre_affinity, top_artists
        mock_builder.update.assert_any_call({
            "artist_affinity": None,
            "genre_affinity": None,
            "top_artists": None,
            "music_taste_synced_at": None,
        })
        # Verify discovery_session_items update resets candidate_spotify_connected and music_match_grade
        mock_builder.update.assert_any_call({
            "candidate_spotify_connected": False,
            "music_match_grade": None,
        })


@pytest.mark.anyio
@patch("app.db.spotify.supabase_client.table")
async def test_get_connection_selects_disconnected_at(mock_table: MagicMock) -> None:
    from app.db.spotify import get_connection

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.limit.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(
        data=[{"user_id": "u-1", "disconnected_at": "2026-08-20T00:00:00Z"}],
    )
    mock_table.return_value = mock_builder

    conn = get_connection("u-1")
    assert conn is not None
    assert conn.get("disconnected_at") == "2026-08-20T00:00:00Z"
    select_cols = mock_builder.select.call_args[0][0]
    assert "disconnected_at" in select_cols


def test_replace_playlists_trims_bloated_tracks() -> None:
    import json

    from app.db.profiles.encryption import decrypt_pii
    from app.db.spotify import replace_playlists

    mock_table = MagicMock()
    mock_builder = MagicMock()
    mock_builder.upsert.return_value = mock_builder
    mock_builder.delete.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.not_ = MagicMock()
    mock_builder.not_.in_.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])
    mock_table.return_value = mock_builder

    # Generate a playlist with 100 tracks and bloated internal metadata
    bloated_tracks = [
        {
            "spotify_track_id": f"track-{i}",
            "name": f"Track Name {i}",
            "artists": [f"Artist {i}", "Featured Artist"],
            "artist_ids": [f"artist-id-{i}", "featured-artist-id"],
            "album_internal": "Huge Album Metadata Blob" * 50,
            "popularity": 85,
        }
        for i in range(100)
    ]
    playlist = {
        "spotify_playlist_id": "playlist-123",
        "name": "My Heavy Playlist",
        "is_collaborative": False,
        "track_count": 100,
        "tracks": bloated_tracks,
    }

    with patch("app.db.spotify.supabase_client.table", mock_table):
        replace_playlists("user-123", [playlist])

    mock_builder.upsert.assert_called_once()
    upsert_rows = mock_builder.upsert.call_args[0][0]
    assert len(upsert_rows) == 1
    row = upsert_rows[0]
    assert row["user_id"] == "user-123"
    assert row["spotify_playlist_id"] == "playlist-123"

    # Decrypt and check stored tracks
    decrypted_tracks_json = decrypt_pii(row["tracks"], category="oauth")
    stored_tracks = json.loads(decrypted_tracks_json)
    # Bounded to 25 items max
    assert len(stored_tracks) == 25
    # Internal bloat fields stripped
    first_track = stored_tracks[0]
    assert "artist_ids" not in first_track
    assert "album_internal" not in first_track
    assert "popularity" not in first_track
    assert first_track["spotify_track_id"] == "track-0"
    assert first_track["name"] == "Track Name 0"
    assert first_track["artists"] == ["Artist 0", "Featured Artist"]


@pytest.mark.anyio
@patch("app.services.spotify_sync.logger")
@patch("app.services.spotify_sync.httpx.AsyncClient")
async def test_revoke_refresh_token_logs_exception_class_without_exc_info(
    mock_client_cls: MagicMock,
    mock_logger: MagicMock,
) -> None:
    import httpx

    from app.services.spotify_sync import revoke_refresh_token

    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    mock_client.post.side_effect = httpx.ConnectTimeout("Connection to Spotify API timed out with bearer=secret123")
    mock_client_cls.return_value = mock_client

    result = await revoke_refresh_token("sample_refresh_token_12345")
    assert result is False

    mock_logger.warning.assert_called_once()
    args, kwargs = mock_logger.warning.call_args
    assert "Failed to revoke Spotify token at provider: ConnectTimeout" in (args[0] % args[1:])
    assert kwargs.get("exc_info") is not True


def test_mark_sync_result_sanitizes_spotify_user_ids_and_tokens() -> None:
    from app.db.spotify import _sanitize_sync_error, mark_sync_result

    raw_err = "Failed to fetch playlist for spotify:user:alice_smith_123456789 with bearer 1234567890abcdef and contact test@example.com"
    sanitized = _sanitize_sync_error(raw_err)
    assert sanitized is not None
    assert "spotify:user:[REDACTED]" in sanitized
    assert "alice_smith_123456789" not in sanitized
    assert "bearer [REDACTED]" in sanitized
    assert "[EMAIL_REDACTED]" in sanitized

    # Verify mark_sync_result stores sanitized error
    with patch("app.db.spotify.supabase_client.table") as mock_table:
        mock_builder = MagicMock()
        mock_builder.update.return_value = mock_builder
        mock_builder.eq.return_value = mock_builder
        mock_table.return_value = mock_builder

        mark_sync_result("user-1", "failed", error=raw_err)

        mock_table.assert_called_once_with("spotify_connections")
        mock_builder.update.assert_called_once()
        update_arg = mock_builder.update.call_args[0][0]
        assert "spotify:user:[REDACTED]" in update_arg["last_sync_error"]
        assert "alice_smith" not in update_arg["last_sync_error"]


def test_retrieval_candidate_spotify_connected_not_leaked_from_stale_affinity() -> None:
    from Nexus_Engine.retrieval import discover_orbit

    viewer: dict[str, Any] = {
        "id": "viewer-1",
        "identity_embedding": [1.0, 0.0],
        "activities": ["Music"],
        "artist_affinity": {"Radiohead": 1.0},
        "genre_affinity": {"Rock": 1.0},
        "viewer_spotify_connected": True,
    }

    # Cand 1: Has stale artist affinity but disconnected/no active connection
    cand_stale: dict[str, Any] = {
        "id": "cand-stale",
        "identity_embedding": [1.0, 0.0],
        "activities": ["Music"],
        "artist_affinity": {"Radiohead": 1.0},
        "genre_affinity": {"Rock": 1.0},
        "spotify_connected": False,
    }

    # Cand 2: Actively connected
    cand_active: dict[str, Any] = {
        "id": "cand-active",
        "identity_embedding": [1.0, 0.0],
        "activities": ["Music"],
        "artist_affinity": {"Radiohead": 1.0},
        "genre_affinity": {"Rock": 1.0},
        "spotify_connected": True,
    }

    orbit = discover_orbit(viewer, "Friends", [cand_stale, cand_active])
    by_id = {item["profile"]["id"]: item for item in orbit}

    assert by_id["cand-stale"]["candidate_spotify_connected"] is False
    assert by_id["cand-active"]["candidate_spotify_connected"] is True


@pytest.mark.anyio
@patch("app.db.spotify.get_connection")
async def test_node_details_candidate_spotify_connected_checks_live_connection(
    mock_get_conn: MagicMock,
) -> None:
    from app.db.sessions.node_details import _build_node_detail_payload

    row = {
        "score": 0.8,
        "x": 10.0,
        "y": 20.0,
        "orbit_tier": 2,
        "music_match_grade": 8,
        "candidate_spotify_connected": True,  # stale session item value
    }
    raw_profile = {
        "id": "cand-123",
        "name": "Bob",
        "age": 22,
    }

    def _identity(data: dict[str, Any]) -> dict[str, Any]:
        return data

    def _get_conn_side_effect(uid: str) -> dict[str, Any] | None:
        if uid == "viewer-1":
            return {"user_id": "viewer-1", "disconnected_at": None}
        return {"user_id": "cand-123", "disconnected_at": "2026-08-20T00:00:00Z"}

    mock_get_conn.side_effect = _get_conn_side_effect

    with patch("app.db.sessions.node_details.decrypt_profile_record", side_effect=_identity), \
         patch("app.db.sessions.node_details.sanitize_decrypted_profile", side_effect=_identity), \
         patch("app.db.sessions.node_details.sign_profile_media", side_effect=_identity):
        payload = _build_node_detail_payload(
            row=row,
            profile=raw_profile,
            cid="cand-123",
            session_id="sess-1",
            viewer_id="viewer-1",
            candidate_id="cand-123",
            connection=None,
        )

    assert payload["viewer_spotify_connected"] is True
    # Candidate disconnected -> candidate_spotify_connected MUST be False
    assert payload["candidate_spotify_connected"] is False
    # Grade should be wiped since one party is disconnected
    assert payload["music_match_grade"] is None

