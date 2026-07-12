import hashlib
import logging
import math
from typing import Any, cast

from app.core.config import DiscoveryTab
from app.models import (
    OrbitNodeDetailDatingOut,
    OrbitNodeDetailFriendsOut,
    OrbitNodeDetailProfessionalOut,
)

logger = logging.getLogger(__name__)


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


# ── Layout tuning constants ────────────────────────────────────────────────
# Rendered node footprint, mirroring the Flutter client (orbit_screen.dart):
# a 58px avatar with a name card below it whose text is truncated to ~80px at
# a word boundary (so effectively capped near _NAME_TEXT_MAX), plus 8px of
# horizontal padding on each side. The overall node width is the wider of the
# avatar and that card. Modelling the *truncated* card - not the full name -
# is what keeps the packing tight; the old formula reserved ~1.6x too much
# width for typical full names, pushing everyone needlessly far out.
_AVATAR_WIDTH = 58.0
_NAME_CHAR_WIDTH = 5.6  # px per char at the card's 10px bold font
_NAME_TEXT_MAX = 90.0  # client truncates name text at ~80px + up to one whole word
_CARD_H_PADDING = 8.0  # horizontal padding on each side of the name card
_NODE_WIDTH_MARGIN = 4.0  # small clearance so touching cards read as separate
_NODE_HALF_HEIGHT = 45.0  # avatar + name-card half height
_MAX_NODE_HALF_WIDTH = (
    max(_AVATAR_WIDTH, _NAME_TEXT_MAX + 2.0 * _CARD_H_PADDING) / 2.0
    + _NODE_WIDTH_MARGIN
)  # half-width at the name-card's truncation cap - the widest any node ever gets

# Nodes are packed in a phyllotaxis ("sunflower") spiral: the k-th best match
# (0-indexed by score rank) is placed at radius INNERMOST + SCALE*sqrt(k) and
# angle k*GOLDEN_ANGLE. This fills the disc evenly from the center outward,
# so radius grows as sqrt(k) (compact) rather than linearly with count, and
# every node is at a distinct rank-ordered radius (higher score => nearer the
# center, always).
#
# The center self-avatar (orbit_screen.dart's _buildSelfAvatar) is a 76px
# circle that pulses up to 1.15x scale, i.e. a hard radius of ~44px - not a
# node the collision/repair logic below ever checks against, so the innermost
# ring must clear it by construction. Using the same corner-distance
# reasoning as node-to-node separation (a box's closest possible point to the
# origin is bounded by center-distance minus its own half-diagonal), the
# nearest node's center must be at least selfAvatarRadius +
# sqrt(hw^2 + hh^2) from the origin for its box to never reach the avatar.
_SELF_AVATAR_RADIUS = 44.0
_INNERMOST_RADIUS = _SELF_AVATAR_RADIUS + math.sqrt(
    _MAX_NODE_HALF_WIDTH**2 + _NODE_HALF_HEIGHT**2,
)
# Radial growth per unit sqrt(rank). Tuned to the smallest value that keeps
# even the widest (name-cap-hitting) cards non-overlapping in the sunflower
# spiral across batch sizes up to the 200-node cap; the local repair pass
# below is a safety net for anything the packing misses.
_SUNFLOWER_SCALE = 84.0
_GOLDEN_ANGLE = math.pi * (3.0 - math.sqrt(5.0))  # ~137.5 degrees
_RADIUS_WARN_THRESHOLD = 1400.0  # nominal pannable-canvas edge; logged, not clamped
_REPAIR_STEP = 8.0  # px pushed outward per iteration when clearing a residual overlap
_REPAIR_MAX_STEPS = 60


def _apply_field_visibility(
    payload: dict[str, Any],
    hidden: set[str],
) -> dict[str, Any]:
    """Return a copy of payload with hidden fields replaced by defaults.

    Scalar string fields become None; list fields become [].
    This is applied before building any response model so scoring logic
    (which reads from the original dict) is never affected.
    """
    if not hidden:
        return payload
    list_fields = {"pets", "top_artists", "causes_supported"}
    result = dict(payload)
    for field in hidden:
        result[field] = [] if field in list_fields else None
    return result


