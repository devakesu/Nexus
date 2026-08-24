from typing import Any
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
            request=MagicMock(),
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
        request=MagicMock(),
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


@patch("app.api.user.supabase_client")
@patch("app.api.user.decrypt_profile_record")
def test_update_profile_details_tab_activation_conditional_pic_check(
    mock_decrypt: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    # Initial fetch returns valid profile with pic
    mock_select = MagicMock()
    chain = mock_supabase.table.return_value.select.return_value.eq.return_value.maybe_single
    chain.return_value.execute = mock_select

    mock_select.return_value.data = {
        "name": "Alex",
        "age": 22,
        "profile_pic": "enc_pic",
        "normal_pics": "[]",
        "interests": "[]",
        "sub_interests": "[]",
        "drinking": "no",
        "smoking": "no",
        "partner_values": "[]",
        "dating_target_buckets": ["F"],
        "dating_for": ["relationship"],
        "bio": "Hello there my friend",
        "is_dating_active": False,
    }
    mock_decrypt.return_value = {
        "name": "Alex",
        "age": 22,
        "profile_pic": "https://img.example.com/pic.jpg",
        "normal_pics": ["https://img.example.com/normal1.jpg"],
        "sub_interests": {"tech": ["python", "fastapi"]},
        "drinking": "no",
        "smoking": "no",
        "partner_values": ["honesty"],
        "dating_target_buckets": ["F"],
        "dating_for": ["relationship"],
        "bio": "Hello there my friend",
        "is_dating_active": False,
    }

    # Simulate conditional update failure (e.g. pic was cleared concurrently)
    update_mock = MagicMock()
    mock_supabase.table.return_value.update.return_value.eq.return_value = update_mock
    update_mock.not_.is_.return_value.execute.return_value.data = []

    # And fallback select finds profile without pic
    fallback_select = MagicMock()
    fallback_select.execute.return_value.data = {"id": "user123", "profile_pic": None}
    chain.return_value = fallback_select

    payload = ProfileDetailsUpdate(is_dating_active=True)
    with pytest.raises(HTTPException) as excinfo:
        update_profile_details(
            request=MagicMock(),
            background_tasks=MagicMock(),
            payload=payload,
            user_id="user123",
            _device=None,
        )

    assert excinfo.value.status_code == 400
    assert "Cannot activate tab without a profile picture" in str(excinfo.value.detail)


@patch("app.api.user.supabase_client")
@patch("app.api.user.decrypt_profile_record")
def test_update_profile_details_activation_toctou_profile_pic_race(
    mock_decrypt: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    mock_select = MagicMock()
    chain = mock_supabase.table.return_value.select.return_value.eq.return_value.maybe_single
    chain.return_value.execute = mock_select

    mock_select.return_value.data = {
        "name": "Alex",
        "age": 22,
        "profile_pic": "enc_pic",
        "normal_pics": "[]",
        "interests": "[]",
        "sub_interests": "[]",
        "drinking": "no",
        "smoking": "no",
        "partner_values": "[]",
        "dating_target_buckets": ["F"],
        "dating_for": ["relationship"],
        "bio": "Hello there my friend",
        "is_dating_active": False,
    }
    mock_decrypt.return_value = {
        "name": "Alex",
        "age": 22,
        "profile_pic": "https://img.example.com/pic.jpg",
        "normal_pics": ["https://img.example.com/normal1.jpg"],
        "sub_interests": {"tech": ["python", "fastapi"]},
        "drinking": "no",
        "smoking": "no",
        "partner_values": ["honesty"],
        "dating_target_buckets": ["F"],
        "dating_for": ["relationship"],
        "bio": "Hello there my friend",
        "is_dating_active": False,
    }

    # Simulate conditional update failure
    update_mock = MagicMock()
    mock_supabase.table.return_value.update.return_value.eq.return_value = update_mock
    update_mock.not_.is_.return_value.execute.return_value.data = []

    # And fallback select finds profile where profile_pic was concurrently populated
    fallback_select = MagicMock()
    fallback_select.execute.return_value.data = {"id": "user123", "profile_pic": "https://example.com/pic.jpg"}
    chain.return_value = fallback_select

    payload = ProfileDetailsUpdate(is_dating_active=True)
    with pytest.raises(HTTPException) as excinfo:
        update_profile_details(
            request=MagicMock(),
            background_tasks=MagicMock(),
            payload=payload,
            user_id="user123",
            _device=None,
        )

    # Must raise 400 with "Cannot activate tab without a profile picture", NOT 404
    assert excinfo.value.status_code == 400
    assert "Cannot activate tab without a profile picture" in str(excinfo.value.detail)




def test_validate_common_activation_decryption_failed_profile_pic() -> None:
    from app.api.user.profile.helpers import _validate_common_activation

    profile = {
        "name": "Jane Doe",
        "age": 25,
        "sub_interests": {"tech": ["python", "fastapi"]},
        "profile_pic": "__DECRYPTION_FAILED__",
        "normal_pics": ["https://img.example.com/pic1.jpg"],
        "bio": "Software developer in the city.",
    }
    missing: list[str] = []
    _validate_common_activation(profile=profile, payload=ProfileDetailsUpdate(), missing=missing)

    assert "profile_pic" in missing


def test_validate_common_activation_decryption_failed_normal_pics() -> None:
    from app.api.user.profile.helpers import _validate_common_activation

    profile = {
        "name": "Jane Doe",
        "age": 25,
        "sub_interests": {"tech": ["python", "fastapi"]},
        "profile_pic": "https://img.example.com/pic.jpg",
        "normal_pics": ["__DECRYPTION_FAILED__"],
        "bio": "Software developer in the city.",
    }
    missing: list[str] = []
    _validate_common_activation(profile=profile, payload=ProfileDetailsUpdate(), missing=missing)

    assert "normal_pics" in missing


@patch("app.services.profile.generate_nexus_intent_embeddings")
@patch("app.services.profile.decrypt_profile_record")
@patch("app.services.profile.supabase_client")
def test_recompile_and_push_vectors_preserves_persisted_bio(
    mock_supabase: MagicMock,
    mock_decrypt: MagicMock,
    mock_embeddings: MagicMock,
) -> None:
    from app.services.profile import recompile_and_push_vectors

    # Mock profile fetch returning persisted bio
    mock_select = MagicMock()
    mock_supabase.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute = mock_select
    mock_select.return_value.data = {"id": "user123", "bio": "enc_persisted_bio"}
    mock_decrypt.return_value = {"id": "user123", "bio": "My persisted long bio."}

    # Mock pseudonym mapping and vector upsert
    mock_upsert = MagicMock()
    mock_supabase.table.return_value.upsert.return_value.select.return_value.execute.return_value.data = [{"pseudonym_id": "pseudo-123"}]
    mock_supabase.table.return_value.upsert.return_value.execute = mock_upsert

    mock_embeddings.return_value = {
        "bio_embedding": [0.1, 0.2],
        "career_embedding": [0.3, 0.4],
        "identity_embedding": [0.5, 0.6],
    }

    # Call with plaintext_bio=None (PATCH without bio update)
    recompile_and_push_vectors(user_id="user123", plaintext_bio=None)

    # Verify embeddings were generated with persisted bio, not empty string!
    mock_embeddings.assert_called_once()
    assert mock_embeddings.call_args[0][1] == "My persisted long bio."


@patch("app.api.user.settings.supabase_client")
def test_update_privacy_settings_filters_allowed_fields(mock_supabase: MagicMock) -> None:
    from fastapi import Request

    from app.api.user.settings import update_privacy_settings
    from app.models import PrivacySettingsUpdate

    mock_update_chain = mock_supabase.table.return_value.update.return_value.eq.return_value.select.return_value.execute
    mock_update_chain.return_value.data = [
        {
            "hidden_profile_fields": ["pronouns", "hometown"],
            "share_active_status": True,
            "share_read_receipts": False,
        },
    ]

    payload = PrivacySettingsUpdate(
        hidden_fields=["pronouns", "hometown"],
        share_read_receipts=False,
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/profile/privacy-settings",
    }
    request = Request(scope)

    res = update_privacy_settings(
        request=request,
        payload=payload,
        user_id="user123",
        _device=None,
    )

    assert res.share_read_receipts is False
    assert set(res.hidden_fields) == {"pronouns", "hometown"}

    # Verify update payload written to DB
    update_call_arg = mock_supabase.table.return_value.update.call_args[0][0]
    assert "hidden_profile_fields" in update_call_arg
    for f in update_call_arg["hidden_profile_fields"]:
        assert f in {"pronouns", "hometown"}


@patch("app.api.user.settings.supabase_client")
def test_update_privacy_settings_disabling_active_status(mock_supabase: MagicMock) -> None:
    from fastapi import Request

    from app.api.user.settings import update_privacy_settings
    from app.models import PrivacySettingsUpdate

    mock_update_chain = mock_supabase.table.return_value.update.return_value.eq.return_value.select.return_value.execute
    mock_update_chain.return_value.data = [
        {
            "hidden_profile_fields": [],
            "share_active_status": False,
            "share_read_receipts": True,
        },
    ]

    payload = PrivacySettingsUpdate(share_active_status=False)
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/profile/privacy-settings",
    }
    request = Request(scope)

    res = update_privacy_settings(
        request=request,
        payload=payload,
        user_id="user123",
        _device=None,
    )

    assert res.share_active_status is False


@patch("app.api.user.settings.supabase_client")
def test_update_email_notification_settings_allowlist(mock_supabase: MagicMock) -> None:
    from fastapi import Request

    from app.api.user.settings import update_email_notification_settings
    from app.models import EmailNotificationSettingsUpdate

    mock_update_chain = mock_supabase.table.return_value.update.return_value.eq.return_value.select.return_value.execute
    mock_update_chain.return_value.data = [
        {
            "email_notify_matches": True,
            "email_notify_messages": False,
            "email_notify_digest": True,
            "email_notify_product_updates": False,
            "email_notify_promotions": False,
        },
    ]

    payload = EmailNotificationSettingsUpdate(
        email_notify_messages=False,
        email_notify_promotions=False,
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/profile/email-notification-settings",
    }
    request = Request(scope)

    res = update_email_notification_settings(
        request=request,
        payload=payload,
        user_id="user123",
        _device=None,
    )

    assert res.email_notify_messages is False
    assert res.email_notify_promotions is False
    assert res.email_notify_matches is True

    # Verify update payload passed to DB contains strictly allowlisted fields
    update_call_arg = mock_supabase.table.return_value.update.call_args[0][0]
    assert update_call_arg == {
        "email_notify_messages": False,
        "email_notify_promotions": False,
    }


@patch("app.api.user.settings.supabase_client")
def test_update_email_notification_settings_empty_raises_400(mock_supabase: MagicMock) -> None:
    from fastapi import HTTPException, Request

    from app.api.user.settings import update_email_notification_settings
    from app.models import EmailNotificationSettingsUpdate

    payload = EmailNotificationSettingsUpdate()
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/profile/email-notification-settings",
    }
    request = Request(scope)

    import pytest

    with pytest.raises(HTTPException) as exc_info:
        update_email_notification_settings(
            request=request,
            payload=payload,
            user_id="user123",
            _device=None,
        )
    assert exc_info.value.status_code == 400
    assert exc_info.value.detail == "No fields to update."


