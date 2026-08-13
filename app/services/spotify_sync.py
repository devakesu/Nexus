"""
Spotify fetch/paginate/blend pipeline: OAuth token exchange + refresh,
playlist and track pagination, and the artist_affinity / genre_affinity
blending logic that feeds the matching engine.

Policy notes this module deliberately respects (see Spotify Developer
Policy): only track/artist/playlist NAMES, genre labels, and Spotify IDs
are ever fetched or stored - no album art, preview URLs, popularity, or
audio-feature data (the kind of signal that would edge toward "training a
model on Spotify content", which Spotify's terms prohibit). All blending
below is a deterministic frequency/rank computation, not a trained model.
"""

import asyncio
import logging
import time
from collections import Counter
from dataclasses import dataclass
from typing import Any, cast

import httpx

from app.core.config import (
    SPOTIFY_AFFINITY_NATIVE_WEIGHT,
    SPOTIFY_AFFINITY_PLAYLIST_WEIGHT,
    settings,
)
from app.db.spotify import mark_sync_result, persist_artist_signals, replace_playlists

logger = logging.getLogger(__name__)

_SPOTIFY_AUTH_ENDPOINT = "https://accounts.spotify.com/api/token"
_SPOTIFY_ME_URL = "https://api.spotify.com/v1/me"
_SPOTIFY_TOP_ARTISTS_URL = "https://api.spotify.com/v1/me/top/artists"
_SPOTIFY_PLAYLISTS_URL = "https://api.spotify.com/v1/me/playlists"
_SPOTIFY_PLAYLIST_ITEMS_URL_TEMPLATE = (
    "https://api.spotify.com/v1/playlists/{playlist_id}/items"
)

_HTTP_TIMEOUT_SECONDS = 15.0
_MAX_RETRIES_PER_REQUEST = 3
_MAX_RETRY_AFTER_SECONDS = 10.0

_NATIVE_TOP_ARTISTS_LIMIT = 50
_TOP_ARTISTS_DISPLAY_LIMIT = 10  # unchanged from the pre-playlists integration
_MAX_PLAYLIST_LIST_PAGES = 4  # 50/page -> up to 200 playlists scanned
_MAX_PLAYLISTS_FOR_TRACKS = (
    30  # only fetch tracks for the first N owned/collaborative playlists
)
_MAX_TRACK_PAGES_PER_PLAYLIST = 6  # 50/page -> up to 300 tracks per playlist
_ARTIST_AFFINITY_MAX_ENTRIES = 50
_ARTIST_AFFINITY_MIN_WEIGHT = 0.03
_SYNC_TIME_BUDGET_SECONDS = 60.0


@dataclass
class SpotifyTokenBundle:
    """Spotifytokenbundle class representation."""
    access_token: str
    refresh_token: str | None
    scope: str
    expires_in: int


def _auth_header(access_token: str) -> dict[str, str]:
    """Executes auth header operation.

        Args:
            access_token: Raw JWT access token string.

        Returns:
            dict[str, str]: Response payload or result."""
    return {"Authorization": f"Bearer {access_token}"}


def _parse_retry_after(resp: httpx.Response) -> float:
    """Parse retry after.

        Args:
            resp: Input resp parameter.

        Returns:
            float: Response payload or result."""
    try:
        return min(
            float(resp.headers.get("Retry-After", "1")),
            _MAX_RETRY_AFTER_SECONDS,
        )
    except ValueError:
        return 1.0


async def _get_with_retry(
    client: httpx.AsyncClient,
    url: str,
    *,
    params: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
) -> httpx.Response:
    """GET with bounded retry-on-429, honoring Spotify's Retry-After header."""
    attempt = 0
    while True:
        resp = await client.get(url, params=params, headers=headers)
        if resp.status_code == 429 and attempt < _MAX_RETRIES_PER_REQUEST:
            await asyncio.sleep(_parse_retry_after(resp))
            attempt += 1
            continue
        resp.raise_for_status()
        return resp


