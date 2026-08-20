"""High-level discovery scoring, session orchestrator, and candidate orbit pipeline service.

Integrates database session stores with the Nexus_Engine recommendation engine to compute
candidate compatibility scores and manage active radar sessions.
"""

import logging
from datetime import datetime
from typing import Any, cast

from fastapi import HTTPException

from app.core.config import DiscoveryTab
from app.db.client import parse_utc_datetime, utcnow
from app.db.discovery import fetch_expired_pass_candidates
from app.db.profiles import fetch_stage_1_candidates
from app.db.sessions import (
    create_discovery_session,
    get_discovery_session,
)
from app.models import DiscoveryFilters
from Nexus_Engine import engine

logger = logging.getLogger(__name__)



def get_or_validate_session(
    session_id: str,
    user_id: str,
    active_tab: DiscoveryTab,
) -> tuple[str, datetime]:
    """Retrieve and validate an existing discovery session for expiration and viewer ownership.

    Args:
        session_id: Unique string UUID identifier of the session.
        user_id: Unique UUID string identifier of the authenticated viewer.
        active_tab: Active discovery tab category ('Dating', 'Friends', or 'Professional').

    Returns:
        tuple[str, datetime]: Tuple containing (session_id, expiration_datetime).

    Raises:
        HTTPException: 404 if session not found, 410 if session expired.
    """
    session = get_discovery_session(
        session_id=session_id,
        viewer_id=user_id,
        active_tab=active_tab,
    )

    if not session or session.get("tab") != active_tab:
        raise HTTPException(status_code=404, detail="Discovery session not found.")

    expires_at_raw = session.get("expires_at")
    if not isinstance(expires_at_raw, (str, datetime)):
        raise HTTPException(
            status_code=410,
            detail="Discovery session expired. Please refresh.",
        )
    try:
        expires_at = parse_utc_datetime(expires_at_raw)
    except (ValueError, TypeError):
        raise HTTPException(
            status_code=410,
            detail="Discovery session expired. Please refresh.",
        ) from None

    if expires_at <= utcnow():
        raise HTTPException(
            status_code=410,
            detail="Discovery session expired. Please refresh.",
        )

    return session_id, expires_at


def create_new_discovery_session(
    user_id: str,
    active_tab: DiscoveryTab,
    filters: DiscoveryFilters,
) -> tuple[str, datetime]:
    """Fetch candidate pool, run matchmaking engine, and persist a new discovery session.

    Args:
        user_id: Unique UUID string identifier of the requesting user.
        active_tab: Active discovery tab category ('Dating', 'Friends', or 'Professional').
        filters: Discovery search filter preferences.

    Returns:
        tuple[str, datetime]: Tuple containing (session_id, expiration_datetime).
    """
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

    # Time-graduated score penalty for candidates whose pass window has expired.
    # While the pass is active they are excluded entirely (handled by exclusions).
    # Once expired they re-enter the pool but land lower depending on how long ago
    # the exclusion window ended:
    #   ≤  7 days → heavy penalty   (0.25x) → outer orbit
    #   ≤ 30 days → moderate penalty (0.50x) → mid-outer orbit
    #   > 30 days → light penalty   (0.85x) → near-normal position
    expired_passes = fetch_expired_pass_candidates(user_id, active_tab)
    if expired_passes:
        now = utcnow()
        for item in ranked_orbit:
            profile = item.get("profile")
            profile_dict = (
                cast(dict[str, Any], profile)
                if isinstance(profile, dict)
                else {}
            )
            cid = str(cast(object, profile_dict.get("id")) or "")
            if cid in expired_passes:
                days_since = (now - expired_passes[cid]).days
                if days_since <= 7:
                    multiplier = 0.25
                elif days_since <= 30:
                    multiplier = 0.50
                else:
                    multiplier = 0.85
                item["score"] = float(item.get("score") or 0.0) * multiplier

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
    )

    return session_id, expires_at
