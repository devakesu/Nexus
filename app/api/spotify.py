"""
Spotify OAuth integration - server-side Authorization Code flow.

Security model:
  - /connect requires a valid Supabase JWT (authenticated user).
  - /callback is public (called by Spotify's servers as an OAuth redirect),
    secured by a one-time state token stored in Redis with a 10-minute TTL.
  - The Spotify client_secret never leaves the backend.
  - Artist names are encrypted before persisting (same scheme as all PII).
"""

import html
import json
import logging
import secrets
from typing import Any, cast
from urllib.parse import urlencode

import httpx
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from app.api.dependencies import get_authenticated_user_id
from app.core.cache import redis_client
from app.core.config import settings
from app.core.crypto import encrypt_to_hex
from app.core.limiter import limiter
from app.db.client import supabase_client

logger = logging.getLogger(__name__)

router = APIRouter()

_STATE_TTL_SECONDS = 600  # 10 minutes - enough for the user to complete auth
_TOP_ARTISTS_LIMIT = 10
_SPOTIFY_AUTH_URL = "https://accounts.spotify.com/authorize"
_SPOTIFY_TOKEN_ENDPOINT = "https://accounts.spotify.com/api/token"  # noqa: S105
_SPOTIFY_TOP_ARTISTS_URL = "https://api.spotify.com/v1/me/top/artists"


def _state_redis_key(state: str) -> str:
    return f"spotify:oauth:state:{state}"


async def _store_state(state: str, user_id: str) -> None:
    await redis_client.setex(_state_redis_key(state), _STATE_TTL_SECONDS, user_id)


async def _consume_state(state: str) -> str | None:
    """Atomically retrieve and delete the state token. Returns the user_id or None."""
    # decode_responses=True on the Redis client means values are always str.
    result: str | None = await redis_client.getdel(_state_redis_key(state))  # type: ignore[assignment]
    return result


class _NativeExchangeRequest(BaseModel):
    # Authorization code from the Spotify Android Auth Library.
    code: str
    # Must match the redirect_uri used when the auth request was made.
    redirect_uri: str


@router.post("/api/v1/spotify/native-exchange")
@limiter.limit("10/minute")
async def spotify_native_exchange(
    request: Request,
    body: _NativeExchangeRequest,
    user_id: str = Depends(get_authenticated_user_id),
) -> dict[str, Any]:
    """
    Exchange a native SDK authorization code for top artists and persist them.

    Used by the Android native auth path (Spotify Auth Library) which returns an
    Authorization Code instead of an access token - the backend holds the secret
    and completes the exchange.
    """
    _ = request
    allowed_redirect_uris = {
        settings.spotify_redirect_uri,
        "com.devakesu.apps.nexus://callback",
    }
    if body.redirect_uri not in allowed_redirect_uris:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid redirect_uri.",
        )

    try:
        access_token = await _exchange_code(body.code, body.redirect_uri)
    except Exception:
        logger.exception("Native code exchange failed for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to exchange Spotify authorization code.",
        ) from None

    if not access_token:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Spotify did not return a valid access token.",
        )

    try:
        artist_names = await _fetch_top_artist_names(access_token)
    except Exception:
        logger.exception("Spotify top-artists fetch failed for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail="Failed to fetch top artists from Spotify.",
        ) from None

    if not artist_names:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=(
                "No top artists found. Listen to more music on Spotify and try again."
            ),
        )

    try:
        _persist_artists(user_id, artist_names)
    except Exception:
        logger.exception("Failed to persist Spotify artists for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to save artists.",
        ) from None

    logger.info(
        "Native exchange: %d Spotify top artists saved for user %s",
        len(artist_names),
        user_id,
    )
    return {"synced": len(artist_names), "artists": artist_names}


