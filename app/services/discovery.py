"""High-level discovery scoring, session orchestrator, and candidate orbit pipeline service.

Integrates database session stores with the Nexus_Engine recommendation engine to compute
candidate compatibility scores and manage active radar sessions.
"""

import logging
from datetime import datetime
from typing import Any, cast

from fastapi import HTTPException

from app.core.config import DiscoveryTab, settings
from app.core.infra.cache import sync_redis_client
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
    session = get_discovery_session(session_id, user_id, active_tab)
    if not session or session.get("tab") != active_tab:
        raise HTTPException(
            status_code=404,
            detail="Discovery session not found or access denied.",
        )

    expires_at_raw = session.get("expires_at")
    if not expires_at_raw:
        raise HTTPException(
            status_code=410,
            detail="Discovery session expired.",
        )

    try:
        if isinstance(expires_at_raw, datetime):
            expires_at = expires_at_raw
        else:
            expires_at = parse_utc_datetime(str(expires_at_raw))
    except Exception as err:
        raise HTTPException(
            status_code=410,
            detail="Discovery session expired.",
        ) from err

    if expires_at <= utcnow():
        raise HTTPException(
            status_code=410,
            detail="Discovery session expired.",
        )

    return session_id, expires_at


def _check_hourly_session_creation_limit(user_id: str) -> None:
    hourly_session_key = f"user:session_creations_hourly:{user_id}"
    try:
        creation_count = int(sync_redis_client.incr(hourly_session_key))
        if creation_count == 1:
            sync_redis_client.expire(hourly_session_key, 3600)
        max_hourly_sessions = getattr(settings, "rate_limit_session_creation_hourly", 20)
        if creation_count > max_hourly_sessions:
            logger.warning(
                "Hourly discovery session creation rate limit exceeded",
                extra={"user_id": user_id, "creation_count": creation_count},
            )
            raise HTTPException(
                status_code=429,
                detail="Hourly discovery session creation limit exceeded. Please reuse existing sessions or try again later.",
            )
    except (ValueError, TypeError):
        pass


def _check_mutation_probe_limit(user_id: str) -> None:
    mutation_count_raw = sync_redis_client.get(f"user:profile_mutations:{user_id}")
    if mutation_count_raw:
        mutation_count = int(mutation_count_raw)
        if mutation_count >= 3:
            session_probe_key = f"user:session_probe_count:{user_id}"
            session_count = sync_redis_client.incr(session_probe_key)
            if session_count == 1:
                sync_redis_client.expire(session_probe_key, 600)
            if session_count > 5:
                logger.warning(
                    "Systematic discovery probing detected",
                    extra={
                        "user_id": user_id,
                        "mutation_count": mutation_count,
                        "session_count": session_count,
                    },
                )
                raise HTTPException(
                    status_code=429,
                    detail="Session creation rate limit exceeded due to frequent profile updates. Please wait before creating a new session.",
                )


def _check_filter_combination_probing(user_id: str, filters: DiscoveryFilters) -> None:
    if not filters:
        return
    filter_dict = filters.model_dump(exclude_none=True) if hasattr(filters, "model_dump") else {}
    if not filter_dict:
        return
    import hashlib
    import json

    filter_hash = hashlib.sha256(
        json.dumps(filter_dict, sort_keys=True).encode("utf-8"),
    ).hexdigest()[:16]
    filter_set_key = f"user:discovery_filter_hashes:{user_id}"
    sync_redis_client.sadd(filter_set_key, filter_hash)
    sync_redis_client.expire(filter_set_key, 600)
    try:
        scard_val = int(sync_redis_client.scard(filter_set_key))
        if scard_val > 15:
            logger.warning(
                "High distinct filter combination probing detected",
                extra={"user_id": user_id, "distinct_count": scard_val},
            )
            raise HTTPException(
                status_code=429,
                detail="Discovery filter search rate limit exceeded. Please slow down your filter changes.",
            )
    except (ValueError, TypeError):
        pass


def _check_discovery_throttling(user_id: str, filters: DiscoveryFilters) -> None:
    _check_hourly_session_creation_limit(user_id)
    _check_mutation_probe_limit(user_id)
    _check_filter_combination_probing(user_id, filters)


def _validate_viewer_for_discovery(
    viewer: dict[str, Any] | None,
    active_tab: DiscoveryTab,
    filters: DiscoveryFilters,
    user_id: str,
) -> dict[str, Any]:
    if viewer is None:
        raise HTTPException(
            status_code=404,
            detail="Target user profile unpopulated.",
        )

    completion_flag_map = {
        "Dating": "is_dating_active",
        "Friends": "is_friends_active",
        "Professional": "is_professional_active",
    }
    completion_flag = completion_flag_map.get(active_tab)
    if completion_flag and viewer.get(completion_flag) is False:
        logger.warning(
            "Viewer profile incomplete for discovery tab",
            extra={"user_id": user_id, "active_tab": active_tab, "flag": completion_flag},
        )
        raise HTTPException(
            status_code=403,
            detail=f"Profile incomplete for {active_tab} tab. Please complete your profile to access discovery.",
        )

    viewer_age = viewer.get("age")
    if viewer_age is not None and isinstance(viewer_age, int) and viewer_age < 18:
        logger.warning(
            "Underage viewer attempted discovery session creation",
            extra={"user_id": user_id, "age": viewer_age},
        )
        raise HTTPException(
            status_code=403,
            detail="Underage accounts (age < 18) are not permitted to access discovery.",
        )

    if filters and filters.search_bucket_filter:
        from Nexus_Engine.utils import expand_target_buckets

        target_bucket_col = {
            "Dating": "dating_target_buckets",
            "Friends": "friends_target_buckets",
            "Professional": "professional_target_buckets",
        }.get(active_tab, "dating_target_buckets")
        viewer_targets_raw = viewer.get(target_bucket_col)
        if isinstance(viewer_targets_raw, list) and viewer_targets_raw:
            raw_list = cast(list[Any], viewer_targets_raw)
            viewer_targets = expand_target_buckets([str(x) for x in raw_list])
            filter_buckets = expand_target_buckets([str(x) for x in filters.search_bucket_filter])
            if not any(b in viewer_targets for b in filter_buckets):
                raise HTTPException(
                    status_code=400,
                    detail="Requested search_bucket_filter does not intersect with viewer's configured target buckets.",
                )
    return viewer


def _apply_expired_pass_penalties(
    ranked_orbit: list[dict[str, Any]], expired_passes: dict[str, datetime],
) -> None:
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


def create_new_discovery_session(
    user_id: str,
    active_tab: DiscoveryTab,
    filters: DiscoveryFilters,
) -> tuple[str, datetime]:
    """Fetch candidate pool, run matchmaking engine, and persist a new discovery session."""
    try:
        _check_discovery_throttling(user_id, filters)
    except HTTPException:
        raise
    except Exception as e:  # noqa: BLE001
        logger.warning("Redis filter tracking failed, continuing without filter throttling: %s", e)

    raw_viewer, candidate_pool = fetch_stage_1_candidates(
        viewer_id=user_id,
        active_tab=active_tab,
        filters=filters,
        candidate_limit=200,
    )

    viewer = _validate_viewer_for_discovery(raw_viewer, active_tab, filters, user_id)

    ranked_orbit: list[dict[str, Any]] = engine.discover_orbit(
        viewer,
        active_tab,
        candidate_pool,
        orbit_limit=200,
    )

    expired_passes = fetch_expired_pass_candidates(user_id, active_tab)
    if expired_passes:
        _apply_expired_pass_penalties(ranked_orbit, expired_passes)

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
