import logging
from datetime import datetime, timedelta
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import DiscoveryTab
from app.db.client import (
    DatabaseAccessError,
    ProfileDecodeError,
    parse_utc_datetime,
    supabase_client,
    utcnow,
)
from app.db.exclusions import get_cached_active_block_ids
from app.db.orbit import assign_orbit_positions, coerce_float, coerce_score
from app.db.profiles import decrypt_profile_record, sanitize_decrypted_profile

logger = logging.getLogger(__name__)


def create_discovery_session(
    viewer_id: str,
    active_tab: DiscoveryTab,
    filters: dict[str, Any],
    ranked_items: list[dict[str, Any]],
    expires_in_minutes: int = 60,
) -> tuple[str, datetime]:
    expires_at = utcnow() + timedelta(minutes=expires_in_minutes)

    positioned_items = assign_orbit_positions(
        viewer_id=viewer_id,
        active_tab=active_tab,
        ranked_items=ranked_items,
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

        items_payload.append(
            {
                "position": position,
                "candidate_id": str(candidate_id),
                "score": coerce_score(item.get("score")),
                "x": coerce_float(item.get("_x")),
                "y": coerce_float(item.get("_y")),
                "orbit_tier": int(coerce_float(item.get("_orbit_tier"), 3.0)),
            },
        )

    try:
        res = (
            supabase_client.rpc(
                "create_discovery_session_with_items",
                {
                    "p_viewer_id": viewer_id,
                    "p_tab": active_tab,
                    "p_filters": filters or {},
                    "p_expires_at": expires_at.isoformat(),
                    "p_items": items_payload,
                },
            )
            .execute()
        )
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


async def _filter_and_sort_viewport_items(
    rows: list[Any],
    viewer_id: str,
    center_x: float,
    center_y: float,
    radius: float,
) -> list[dict[str, Any]]:
    # Note: Double exclusion filtering is intentional here. Exclusions (hide,
    # pass, like, superlike) are pre-filtered at session generation time.
    # However, we re-fetch and re-check block IDs from Redis here to catch
    # any new user blocks created since the session snapshot was frozen.
    hard_excluded = await get_cached_active_block_ids(viewer_id)
    radius_sq = radius**2
    result: list[dict[str, Any]] = []

    for row_raw in rows:
        if not isinstance(row_raw, dict):
            continue
        row = cast(dict[str, Any], row_raw)

        profile_raw = row.get("profiles")
        profile = (
            cast(dict[str, Any], profile_raw) if isinstance(profile_raw, dict) else None
        )
        if profile is None:
            continue

        cid = str(cast(object, profile.get("id") or row.get("candidate_id") or ""))
        if not cid or cid in hard_excluded:
            continue

        if profile.get("is_deactivated") is True:
            continue

        x = coerce_float(row.get("x"))
        y = coerce_float(row.get("y"))
        dx = x - center_x
        dy = y - center_y

        if dx * dx + dy * dy <= radius_sq:
            result.append(
                {
                    "id": cid,
                    "name": None,
                    "profile_pic": None,
                    "score": coerce_score(row.get("score")),
                    "orbit_tier": int(coerce_float(row.get("orbit_tier"), 3.0)),
                    "x": x,
                    "y": y,
                },
            )

    result.sort(
        key=lambda r: (
            r.get("orbit_tier", 99),
            -coerce_score(r.get("score")),
            str(r.get("id") or ""),
        ),
    )
    return result


def _fetch_total_session_items_count(session_id: str, viewer_id: str) -> int:
    try:
        count_res = (
            supabase_client.table("discovery_session_items")
            .select("candidate_id, discovery_sessions!inner(viewer_id)", count="exact")  # type: ignore[arg-type]
            .eq("session_id", session_id)
            .eq("discovery_sessions.viewer_id", viewer_id)
            .limit(1)
            .execute()
        )
        return int(count_res.count or 0)
    except APIError as e:
        logger.exception(
            "Failed to count spatial session items",
            extra={"session_id": session_id, "viewer_id": viewer_id},
        )
        raise DatabaseAccessError("Failed to count spatial session items") from e
    except Exception as e:
        logger.exception(
            "Unexpected spatial session count failure",
            extra={"session_id": session_id, "viewer_id": viewer_id},
        )
        raise DatabaseAccessError("Unexpected spatial session count failure") from e


async def fetch_spatial_viewport(
    session_id: str,
    viewer_id: str,
    center_x: float,
    center_y: float,
    radius: float,
) -> tuple[list[dict[str, Any]], int]:
    """
    Fetch session items within a circular viewport using bounding box
    pre-filter then distance check.
    """
    x_min, x_max = center_x - radius, center_x + radius
    y_min, y_max = center_y - radius, center_y + radius

    try:
        res = (
            supabase_client.table("discovery_session_items")
            .select(
                """
                candidate_id,
                score,
                x,
                y,
                orbit_tier,
                profiles:candidate_id (
                    id,
                    is_deactivated
                ),
                discovery_sessions!inner (
                    viewer_id
                )
                """,
            )
            .eq("session_id", session_id)
            .eq("discovery_sessions.viewer_id", viewer_id)
            .gte("x", x_min)
            .lte("x", x_max)
            .gte("y", y_min)
            .lte("y", y_max)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch spatial viewport",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "center_x": center_x,
                "center_y": center_y,
                "radius": radius,
            },
        )
        raise DatabaseAccessError("Failed to fetch spatial viewport") from e
    except Exception as e:
        logger.exception(
            "Unexpected spatial viewport fetch failure",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "center_x": center_x,
                "center_y": center_y,
                "radius": radius,
            },
        )
        raise DatabaseAccessError("Unexpected spatial viewport fetch failure") from e

    rows = cast(list[Any], res.data or [])
    result = await _filter_and_sort_viewport_items(
        rows=rows,
        viewer_id=viewer_id,
        center_x=center_x,
        center_y=center_y,
        radius=radius,
    )
    total_count = _fetch_total_session_items_count(session_id, viewer_id)

    return result, total_count


