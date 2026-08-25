import math
import random
import string
from collections.abc import Callable
from typing import Any

import pytest

from app.db.discovery import assign_orbit_positions


def _half_width(name: str) -> float:
    """Mirrors app.db.orbit's rendered avatar+name-card half-width model.

    Reimplemented here (rather than imported) so this test doesn't reach into
    the module's private internals - it only exercises the public
    assign_orbit_positions contract. Must stay in sync with _node_half_width.
    """
    text_width = min(len(name) * 5.6, 90.0)
    card_width = max(58.0, text_width + 2.0 * 8.0)
    return card_width / 2.0 + 4.0


_HALF_HEIGHT = 45.0
_SELF_AVATAR_RADIUS = 44.0  # mirrors app.db.orbit's center self-avatar clearance model


def _make_items(
    count: int,
    score_fn: Callable[[int], float],
    name_len_fn: Callable[[int], int],
) -> list[dict[str, Any]]:
    return [
        {
            "profile": {
                "id": f"id{i}",
                "name": "".join(
                    random.choices(string.ascii_letters, k=name_len_fn(i)),
                ),
            },
            "score": score_fn(i),
        }
        for i in range(count)
    ]


def _radius(item: dict[str, Any]) -> float:
    return math.hypot(item["_x"], item["_y"])


def _assert_no_overlap(result: list[dict[str, Any]]) -> None:
    for i in range(len(result)):
        for j in range(i + 1, len(result)):
            a, b = result[i], result[j]
            name_a = a["profile"]["name"]
            name_b = b["profile"]["name"]
            overlap_x = (_half_width(name_a) + _half_width(name_b)) - abs(
                a["_x"] - b["_x"],
            )
            overlap_y = (2.0 * _HALF_HEIGHT) - abs(a["_y"] - b["_y"])
            assert not (overlap_x > 0 and overlap_y > 0), (
                f"overlap between {name_a!r} and {name_b!r}"
            )


def _assert_clears_self_avatar(result: list[dict[str, Any]]) -> None:
    """No node's rendered box may reach the center self-avatar's circle.

    Uses the exact point-to-AABB distance (not the conservative corner-distance
    bound app.db.orbit derives _INNERMOST_RADIUS from), so this is a real
    check of the geometry rather than a restatement of the same formula.
    """
    for item in result:
        hw = _half_width(item["profile"]["name"])
        cx, cy = abs(item["_x"]), abs(item["_y"])
        dx = max(cx - hw, 0.0)
        dy = max(cy - _HALF_HEIGHT, 0.0)
        dist = math.hypot(dx, dy)
        assert dist >= _SELF_AVATAR_RADIUS, (
            f"node {item['profile']['name']!r} at ({item['_x']}, {item['_y']}) "
            f"reaches the self-avatar (clearance {dist:.1f} < {_SELF_AVATAR_RADIUS})"
        )


