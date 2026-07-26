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
from app.db.exclusions import fetch_expired_pass_candidates
from app.db.profiles import fetch_stage_1_candidates
from app.db.sessions import (
    create_discovery_session,
    get_discovery_session,
    get_discovery_session_by_id,
)
from app.models import DiscoveryFilters
from Nexus_Engine import engine

logger = logging.getLogger(__name__)



def get_or_validate_session(
    session_id: str,
    user_id: str,
    active_tab: DiscoveryTab | None = None,
) -> tuple[str, datetime]:
    """Get or validate session.

        Args:
            session_id: get or validate session.
            user_id: get or validate session.
            active_tab: get or validate session.

        Returns:
            tuple[str, datetime]: Result value.
        """
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
    filters: DiscoveryFilters,
) -> tuple[str, datetime]:
    """Create new discovery session.

        Args:
            user_id: create new discovery session.
            active_tab: create new discovery session.
            filters: create new discovery session.

        Returns:
            tuple[str, datetime]: Result value.
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