def delete_expired_discovery_sessions() -> int:
    """
    Delete expired discovery sessions. Session items cascade automatically.
    """
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


def _verify_session_not_expired(session: dict[str, Any]) -> bool:
    expires_at_raw = session.get("expires_at")
    if not isinstance(expires_at_raw, (str, datetime)):
        return False
    return parse_utc_datetime(expires_at_raw) > utcnow()


def _build_node_detail_payload(
    row: dict[str, Any],
    profile: dict[str, Any],
    cid: str,
    session_id: str,
    viewer_id: str,
    candidate_id: str,
) -> dict[str, Any]:
    from app.core.crypto import DecryptFailedError

    try:
        hydrated_profile = decrypt_profile_record(profile)
        hydrated_profile = sanitize_decrypted_profile(hydrated_profile)
    except (DecryptFailedError, ProfileDecodeError):
        logger.exception(
            "Failed to decrypt orbit node detail profile",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "candidate_id": candidate_id,
            },
        )
        raise

    payload: dict[str, Any] = {
        "id": str(hydrated_profile.get("id") or cid),
        "name": hydrated_profile.get("name"),
        "age": hydrated_profile.get("age"),
        "bio": hydrated_profile.get("bio"),
        "campus_branch": hydrated_profile.get("campus_branch"),
        "campus_year": hydrated_profile.get("campus_year"),
        "campus_name": hydrated_profile.get("campus_name"),
        "role_at": hydrated_profile.get("role_at"),
        "profile_pic": hydrated_profile.get("profile_pic"),
        "normal_pics": hydrated_profile.get("normal_pics") or [],
        "display_gender": hydrated_profile.get("display_gender"),
        "display_sexuality": hydrated_profile.get("display_sexuality"),
        "drinking": hydrated_profile.get("drinking"),
        "smoking": hydrated_profile.get("smoking"),
        "hometown": hydrated_profile.get("hometown"),
        "current_place": hydrated_profile.get("current_place"),
        "pronouns": hydrated_profile.get("pronouns"),
        "partner_values": hydrated_profile.get("partner_values"),
        "children_plans": hydrated_profile.get("children_plans"),
        "religious_beliefs": hydrated_profile.get("religious_beliefs"),
        "lifestyle": hydrated_profile.get("lifestyle"),
        "activities": hydrated_profile.get("activities") or [],
        "looking_for": hydrated_profile.get("looking_for") or [],
        "dating_for": hydrated_profile.get("dating_for") or [],
        "causes_supported": hydrated_profile.get("causes_supported") or [],
        "top_artists": hydrated_profile.get("top_artists") or [],
        "tech_skills": hydrated_profile.get("tech_skills") or [],
        "languages": hydrated_profile.get("languages") or [],
        "interests": hydrated_profile.get("interests") or {},
        "sub_interests": hydrated_profile.get("sub_interests") or {},
        "ai_vibe_tags": hydrated_profile.get("ai_vibe_tags") or [],
        "pets": hydrated_profile.get("pets") or [],
        "hidden_profile_fields": hydrated_profile.get("hidden_profile_fields") or [],
        "score": coerce_score(row.get("score")),
        "x": coerce_float(row.get("x")),
        "y": coerce_float(row.get("y")),
        "orbit_tier": int(coerce_float(row.get("orbit_tier"), 3.0)),
    }
    return payload