async def _post_with_retry(
    client: httpx.AsyncClient,
    url: str,
    *,
    data: dict[str, Any],
    auth: tuple[str, str],
    headers: dict[str, str],
    max_retries: int = _MAX_RETRIES_PER_REQUEST,
) -> httpx.Response:
    """POST with bounded exponential backoff retry for transient 5xx errors or 429."""
    attempt = 0
    backoff = 0.5
    while True:
        try:
            resp = await client.post(url, data=data, auth=auth, headers=headers)
            if (resp.status_code == 429 or resp.status_code >= 500) and attempt < max_retries:
                retry_after = _parse_retry_after(resp) if resp.status_code == 429 else backoff
                await asyncio.sleep(retry_after)
                attempt += 1
                backoff *= 2
                continue
            resp.raise_for_status()
            return resp
        except (httpx.ConnectError, httpx.TimeoutException) as exc:
            if attempt < max_retries:
                await asyncio.sleep(backoff)
                attempt += 1
                backoff *= 2
                continue
            raise exc


# ---------------------------------------------------------------------------
# Token exchange / refresh
# ---------------------------------------------------------------------------


async def exchange_code(code: str, redirect_uri: str) -> SpotifyTokenBundle:
    """Exchange an OAuth authorization code for an access + refresh token."""
    async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT_SECONDS) as client:
        resp = await _post_with_retry(
            client,
            _SPOTIFY_AUTH_ENDPOINT,
            data={
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirect_uri,
            },
            auth=(
                settings.spotify_client_id or "",
                settings.spotify_client_secret or "",
            ),
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        data: dict[str, Any] = resp.json()

    return SpotifyTokenBundle(
        access_token=data.get("access_token") or "",
        refresh_token=data.get("refresh_token"),
        scope=data.get("scope") or "",
        expires_in=int(data.get("expires_in") or 0),
    )


async def refresh_access_token(refresh_token: str) -> SpotifyTokenBundle:
    """Exchange a stored refresh token for a fresh access token.

    Spotify may rotate the refresh token on any refresh call - if the
    response includes a new one, callers must re-persist it; if omitted,
    the caller should keep using the token it already has.
    """
    async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT_SECONDS) as client:
        resp = await _post_with_retry(
            client,
            _SPOTIFY_AUTH_ENDPOINT,
            data={
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
            },
            auth=(
                settings.spotify_client_id or "",
                settings.spotify_client_secret or "",
            ),
            headers={"Content-Type": "application/x-www-form-urlencoded"},
        )
        data: dict[str, Any] = resp.json()

    return SpotifyTokenBundle(
        access_token=data.get("access_token") or "",
        refresh_token=data.get("refresh_token"),
        scope=data.get("scope") or "",
        expires_in=int(data.get("expires_in") or 0),
    )


async def revoke_refresh_token(refresh_token: str) -> bool:
    """Best-effort revocation of Spotify refresh token at provider."""
    if not refresh_token:
        return False
    try:
        async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT_SECONDS) as client:
            resp = await client.post(
                _SPOTIFY_AUTH_ENDPOINT,
                data={
                    "token": refresh_token,
                    "token_type_hint": "refresh_token",
                },
                auth=(
                    settings.spotify_client_id or "",
                    settings.spotify_client_secret or "",
                ),
                headers={"Content-Type": "application/x-www-form-urlencoded"},
            )
            return resp.is_success
    except Exception:
        logger.warning("Failed to revoke Spotify token at provider", exc_info=True)
        return False


async def fetch_spotify_user_id(access_token: str) -> str:
    """Fetch the connected Spotify account's own user id (needed to determine
    playlist ownership - see fetch_owned_or_collaborative_playlists)."""
    async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT_SECONDS) as client:
        resp = await _get_with_retry(
            client,
            _SPOTIFY_ME_URL,
            headers=_auth_header(access_token),
        )
        data: dict[str, Any] = resp.json()
    return str(data.get("id") or "")


