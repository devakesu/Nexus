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
    mock_persist_signals: MagicMock,
    mock_run_full_sync: MagicMock,
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
        "user-123", "spotify-user-123", "refresh-xyz", "user-top-read"
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
    mock_invalidate: MagicMock,
    mock_fetch_top_artists: AsyncMock,
    mock_persist_signals: MagicMock,
    mock_run_full_sync: MagicMock,
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
        "user-456", "spotify-user-456", None, "user-top-read"
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
    mock_tokens.access_token = "access_token_123"
    mock_tokens.refresh_token = "refresh_token_123"
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
    assert res["success"] is True
    assert res["top_artists"] == ["Artist A", "Artist B"]


@pytest.mark.anyio
@patch("app.api.spotify.sync.get_decrypted_refresh_token")
@patch("app.api.spotify.sync.refresh_access_token")
@patch("app.api.spotify.sync.get_connection")
@patch("app.api.spotify.sync.upsert_connection")
@patch("app.api.spotify.sync.run_full_sync")
async def test_spotify_resync_persists_rotated_refresh_token(
    mock_run_full_sync: MagicMock,
    mock_upsert_connection: MagicMock,
    mock_get_connection: MagicMock,
    mock_refresh: AsyncMock,
    mock_get_refresh_token: MagicMock,
) -> None:
    from app.api.spotify.sync import spotify_resync

    mock_get_refresh_token.return_value = "old_refresh_token"
    mock_bundle = MagicMock()
    mock_bundle.access_token = "new_access_token"
    mock_bundle.refresh_token = "rotated_refresh_token"
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
        "user-resync-1", "spot-user-999", "rotated_refresh_token", "user-top-read"
    )


@pytest.mark.anyio
@patch("app.services.spotify_sync._get_with_retry")
async def test_fetch_artist_genres_batch_keyed_by_id(mock_get: AsyncMock) -> None:
    from app.services.spotify_sync import fetch_artist_genres_batch
    import httpx

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
        ]
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
    from app.services.spotify_sync import _blend_playlist_genres_affinity
    import httpx

    mock_fetch_genres.return_value = {
        "artist_id_1": ["indie pop", "synth-pop"],
    }
    all_tracks = [
        {
            "spotify_track_id": "track_1",
            "name": "Song 1",
            "artists": ["Different Cased Name"],
            "artist_ids": ["artist_id_1"],
        }
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
    from app.services.spotify_sync import _blend_playlist_genres_affinity
    import httpx

    all_tracks = [
        {
            "spotify_track_id": "track_1",
            "name": "Song 1",
            "artists": ["Artist 1"],
            "artist_ids": ["aid_1"],
        }
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




