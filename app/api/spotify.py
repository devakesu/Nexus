"""
Spotify OAuth integration - server-side Authorization Code flow, with a
persistent (encrypted) refresh token so playlists/artists can be resynced
on demand without the user re-authenticating every time.

Security model:
  - /connect and /native-exchange require a valid Supabase JWT (authenticated user).
  - /callback is public (called by Spotify's servers as an OAuth redirect),
    secured by a one-time state token stored in Redis with a 10-minute TTL.
  - /status, /playlists, /resync, /connection all require a valid JWT and are
    scoped to the caller's own user_id.
  - The Spotify client_secret never leaves the backend.
  - Artist names, playlist names, and track data are encrypted before
    persisting (same scheme as all PII) - see app/db/spotify.py.

Privacy boundary: this router populates profiles.artist_affinity (the
matching-engine signal) and spotify_playlists (private playlist detail).
Neither is ever returned from any endpoint other than the owner-scoped ones
here - see app/db/profiles.py and app/db/sessions.py for the peer-facing
query sites that must never select these fields.
"""

import html
import logging
import secrets
from typing import Any, cast
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

from app.api.dependencies import get_active_user_id
from app.core.cache import redis_client
from app.core.config import settings
from app.core.limiter import limiter
from app.db.client import DatabaseAccessError
from app.db.spotify import (
    disconnect as disconnect_connection,
)
from app.db.spotify import (
    fetch_playlists_for_owner,
    get_connection,
    get_decrypted_refresh_token,
    persist_artist_signals,
    upsert_connection,
)
from app.models import (
    SpotifyPlaylistOut,
    SpotifyPlaylistsResponse,
    SpotifyStatusResponse,
    SpotifyTrackOut,
)
from app.services.spotify_sync import (
    blend_artist_affinity,
    compute_artist_frequency,
    compute_genre_affinity,
    exchange_code,
    fetch_owned_or_collaborative_playlists,
    fetch_playlist_tracks,
    fetch_spotify_user_id,
    fetch_top_artists_ranked,
    refresh_access_token,
    run_full_sync,
    top_display_names,
)

logger = logging.getLogger(__name__)

router = APIRouter()

_STATE_TTL_SECONDS = 600  # 10 minutes - enough for the user to complete auth
_SPOTIFY_AUTH_URL = "https://accounts.spotify.com/authorize"
_SPOTIFY_SCOPES = "user-top-read playlist-read-private playlist-read-collaborative"


def _state_redis_key(state: str) -> str:
    """State redis key.

        Args:
            state: state redis key.

        Returns:
            str: Result value.
        """
    return f"spotify:oauth:state:{state}"


async def _store_state(state: str, user_id: str) -> None:
    """Store state.

        Args:
            state: store state.
            user_id: store state.

        Returns:
            None: Result value.
        """
    await redis_client.setex(_state_redis_key(state), _STATE_TTL_SECONDS, user_id)


async def _consume_state(state: str) -> str | None:
    """Atomically retrieve and delete the state token. Returns the user_id or None."""
    result: str | None = await redis_client.getdel(_state_redis_key(state))  # type: ignore[assignment]
    return result


async def _seed_and_queue_sync(
    background_tasks: BackgroundTasks,
    user_id: str,
    access_token: str,
    refresh_token: str | None,
    scope: str,
) -> list[str]:
    """Shared post-token-exchange flow for /native-exchange and /callback.

    Persists the refresh token (if granted), fetches native top artists
    inline so a fast public signal exists immediately, then queues the
    slower playlist fetch+blend as a background task. Returns the seeded
    display artist names for the caller's immediate response.
    """
    spotify_user_id = await fetch_spotify_user_id(access_token)

    if refresh_token:
        upsert_connection(user_id, spotify_user_id, refresh_token, scope)
    else:
        logger.warning(
            "Spotify did not return a refresh_token on exchange; resync will "
            "require full re-auth for this user",
            extra={"user_id": user_id},
        )

    top_artists_result = await fetch_top_artists_ranked(access_token)
    native_ranked = top_artists_result.ranked
    genre_affinity = compute_genre_affinity(top_artists_result.genre_weights)
    blended, casing_map = blend_artist_affinity(native_ranked, {})
    display_names = top_display_names(blended, casing_map)

    # Fallback: if native listening history is too low/new, check playlists inline.
    if not display_names:
        try:
            async with httpx.AsyncClient(timeout=15.0) as client:
                candidate_playlists = (
                    await fetch_owned_or_collaborative_playlists(
                        client,
                        access_token,
                        spotify_user_id,
                    )
                )
                all_tracks: list[dict[str, Any]] = []
                # Fetch tracks from up to 3 candidate playlists inline.
                for playlist in candidate_playlists[:3]:
                    playlist_id = cast(str, playlist.get("spotify_playlist_id") or "")
                    if playlist_id:
                        tracks = await fetch_playlist_tracks(
                            client,
                            access_token,
                            playlist_id,
                        )
                        all_tracks.extend(tracks)

                if all_tracks:
                    playlist_freq = compute_artist_frequency(all_tracks)
                    blended, casing_map = blend_artist_affinity(
                        native_ranked,
                        playlist_freq,
                    )
                    display_names = top_display_names(blended, casing_map)
        except Exception:
            logger.exception(
                "Fallback playlist sync failed inline for user %s",
                user_id,
            )

    if display_names:
        persist_artist_signals(user_id, blended, display_names, genre_affinity)

    background_tasks.add_task(run_full_sync, user_id, access_token, spotify_user_id)
    return display_names


