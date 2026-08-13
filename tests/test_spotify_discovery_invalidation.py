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


