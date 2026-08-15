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

_MAX_ACTIVE_DISCOVERY_SESSIONS_PER_VIEWER = 5


def prune_excess_viewer_discovery_sessions(
    viewer_id: str,
    max_active: int = _MAX_ACTIVE_DISCOVERY_SESSIONS_PER_VIEWER,
) -> None:
    """Prunes older active discovery sessions if viewer exceeds max_active limit."""
    try:
        res = (
            supabase_client.table("discovery_sessions")
            .select("id, created_at")
            .eq("viewer_id", viewer_id)
            .gt("expires_at", utcnow().isoformat())
            .order("created_at", desc=True)
            .execute()
        )
        active_sessions = cast(list[dict[str, Any]], res.data or [])
        if len(active_sessions) >= max_active:
            # Keep newest (max_active - 1) so new session brings total to max_active
            sessions_to_delete = [
                str(s["id"]) for s in active_sessions[max_active - 1 :]
            ]
            if sessions_to_delete:
                supabase_client.table("discovery_sessions").delete().in_(
                    "id", sessions_to_delete,
                ).execute()
    except Exception as e:
        logger.warning(
            "Failed to prune excess discovery sessions for viewer",
            extra={"viewer_id": viewer_id, "error": str(e)},
        )


def create_discovery_session(
    viewer_id: str,
    active_tab: DiscoveryTab,
    filters: dict[str, Any],
    ranked_items: list[dict[str, Any]],
    expires_in_minutes: int = 60,
) -> tuple[str, datetime]:
    """Creates a new discovery session and persists ranked candidate items."""
    prune_excess_viewer_discovery_sessions(viewer_id)
    expires_at = utcnow() + timedelta(minutes=expires_in_minutes)

    positioned_items = assign_orbit_positions(
        viewer_id=viewer_id,
        active_tab=active_tab,
        ranked_items=ranked_items,
    )

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
        response = (
            supabase_client.table("discovery_sessions")
            .select("id, viewer_id, tab, expires_at")
            .eq("id", session_id)
            .eq("viewer_id", viewer_id)
            .eq("tab", active_tab)
            .maybe_single()
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

    if response is None:
        return None

    row = response.data
    if row is None:
        return None

    if not isinstance(row, dict):
        raise DatabaseAccessError("Discovery session lookup returned malformed data")

    return cast(dict[str, Any], row)


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


def invalidate_viewer_discovery_sessions(viewer_id: str) -> None:
    """Invalidates/deletes all active discovery sessions for a viewer."""
    try:
        supabase_client.table("discovery_sessions").delete().eq(
            "viewer_id", viewer_id,
        ).execute()
    except APIError as e:
        logger.exception(
            "Failed to invalidate discovery sessions for viewer",
            extra={"viewer_id": viewer_id},
        )
        raise DatabaseAccessError("Failed to invalidate discovery sessions") from e
    except Exception as e:
        logger.exception(
            "Unexpected error invalidating discovery sessions for viewer",
            extra={"viewer_id": viewer_id},
        )
        raise DatabaseAccessError(
            "Unexpected error invalidating discovery sessions",
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


def get_candidate_session_details(viewer_id: str, candidate_id: str) -> dict[str, Any] | None:
    """Retrieves session details for a candidate associated with the viewer."""
    try:
        res = (
            supabase_client.table("discovery_session_items")
            .select("session_id, discovery_sessions!inner(viewer_id, expires_at)")
            .eq("candidate_id", candidate_id)
            .eq("discovery_sessions.viewer_id", viewer_id)
            .limit(1)
            .execute()
        )
        if res.data:
            item = cast(dict[str, Any], res.data[0])
            ds = cast(dict[str, Any], item.get("discovery_sessions") or {})
            expires_at_val = ds.get("expires_at")
            return {
                "session_id": str(item.get("session_id") or ""),
                "expires_at": parse_utc_datetime(str(expires_at_val)) if expires_at_val else None,
            }
        return None
    except Exception:
        logger.exception(
            "Error fetching session details for candidate",
            extra={"viewer_id": viewer_id, "candidate_id": candidate_id},
        )
        return None

