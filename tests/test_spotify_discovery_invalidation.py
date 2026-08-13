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
@patch("app.api.spotify.sync.invalidate_viewer_discovery_sessions")
@patch("app.api.spotify.sync.disconnect_connection")
async def test_spotify_disconnect_invalidates_discovery_sessions(
    mock_disconnect: MagicMock,
    mock_invalidate: MagicMock,
) -> None:
    res = await spotify_disconnect(
        request=_make_dummy_request(),
        _device=None,
        user_id="user-123",
    )

    assert res == {"disconnected": True}
    mock_disconnect.assert_called_once_with("user-123")
    mock_invalidate.assert_called_once_with("user-123")


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
