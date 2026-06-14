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
        "campus_branch": payload.get("campus_branch"),
        "campus_year": payload.get("campus_year"),
        "campus_name": payload.get("campus_name"),
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
            campus_branch=base["campus_branch"],
            campus_year=base["campus_year"],
            campus_name=base.get("campus_name"),
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
            current_place=payload.get("current_place"),
            pronouns=payload.get("pronouns"),
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
            campus_branch=base["campus_branch"],
            campus_year=base["campus_year"],
            campus_name=base.get("campus_name"),
            role=base["role"],
            score=base["score"],
            x=base["x"],
            y=base["y"],
            orbit_tier=base["orbit_tier"],
            profile_pic=base["profile_pic"],
            normal_pics=base["normal_pics"],
            tab="Friends",
            hometown=payload.get("hometown"),
            current_place=payload.get("current_place"),
            pronouns=payload.get("pronouns"),
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
            campus_branch=base["campus_branch"],
            campus_year=base["campus_year"],
            campus_name=base.get("campus_name"),
            role=base["role"],
            score=base["score"],
            x=base["x"],
            y=base["y"],
            orbit_tier=base["orbit_tier"],
            profile_pic=base["profile_pic"],
            normal_pics=base["normal_pics"],
            tab="Professional",
            hometown=payload.get("hometown"),
            current_place=payload.get("current_place"),
            pronouns=payload.get("pronouns"),
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


def _bucket_low_score_items(
    sorted_items: list[dict[str, Any]],
    tier_buckets: dict[int, list[dict[str, Any]]],
) -> None:
    """Helper to bucket sorted items when max score is < 70.0."""
    for index, item in enumerate(sorted_items):
        if index < 3:
            # Top 3 matches go to Tier 1 (radius 200) so they are visible,
            # close but not too near (Tier 0).
            tier_buckets[1].append(item)
        elif index < 8:
            # Next 5 matches go to Tier 2 (radius 300)
            tier_buckets[2].append(item)
        else:
            # The rest go to Tier 3 (radius 420)
            tier_buckets[3].append(item)


def _bucket_standard_score_items(
    sorted_items: list[dict[str, Any]],
    tier_buckets: dict[int, list[dict[str, Any]]],
) -> None:
    """Helper to bucket sorted items based on standard absolute score ranges."""
    for item in sorted_items:
        score = coerce_score(item.get("score"))
        if score >= 85.0:
            tier_buckets[0].append(item)
        elif score >= 70.0:
            tier_buckets[1].append(item)
        elif score >= 50.0:
            tier_buckets[2].append(item)
        else:
            tier_buckets[3].append(item)


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
    if not ranked_items:
        return tier_buckets

    sorted_items = sorted(
        ranked_items,
        key=lambda x: coerce_score(x.get("score")),
        reverse=True,
    )

    max_score = coerce_score(sorted_items[0].get("score"))

    # If the maximum score is very low, dynamically scale/distribute them
    # so that the user sees matches on their screen (in Tier 1 and Tier 2)
    # instead of pushing all matches off-screen into Tier 3
    if max_score < 70.0:
        _bucket_low_score_items(sorted_items, tier_buckets)
    else:
        # Standard absolute score bucketing
        _bucket_standard_score_items(sorted_items, tier_buckets)

    return tier_buckets