class _NativeExchangeRequest(BaseModel):
    """ nativeexchangerequest class representation."""
    # Authorization code from the Spotify Android Auth Library.
    code: str = Field(..., min_length=1, max_length=512)
    # Must match the redirect_uri used when the auth request was made.
    redirect_uri: str = Field(..., min_length=1, max_length=512)


@router.post("/api/v1/spotify/native-exchange")
@limiter.limit(settings.rate_limit_spotify)
async def spotify_native_exchange(
    request: Request,
    body: _NativeExchangeRequest,
    background_tasks: BackgroundTasks,
    user_id: str = Depends(get_active_user_id),
) -> dict[str, Any]:
    """
    Exchange a native SDK authorization code for artists + a persistent
    connection, then queue a full playlist sync in the background.

    Used by the Android native auth path (Spotify Auth Library) which returns
    an Authorization Code instead of an access token - the backend holds the
    secret and completes the exchange.
    """
    _ = request
    redirect_uri = settings.spotify_redirect_uri
    if not redirect_uri:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Spotify integration is not configured.",
        )
    allowed_redirect_uris = {
        redirect_uri,
        "com.devakesu.apps.nexus://callback",
    }
    if body.redirect_uri not in allowed_redirect_uris:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid redirect_uri.",
        )

    try:
        tokens = await exchange_code(body.code, body.redirect_uri)
    except Exception:
        logger.exception("Native code exchange failed for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to exchange Spotify authorization code.",
        ) from None

    if not tokens.access_token:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Spotify did not return a valid access token.",
        )

    try:
        display_names = await _seed_and_queue_sync(
            background_tasks,
            user_id,
            tokens.access_token,
            tokens.refresh_token,
            tokens.scope,
        )
    except Exception:
        logger.exception("Spotify sync setup failed for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to fetch data from Spotify.",
        ) from None

    logger.info(
        "Native exchange: %d Spotify top artists seeded for user %s, full sync queued",
        len(display_names),
        user_id,
    )
    return {"synced": len(display_names), "artists": display_names, "syncing": True}


@router.get("/api/v1/spotify/connect")
@limiter.limit(settings.rate_limit_spotify)
async def spotify_connect(
    request: Request,
    user_id: str = Depends(get_active_user_id),
) -> dict[str, str]:
    """Return a Spotify authorization URL for the current user."""
    _ = request
    redirect_uri = settings.spotify_redirect_uri
    if not settings.spotify_client_id or not redirect_uri:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Spotify integration is not configured on this server.",
        )

    state = secrets.token_urlsafe(32)
    await _store_state(state, user_id)

    params = {
        "response_type": "code",
        "client_id": settings.spotify_client_id,
        "scope": _SPOTIFY_SCOPES,
        "redirect_uri": redirect_uri,
        "state": state,
        "show_dialog": "false",
    }
    return {"auth_url": f"{_SPOTIFY_AUTH_URL}?{urlencode(params)}"}


@router.get("/api/v1/spotify/callback", response_class=HTMLResponse)
async def spotify_callback(
    request: Request,
    background_tasks: BackgroundTasks,
    code: str | None = None,
    state: str | None = None,
    error: str | None = None,
) -> HTMLResponse:
    """
    OAuth callback invoked by Spotify after the user grants (or denies) access.

    Public endpoint - no JWT or App Check - because it is called by Spotify's
    servers, not the app. Security comes from the one-time Redis state token.
    """
    _ = request
    if error or not code or not state:
        reason = error or "missing parameters"
        return _html_result(
            title="Connection failed",
            success=False,
            message=f"Spotify denied access: {reason}. Please try again from the app.",
        )

    user_id = await _consume_state(state)
    if not user_id:
        return _html_result(
            title="Session expired",
            success=False,
            message=(
                "This link has already been used or has expired. "
                "Please try connecting again from the app."
            ),
        )

    redirect_uri = settings.spotify_redirect_uri
    if not redirect_uri:
        return _html_result(
            title="Configuration error",
            success=False,
            message="Spotify integration is not configured on the server.",
        )

    try:
        tokens = await exchange_code(code, redirect_uri)
    except Exception:
        logger.exception("Spotify token exchange failed for user %s", user_id)
        return _html_result(
            title="Token exchange failed",
            success=False,
            message="Could not complete Spotify authorization. Please try again.",
        )

    if not tokens.access_token:
        return _html_result(
            title="Authorization error",
            success=False,
            message="Spotify did not return a valid access token. Please try again.",
        )

    try:
        display_names = await _seed_and_queue_sync(
            background_tasks,
            user_id,
            tokens.access_token,
            tokens.refresh_token,
            tokens.scope,
        )
    except Exception:
        logger.exception("Spotify sync setup failed for user %s", user_id)
        return _html_result(
            title="Could not fetch artists",
            success=False,
            message=(
                "Authorization succeeded but fetching your Spotify data failed. "
                "Please try again."
            ),
        )

    if not display_names:
        return _html_result(
            title="No top artists found",
            success=False,
            message=(
                "Your Spotify account doesn't have enough listening history yet. "
                "Listen to more music and try again!"
            ),
        )

    logger.info(
        "Synced %d Spotify top artists for user %s",
        len(display_names),
        user_id,
    )
    return _html_result(
        title="Spotify Connected!",
        success=True,
        message=(
            f"Synced {len(display_names)} top artists. Your playlists are "
            "syncing in the background - check the app in a moment."
        ),
        artists=display_names,
    )


