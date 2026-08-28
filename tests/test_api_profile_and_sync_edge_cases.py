"""Unit tests for edge cases in profile media, moderation lookups, and cross-flavor sync APIs."""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.api.user.profile.media import update_profile_media_and_tags
from app.api.user.profile.moderation import get_moderation_subjects
from app.api.user.sync import (
    _record_failed_attempt,
    create_export_code,
    import_from_flavor,
)
from app.models import (
    ImportRequest,
    ModerationSubjectsRequest,
    ProfileImagesAndTagsUpdate,
)

TARGET_UUID = "11111111-1111-1111-1111-111111111111"
USER_UUID = "22222222-2222-2222-2222-222222222222"


@pytest.mark.anyio
async def test_update_profile_media_error_mappings():
    """Test ValueError mapping to 404 and unexpected errors mapping to 500 in media update."""
    payload = ProfileImagesAndTagsUpdate(
        profile_pic=f"{USER_UUID}/profile.jpg",
        normal_pics=[f"{USER_UUID}/normal1.jpg"],
        ai_vibe_tags=["tech", "music"],
    )

    # 1. ValueError -> 404
    with patch("app.api.user.profile.media.update_profile_images_and_metadata", side_effect=ValueError("Mismatch")):
        with pytest.raises(HTTPException) as exc_info:
            await update_profile_media_and_tags(
                request=MagicMock(),
                payload=payload,
                user_id=USER_UUID,
                _device=None,
            )
        assert exc_info.value.status_code == 404

    # 2. General Exception -> 500
    with patch("app.api.user.profile.media.update_profile_images_and_metadata", side_effect=RuntimeError("DB exploded")):
        with pytest.raises(HTTPException) as exc_info:
            await update_profile_media_and_tags(
                request=MagicMock(),
                payload=payload,
                user_id=USER_UUID,
                _device=None,
            )
        assert exc_info.value.status_code == 500


def test_get_moderation_subjects_decryption_fallback_and_error():
    """Test decryption error fallback to raw sanitized profile, and query error handling."""
    payload = ModerationSubjectsRequest(target_ids=[TARGET_UUID])

    mock_valid_actions = MagicMock(data=[{"target_id": TARGET_UUID}])
    mock_profiles = MagicMock(
        data=[
            {
                "id": TARGET_UUID,
                "name": "Fallback Name",
                "age": 21,
                "campus_year": "Senior",
                "campus_name": "MIT",
                "campus_branch": "CS",
                "hometown": "Boston",
                "current_place": "Cambridge",
                "profile_pic": f"{TARGET_UUID}/pic.jpg",
            },
        ],
    )

    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.in_.return_value.in_.return_value.is_.return_value.execute.return_value = mock_valid_actions
    mock_table.select.return_value.in_.return_value.eq.return_value.execute.return_value = mock_profiles

    # 1. Decryption error falls back to sanitized raw dict
    with patch("app.api.user.profile.moderation.supabase_client.table", return_value=mock_table):
        with patch("app.api.user.profile.moderation.decrypt_profile_record", side_effect=ValueError("Corrupted PII")):
            with patch("app.api.user.profile.moderation.sign_profile_media_bulk"):
                res = get_moderation_subjects(
                    request=MagicMock(),
                    payload=payload,
                    _device=None,
                    user_id=USER_UUID,
                )
                assert len(res) == 1
                assert res[0]["name"] == "Fallback Name"

    # 2. General error raises HTTPException(500)
    mock_table_err = MagicMock()
    mock_table_err.select.return_value.eq.return_value.in_.return_value.in_.return_value.is_.return_value.execute.side_effect = RuntimeError("Crash")
    with patch("app.api.user.profile.moderation.supabase_client.table", return_value=mock_table_err):
        with pytest.raises(HTTPException) as exc_info:
            get_moderation_subjects(
                request=MagicMock(),
                payload=payload,
                _device=None,
                user_id=USER_UUID,
            )
        assert exc_info.value.status_code == 500