# ---------------------------------------------------------------------------
# Fetch: native top artists, playlists, playlist tracks
# ---------------------------------------------------------------------------


@dataclass
class TopArtistsResult:
    """Ranked artist weights and a parallel per-artist genre list.

    ranked: {original_case_name: weight}  (weight in (0, 1], rank-derived)
    genre_weights: {genre_name: weight}   (see compute_genre_affinity)
    """

    ranked: dict[str, float]
    genre_weights: dict[str, float]


async def fetch_top_artists_ranked(
    access_token: str,
    limit: int = _NATIVE_TOP_ARTISTS_LIMIT,
) -> TopArtistsResult:
    """Fetch Spotify's algorithmic top artists, weighted by rank.

    Rank 0 (Spotify's #1 artist) gets weight 1.0, decaying linearly to the
    last entry. The genres array returned per-artist is used to build a
    weighted genre signal alongside the artist weights.

    Returns a TopArtistsResult; the caller (blend_artist_affinity /
    compute_genre_affinity) handles case-insensitive normalization.
    """
    async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT_SECONDS) as client:
        resp = await _get_with_retry(
            client,
            _SPOTIFY_TOP_ARTISTS_URL,
            params={"limit": limit, "time_range": "medium_term"},
            headers=_auth_header(access_token),
        )
        data: dict[str, Any] = resp.json()

    items: list[Any] = data.get("items") or []
    valid_names: list[str] = []
    genres_per_rank: list[tuple[float, list[str]]] = []  # (rank_weight, genres)
    for rank, raw in enumerate(items):
        if not isinstance(raw, dict):
            continue
        item = cast(dict[str, Any], raw)
        name = item.get("name")
        if not isinstance(name, str) or not name.strip():
            continue
        valid_names.append(name)
        raw_genres: list[Any] = item.get("genres") or []
        genres = [g for g in raw_genres if isinstance(g, str) and g.strip()]
        # Rank weight will be assigned after we know `total`
        genres_per_rank.append((rank, genres))

    if not valid_names:
        return TopArtistsResult(ranked={}, genre_weights={})

    total = len(valid_names)
    ranked: dict[str, float] = {
        name: (total - rank) / total for rank, name in enumerate(valid_names)
    }

    # Build rank-weighted genre map: each genre inherits the weight of every
    # artist that carries it. Higher-ranked artists contribute more.
    genre_acc: dict[str, float] = {}
    for rank_idx, genres in genres_per_rank:
        rank_weight = (total - rank_idx) / total
        for genre in genres:
            key = genre.strip().lower()
            genre_acc[key] = genre_acc.get(key, 0.0) + rank_weight

    return TopArtistsResult(ranked=ranked, genre_weights=genre_acc)


async def fetch_owned_or_collaborative_playlists(
    client: httpx.AsyncClient,
    access_token: str,
    spotify_user_id: str,
) -> list[dict[str, Any]]:
    """Paginate GET /v1/me/playlists, filtered to playlists the caller owns
    or collaborates on.

    Get Playlist Items 403s for playlists the user only follows (per
    Spotify's API policy), so those are excluded here rather than discovered
    as failures later.
    """
    playlists: list[dict[str, Any]] = []
    url: str | None = _SPOTIFY_PLAYLISTS_URL
    params: dict[str, Any] | None = {"limit": 50}
    headers = _auth_header(access_token)

    for _ in range(_MAX_PLAYLIST_LIST_PAGES):
        if url is None or len(playlists) >= _MAX_PLAYLISTS_FOR_TRACKS:
            break
        resp = await _get_with_retry(client, url, params=params, headers=headers)
        data: dict[str, Any] = resp.json()

        page_items: list[Any] = data.get("items") or []
        for raw in page_items:
            if not isinstance(raw, dict):
                continue
            item = cast(dict[str, Any], raw)

            raw_owner = item.get("owner")
            is_owned = (
                isinstance(raw_owner, dict)
                and cast(
                    dict[str, Any],
                    raw_owner,
                ).get("id")
                == spotify_user_id
            )
            is_collaborative = bool(item.get("collaborative"))
            if not (is_owned or is_collaborative):
                continue

            playlist_id = item.get("id")
            name = item.get("name")
            if not isinstance(playlist_id, str) or not isinstance(name, str):
                continue

            tracks_meta = item.get("tracks") or item.get("items")
            track_count = 0
            if isinstance(tracks_meta, dict):
                track_count = int(cast(dict[str, Any], tracks_meta).get("total") or 0)

            playlists.append(
                {
                    "spotify_playlist_id": playlist_id,
                    "name": name,
                    "is_collaborative": is_collaborative,
                    "track_count": track_count,
                },
            )

        url = data.get("next")
        params = None  # `next` is a full URL with query params already included

    return playlists[:_MAX_PLAYLISTS_FOR_TRACKS]


