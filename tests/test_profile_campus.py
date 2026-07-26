from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from pydantic import ValidationError

from app.api.user import update_profile_details
from app.models import MECOnboardingRequest, ProfileDetailsUpdate


def test_mec_onboarding_request_campus_name() -> None:
    # Valid campus name (at least 3 letters)
    req = MECOnboardingRequest(
        app_variant="nexus_mec",
        campus_branch="CS",
        campus_year=2,
        campus_name="Model Engineering College",
        age=20,
    )
    assert req.campus_name == "Model Engineering College"

    # Empty campus name should fail
    with pytest.raises(ValidationError) as excinfo:
        MECOnboardingRequest(
            app_variant="nexus_mec",
            campus_branch="CS",
            campus_year=2,
            campus_name="",
            age=20,
        )
    assert "Institute name is required" in str(excinfo.value)

    # Campus name with < 3 letters should fail
    with pytest.raises(ValidationError) as excinfo:
        MECOnboardingRequest(
            app_variant="nexus_mec",
            campus_branch="CS",
            campus_year=2,
            campus_name="AB",
            age=20,
        )
    assert "Institute name must contain at least three letters" in str(excinfo.value)


def test_profile_details_update_campus_name() -> None:
    # Valid campus name (at least 3 letters)
    update = ProfileDetailsUpdate(campus_name="Model Engineering College")
    assert update.campus_name == "Model Engineering College"

    # Empty campus name is allowed (coerced to empty string to allow clearing)
    update = ProfileDetailsUpdate(campus_name="  ")
    assert update.campus_name == ""

    # Campus name with < 3 letters should fail
    with pytest.raises(ValidationError) as excinfo:
        ProfileDetailsUpdate(campus_name="AB 12")
    assert "Institute name must contain at least three letters" in str(excinfo.value)


def test_profile_details_update_campus_year_restriction() -> None:
    # Selecting campus year when campus_name is empty should fail
    with pytest.raises(ValidationError) as excinfo:
        ProfileDetailsUpdate(campus_year=2, campus_name="")
    assert "Cannot select a campus year when institute is empty" in str(excinfo.value)

    # Selecting campus year when campus_name is not provided in payload is allowed
    # (since campus_name might exist in the database; endpoint-level logic handles this)
    update = ProfileDetailsUpdate(campus_year=2)
    assert update.campus_year == 2
    assert update.campus_name is None


@patch("app.api.user.supabase_client")
@patch("app.api.user.decrypt_profile_record")
def test_update_profile_details_endpoint_campus_validation(
    mock_decrypt: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    # Mock database profiles response when fetching profile details for validation
    mock_execute = MagicMock()
    chain = mock_supabase.table.return_value.select.return_value.eq.return_value.maybe_single
    chain.return_value.execute = mock_execute

    # Define a helper to mock DB state
    def set_db_state(campus_name: str, campus_year: int | None) -> None:
        mock_execute.return_value.data = {
            "campus_name": "encrypted_" + campus_name if campus_name else "",
            "campus_year": campus_year,
        }
        mock_decrypt.return_value = {
            "campus_name": campus_name,
            "campus_year": campus_year,
        }

    # Case 1: DB has empty campus name, and payload tries to set campus_year = 2.
    # This should raise HTTPException with status code 400.
    set_db_state(campus_name="", campus_year=None)
    payload = ProfileDetailsUpdate(campus_year=2)
    with pytest.raises(HTTPException) as excinfo:
        update_profile_details(
            background_tasks=MagicMock(),
            payload=payload,
            user_id="user123",
            _device=None,
        )
    assert excinfo.value.status_code == 400
    assert "Cannot select a campus year when institute is empty" in str(
        excinfo.value.detail,
    )

    # Case 2: Payload sets campus_name to less than 3 letters.
    # This is caught by Pydantic validator during model validation.
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(campus_name="AB")

    # Case 3: DB has valid campus name, payload sets campus_year = 2.
    # This should succeed and not raise.
    set_db_state(campus_name="Model Engineering College", campus_year=None)
    payload = ProfileDetailsUpdate(campus_year=2)
    # Mock the update call execution as well so it doesn't fail on final save
    update_chain = (
        mock_supabase.table.return_value.update.return_value.eq.return_value.execute
    )
    update_chain.return_value.data = {"status": "success"}

    res = update_profile_details(
        background_tasks=MagicMock(),
        payload=payload,
        user_id="user123",
        _device=None,
    )
    assert res == {"status": "success", "detail": "Profile details synchronized."}


@patch("app.db.profiles.supabase_client")
def test_build_candidate_query_open_bucket_expansion(mock_supabase: MagicMock) -> None:
    from app.db.profiles import (
        _build_candidate_query,
    )
    from app.models import DiscoveryFilters

    mock_query = MagicMock()
    mock_supabase.table.return_value = mock_query
    mock_query.select.return_value = mock_query
    mock_query.neq.return_value = mock_query
    mock_query.eq.return_value = mock_query
    mock_query.gte.return_value = mock_query
    mock_query.lte.return_value = mock_query
    mock_query.in_.return_value = mock_query
    mock_query.overlaps.return_value = mock_query

    filters = DiscoveryFilters(
        min_age=18,
        max_age=25,
        search_bucket_filter=["Open"],
    )

    _build_candidate_query(
        viewer_id="viewer123",
        active_tab="Dating",
        filters=filters,
        excluded_ids=set(),
        app_variant="nexus",
    )

    mock_query.in_.assert_any_call("search_bucket", ["M", "F", "NB"])