@pytest.mark.anyio
async def test_sync_export_code_edge_cases():
    """Test sync export code empty ID, missing profile, missing user, and nexus variant 403."""
    # 1. Empty user_id -> 401
    with pytest.raises(HTTPException) as exc_info:
        await create_export_code(request=MagicMock(), _device=None, auth_user={"id": ""})
    assert exc_info.value.status_code == 401

    # 2. Missing profile -> 404
    with patch("app.api.user.sync.fetch_profile", return_value=None):
        with pytest.raises(HTTPException) as exc_info:
            await create_export_code(request=MagicMock(), _device=None, auth_user={"id": USER_UUID})
        assert exc_info.value.status_code == 404

    # 3. Missing user bootstrap row -> 404
    with patch("app.api.user.sync.fetch_profile", return_value={"id": USER_UUID}):
        with patch("app.api.user.sync.fetch_public_user", return_value=None):
            with pytest.raises(HTTPException) as exc_info:
                await create_export_code(request=MagicMock(), _device=None, auth_user={"id": USER_UUID})
            assert exc_info.value.status_code == 404

    # 4. Main 'nexus' variant attempting export -> 403
    with patch("app.api.user.sync.fetch_profile", return_value={"id": USER_UUID}):
        with patch("app.api.user.sync.fetch_public_user", return_value={"id": USER_UUID, "app_variant": "nexus", "account_status": "active"}):
            with pytest.raises(HTTPException) as exc_info:
                await create_export_code(request=MagicMock(), _device=None, auth_user={"id": USER_UUID})
            assert exc_info.value.status_code == 403


@pytest.mark.anyio
async def test_sync_import_edge_cases_and_rate_limiting():
    """Test sync import empty user_id, non-nexus caller 403, and failed attempt rate limiting."""
    payload = ImportRequest(sync_code="ABC123")

    # 1. Empty user_id -> 401
    with pytest.raises(HTTPException) as exc_info:
        await import_from_flavor(request=MagicMock(), payload=payload, _device=None, auth_user={"id": ""})
    assert exc_info.value.status_code == 401

    # 2. Non-nexus user attempting import -> 403
    with patch("app.api.user.sync._check_import_rate_limits", return_value=("key1", "key2")):
        with patch("app.api.user.sync.fetch_public_user", return_value={"id": USER_UUID, "app_variant": "nexus_mec", "account_status": "active"}):
            with pytest.raises(HTTPException) as exc_info:
                await import_from_flavor(request=MagicMock(), payload=payload, _device=None, auth_user={"id": USER_UUID})
            assert exc_info.value.status_code == 403

    # 3. Failed attempt counting triggers 429
    with patch("app.api.user.sync._check_import_rate_limits", return_value=("key1", "key2")):
        with patch("app.api.user.sync.fetch_public_user", return_value={"id": USER_UUID, "app_variant": "nexus", "account_status": "active"}):
            with patch("app.api.user.sync.execute_import", side_effect=HTTPException(status_code=400, detail="Invalid or already-used sync code.")):
                with patch("app.api.user.sync._record_failed_attempt", side_effect=[5, 1]):
                    with pytest.raises(HTTPException) as exc_info:
                        await import_from_flavor(request=MagicMock(), payload=payload, _device=None, auth_user={"id": USER_UUID})
                    assert exc_info.value.status_code == 429

                with patch("app.api.user.sync._record_failed_attempt", side_effect=[1, 10]):
                    with pytest.raises(HTTPException) as exc_info:
                        await import_from_flavor(request=MagicMock(), payload=payload, _device=None, auth_user={"id": USER_UUID})
                    assert exc_info.value.status_code == 429

    # 4. _record_failed_attempt Redis exception fallback returns 1
    with patch("app.api.user.sync.redis_client.incr", side_effect=Exception("Redis down")):
        count = await _record_failed_attempt("key-test")
        assert count == 1
