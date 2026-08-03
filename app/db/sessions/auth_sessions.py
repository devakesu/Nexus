"""Discovery session creation, lookup, and expiration management persistence layer."""

import logging
from datetime import datetime, timedelta
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import DiscoveryTab
from app.db.client import (
    DatabaseAccessError,
    parse_utc_datetime,
    supabase_client,
    utcnow,
)
from app.db.discovery import assign_orbit_positions, coerce_float, coerce_score

logger = logging.getLogger(__name__)


def create_discovery_session(
    viewer_id: str,
    active_tab: DiscoveryTab,
    filters: dict[str, Any],
    ranked_items: list[dict[str, Any]],
    expires_in_minutes: int = 60,
) -> tuple[str, datetime]:
    """Creates a new discovery session and persists ranked candidate items."""
    expires_at = utcnow() + timedelta(minutes=expires_in_minutes)

    positioned_items = assign_orbit_positions(
        viewer_id=viewer_id,
        active_tab=active_tab,
        ranked_items=ranked_items,
    )

    from app.db.spotify import get_connection

    connection = get_connection(viewer_id)
    if connection is not None:
        viewer_spotify_connected = not connection.get("disconnected_at")
    else:
        viewer_spotify_connected = (
            bool(positioned_items[0].get("viewer_spotify_connected", False))
            if positioned_items
            else False
        )

    items_payload: list[dict[str, Any]] = []
    for position, item in enumerate(positioned_items):
        profile_raw = item.get("profile")
        profile = (
            cast(dict[str, Any], profile_raw) if isinstance(profile_raw, dict) else {}
        )
        candidate_id = profile.get("id")
        if not candidate_id:
            continue

        grade_raw = item.get("music_match_grade")
        music_match_grade = int(grade_raw) if grade_raw is not None else None

        items_payload.append(
            {
                "position": position,
                "candidate_id": str(candidate_id),
                "score": coerce_score(item.get("score")),
                "x": coerce_float(item.get("_x")),
                "y": coerce_float(item.get("_y")),
                "orbit_tier": int(coerce_float(item.get("_orbit_tier"), 3.0)),
                "music_match_grade": music_match_grade,
                "candidate_spotify_connected": bool(
                    item.get("candidate_spotify_connected", False),
                ),
            },
        )

    try:
        res = supabase_client.rpc(
            "create_discovery_session_with_items",
            {
                "p_viewer_id": viewer_id,
                "p_tab": active_tab,
                "p_filters": filters or {},
                "p_expires_at": expires_at.isoformat(),
                "p_viewer_spotify_connected": viewer_spotify_connected,
                "p_items": items_payload,
            },
        ).execute()
        session_id = str(res.data)
        if not session_id or session_id == "None":
            raise DatabaseAccessError("Failed to create discovery session")
        return session_id, expires_at
    except APIError as e:
        logger.exception(
            "Failed to create discovery session via RPC",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError("Failed to create discovery session") from e
    except Exception as e:
        logger.exception(
            "Unexpected discovery session creation failure via RPC",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError(
            "Unexpected discovery session creation failure",
        ) from e


def get_discovery_session(
    session_id: str,
    viewer_id: str,
    active_tab: DiscoveryTab,
) -> dict[str, Any] | None:
    """Fetch discovery session record by session_id, viewer_id, and tab."""
    try:
        res = (
            supabase_client.table("discovery_sessions")
            .select("id, viewer_id, tab, expires_at")
            .eq("id", session_id)
            .eq("viewer_id", viewer_id)
            .eq("tab", active_tab)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch discovery session",
            extra={
                "viewer_id": viewer_id,
                "active_tab": active_tab,
                "session_id": session_id,
            },
        )
        raise DatabaseAccessError("Failed to fetch discovery session") from e
    except Exception as e:
        logger.exception(
            "Unexpected discovery session lookup failure",
            extra={
                "viewer_id": viewer_id,
                "active_tab": active_tab,
                "session_id": session_id,
            },
        )
        raise DatabaseAccessError("Unexpected discovery session lookup failure") from e

    rows = cast(list[Any], res.data or [])
    row = rows[0] if rows else None
    return cast(dict[str, Any], row) if isinstance(row, dict) else None


def get_discovery_session_by_id(
    session_id: str,
    viewer_id: str,
) -> dict[str, Any] | None:
    """Fetch discovery session metadata by session_id and viewer_id."""
    try:
        response = (
            supabase_client.table("discovery_sessions")
            .select("id, viewer_id, tab, filters, expires_at, created_at")
            .eq("id", session_id)
            .eq("viewer_id", viewer_id)
            .maybe_single()
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch discovery session by id",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
            },
        )
        raise DatabaseAccessError("Failed to fetch discovery session") from e
    except Exception as e:
        logger.exception(
            "Unexpected discovery session lookup failure",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
            },
        )
        raise DatabaseAccessError("Unexpected discovery session lookup failure") from e

    if response is None:
        return None

    row = response.data
    if row is None:
        return None

    if not isinstance(row, dict):
        raise DatabaseAccessError("Discovery session lookup returned malformed data")

    return cast(dict[str, Any], row)


def delete_expired_discovery_sessions() -> int:
    """Delete expired discovery sessions. Session items cascade automatically."""
    try:
        res = (
            supabase_client.table("discovery_sessions")
            .delete()
            .lte("expires_at", utcnow().isoformat())
            .execute()
        )
        deleted_rows = cast(list[Any], res.data or [])
        return len(deleted_rows)
    except APIError as e:
        logger.exception("Failed to delete expired discovery sessions")
        raise DatabaseAccessError("Failed to delete expired discovery sessions") from e
    except Exception as e:
        logger.exception("Unexpected expired discovery session cleanup failure")
        raise DatabaseAccessError(
            "Unexpected expired discovery session cleanup failure",
        ) from e


def verify_session_not_expired(session: dict[str, Any]) -> bool:
    """Verify session is not expired."""
    expires_at_raw = session.get("expires_at")
    if not isinstance(expires_at_raw, (str, datetime)):
        return False
    return parse_utc_datetime(expires_at_raw) > utcnow()


_verify_session_not_expired = verify_session_not_expired


def is_candidate_in_active_session(viewer_id: str, candidate_id: str) -> bool:
    """Checks whether a candidate is present in an active session for the viewer."""
    try:
        now = utcnow()
        res = (
            supabase_client.table("discovery_session_items")
            .select("session_id, discovery_sessions!inner(viewer_id, expires_at)")
            .eq("candidate_id", candidate_id)
            .eq("discovery_sessions.viewer_id", viewer_id)
            .gt("discovery_sessions.expires_at", now.isoformat())
            .limit(1)
            .execute()
        )
        return bool(res.data)
    except Exception:
        logger.exception(
            "Error checking active session for candidate",
            extra={"viewer_id": viewer_id, "candidate_id": candidate_id},
        )
        return False
