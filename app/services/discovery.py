import logging
from datetime import datetime
from typing import Any

from fastapi import HTTPException

from app.core.config import DiscoveryTab
from app.db.client import parse_utc_datetime, utcnow
from app.db.profiles import fetch_stage_1_candidates
from app.db.sessions import (
    create_discovery_session,
    get_discovery_session,
    get_discovery_session_by_id,
)
from Nexus_Engine import engine

logger = logging.getLogger(__name__)


def get_or_validate_session(
    session_id: str,
    user_id: str,
    active_tab: DiscoveryTab | None = None,
) -> tuple[str, datetime]:
    if active_tab is not None:
        session = get_discovery_session(
            session_id=session_id,
            viewer_id=user_id,
            active_tab=active_tab,
        )
    else:
        session = get_discovery_session_by_id(
            session_id=session_id,
            viewer_id=user_id,
        )

    if not session:
        raise HTTPException(status_code=404, detail="Discovery session not found.")

    expires_at_raw = session.get("expires_at")
    if not isinstance(expires_at_raw, (str, datetime)):
        raise HTTPException(
            status_code=500,
            detail="Discovery session expiry malformed.",
        )
    expires_at = parse_utc_datetime(expires_at_raw)

    if expires_at <= utcnow():
        raise HTTPException(
            status_code=410,
            detail="Discovery session expired. Please refresh.",
        )

    return session_id, expires_at


def create_new_discovery_session(
    user_id: str,
    active_tab: DiscoveryTab,
    filters: Any,
) -> tuple[str, datetime]:
    viewer, candidate_pool = fetch_stage_1_candidates(
        viewer_id=user_id,
        active_tab=active_tab,
        filters=filters,
        candidate_limit=200,
    )

    if viewer is None:
        raise HTTPException(
            status_code=404,
            detail="Target user profile unpopulated.",
        )

    ranked_orbit: list[dict[str, Any]] = engine.discover_orbit(
        viewer,
        active_tab,
        candidate_pool,
        orbit_limit=200,
    )

    ranked_orbit.sort(
        key=lambda x: (
            -float(x.get("score") or 0.0),
            str(x.get("profile", {}).get("id") or ""),
        ),
    )

    session_id, expires_at = create_discovery_session(
        viewer_id=user_id,
        active_tab=active_tab,
        filters=filters.model_dump(mode="json"),
        ranked_items=ranked_orbit,
        expires_in_minutes=15,
    )

    return session_id, expires_at
