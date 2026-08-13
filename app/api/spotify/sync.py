"""Spotify status, playlist retrieval, background resync, and disconnection endpoints."""

import logging
from typing import Any, cast

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status

from app.api.dependencies import (
    get_active_user_id,
    verify_app_check_token,
    verify_app_check_with_replay_protection,
)
from app.core.config import settings
from app.core.infra.limiter import limiter
from app.db.client import DatabaseAccessError
from app.db.sessions import invalidate_viewer_discovery_sessions
from app.db.spotify import (
    disconnect as disconnect_connection,
)
from app.db.spotify import (
    fetch_playlists_for_owner,
    get_connection,
    get_decrypted_refresh_token,
    upsert_connection,
)
from app.models import (
    SpotifyPlaylistOut,
    SpotifyPlaylistsResponse,
    SpotifyStatusResponse,
    SpotifyTrackOut,
)
from app.services.spotify_sync import (
    fetch_spotify_user_id,
    refresh_access_token,
    run_full_sync,
)

logger = logging.getLogger(__name__)
router = APIRouter()


def _track_out_from_row(raw: dict[str, Any]) -> SpotifyTrackOut:
    """Converts a database track dictionary into SpotifyTrackOut model."""
    raw_artists = raw.get("artists")
    artists: list[Any] = (
        cast(list[Any], raw_artists) if isinstance(raw_artists, list) else []
    )
    return SpotifyTrackOut(
        spotify_track_id=raw.get("spotify_track_id"),
        name=str(raw.get("name") or ""),
        artists=[a for a in artists if isinstance(a, str)],
    )


def _playlist_out_from_row(raw: dict[str, Any]) -> SpotifyPlaylistOut:
    """Converts a database playlist dictionary into SpotifyPlaylistOut model."""
    raw_tracks = raw.get("tracks")
    tracks: list[Any] = (
        cast(list[Any], raw_tracks) if isinstance(raw_tracks, list) else []
    )
    spotify_playlist_id = str(raw.get("spotify_playlist_id") or "")
    return SpotifyPlaylistOut(
        id=str(raw.get("id") or ""),
        spotify_playlist_id=spotify_playlist_id,
        name=str(raw.get("name") or ""),
        is_collaborative=bool(raw.get("is_collaborative", False)),
        track_count=int(raw.get("track_count") or 0),
        tracks=[
            _track_out_from_row(cast(dict[str, Any], t))
            for t in tracks
            if isinstance(t, dict)
        ],
        synced_at=raw.get("synced_at"),
        spotify_url=f"https://open.spotify.com/playlist/{spotify_playlist_id}",
    )


@router.get("/api/v1/spotify/status")
@limiter.limit(settings.rate_limit_spotify)
async def spotify_status(
    request: Request,
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> SpotifyStatusResponse:
    """Returns caller's current Spotify connection and sync status."""
    _ = request
    connection = get_connection(user_id)
    if connection is None or connection.get("disconnected_at"):
        return SpotifyStatusResponse(connected=False)

    playlists = fetch_playlists_for_owner(user_id)
    return SpotifyStatusResponse(
        connected=True,
        last_synced_at=connection.get("last_synced_at"),
        playlist_count=len(playlists),
    )


@router.get("/api/v1/spotify/playlists")
@limiter.limit(settings.rate_limit_spotify)
async def spotify_playlists(
    request: Request,
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> SpotifyPlaylistsResponse:
    """Owner-only: full decrypted playlist + track payload."""
    _ = request
    connection = get_connection(user_id)
    try:
        raw_playlists = fetch_playlists_for_owner(user_id)
    except DatabaseAccessError:
        logger.exception("Failed to fetch playlists for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to fetch your Spotify playlists.",
        ) from None

    playlists = [_playlist_out_from_row(p) for p in raw_playlists]

    return SpotifyPlaylistsResponse(
        connected=connection is not None and not connection.get("disconnected_at"),
        last_synced_at=connection.get("last_synced_at") if connection else None,
        playlists=playlists,
    )


@router.post("/api/v1/spotify/resync")
@limiter.limit(settings.rate_limit_spotify_resync)
async def spotify_resync(
    request: Request,
    background_tasks: BackgroundTasks,
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Resync playlists + artists using the stored refresh token."""
    _ = request
    refresh_token = get_decrypted_refresh_token(user_id)
    if not refresh_token:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No Spotify connection found. Please connect Spotify first.",
        )

    try:
        tokens = await refresh_access_token(refresh_token)
    except Exception:
        logger.exception("Spotify token refresh failed for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to refresh Spotify access. Please reconnect Spotify.",
        ) from None

    if not tokens.access_token:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Spotify did not return a valid access token.",
        )

    connection = get_connection(user_id)
    spotify_user_id = str((connection or {}).get("spotify_user_id") or "")
    if not spotify_user_id:
        spotify_user_id = await fetch_spotify_user_id(tokens.access_token)

    if tokens.refresh_token and tokens.refresh_token != refresh_token:
        upsert_connection(user_id, spotify_user_id, tokens.refresh_token, tokens.scope)

    background_tasks.add_task(
        run_full_sync,
        user_id,
        tokens.access_token,
        spotify_user_id,
    )
    return {"syncing": True}


@router.delete("/api/v1/spotify/connection")
@limiter.limit(settings.rate_limit_spotify)
async def spotify_disconnect(
    request: Request,
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Revokes Spotify integration, deleting stored access tokens and artist affinity data."""
    _ = request
    try:
        disconnect_connection(user_id)
        try:
            invalidate_viewer_discovery_sessions(user_id)
        except Exception:
            logger.warning(
                "Failed to invalidate discovery sessions on Spotify disconnect",
                extra={"user_id": user_id},
            )
    except DatabaseAccessError:
        logger.exception("Failed to disconnect spotify for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to disconnect Spotify.",
        ) from None
    return {"disconnected": True}