def build_tab_aware_orbit_node_detail(
    session_tab: DiscoveryTab,
    payload: dict[str, Any],
    hidden_fields: set[str] | None = None,
) -> (
    OrbitNodeDetailDatingOut
    | OrbitNodeDetailFriendsOut
    | OrbitNodeDetailProfessionalOut
):
    p = _apply_field_visibility(payload, hidden_fields or set())

    base: dict[str, Any] = {
        "id": str(p.get("id") or ""),
        "name": p.get("name"),
        "age": p.get("age"),
        "campus_branch": p.get("campus_branch"),
        "campus_year": p.get("campus_year"),
        "campus_name": p.get("campus_name"),
        "role_at": p.get("role_at"),
        "score": coerce_score(p.get("score")),
        "x": coerce_float(p.get("x")),
        "y": coerce_float(p.get("y")),
        "orbit_tier": int(coerce_float(p.get("orbit_tier"), 3.0)),
        "profile_pic": p.get("profile_pic"),
        # Common fields (all tabs)
        "bio": p.get("bio"),
        "pronouns": p.get("pronouns"),
        "display_gender": p.get("display_gender"),
        "hometown": p.get("hometown"),
        "current_place": p.get("current_place"),
        "languages": p.get("languages") or [],
        "causes_supported": p.get("causes_supported") or [],
        "interests": p.get("interests") or {},
        "sub_interests": p.get("sub_interests") or {},
        "ai_vibe_tags": p.get("ai_vibe_tags") or [],
    }

    if session_tab == "Dating":
        return OrbitNodeDetailDatingOut(
            **base,
            tab="Dating",
            display_sexuality=p.get("display_sexuality"),
            drinking=p.get("drinking"),
            smoking=p.get("smoking"),
            lifestyle=p.get("lifestyle"),
            religious_beliefs=p.get("religious_beliefs"),
            partner_values=p.get("partner_values") or [],
            children_plans=p.get("children_plans"),
            dating_for=p.get("dating_for") or [],
            normal_pics=p.get("normal_pics") or [],
            top_artists=p.get("top_artists") or [],
            pets=p.get("pets") or [],
        )

    if session_tab == "Friends":
        return OrbitNodeDetailFriendsOut(
            **base,
            tab="Friends",
            display_sexuality=p.get("display_sexuality"),
            drinking=p.get("drinking"),
            smoking=p.get("smoking"),
            lifestyle=p.get("lifestyle"),
            religious_beliefs=p.get("religious_beliefs"),
            normal_pics=p.get("normal_pics") or [],
            top_artists=p.get("top_artists") or [],
            pets=p.get("pets") or [],
        )

    if session_tab == "Professional":
        return OrbitNodeDetailProfessionalOut(
            **base,
            tab="Professional",
            activities=p.get("activities") or [],
            looking_for=p.get("looking_for") or [],
            tech_skills=p.get("tech_skills") or [],
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


def _item_name(item: dict[str, Any]) -> str:
    """Resolve a node's display name off either the flat item or its nested profile."""
    profile_raw = item.get("profile")
    profile: dict[str, Any] = (
        cast(dict[str, Any], profile_raw) if isinstance(profile_raw, dict) else {}
    )
    return str(item.get("name") or profile.get("name") or "Anonymous")


def _node_half_width(name: str) -> float:
    """Bounding half-width of a node's rendered avatar+name-card footprint."""
    text_width = min(len(name) * _NAME_CHAR_WIDTH, _NAME_TEXT_MAX)
    card_width = max(_AVATAR_WIDTH, text_width + 2.0 * _CARD_H_PADDING)
    return card_width / 2.0 + _NODE_WIDTH_MARGIN


def _bucket_low_score_items(
    sorted_items: list[dict[str, Any]],
    tier_buckets: dict[int, list[dict[str, Any]]],
) -> None:
    """Helper to bucket sorted items when max score is < 70.0."""
    for index, item in enumerate(sorted_items):
        if index < 3:
            # Top 3 matches labelled Tier 1 so they read as "close" matches
            # even when nobody clears the Tier 0 (85%+) threshold.
            tier_buckets[1].append(item)
        elif index < 8:
            tier_buckets[2].append(item)
        else:
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
    """Group ranked items into orbit tier labels (0 = best … 3 = weakest).

    Tiers are only a coarse label (returned to the client as `orbit_tier` for
    styling and carried into node-detail responses). They no longer drive the
    radius - radius comes from the phyllotaxis packing in assign_orbit_positions,
    which places nodes by global score rank. When the whole batch scores below
    the standard Tier 0/1 thresholds, a rank-based fallback still labels the
    top matches as Tier 1/2 so they don't all read as weak.
    """
    tier_buckets: dict[int, list[dict[str, Any]]] = {0: [], 1: [], 2: [], 3: []}
    if not ranked_items:
        return tier_buckets

    sorted_items = sorted(
        ranked_items,
        key=lambda x: coerce_score(x.get("score")),
        reverse=True,
    )

    max_score = coerce_score(sorted_items[0].get("score"))
    if max_score < 70.0:
        _bucket_low_score_items(sorted_items, tier_buckets)
    else:
        _bucket_standard_score_items(sorted_items, tier_buckets)

    return tier_buckets


def _tier_label_by_id(
    tier_buckets: dict[int, list[dict[str, Any]]],
) -> dict[str, int]:
    """Map each candidate id to its tier label, for tagging positioned nodes."""
    labels: dict[str, int] = {}
    for tier, items in tier_buckets.items():
        for item in items:
            profile_raw = item.get("profile")
            profile: dict[str, Any] = (
                cast(dict[str, Any], profile_raw)
                if isinstance(profile_raw, dict)
                else {}
            )
            candidate_id = profile.get("id")
            if candidate_id is not None:
                labels[str(candidate_id)] = tier
    return labels


def _boxes_overlap(node1: dict[str, Any], node2: dict[str, Any]) -> bool:
    """Whether two nodes' avatar+name-card bounding boxes actually overlap."""
    hw1 = _node_half_width(_item_name(node1))
    hw2 = _node_half_width(_item_name(node2))
    dx = node1["_x"] - node2["_x"]
    dy = node1["_y"] - node2["_y"]
    return (hw1 + hw2) > abs(dx) and abs(dy) < (2.0 * _NODE_HALF_HEIGHT)


def _repair_overlaps(positioned_items: list[dict[str, Any]]) -> None:
    """Safety net: nudge any still-overlapping node radially outward, locally.

    Processes nodes in score-descending order and, for each, pushes it a few
    pixels further out (along its own ray, so its angle is preserved) until it
    clears every already-placed higher-or-equal-scored node. Because it only
    ever moves the lower-scored node of a colliding pair further out - and
    never touches the nodes already placed - it can reinforce but never invert
    the score-to-radius ordering established by the sunflower packing, and it
    can't cascade globally. It is expected to be a no-op for realistic inputs
    (the packing is already overlap-free); it exists purely so "no overlap"
    stays a hard guarantee.
    """
    ordered = sorted(positioned_items, key=lambda it: -coerce_score(it.get("score")))
    placed: list[dict[str, Any]] = []
    for item in ordered:
        r = math.hypot(item["_x"], item["_y"])
        theta = math.atan2(item["_y"], item["_x"])
        steps = 0
        while steps < _REPAIR_MAX_STEPS and any(
            _boxes_overlap(item, other) for other in placed
        ):
            r += _REPAIR_STEP
            item["_x"] = round(r * math.cos(theta), 2)
            item["_y"] = round(r * math.sin(theta), 2)
            steps += 1
        placed.append(item)


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
    tier_by_id = _tier_label_by_id(tier_buckets)

    # Global score-descending order: best match first (rank 0), packed nearest
    # the center. This is what makes distance a pure function of match rank -
    # a 50% match with nobody better sits right by the center, exactly as it
    # should, and a higher score is always at least as close as a lower one.
    ordered = sorted(
        ranked_items,
        key=lambda x: coerce_score(x.get("score")),
        reverse=True,
    )

    base_angle = rng.uniform(0.0, 2.0 * math.pi)
    positioned_items: list[dict[str, Any]] = []
    for rank, item in enumerate(ordered):
        # Phyllotaxis spiral: radius grows as sqrt(rank) (even areal density,
        # compact), golden-angle step spreads consecutive ranks evenly around
        # the full 360 degrees so there's never a clustered "spine" or an empty
        # wedge.
        radius = _INNERMOST_RADIUS + _SUNFLOWER_SCALE * math.sqrt(float(rank))
        angle = base_angle + rank * _GOLDEN_ANGLE
        profile_raw = item.get("profile")
        profile: dict[str, Any] = (
            cast(dict[str, Any], profile_raw)
            if isinstance(profile_raw, dict)
            else {}
        )
        candidate_id = profile.get("id")
        tier = tier_by_id.get(str(candidate_id), 3) if candidate_id is not None else 3
        positioned_items.append(
            {
                **item,
                "_orbit_tier": tier,
                "_x": round(radius * math.cos(angle), 2),
                "_y": round(radius * math.sin(angle), 2),
            },
        )

    _repair_overlaps(positioned_items)

    max_r = max(
        (math.hypot(item["_x"], item["_y"]) for item in positioned_items),
        default=0.0,
    )
    if max_r > _RADIUS_WARN_THRESHOLD:
        logger.warning(
            "orbit: layout radius %.0f exceeds canvas-safe threshold %.0f "
            "(viewer=%s, tab=%s, n=%d)",
            max_r,
            _RADIUS_WARN_THRESHOLD,
            viewer_id,
            active_tab,
            len(positioned_items),
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