@router.get("/api/v1/spotify/status")
@limiter.limit(settings.rate_limit_spotify)
async def spotify_status(
    request: Request,
    user_id: str = Depends(get_active_user_id),
) -> SpotifyStatusResponse:
    """Cheap connected/last-synced/counts summary for the Profile tab's
    initial render - avoids pulling the full playlist payload just to decide
    whether to show a Connect or Manage button."""
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


def _track_out_from_row(raw: dict[str, Any]) -> SpotifyTrackOut:
    """Track out from row.

        Args:
            raw: track out from row.

        Returns:
            SpotifyTrackOut: Result value.
        """
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
    """Playlist out from row.

        Args:
            raw: playlist out from row.

        Returns:
            SpotifyPlaylistOut: Result value.
        """
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


@router.get("/api/v1/spotify/playlists")
@limiter.limit(settings.rate_limit_spotify)
async def spotify_playlists(
    request: Request,
    user_id: str = Depends(get_active_user_id),
) -> SpotifyPlaylistsResponse:
    """Owner-only: full decrypted playlist + track payload.

    Never called for or on behalf of another user - there is no peer-facing
    equivalent of this endpoint anywhere in the API.
    """
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
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Resync playlists + artists using the stored refresh token - no
    re-auth needed. Tightly rate-limited since it can trigger ~100+ Spotify
    API calls per invocation."""
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

    # Spotify may rotate the refresh token on any refresh call - re-persist
    # it if a new one came back, otherwise keep using the one already stored.
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
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Fully revoke a Spotify connection: deletes the stored refresh token
    and all synced playlists, and clears artist_affinity/top_artists/
    music_taste_synced_at from the profile. Spotify has no public revoke
    endpoint, so the app should also point users to
    open.spotify.com/account/apps to revoke access on Spotify's side."""
    _ = request
    try:
        disconnect_connection(user_id)
    except DatabaseAccessError:
        logger.exception("Failed to disconnect spotify for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to disconnect Spotify.",
        ) from None
    return {"disconnected": True}


def _html_result(
    *,
    title: str,
    success: bool,
    message: str,
    artists: list[str] | None = None,
) -> HTMLResponse:
    """Html result.

        Returns:
            HTMLResponse: Result value.
        """
    accent = "#1DB954" if success else "#FF4B4B"
    icon = "✓" if success else "✕"
    artist_html = ""
    if artists:
        rows = "".join(f"<li>{html.escape(name)}</li>" for name in artists)
        artist_html = f'<ul class="artists">{rows}</ul>'

    safe_title = html.escape(title)
    safe_message = html.escape(message)

    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{safe_title}</title>
  <style>
    *{{box-sizing:border-box;margin:0;padding:0}}
    body{{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
         background:#121212;color:#fff;display:flex;align-items:center;
         justify-content:center;min-height:100vh;padding:24px}}
    .card{{background:#1e1e1e;border-radius:20px;padding:40px 32px;
           max-width:420px;width:100%;text-align:center;
           box-shadow:0 16px 48px rgba(0,0,0,.6)}}
    .icon{{width:64px;height:64px;border-radius:50%;
           background:{accent}22;display:flex;align-items:center;
           justify-content:center;margin:0 auto 20px;
           font-size:28px;color:{accent}}}
    h1{{font-size:22px;font-weight:700;margin-bottom:10px}}
    .msg{{color:#aaa;line-height:1.55;font-size:15px}}
    .artists{{list-style:none;margin-top:20px;text-align:left;
              color:#ccc;font-size:14px}}
    .artists li{{padding:6px 0;border-bottom:1px solid #2a2a2a}}
    .artists li:last-child{{border:none}}
    .hint{{margin-top:28px;font-size:12px;color:#555}}
  </style>
</head>
<body>
  <div class="card">
    <div class="icon">{icon}</div>
    <h1>{safe_title}</h1>
    <p class="msg">{safe_message}</p>
    {artist_html}
    <p class="hint">You can close this tab and return to the app.</p>
  </div>
</body>
</html>"""
    return HTMLResponse(content=html_content, status_code=200)