async def fetch_playlist_tracks(  # noqa: C901
    client: httpx.AsyncClient,
    access_token: str,
    playlist_id: str,
) -> list[dict[str, Any]]:
    """Paginate GET /v1/playlists/{id}/items.

    Requests only track id/name/artist names via the `fields` filter - no
    album art, preview URLs, or popularity/audio-feature data is ever
    requested or stored.
    """
    tracks: list[dict[str, Any]] = []
    url: str | None = _SPOTIFY_PLAYLIST_ITEMS_URL_TEMPLATE.format(
        playlist_id=playlist_id,
    )
    params: dict[str, Any] | None = {
        "limit": 50,
        "fields": (
            "items(track(id,name,artists(name,id)),"
            "item(id,name,artists(name,id))),next"
        ),
    }
    headers = _auth_header(access_token)

    for _ in range(_MAX_TRACK_PAGES_PER_PLAYLIST):
        if url is None:
            break
        try:
            resp = await _get_with_retry(client, url, params=params, headers=headers)
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 403:
                # Ownership/collaborator status can change between the
                # /me/playlists listing and this call (e.g. removed as a
                # collaborator mid-sync) - skip rather than fail the sync.
                logger.warning(
                    "Spotify playlist items 403, skipping playlist",
                    extra={"playlist_id": playlist_id},
                )
                break
            raise

        data: dict[str, Any] = resp.json()
        page_items: list[Any] = data.get("items") or []
        for raw_item in page_items:
            if not isinstance(raw_item, dict):
                continue
            item = cast(dict[str, Any], raw_item)
            raw_track = item.get("track") or item.get("item")
            if not isinstance(raw_track, dict):
                continue
            track = cast(dict[str, Any], raw_track)
            name = track.get("name")
            if not isinstance(name, str) or not name.strip():
                continue

            raw_artists: list[Any] = track.get("artists") or []
            artist_names: list[str] = []
            artist_ids: list[str] = []
            for raw_artist in raw_artists:
                if not isinstance(raw_artist, dict):
                    continue
                artist_name = cast(dict[str, Any], raw_artist).get("name")
                artist_id = cast(dict[str, Any], raw_artist).get("id")
                if isinstance(artist_name, str):
                    artist_names.append(artist_name)
                if isinstance(artist_id, str):
                    artist_ids.append(artist_id)

            tracks.append(
                {
                    "spotify_track_id": track.get("id"),
                    "name": name,
                    "artists": artist_names,
                    "artist_ids": artist_ids,
                },
            )

        url = data.get("next")
        params = None

    return tracks


# ---------------------------------------------------------------------------
# Aggregate + blend
# ---------------------------------------------------------------------------

