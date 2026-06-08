import hashlib
import math
from typing import Any, cast

from app.core.config import DiscoveryTab
from app.models import (
    OrbitNodeDetailDatingOut,
    OrbitNodeDetailFriendsOut,
    OrbitNodeDetailProfessionalOut,
)


class DeterministicRNG:
    """A simple deterministic LCG random number generator to avoid Ruff S311."""

    def __init__(self, seed: int) -> None:
        self.state = seed

    def _next(self) -> float:
        self.state = (1103515245 * self.state + 12345) & 0x7FFFFFFF
        return self.state / 2147483647.0

    def uniform(self, a: float, b: float) -> float:
        return a + (b - a) * self._next()


def coerce_score(value: Any) -> float:
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    return coerce_float(value, 0.0)


def coerce_float(value: Any, default: float = 0.0) -> float:
    if isinstance(value, bool):
        return default
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return default
    return default


def build_tab_aware_orbit_node_detail(
    session_tab: DiscoveryTab,
    payload: dict[str, Any],
) -> (
    OrbitNodeDetailDatingOut
    | OrbitNodeDetailFriendsOut
    | OrbitNodeDetailProfessionalOut
):
    base: dict[str, Any] = {
        "id": str(payload.get("id") or ""),
        "name": payload.get("name"),
        "age": payload.get("age"),
        "branch": payload.get("branch"),
        "year": payload.get("year"),
        "role": payload.get("role"),
        "score": coerce_score(payload.get("score")),
        "x": coerce_float(payload.get("x")),
        "y": coerce_float(payload.get("y")),
        "orbit_tier": int(coerce_float(payload.get("orbit_tier"), 3.0)),
        "profile_pic": payload.get("profile_pic"),
        "normal_pics": payload.get("normal_pics") or [],
    }

    if session_tab == "Dating":
        return OrbitNodeDetailDatingOut(
            id=base["id"],
            name=base["name"],
            age=base["age"],
            branch=base["branch"],
            year=base["year"],
            role=base["role"],
            score=base["score"],
            x=base["x"],
            y=base["y"],
            orbit_tier=base["orbit_tier"],
            profile_pic=base["profile_pic"],
            normal_pics=base["normal_pics"],
            tab="Dating",
            display_gender=payload.get("display_gender"),
            display_sexuality=payload.get("display_sexuality"),
            drinking=payload.get("drinking"),
            smoking=payload.get("smoking"),
            hometown=payload.get("hometown"),
            partner_values=payload.get("partner_values"),
            children_plans=payload.get("children_plans"),
            religious_beliefs=payload.get("religious_beliefs"),
            lifestyle=payload.get("lifestyle"),
            activities=payload.get("activities") or [],
            looking_for=payload.get("looking_for") or [],
            causes_supported=payload.get("causes_supported") or [],
            top_artists=payload.get("top_artists") or [],
            tech_skills=payload.get("tech_skills") or [],
            languages=payload.get("languages") or [],
            ai_vibe_tags=payload.get("ai_vibe_tags") or [],
            pets=payload.get("pets") or [],
        )

    if session_tab == "Friends":
        return OrbitNodeDetailFriendsOut(
            id=base["id"],
            name=base["name"],
            age=base["age"],
            branch=base["branch"],
            year=base["year"],
            role=base["role"],
            score=base["score"],
            x=base["x"],
            y=base["y"],
            orbit_tier=base["orbit_tier"],
            profile_pic=base["profile_pic"],
            normal_pics=base["normal_pics"],
            tab="Friends",
            hometown=payload.get("hometown"),
            lifestyle=payload.get("lifestyle"),
            activities=payload.get("activities") or [],
            causes_supported=payload.get("causes_supported") or [],
            top_artists=payload.get("top_artists") or [],
            languages=payload.get("languages") or [],
            ai_vibe_tags=payload.get("ai_vibe_tags") or [],
            pets=payload.get("pets") or [],
        )

    if session_tab == "Professional":
        return OrbitNodeDetailProfessionalOut(
            id=base["id"],
            name=base["name"],
            age=base["age"],
            branch=base["branch"],
            year=base["year"],
            role=base["role"],
            score=base["score"],
            x=base["x"],
            y=base["y"],
            orbit_tier=base["orbit_tier"],
            profile_pic=base["profile_pic"],
            normal_pics=base["normal_pics"],
            tab="Professional",
            hometown=payload.get("hometown"),
            tech_skills=payload.get("tech_skills") or [],
            languages=payload.get("languages") or [],
            causes_supported=payload.get("causes_supported") or [],
        )

    raise ValueError(f"Unsupported session_tab: {session_tab}")


def _extract_candidate_ids(ranked_items: list[dict[str, Any]]) -> list[str]:
    """Helper to extract active candidate ID list for position seeding."""
    candidate_ids: list[str] = []
    for item in ranked_items:
        profile_raw = item.get("profile")
        profile: dict[str, Any] = {}
        if isinstance(profile_raw, dict):
            profile.update(cast(dict[str, Any], profile_raw))
        candidate_id = profile.get("id")
        if candidate_id:
            candidate_ids.append(str(candidate_id))
    return candidate_ids


def _bucket_items_by_tier(
    ranked_items: list[dict[str, Any]],
) -> dict[int, list[dict[str, Any]]]:
    """Helper to group ranked items into distinct orbit tier buckets."""
    tier_buckets: dict[int, list[dict[str, Any]]] = {
        0: [],
        1: [],
        2: [],
        3: [],
    }
    for item in ranked_items:
        score = coerce_score(item.get("score"))
        if score >= 85.0:
            tier_buckets[0].append(item)
        elif score >= 70.0:
            tier_buckets[1].append(item)
        elif score >= 50.0:
            tier_buckets[2].append(item)
        else:
            tier_buckets[3].append(item)
    return tier_buckets


def assign_orbit_positions(
    viewer_id: str,
    active_tab: DiscoveryTab,
    ranked_items: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    candidate_ids = _extract_candidate_ids(ranked_items)
    seed_input = f"{viewer_id}:{active_tab}:{'|'.join(sorted(candidate_ids))}"
    seed_value = int(hashlib.sha256(seed_input.encode("utf-8")).hexdigest()[:16], 16)
    rng = DeterministicRNG(seed_value)

    tier_buckets = _bucket_items_by_tier(ranked_items)
    tier_radii = {
        0: 120.0,
        1: 240.0,
        2: 380.0,
        3: 560.0,
    }

    positioned_items: list[dict[str, Any]] = []

    for tier, items in tier_buckets.items():
        if not items:
            continue

        radius = tier_radii[tier]
        count = len(items)
        base_angle_offset = rng.uniform(0.0, 2.0 * math.pi)

        for index, item in enumerate(items):
            angle = base_angle_offset + ((2.0 * math.pi * index) / count)
            radial_jitter = rng.uniform(-18.0, 18.0)
            angular_jitter = rng.uniform(-0.08, 0.08)

            final_radius = max(40.0, radius + radial_jitter)
            final_angle = angle + angular_jitter

            positioned_items.append(
                {
                    **item,
                    "_orbit_tier": tier,
                    "_x": round(final_radius * math.cos(final_angle), 2),
                    "_y": round(final_radius * math.sin(final_angle), 2),
                },
            )

    positioned_items.sort(
        key=lambda item: (
            -coerce_score(item.get("score")),
            str(
                item.get("profile", {}).get("id")
                if isinstance(item.get("profile"), dict)
                else "",
            ),
        ),
    )

    return positioned_items
