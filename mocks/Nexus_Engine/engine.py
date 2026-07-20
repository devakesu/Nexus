import logging
from datetime import datetime
from typing import Any

logger = logging.getLogger(__name__)


class EngineInputError(Exception):
    """Raised when matchmaking inputs are malformed."""
    pass


def discover_orbit(
    viewer: dict[str, Any],
    active_tab: Any,
    global_pool: list[dict[str, Any]],
    orbit_limit: int = 200,
    now: datetime | None = None,
) -> list[dict[str, Any]]:
    """Mock implementation of discover_orbit.

    Runtime injection required for real matching.
    """
    logger.warning("Executing MOCK discover_orbit")
    _ = (viewer, active_tab, now)
    orbit_payload: list[dict[str, Any]] = []
    for candidate in global_pool[:orbit_limit]:
        orbit_payload.append({
            "profile": candidate,
            "score": 1.0,
            "music_match_grade": 5,
            "viewer_spotify_connected": True,
            "candidate_spotify_connected": True,
        })
    return orbit_payload


def calculate_playlist_match_grade(
    affinity_a: Any,
    affinity_b: Any,
    genre_a: Any = None,
    genre_b: Any = None,
) -> int | None:
    """Mock implementation of calculate_playlist_match_grade."""
    if not affinity_a and not affinity_b and not genre_a and not genre_b:
        return None
    return 5


def calculate_recency_decay(
    profile: dict[str, Any],
    now: datetime | None = None,
) -> float:
    _ = (profile, now)
    return 1.0


def calculate_mutual_match(
    viewer: dict[str, Any],
    candidate: dict[str, Any],
    active_tab: Any,
) -> float:
    _ = (viewer, candidate, active_tab)
    return 1.0


def calculate_weighted_affinity_match(
    affinity_a: Any,
    affinity_b: Any,
) -> float:
    _ = (affinity_a, affinity_b)
    return 0.5


def calculate_directional_match(
    profile_a: dict[str, Any],
    profile_b: dict[str, Any],
) -> float:
    _ = (profile_a, profile_b)
    return 1.0