def _resolve_pair_collision(
    node1: dict[str, Any],
    node2: dict[str, Any],
    rng: DeterministicRNG,
) -> bool:
    """Resolve collision between two nodes and return True if they were moved."""
    p1 = node1.get("profile")
    p2 = node2.get("profile")
    p1_dict: dict[str, Any] = (
        cast(dict[str, Any], p1) if isinstance(p1, dict) else {}
    )
    p2_dict: dict[str, Any] = (
        cast(dict[str, Any], p2) if isinstance(p2, dict) else {}
    )

    name1 = str(node1.get("name") or p1_dict.get("name") or "Anonymous")
    name2 = str(node2.get("name") or p2_dict.get("name") or "Anonymous")

    # Calculate bounding box dimensions based on name card length
    hw1 = (58.0 + len(name1) * 6.5) / 2.0 + 8.0
    hw2 = (58.0 + len(name2) * 6.5) / 2.0 + 8.0
    hh1 = 45.0  # Avatar height + name card height + padding
    hh2 = 45.0

    dx: float = node1["_x"] - node2["_x"]
    dy: float = node1["_y"] - node2["_y"]

    overlap_x = (hw1 + hw2) - abs(dx)
    overlap_y = (hh1 + hh2) - abs(dy)

    if overlap_x > 0 and overlap_y > 0:
        # Resolve overlap along the axis of minimum overlap
        if overlap_x < overlap_y:
            # Push in X
            sign = 1.0 if dx >= 0 else -1.0
            if dx == 0:
                sign = 1.0 if rng.uniform(-1.0, 1.0) >= 0 else -1.0
            px = overlap_x * 0.5 * sign
            node1["_x"] = round(node1["_x"] + px, 2)
            node2["_x"] = round(node2["_x"] - px, 2)
        else:
            # Push in Y
            sign = 1.0 if dy >= 0 else -1.0
            if dy == 0:
                sign = 1.0 if rng.uniform(-1.0, 1.0) >= 0 else -1.0
            py = overlap_y * 0.5 * sign
            node1["_y"] = round(node1["_y"] + py, 2)
            node2["_y"] = round(node2["_y"] - py, 2)
        return True
    return False


def _resolve_node_collisions(
    positioned_items: list[dict[str, Any]],
    rng: DeterministicRNG,
) -> None:
    """Relaxation loop to resolve any remaining overlaps using AABB checks."""
    for _ in range(50):
        moved = False
        for i in range(len(positioned_items)):
            for j in range(i + 1, len(positioned_items)):
                if _resolve_pair_collision(
                    positioned_items[i],
                    positioned_items[j],
                    rng,
                ):
                    moved = True
        if not moved:
            break


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
        0: 100.0,
        1: 200.0,
        2: 300.0,
        3: 420.0,
    }

    positioned_items: list[dict[str, Any]] = []

    for tier, items in tier_buckets.items():
        if not items:
            continue

        radius = tier_radii[tier]
        count = len(items)

        # Distribute items into nested sub-orbitals if a tier contains
        # too many nodes to prevent overlaps
        max_per_ring = 8
        num_rings = math.ceil(count / max_per_ring)
        global_base_angle_offset = rng.uniform(0.0, 2.0 * math.pi)

        for ring_idx in range(num_rings):
            # Alternating slice so scores/nodes are distributed evenly
            ring_items = items[ring_idx::num_rings]
            ring_count = len(ring_items)
            if not ring_items:
                continue

            # Sub-orbital radius spacing (e.g. 60 units apart)
            if num_rings > 1:
                ring_offset = (ring_idx - (num_rings - 1) / 2.0) * 60.0
                # Stagger the angle of each ring by a fraction of the angular step
                # so nodes align with the gaps of the adjacent ring
                stagger_angle = (ring_idx * math.pi) / ring_count
            else:
                ring_offset = 0.0
                stagger_angle = 0.0

            ring_radius = radius + ring_offset
            ring_base_angle = global_base_angle_offset + stagger_angle

            for index, item in enumerate(ring_items):
                angle = ring_base_angle + ((2.0 * math.pi * index) / ring_count)
                radial_jitter = rng.uniform(-10.0, 10.0)
                angular_jitter = rng.uniform(-0.05, 0.05)

                final_radius = max(40.0, ring_radius + radial_jitter)
                final_angle = angle + angular_jitter

                positioned_items.append(
                    {
                        **item,
                        "_orbit_tier": tier,
                        "_x": round(final_radius * math.cos(final_angle), 2),
                        "_y": round(final_radius * math.sin(final_angle), 2),
                    },
                )

    # Relaxation loop to resolve any remaining overlaps using AABB (bounding box) checks
    # to account for name card widths and prevent overlaps 100%
    _resolve_node_collisions(positioned_items, rng)

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