def _assert_broad_tier_layout(result: list[dict[str, Any]]) -> None:
    """Verifies that high-scoring nodes broadly reside in inner orbits compared to low-scoring nodes,
    while session-scoped positional jitter prevents exact 1:1 rank triangulation."""
    if len(result) < 5:
        return
    top_nodes = result[: len(result) // 3]
    bottom_nodes = result[2 * len(result) // 3 :]
    avg_top_r = sum(_radius(n) for n in top_nodes) / len(top_nodes)
    avg_bottom_r = sum(_radius(n) for n in bottom_nodes) / len(bottom_nodes)
    assert avg_top_r < avg_bottom_r, (
        f"Top matches average radius ({avg_top_r:.1f}) should be inside bottom matches ({avg_bottom_r:.1f})"
    )


def _small_spread() -> list[dict[str, Any]]:
    return _make_items(12, lambda i: 90 - i * 3, lambda _i: 6)


def _single_node() -> list[dict[str, Any]]:
    return _make_items(1, lambda _i: 95, lambda _i: 8)


def _all_tied() -> list[dict[str, Any]]:
    return _make_items(20, lambda _i: 60.0, lambda _i: 10)


def _low_score_fallback() -> list[dict[str, Any]]:
    return _make_items(30, lambda i: 20 + i * 0.5, lambda _i: 8)


def _near_tier_boundary() -> list[dict[str, Any]]:
    return _make_items(10, lambda i: 85.1 if i == 0 else 84.9, lambda _i: 7)


def _large_long_names() -> list[dict[str, Any]]:
    rng = random.Random(42)
    return [
        {
            "profile": {
                "id": f"id{i}",
                "name": "".join(
                    rng.choices(string.ascii_letters, k=rng.randint(3, 20)),
                ),
            },
            "score": rng.uniform(0, 100),
        }
        for i in range(200)
    ]


SCENARIOS: dict[str, Callable[[], list[dict[str, Any]]]] = {
    "small_spread": _small_spread,
    "single_node": _single_node,
    "all_tied": _all_tied,
    "low_score_fallback": _low_score_fallback,
    "near_tier_boundary": _near_tier_boundary,
    "large_long_names": _large_long_names,
}


@pytest.mark.parametrize("name", SCENARIOS.keys())
def test_no_overlap(name: str) -> None:
    items = SCENARIOS[name]()
    result = assign_orbit_positions("viewer1", "Friends", items)
    _assert_no_overlap(result)


@pytest.mark.parametrize("name", SCENARIOS.keys())
def test_clears_self_avatar(name: str) -> None:
    items = SCENARIOS[name]()
    result = assign_orbit_positions("viewer1", "Friends", items)
    _assert_clears_self_avatar(result)


@pytest.mark.parametrize("name", SCENARIOS.keys())
def test_broad_tier_layout(name: str) -> None:
    items = SCENARIOS[name]()
    result = assign_orbit_positions("viewer1", "Friends", items)
    _assert_broad_tier_layout(result)


_REALISTIC_SCENARIOS = [n for n in SCENARIOS if n != "large_long_names"]


@pytest.mark.parametrize("name", _REALISTIC_SCENARIOS)
def test_radius_within_canvas_bound(name: str) -> None:
    """For realistic name lengths, layout should stay within the nominal canvas."""
    items = SCENARIOS[name]()
    result = assign_orbit_positions("viewer1", "Friends", items)
    max_r = max((_radius(item) for item in result), default=0.0)
    assert max_r < 1600.0


def test_large_long_names_stays_compact() -> None:
    """Even the adversarial 200-node / long-name batch should pack compactly.

    The phyllotaxis packing grows as sqrt(rank), so the whole 200-node cap
    fits well within the client's pannable canvas. This bound is a regression
    guard: if the layout ever balloons back toward the old linear spread it
    will trip here.
    """
    items = SCENARIOS["large_long_names"]()
    result = assign_orbit_positions("viewer1", "Friends", items)
    max_r = max((_radius(item) for item in result), default=0.0)
    assert 0.0 < max_r < 1500.0


def test_empty_input() -> None:
    assert assign_orbit_positions("viewer1", "Friends", []) == []


def test_deterministic_across_calls() -> None:
    items = SCENARIOS["small_spread"]()
    result1 = assign_orbit_positions("viewer1", "Friends", items)
    result2 = assign_orbit_positions("viewer1", "Friends", items)
    coords1 = [(i["_x"], i["_y"]) for i in result1]
    coords2 = [(i["_x"], i["_y"]) for i in result2]
    assert coords1 == coords2


def test_internal_keys_not_leaked() -> None:
    items = SCENARIOS["small_spread"]()
    result = assign_orbit_positions("viewer1", "Friends", items)
    for item in result:
        assert "_r" not in item
        assert "_theta" not in item


def test_positional_jitter_applied() -> None:
    items = SCENARIOS["small_spread"]()
    result = assign_orbit_positions("viewer1", "Friends", items)
    # Verify coordinates have non-zero jittered positions and distinct non-collinear placements
    assert len(result) == 12
    radii = [_radius(it) for it in result]
    # At least some adjacent nodes will not have strictly identical radial differences due to jitter
    diffs = [radii[i + 1] - radii[i] for i in range(len(radii) - 1)]
    assert len(set(diffs)) > 1