async def fetch_discovery_node_detail(
    session_id: str,
    viewer_id: str,
    candidate_id: str,
) -> tuple[DiscoveryTab, dict[str, Any]] | None:
    """
    Return (session_tab, hydrated_profile_payload) for a clicked discovery node.
    Returns None when the session/item/profile is not available to the viewer.
    """
    try:
        res = (
            supabase_client.table("discovery_session_items")
            .select(
                """
                candidate_id,
                score,
                x,
                y,
                orbit_tier,
                profiles:candidate_id (
                    id,
                    name,
                    age,
                    bio,
                    campus_branch,
                    campus_year,
                    campus_name,
                    role_at,
                    profile_pic,
                    normal_pics,
                    display_gender,
                    display_sexuality,
                    drinking,
                    smoking,
                    hometown,
                    current_place,
                    pronouns,
                    partner_values,
                    children_plans,
                    religious_beliefs,
                    lifestyle,
                    activities,
                    looking_for,
                    dating_for,
                    causes_supported,
                    top_artists,
                    tech_skills,
                    languages,
                    interests,
                    sub_interests,
                    ai_vibe_tags,
                    pets,
                    hidden_profile_fields,
                    is_deactivated
                ),
                discovery_sessions!inner (
                    id,
                    viewer_id,
                    tab,
                    expires_at
                )
                """,
            )
            .eq("session_id", session_id)
            .eq("candidate_id", candidate_id)
            .eq("discovery_sessions.viewer_id", viewer_id)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch discovery node detail",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "candidate_id": candidate_id,
            },
        )
        raise DatabaseAccessError("Failed to fetch discovery node detail") from e
    except Exception as e:
        logger.exception(
            "Unexpected discovery node detail failure",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "candidate_id": candidate_id,
            },
        )
        raise DatabaseAccessError("Unexpected discovery node detail failure") from e

    rows = cast(list[Any], res.data or [])
    row_raw = rows[0] if rows else None
    if not isinstance(row_raw, dict):
        return None
    row = cast(dict[str, Any], row_raw)

    validated = await _validate_discovery_node_data(row, viewer_id)
    if not validated:
        return None

    session_tab, profile, cid = validated

    payload = _build_node_detail_payload(
        row=row,
        profile=profile,
        cid=cid,
        session_id=session_id,
        viewer_id=viewer_id,
        candidate_id=candidate_id,
    )

    return session_tab, payload


async def _validate_discovery_node_data(
    row: dict[str, Any],
    viewer_id: str,
) -> tuple[DiscoveryTab, dict[str, Any], str] | None:
    session_raw = row.get("discovery_sessions")
    session = (
        cast(dict[str, Any], session_raw) if isinstance(session_raw, dict) else None
    )
    if session is None:
        return None

    session_tab_raw = session.get("tab")
    if session_tab_raw not in {"Dating", "Friends", "Professional"}:
        return None

    if not _verify_session_not_expired(session):
        return None

    profile_raw = row.get("profiles")
    profile = (
        cast(dict[str, Any], profile_raw) if isinstance(profile_raw, dict) else None
    )
    if profile is None:
        return None

    if profile.get("is_deactivated") is True:
        return None

    hard_excluded = await get_cached_active_block_ids(viewer_id)
    cid = str(cast(object, profile.get("id") or row.get("candidate_id") or ""))
    if not cid or cid in hard_excluded:
        return None

    return cast(DiscoveryTab, session_tab_raw), profile, cid


def is_candidate_in_active_session(viewer_id: str, candidate_id: str) -> bool:
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
