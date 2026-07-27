"""Discovery spatial viewport querying, distance filtering, and count calculations."""

import logging
from typing import Any, cast

from postgrest.exceptions import APIError
from postgrest.types import CountMethod

from app.db.client import DatabaseAccessError, supabase_client
from app.db.discovery import coerce_float, coerce_score, get_cached_active_block_ids
from app.db.profiles import decrypt_profile_rows

logger = logging.getLogger(__name__)


async def _filter_and_sort_viewport_items(
    rows: list[Any],
    viewer_id: str,
    center_x: float,
    center_y: float,
    radius: float,
) -> list[dict[str, Any]]:
    """Filter and sort spatial viewport items by radial distance."""
    hard_excluded = await get_cached_active_block_ids(viewer_id)
    radius_sq = radius**2
    candidates: list[dict[str, Any]] = []
    profiles_data: list[Any] = []

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
            candidates.append({"cid": cid, "row": row, "x": x, "y": y})
            profiles_data.append(profile)

    profile_map = decrypt_profile_rows(profiles_data)

    result: list[dict[str, Any]] = [
        {
            "id": item["cid"],
            "name": profile_map.get(item["cid"], {}).get("name"),
            "profile_pic": profile_map.get(item["cid"], {}).get("profile_pic"),
            "score": coerce_score(item["row"].get("score")),
            "orbit_tier": int(coerce_float(item["row"].get("orbit_tier"), 3.0)),
            "x": item["x"],
            "y": item["y"],
        }
        for item in candidates
    ]

    result.sort(
        key=lambda r: (
            r.get("orbit_tier", 99),
            -coerce_score(r.get("score")),
            str(r.get("id") or ""),
        ),
    )
    return result


def _fetch_total_session_items_count(session_id: str, viewer_id: str) -> int:
    """Fetch total count of discovery session items."""
    try:
        count_res = (
            supabase_client.table("discovery_session_items")
            .select("candidate_id, discovery_sessions!inner(viewer_id)", count=CountMethod.exact)
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
    """Fetch session items within a circular viewport using bounding box pre-filter."""
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
                    name,
                    profile_pic,
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
