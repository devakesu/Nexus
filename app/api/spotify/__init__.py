"""Spotify OAuth integration router, token exchange, and background playlist sync subpackage."""

from fastapi import APIRouter

from app.api.spotify.auth import (
    _html_result,
    _NativeExchangeRequest,
    _seed_and_queue_sync,
    spotify_callback,
    spotify_connect,
    spotify_native_exchange,
)
from app.api.spotify.auth import (
    router as auth_router,
)
from app.api.spotify.sync import (
    _playlist_out_from_row,
    _track_out_from_row,
    spotify_disconnect,
    spotify_playlists,
    spotify_resync,
    spotify_status,
)
from app.api.spotify.sync import (
    router as sync_router,
)

router = APIRouter()

router.include_router(auth_router)
router.include_router(sync_router)

__all__ = [
    "_NativeExchangeRequest",
    "_html_result",
    "_playlist_out_from_row",
    "_seed_and_queue_sync",
    "_track_out_from_row",
    "router",
    "spotify_callback",
    "spotify_connect",
    "spotify_disconnect",
    "spotify_native_exchange",
    "spotify_playlists",
    "spotify_resync",
    "spotify_status",
]
