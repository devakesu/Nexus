"""Unit tests for F-08: in-memory lifestyle filter replacing low-cardinality blind indexes."""

from typing import Any
from unittest.mock import MagicMock, patch

from app.db.profiles.crud import _apply_post_fetch_filters, _check_lifestyle_filters
from app.models import DiscoveryFilters


def _make_candidate(
    drinking: str | None = None,
    smoking: str | None = None,
    children_plans: str | None = None,
    religious_beliefs: str | None = None,
) -> dict[str, Any]:
    """Return a candidate dict simulating pre-decrypted profile state."""
    return {
        "id": "test-id",
        "drinking": drinking,
        "smoking": smoking,
        "children_plans": children_plans,
        "religious_beliefs": religious_beliefs,
    }


def _no_op_decrypt(row: dict[str, Any], field: str) -> None:
    """decrypt_profile_field no-op: candidate is already plaintext in test."""
    pass


@patch("app.db.profiles.crud.decrypt_profile_field", side_effect=_no_op_decrypt)
class TestCheckLifestyleFilters:

    def test_passes_when_no_filters(self, _mock: MagicMock) -> None:
        c: dict[str, Any] = _make_candidate(drinking="Never")
        assert _check_lifestyle_filters(c, DiscoveryFilters()) is True

    def test_passes_when_value_in_allowed(self, _mock: MagicMock) -> None:
        c: dict[str, Any] = _make_candidate(drinking="Never")
        f = DiscoveryFilters(drinking=["Never", "Socially"])
        assert _check_lifestyle_filters(c, f) is True

    def test_fails_when_value_not_in_allowed(self, _mock: MagicMock) -> None:
        c: dict[str, Any] = _make_candidate(drinking="Regularly")
        f = DiscoveryFilters(drinking=["Never"])
        assert _check_lifestyle_filters(c, f) is False

    def test_case_insensitive_match(self, _mock: MagicMock) -> None:
        c: dict[str, Any] = _make_candidate(drinking="never")
        f = DiscoveryFilters(drinking=["Never"])
        assert _check_lifestyle_filters(c, f) is True

    def test_null_value_fails_when_filter_active(self, _mock: MagicMock) -> None:
        c: dict[str, Any] = _make_candidate(drinking=None)
        f = DiscoveryFilters(drinking=["Never"])
        assert _check_lifestyle_filters(c, f) is False

    def test_all_four_fields_pass(self, _mock: MagicMock) -> None:
        c: dict[str, Any] = _make_candidate(
            drinking="Never",
            smoking="Never",
            children_plans="Someday",
            religious_beliefs="Spiritual",
        )
        f = DiscoveryFilters(
            drinking=["Never"],
            smoking=["Never"],
            children_plans=["Someday"],
            religious_beliefs=["Spiritual", "Agnostic"],
        )
        assert _check_lifestyle_filters(c, f) is True

    def test_one_mismatch_fails_all(self, _mock: MagicMock) -> None:
        c: dict[str, Any] = _make_candidate(
            drinking="Never",
            smoking="Regularly",  # mismatch
            children_plans="Someday",
            religious_beliefs="Spiritual",
        )
        f = DiscoveryFilters(
            drinking=["Never"],
            smoking=["Never"],
            children_plans=["Someday"],
            religious_beliefs=["Spiritual"],
        )
        assert _check_lifestyle_filters(c, f) is False

    def test_apply_post_fetch_filters_integration(self, _mock: MagicMock) -> None:
        c1: dict[str, Any] = _make_candidate(drinking="Never", smoking="Never")
        c2: dict[str, Any] = _make_candidate(drinking="Regularly", smoking="Never")
        candidates: list[dict[str, Any]] = [c1, c2]
        f = DiscoveryFilters(drinking=["Never"])
        res = _apply_post_fetch_filters(candidates, f)
        assert len(res) == 1
        assert res[0]["drinking"] == "Never"
