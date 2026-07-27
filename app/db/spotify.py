"""
Persistence layer for the Spotify connection, playlists, and the derived
matching-engine signal (profiles.artist_affinity).

Privacy boundary: artist_affinity is a matching-engine-only field. It must
only ever be read here and in app/db/profiles.py's _PROFILE_SELECT_COLUMNS
(the scoring hot path) - never added to fetch_peer_profile_by_id or
app/db/sessions.py's fetch_discovery_node_detail, which back every
peer-facing profile view.
"""

import json
import logging
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.security.crypto import DecryptFailedError, decrypt_pii, encrypt_to_hex
from app.db.client import DatabaseAccessError, supabase_client, utcnow

logger = logging.getLogger(__name__)


def get_connection(user_id: str) -> dict[str, Any] | None:
    """Fetch the caller's Spotify connection row, or None if never connected."""
    try:
        res = (
            supabase_client.table("spotify_connections")
            .select(
                "user_id, spotify_user_id, refresh_token, granted_scopes, "
                "connected_at, last_synced_at, last_sync_status, last_sync_error",
            )
            .eq("user_id", user_id)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch spotify connection",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to fetch Spotify connection") from e

    rows = cast(list[Any], res.data or [])
    if not rows or not isinstance(rows[0], dict):
        return None
    return cast(dict[str, Any], rows[0])


def get_decrypted_refresh_token(user_id: str) -> str | None:
    """Fetch + decrypt the caller's stored refresh token, if any."""
    connection = get_connection(user_id)
    if connection is None:
        return None
    raw = connection.get("refresh_token")
    if not raw:
        return None
    try:
        return decrypt_pii(raw)
    except DecryptFailedError:
        logger.exception(
            "Failed to decrypt spotify refresh token",
            extra={"user_id": user_id},
        )
        return None


def upsert_connection(
    user_id: str,
    spotify_user_id: str,
    refresh_token_plain: str,
    scopes: str,
) -> None:
    """Insert or update the caller's Spotify connection, encrypting the token."""
    try:
        supabase_client.table("spotify_connections").upsert(
            {
                "user_id": user_id,
                "spotify_user_id": spotify_user_id,
                "refresh_token": encrypt_to_hex(refresh_token_plain),
                "granted_scopes": scopes,
                "disconnected_at": None,
            },
            on_conflict="user_id",
        ).execute()
    except APIError as e:
        logger.exception(
            "Failed to upsert spotify connection",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to save Spotify connection") from e


def mark_sync_result(user_id: str, status: str, error: str | None = None) -> None:
    """Record the outcome of the most recent sync attempt on the connection row.

    Best-effort: a failure here shouldn't fail the sync itself, since the
    actual artist/playlist data may already have been persisted successfully.
    """
    try:
        supabase_client.table("spotify_connections").update(
            {
                "last_synced_at": utcnow().isoformat(),
                "last_sync_status": status,
                "last_sync_error": error,
            },
        ).eq("user_id", user_id).execute()
    except APIError:
        logger.exception(
            "Failed to record spotify sync result",
            extra={"user_id": user_id, "status": status},
        )


def disconnect(user_id: str) -> None:
    """Fully revoke a Spotify connection.

    Deletes the stored refresh token and all synced playlists, and clears
    every derived signal (artist_affinity, genre_affinity, top_artists,
    music_taste_synced_at) from the profile. A partial revoke would leave
    a stale public top_artists list visible to peers after the user explicitly
    asked to disconnect.
    """
    try:
        supabase_client.table("spotify_connections").delete().eq(
            "user_id",
            user_id,
        ).execute()
        supabase_client.table("spotify_playlists").delete().eq(
            "user_id",
            user_id,
        ).execute()
        supabase_client.table("profiles").update(
            {
                "artist_affinity": None,
                "genre_affinity": None,
                "top_artists": None,
                "music_taste_synced_at": None,
            },
        ).eq("id", user_id).execute()
    except APIError as e:
        logger.exception("Failed to disconnect spotify", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to disconnect Spotify") from e


def replace_playlists(user_id: str, playlists: list[dict[str, Any]]) -> None:
    """Upsert the given playlists and prune ones no longer present.

    Each playlist dict: {spotify_playlist_id, name, is_collaborative,
    track_count, tracks: list[dict]}. Playlists the user deleted or left
    since the last sync are removed from spotify_playlists entirely.
    """
    now_iso = utcnow().isoformat()
    rows = [
        {
            "user_id": user_id,
            "spotify_playlist_id": p["spotify_playlist_id"],
            "name": encrypt_to_hex(p["name"]),
            "is_collaborative": bool(p.get("is_collaborative", False)),
            "track_count": int(p.get("track_count", 0)),
            "tracks": encrypt_to_hex(json.dumps(p.get("tracks", []))),
            "synced_at": now_iso,
        }
        for p in playlists
    ]

    try:
        if rows:
            supabase_client.table("spotify_playlists").upsert(
                rows,
                on_conflict="user_id, spotify_playlist_id",
            ).execute()

        synced_ids = [p["spotify_playlist_id"] for p in playlists]
        query = (
            supabase_client.table("spotify_playlists")
            .delete()
            .eq(
                "user_id",
                user_id,
            )
        )
        if synced_ids:
            query = query.not_.in_("spotify_playlist_id", synced_ids)
        query.execute()
    except APIError as e:
        logger.exception(
            "Failed to persist spotify playlists",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to save Spotify playlists") from e


def fetch_playlists_for_owner(user_id: str) -> list[dict[str, Any]]:
    """Return the caller's own playlists, fully decrypted.

    Only ever called from the owner-scoped GET /api/v1/spotify/playlists
    endpoint - never from any peer-facing code path.
    """
    try:
        res = (
            supabase_client.table("spotify_playlists")
            .select(
                "id, spotify_playlist_id, name, is_collaborative, "
                "track_count, tracks, synced_at",
            )
            .eq("user_id", user_id)
            .order("synced_at", desc=True)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch spotify playlists",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to fetch Spotify playlists") from e

    rows = cast(list[Any], res.data or [])
    playlists: list[dict[str, Any]] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        row_dict = cast(dict[str, Any], row)

        try:
            row_dict["name"] = decrypt_pii(row_dict.get("name"))
        except DecryptFailedError:
            row_dict["name"] = ""

        raw_tracks = row_dict.get("tracks")
        try:
            decrypted_tracks = decrypt_pii(raw_tracks) if raw_tracks else ""
            row_dict["tracks"] = (
                json.loads(decrypted_tracks) if decrypted_tracks else []
            )
        except (DecryptFailedError, json.JSONDecodeError):
            row_dict["tracks"] = []

        playlists.append(row_dict)
    return playlists


def persist_artist_signals(
    user_id: str,
    artist_affinity: dict[str, float],
    top_artists: list[str],
    genre_affinity: dict[str, float] | None = None,
) -> None:
    """Write the blended matching-engine signals and the bounded public display list."""
    payload: dict[str, Any] = {
        "artist_affinity": encrypt_to_hex(json.dumps(artist_affinity)),
        "top_artists": encrypt_to_hex(json.dumps(top_artists)),
        "music_taste_synced_at": utcnow().isoformat(),
    }
    if genre_affinity is not None:
        payload["genre_affinity"] = encrypt_to_hex(json.dumps(genre_affinity))
    try:
        supabase_client.table("profiles").update(payload).eq(
            "id", user_id,
        ).execute()
    except APIError as e:
        logger.exception(
            "Failed to persist spotify artist signals",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to save Spotify artist data") from e