def compute_playlist_artist_ids_frequency(
    tracks: list[dict[str, Any]],
    limit: int = 50,
) -> list[tuple[str, str, float]]:
    """Count artist occurrences by ID across a flat track list.

    Returns top `limit` tuples: [(artist_id, artist_name, frequency_weight_in_0_1), ...].
    """
    counts: Counter[tuple[str, str]] = Counter()  # (id, name)
    for track in tracks:
        names = cast(list[str], track.get("artists") or [])
        ids = cast(list[str], track.get("artist_ids") or [])
        for name, aid in zip(names, ids, strict=False):
            if name.strip() and aid.strip():
                key = (aid.strip(), name.strip())
                counts[key] = counts[key] + 1

    if not counts:
        return []

    top_counts = counts.most_common(limit)
    max_count = top_counts[0][1] if top_counts else 1
    return [
        (aid, name, count / max_count)
        for (aid, name), count in top_counts
    ]



async def fetch_artist_genres_batch(
    client: httpx.AsyncClient,
    access_token: str,
    artist_ids: list[str],
) -> dict[str, list[str]]:
    """Fetch genres for a list of artist IDs using GET /v1/artists.

    Returns {lowercased_artist_name: list_of_genres}.
    """
    if not artist_ids:
        return {}

    # Split into chunks of 50 (Spotify API limit per request)
    chunk_size = 50
    chunks = [
        artist_ids[i : i + chunk_size]
        for i in range(0, len(artist_ids), chunk_size)
    ]
    artist_genres: dict[str, list[str]] = {}
    headers = _auth_header(access_token)

    for chunk in chunks:
        ids_str = ",".join(chunk)
        url = "https://api.spotify.com/v1/artists"
        try:
            resp = await _get_with_retry(
                client,
                url,
                params={"ids": ids_str},
                headers=headers,
            )
            data = cast(dict[str, Any], resp.json())
            artists = cast(list[Any], data.get("artists") or [])
            for artist in artists:
                if not isinstance(artist, dict):
                    continue
                artist_dict = cast(dict[str, Any], artist)
                aid = artist_dict.get("id")
                genres = cast(list[str], artist_dict.get("genres") or [])
                if isinstance(aid, str) and aid.strip():
                    artist_genres[aid.strip()] = [
                        g for g in genres if g.strip()
                    ]

        except Exception:
            logger.exception("Failed to fetch artist genres batch")

    return artist_genres


_GENRE_AFFINITY_MAX_ENTRIES = 30
_GENRE_AFFINITY_MIN_WEIGHT = 0.05

def compute_artist_frequency(tracks: list[dict[str, Any]]) -> dict[str, float]:
    """Count artist occurrences across a flat track list (as produced by
    fetch_playlist_tracks), normalized so the most frequent artist is 1.0.
    """
    counts: Counter[str] = Counter()
    for track in tracks:
        for artist_name in track.get("artists", []):
            if isinstance(artist_name, str) and artist_name.strip():
                counts[artist_name.strip()] += 1

    if not counts:
        return {}

    max_count = max(counts.values())
    return {name: count / max_count for name, count in counts.items()}


def compute_genre_affinity(genre_weights: dict[str, float]) -> dict[str, float]:
    """Normalize the raw rank-weighted genre accumulator into a bounded
    [0, 1]-weighted dict suitable for matching-engine cosine scoring.

    genre_weights: {genre_name: accumulated_rank_weight} as produced by
    fetch_top_artists_ranked. Each genre inherits the rank weight of every
    artist that carries it, so a genre shared by multiple high-ranked artists
    ends up with a higher score than a niche genre of a single mid-tier artist.

    Returns {} if the input is empty or all weights are zero.
    """
    if not genre_weights:
        return {}

    ranked = sorted(genre_weights.items(), key=lambda kv: kv[1], reverse=True)
    top_weight = ranked[0][1]
    if top_weight <= 0.0:
        return {}

    bounded: dict[str, float] = {}
    for genre, weight in ranked[:_GENRE_AFFINITY_MAX_ENTRIES]:
        normalized = round(weight / top_weight, 4)
        if normalized < _GENRE_AFFINITY_MIN_WEIGHT:
            break
        bounded[genre] = normalized

    return bounded


