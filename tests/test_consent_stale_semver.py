"""Unit tests for is_consent_stale semver comparison."""

from app.api.dependencies import is_consent_stale


def test_is_consent_stale_handles_two_digit_minor_semver_correctly() -> None:
    """is_consent_stale must correctly compare multi-digit semver components."""
    # Stored 1.1 is stale when required version is 1.10
    assert is_consent_stale("1.1", "1.10") is True

    # Stored 1.9 is stale when required version is 1.10
    assert is_consent_stale("1.9", "1.10") is True

    # Stored 1.10 equals required version 1.10 (not stale)
    assert is_consent_stale("1.10", "1.10") is False

    # Stored 1.11 is newer than required version 1.10 (not stale)
    assert is_consent_stale("1.11", "1.10") is False

    # Patch version multi-digit comparisons
    assert is_consent_stale("2.0.1", "2.0.10") is True
    assert is_consent_stale("2.0.10", "2.0.10") is False
    assert is_consent_stale("2.0.11", "2.0.10") is False


def test_is_consent_stale_missing_or_invalid_versions_fail_safe() -> None:
    """Missing or invalid versions must fail-safe and evaluate as stale (True)."""
    assert is_consent_stale(None, "1.0") is True
    assert is_consent_stale("", "1.0") is True
    assert is_consent_stale("invalid_version", "1.0") is True
    assert is_consent_stale("1.0", "invalid_req_version") is True
