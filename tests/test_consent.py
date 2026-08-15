from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.db.users.consent import (
    _parse_version_tuple,
    _update_consent_pair,
    _validate_terms_versions,
)


def test_parse_version_tuple_semver_ordering():
    v1_1 = _parse_version_tuple("1.1")
    v1_10 = _parse_version_tuple("1.10")
    v2_0 = _parse_version_tuple("2.0")

    assert v1_1 == (1, 1)
    assert v1_10 == (1, 10)
    assert v2_0 == (2, 0)

    # Crucial test: 1.10 must be strictly greater than 1.1 (previously broken by float casting)
    assert v1_10 > v1_1
    assert v2_0 > v1_10


def test_validate_terms_versions_matching():
    with patch("app.db.users.consent.settings.current_terms_version", "1.10"):
        # Matches server version
        _validate_terms_versions("1.10")

        # Different version -> 409 Conflict
        with pytest.raises(HTTPException) as exc_info:
            _validate_terms_versions("1.1")
        assert exc_info.value.status_code == 409

        # Malformed version string -> 400 Bad Request
        with pytest.raises(HTTPException) as exc_info:
            _validate_terms_versions("invalid_v1")
        assert exc_info.value.status_code == 400


@patch("app.db.users.consent.invalidate_user_status_cache")
@patch("app.db.users.consent._fetch_existing_consent_pair")
@patch("app.db.users.consent.supabase_client.table")
def test_update_consent_pair_downgrade_rejected(
    mock_table: MagicMock,
    mock_fetch: MagicMock,
    _mock_invalidate: MagicMock,
):
    # Existing user has version 1.10 accepted
    mock_fetch.return_value = {
        "accepted_terms_version": "1.10",
        "terms_accepted_at": "2026-08-01T12:00:00Z",
    }

    # Attempting to set version 1.1 should be rejected as a downgrade
    with pytest.raises(HTTPException) as exc_info:
        _update_consent_pair(
            user_id="user-123",
            version_column="accepted_terms_version",
            timestamp_column="terms_accepted_at",
            cleaned_version="1.1",
        )

    assert exc_info.value.status_code == 409
    assert "cannot be downgraded" in exc_info.value.detail
    mock_table.assert_not_called()


@patch("app.db.users.consent.invalidate_user_status_cache")
@patch("app.db.users.consent._fetch_existing_consent_pair")
def test_update_consent_pair_noop_for_same_version(
    mock_fetch: MagicMock,
    _mock_invalidate: MagicMock,
):
    mock_fetch.return_value = {
        "accepted_terms_version": "1.10",
        "terms_accepted_at": "2026-08-01T12:00:00Z",
    }

    version, ts = _update_consent_pair(
        user_id="user-123",
        version_column="accepted_terms_version",
        timestamp_column="terms_accepted_at",
        cleaned_version="1.10",
    )

    assert version == "1.10"
    assert ts.year == 2026


@patch("app.db.users.consent._log_consent_event")
@patch("app.db.users.consent.settings.current_terms_version", "1.0")
@patch("app.db.users.consent._fetch_existing_consent_pair")
def test_update_special_category_consent_requires_general_terms(
    mock_fetch: MagicMock,
    _mock_log: MagicMock,
):
    from app.db.users.consent import update_special_category_consent

    # User has NOT accepted general terms
    mock_fetch.return_value = {
        "accepted_terms_version": None,
        "terms_accepted_at": None,
    }

    with pytest.raises(HTTPException) as exc_info:
        update_special_category_consent(
            user_id="user-123",
            terms_version="1.0",
            granted=True,
        )

    assert exc_info.value.status_code == 409
    assert "General terms must be accepted" in exc_info.value.detail


@patch("app.db.users.consent._log_consent_event")
@patch("app.db.users.consent.settings.current_terms_version", "1.0")
@patch("app.db.users.consent._fetch_existing_consent_pair")
def test_update_safety_data_consent_requires_general_terms(
    mock_fetch: MagicMock,
    _mock_log: MagicMock,
):
    from app.db.users.consent import update_safety_data_consent

    # User has NOT accepted general terms
    mock_fetch.return_value = {
        "accepted_terms_version": None,
        "terms_accepted_at": None,
    }

    with pytest.raises(HTTPException) as exc_info:
        update_safety_data_consent(
            user_id="user-123",
            terms_version="1.0",
            granted=True,
        )

    assert exc_info.value.status_code == 409
    assert "General terms must be accepted" in exc_info.value.detail

