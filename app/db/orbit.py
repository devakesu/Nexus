import hashlib
import math
import random
from typing import Any, Sequence

from app.core.config import DiscoveryTab
from app.models import OrbitNodeDetailDatingOut, OrbitNodeDetailFriendsOut, OrbitNodeDetailProfessionalOut


def _coerce_score(value: Any) -> float:
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    return _coerce_float(value, 0.0)


def _coerce_float(value: Any, default: float = 0.0) -> float:
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
) -> OrbitNodeDetailDatingOut | OrbitNodeDetailFriendsOut | OrbitNodeDetailProfessionalOut:
    base = {
        "id": str(payload.get("id") or ""),
        "name": payload.get("name"),
        "age": payload.get("age"),
        "branch": payload.get("branch"),
        "year": payload.get("year"),
        "role": payload.get("role"),
        "score": _coerce_score(payload.get("score")),
        "x": _coerce_float(payload.get("x")),
        "y": _coerce_float(payload.get("y")),
        "orbit_tier": int(_coerce_float(payload.get("orbit_tier"), 3.0)),
    }

    if session_tab == "Dating":
        return OrbitNodeDetailDatingOut(
            **base,
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
            **base,
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
            **base,
            tab="Professional",
            hometown=payload.get("hometown"),
            tech_skills=payload.get("tech_skills") or [],
            languages=payload.get("languages") or [],
            causes_supported=payload.get("causes_supported") or [],
        )

    raise ValueError(f"Unsupported session_tab: {session_tab}")


def _assign_orbit_positions(
    viewer_id: str,
    active_tab: DiscoveryTab,
    ranked_items: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    candidate_ids: list[str] = []
    for item in ranked_items:
        if not isinstance(item, dict):
            continue
        profile_raw = item.get("profile")
        profile = profile_raw if isinstance(profile_raw, dict) else {}
        candidate_id = profile.get("id")
        if candidate_id:
            candidate_ids.append(str(candidate_id))

    seed_input = f"{viewer_id}:{active_tab}:{'|'.join(sorted(candidate_ids))}"
    seed_value = int(hashlib.sha256(seed_input.encode("utf-8")).hexdigest()[:16], 16)
    rng = random.Random(seed_value)

    tier_buckets: dict[int, list[dict[str, Any]]] = {
        0: [],
        1: [],
        2: [],
        3: [],
    }

    for item in ranked_items:
        score = _coerce_score(item.get("score"))
        if score >= 85.0:
            tier_buckets[0].append(item)
        elif score >= 70.0:
            tier_buckets[1].append(item)
        elif score >= 50.0:
            tier_buckets[2].append(item)
        else:
            tier_buckets[3].append(item)

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
                }
            )

    positioned_items.sort(
        key=lambda item: (
            -_coerce_score(item.get("score")),
            str(
                item.get("profile", {}).get("id")
                if isinstance(item.get("profile"), dict)
                else ""
            ),
        )
    )

    return positioned_items
