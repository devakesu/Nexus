"""Database discovery, exclusions, matches, and orbits persistence package."""

from app.db.discovery.exclusions import (
    fetch_active_block_ids,
    fetch_active_discovery_excluded_ids,
    fetch_expired_pass_candidates,
    fetch_likes_for_user,
    get_cached_active_block_ids,
    has_active_discovery_action,
    invalidate_block_cache,
    mark_likes_seen,
    record_discovery_action,
    record_user_report,
    revoke_incoming_like,
    unrevoke_incoming_like,
)
from app.db.discovery.matches import (
    fetch_matches_for_user,
    record_match,
    record_mutual_pass,
    set_match_unmatched,
)
from app.db.discovery.orbit import (
    assign_orbit_positions,
    build_tab_aware_orbit_node_detail,
    coerce_float,
    coerce_score,
)

__all__ = [
    # orbit
    "assign_orbit_positions",
    "build_tab_aware_orbit_node_detail",
    "coerce_float",
    "coerce_score",
    # exclusions
    "fetch_active_block_ids",
    "fetch_active_discovery_excluded_ids",
    "fetch_expired_pass_candidates",
    "fetch_likes_for_user",
    # matches
    "fetch_matches_for_user",
    "get_cached_active_block_ids",
    "has_active_discovery_action",
    "invalidate_block_cache",
    "mark_likes_seen",
    "record_discovery_action",
    "record_match",
    "record_mutual_pass",
    "record_user_report",
    "revoke_incoming_like",
    "set_match_unmatched",
    "unrevoke_incoming_like",
]