@patch("app.db.profiles.crud.supabase_client")
def test_is_active_profile_returns_true_for_active_user(mock_supabase: MagicMock) -> None:
    from app.db.profiles import is_active_profile

    mock_supabase.table.return_value.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value.data = [
        {"id": "11111111-1111-1111-1111-111111111111"}
    ]

    assert is_active_profile("11111111-1111-1111-1111-111111111111") is True


@patch("app.db.profiles.crud.supabase_client")
def test_is_active_profile_returns_false_for_inactive_or_missing(mock_supabase: MagicMock) -> None:
    from app.db.profiles import is_active_profile

    mock_supabase.table.return_value.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value.data = []

    assert is_active_profile("11111111-1111-1111-1111-111111111111") is False
    assert is_active_profile("not-a-valid-uuid") is False


@patch("app.db.profiles.crud.supabase_client")
def test_fetch_music_affinities_success(mock_supabase: MagicMock) -> None:
    import json
    from app.core.security.crypto import encrypt_to_hex
    from app.db.profiles import fetch_music_affinities

    mock_supabase.table.return_value.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value.data = [
        {
            "artist_affinity": encrypt_to_hex(json.dumps({"The Beatles": 1.0})),
            "genre_affinity": encrypt_to_hex(json.dumps({"Rock": 0.8})),
        }
    ]

    artists, genres = fetch_music_affinities("11111111-1111-1111-1111-111111111111")
    assert artists == {"The Beatles": 1.0}
    assert genres == {"Rock": 0.8}

    # Verify query strictly selected only artist_affinity and genre_affinity
    select_call = mock_supabase.table.return_value.select.call_args[0][0]
    assert select_call == "artist_affinity, genre_affinity"


@patch("app.db.profiles.crud.supabase_client")
def test_fetch_music_affinities_missing_or_invalid(mock_supabase: MagicMock) -> None:
    from app.db.profiles import fetch_music_affinities

    mock_supabase.table.return_value.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value.data = []

    artists, genres = fetch_music_affinities("11111111-1111-1111-1111-111111111111")
    assert artists == {}
    assert genres == {}

    artists, genres = fetch_music_affinities("invalid-uuid")
    assert artists == {}
    assert genres == {}