def blend_artist_affinity(
    native_ranked: dict[str, float],
    playlist_freq: dict[str, float],
) -> tuple[dict[str, float], dict[str, str]]:
    """Blend native top-artists rank and playlist-derived frequency into one
    weighted dict, keyed by lowercased artist name for case-insensitive
    matching across users (see Nexus_Engine.engine.calculate_weighted_affinity_match).

    Returns (blended_weights, casing_map): casing_map maps the lowercased
    key back to a display-friendly original-case name, since top_display_names
    and the UI need real casing, not the matching engine's normalized keys.
    """
    casing_map: dict[str, str] = {}
    combined: dict[str, float] = {}

    def _accumulate(source: dict[str, float], source_weight: float) -> None:
        """Executes accumulate operation.

            Args:
                source: Input source parameter.
                source_weight: Input source weight parameter."""
        for name, weight in source.items():
            key = name.strip().lower()
            if not key:
                continue
            casing_map.setdefault(key, name.strip())
            combined[key] = combined.get(key, 0.0) + source_weight * weight

    _accumulate(native_ranked, SPOTIFY_AFFINITY_NATIVE_WEIGHT)
    _accumulate(playlist_freq, SPOTIFY_AFFINITY_PLAYLIST_WEIGHT)

    if not combined:
        return {}, {}

    ranked_items = sorted(combined.items(), key=lambda kv: kv[1], reverse=True)
    top_weight = ranked_items[0][1]
    if top_weight <= 0.0:
        return {}, {}

    bounded: dict[str, float] = {}
    for key, weight in ranked_items[:_ARTIST_AFFINITY_MAX_ENTRIES]:
        normalized = round(weight / top_weight, 4)
        if normalized < _ARTIST_AFFINITY_MIN_WEIGHT:
            break
        bounded[key] = normalized

    return bounded, casing_map


def top_display_names(
    blended: dict[str, float],
    casing_map: dict[str, str],
    n: int = _TOP_ARTISTS_DISPLAY_LIMIT,
) -> list[str]:
    """Top-N artist names in display-friendly original casing."""
    ranked = sorted(blended.items(), key=lambda kv: kv[1], reverse=True)
    return [casing_map.get(key, key) for key, _ in ranked[:n]]


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------


async def _blend_playlist_genres_affinity(
    client: httpx.AsyncClient,
    access_token: str,
    all_tracks: list[dict[str, Any]],
    genre_acc: dict[str, float],
    start_time: float | None = None,
    budget_seconds: float = _SYNC_TIME_BUDGET_SECONDS,
) -> None:
    """Helper to fetch and blend playlist genres to reduce complexity."""
    if not all_tracks:
        return
    if start_time is not None and (time.monotonic() - start_time) > budget_seconds:
        logger.warning("Skipping playlist genre blend: sync time budget exceeded")
        return
    try:
        top_playlist_artists = compute_playlist_artist_ids_frequency(
            all_tracks,
            limit=50,
        )
        target_ids = [aid for aid, _, _ in top_playlist_artists if aid]
        if target_ids:
            if start_time is not None and (time.monotonic() - start_time) > budget_seconds:
                logger.warning("Skipping playlist genre fetch: sync time budget exceeded")
                return
            playlist_genres = await fetch_artist_genres_batch(
                client,
                access_token,
                target_ids,
            )
            for aid, _, freq_weight in top_playlist_artists:
                genres = playlist_genres.get(aid) or []
                for genre in genres:
                    key = genre.strip().lower()
                    genre_acc[key] = (
                        genre_acc.get(key, 0.0)
                        + SPOTIFY_AFFINITY_PLAYLIST_WEIGHT * freq_weight
                    )
    except Exception:
        logger.exception(
            "Failed to fetch/blend playlist genres during full sync",
        )