@router.get("/api/v1/spotify/connect")
@limiter.limit("10/minute")
async def spotify_connect(
    request: Request,
    user_id: str = Depends(get_authenticated_user_id),
) -> dict[str, str]:
    """Return a Spotify authorization URL for the current user."""
    _ = request
    if not settings.spotify_client_id or not settings.spotify_redirect_uri:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Spotify integration is not configured on this server.",
        )

    state = secrets.token_urlsafe(32)
    await _store_state(state, user_id)

    params = {
        "response_type": "code",
        "client_id": settings.spotify_client_id,
        "scope": "user-top-read",
        "redirect_uri": settings.spotify_redirect_uri,
        "state": state,
        "show_dialog": "false",
    }
    return {"auth_url": f"{_SPOTIFY_AUTH_URL}?{urlencode(params)}"}


async def _exchange_code(code: str, redirect_uri: str | None = None) -> str:
    """Exchange an OAuth code for a Spotify access token. Returns the token or ''."""
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.post(
            _SPOTIFY_TOKEN_ENDPOINT,
            data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirect_uri or settings.spotify_redirect_uri,
            },
            auth=(
                settings.spotify_client_id or "",
                settings.spotify_client_secret or "",
            ),
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        resp.raise_for_status()
        data: dict[str, Any] = resp.json()
    return data.get("access_token") or ""


async def _fetch_top_artist_names(access_token: str) -> list[str]:
    """Fetch the current user's top artist names from Spotify."""
    async with httpx.AsyncClient(timeout=15.0) as client:
        resp = await client.get(
            _SPOTIFY_TOP_ARTISTS_URL,
            params={"limit": _TOP_ARTISTS_LIMIT, "time_range": "medium_term"},
            headers={"Authorization": f"Bearer {access_token}"},
        )
        resp.raise_for_status()
        data: dict[str, Any] = resp.json()

    names: list[str] = []
    raw_items: list[Any] = data.get("items") or []
    for raw in raw_items:
        if not isinstance(raw, dict):
            continue
        item = cast(dict[str, Any], raw)
        name = item.get("name")
        if isinstance(name, str) and name:
            names.append(name)
    return names


def _persist_artists(user_id: str, artist_names: list[str]) -> None:
    """Write encrypted artist names into the user's profile row."""
    supabase_client.table("profiles").update(
        {"top_artists": encrypt_to_hex(json.dumps(artist_names))},
    ).eq("id", user_id).execute()


@router.get("/api/v1/spotify/callback", response_class=HTMLResponse)
async def spotify_callback(
    request: Request,
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

    try:
        access_token = await _exchange_code(code)
    except Exception:
        logger.exception("Spotify token exchange failed for user %s", user_id)
        return _html_result(
            title="Token exchange failed",
            success=False,
            message="Could not complete Spotify authorization. Please try again.",
        )

    if not access_token:
        return _html_result(
            title="Authorization error",
            success=False,
            message="Spotify did not return a valid access token. Please try again.",
        )

    try:
        artist_names = await _fetch_top_artist_names(access_token)
    except Exception:
        logger.exception("Spotify top-artists fetch failed for user %s", user_id)
        return _html_result(
            title="Could not fetch artists",
            success=False,
            message=(
                "Authorization succeeded but fetching your top artists failed. "
                "Please try again."
            ),
        )

    if not artist_names:
        return _html_result(
            title="No top artists found",
            success=False,
            message=(
                "Your Spotify account doesn't have enough listening history yet. "
                "Listen to more music and try again!"
            ),
        )

    try:
        _persist_artists(user_id, artist_names)
    except Exception:
        logger.exception("Failed to persist Spotify artists for user %s", user_id)
        return _html_result(
            title="Save failed",
            success=False,
            message=(
                "Your artists were fetched but could not be saved. Please try again."
            ),
        )

    logger.info("Synced %d Spotify top artists for user %s", len(artist_names), user_id)
    return _html_result(
        title="Spotify Connected!",
        success=True,
        message=(
            f"Synced {len(artist_names)} top artists. Return to the app to see them."
        ),
        artists=artist_names,
    )


def _html_result(
    *,
    title: str,
    success: bool,
    message: str,
    artists: list[str] | None = None,
) -> HTMLResponse:
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