async def run_full_sync(user_id: str, access_token: str, spotify_user_id: str) -> None:
    """Full playlist + artist-affinity + genre-affinity sync for one user.

    Runs via FastAPI BackgroundTasks from the OAuth callback, native
    exchange, and /resync endpoints, so the triggering HTTP response returns
    immediately. Best-effort: partial results (e.g. some playlists synced
    before the time budget is exceeded) are still persisted rather than
    discarded, and a native-only signal is saved even if playlist fetching
    fails entirely, so matching isn't left blank.
    """
    start = time.monotonic()

    try:
        top_artists_result = await fetch_top_artists_ranked(access_token)
    except Exception:
        logger.exception(
            "Native top-artists fetch failed during sync",
            extra={"user_id": user_id},
        )
        top_artists_result = TopArtistsResult(ranked={}, genre_weights={})

    native_ranked = top_artists_result.ranked
    genre_affinity = compute_genre_affinity(top_artists_result.genre_weights)

    playlists_with_tracks: list[dict[str, Any]] = []
    all_tracks: list[dict[str, Any]] = []

    # Blend genre affinity from native top artists
    genre_acc: dict[str, float] = {}
    for genre, weight in top_artists_result.genre_weights.items():
        genre_acc[genre] = (
            genre_acc.get(genre, 0.0) + SPOTIFY_AFFINITY_NATIVE_WEIGHT * weight
        )

    try:
        async with httpx.AsyncClient(timeout=_HTTP_TIMEOUT_SECONDS) as client:
            candidate_playlists = await fetch_owned_or_collaborative_playlists(
                client,
                access_token,
                spotify_user_id,
            )
            for playlist in candidate_playlists:
                if time.monotonic() - start > _SYNC_TIME_BUDGET_SECONDS:
                    logger.warning(
                        "Spotify sync time budget exceeded, persisting partial results",
                        extra={"user_id": user_id},
                    )
                    break
                try:
                    tracks = await fetch_playlist_tracks(
                        client,
                        access_token,
                        playlist["spotify_playlist_id"],
                    )
                except Exception:
                    logger.exception(
                        "Playlist track fetch failed, skipping playlist",
                        extra={
                            "user_id": user_id,
                            "playlist_id": playlist["spotify_playlist_id"],
                        },
                    )
                    continue
                playlists_with_tracks.append({**playlist, "tracks": tracks})
                all_tracks.extend(tracks)

            # Blend genre affinity from playlists using the existing HTTP client if budget allows
            if (time.monotonic() - start) < _SYNC_TIME_BUDGET_SECONDS:
                await _blend_playlist_genres_affinity(
                    client,
                    access_token,
                    all_tracks,
                    genre_acc,
                    start_time=start,
                    budget_seconds=_SYNC_TIME_BUDGET_SECONDS,
                )
            else:
                logger.warning(
                    "Skipping playlist genre blend: sync time budget exceeded",
                    extra={"user_id": user_id},
                )
    except Exception as e:
        logger.exception("Spotify playlist sync failed", extra={"user_id": user_id})
        await asyncio.to_thread(mark_sync_result, user_id, "error", str(e)[:500])
        if native_ranked:
            # Still persist a native-only signal so matching isn't blank
            # while the underlying playlist-fetch issue gets resolved.
            blended, casing_map = blend_artist_affinity(native_ranked, {})
            display_names = top_display_names(blended, casing_map)
            await asyncio.to_thread(
                persist_artist_signals,
                user_id,
                blended,
                display_names,
                genre_affinity,
            )
        return

    playlist_freq = compute_artist_frequency(all_tracks)
    blended, casing_map = blend_artist_affinity(native_ranked, playlist_freq)
    display_names = top_display_names(blended, casing_map)

    genre_affinity = compute_genre_affinity(genre_acc)

    await asyncio.to_thread(
        persist_artist_signals,
        user_id,
        blended,
        display_names,
        genre_affinity,
    )
    await asyncio.to_thread(
        replace_playlists,
        user_id,
        playlists_with_tracks,
    )
    await asyncio.to_thread(
        mark_sync_result,
        user_id,
        "ok",
    )
