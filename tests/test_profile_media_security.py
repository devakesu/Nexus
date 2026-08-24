"""Tests for profile media storage path IDOR, traversal prevention, and signing security."""

from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request, status
from pydantic import ValidationError

from app.api.user.profile.details import update_profile_details
from app.api.user.profile.media import update_profile_media_and_tags
from app.db.profiles.media import (
    _is_safe_media_path,
    sign_profile_media,
    sign_profile_media_bulk,
    update_profile_images_and_metadata,
)
from app.models import ProfileDetailsUpdate, ProfileImagesAndTagsUpdate


def _make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/profile/media",
    }
    return Request(scope)


# ---------------------------------------------------------------------------
# 1. Pydantic Model Validation Tests
# ---------------------------------------------------------------------------


def test_profile_images_and_tags_update_accepts_valid_paths() -> None:
    payload = ProfileImagesAndTagsUpdate(
        profile_pic="11111111-1111-1111-1111-111111111111/photo_123.jpg",
        normal_pics=[
            "11111111-1111-1111-1111-111111111111/photo_124.jpg",
            "11111111-1111-1111-1111-111111111111/photo_125.jpg",
        ],
        ai_vibe_tags=["aesthetic", "analog-vibe"],
    )
    assert payload.profile_pic == "11111111-1111-1111-1111-111111111111/photo_123.jpg"
    assert len(payload.normal_pics) == 2


@pytest.mark.parametrize(
    "invalid_path",
    [
        "../victim/photo.jpg",
        "user123/../../etc/passwd",
        "user123/..%2f..%2fphoto.jpg",
        "user123/..",
        "user123\\photo.jpg",
        "/user123/photo.jpg",
        "user123/\x00photo.jpg",
    ],
)
def test_profile_images_and_tags_update_rejects_unsafe_profile_pic(invalid_path: str) -> None:
    with pytest.raises(ValidationError) as exc_info:
        ProfileImagesAndTagsUpdate(
            profile_pic=invalid_path,
            normal_pics=[],
            ai_vibe_tags=["aesthetic"],
        )
    assert "Validation Error: Profile picture path contains invalid characters" in str(exc_info.value)


@pytest.mark.parametrize(
    "invalid_path",
    [
        "../victim/photo.jpg",
        "user123/../../etc/passwd",
        "user123\\photo.jpg",
        "/user123/photo.jpg",
        "user123/\x00photo.jpg",
    ],
)
def test_profile_images_and_tags_update_rejects_unsafe_normal_pics(invalid_path: str) -> None:
    with pytest.raises(ValidationError) as exc_info:
        ProfileImagesAndTagsUpdate(
            profile_pic="user123/photo_main.jpg",
            normal_pics=[invalid_path],
            ai_vibe_tags=["aesthetic"],
        )
    assert "Validation Error: Gallery image path contains invalid characters" in str(exc_info.value)


@pytest.mark.parametrize(
    "invalid_path",
    [
        "../victim/photo.jpg",
        "user123\\photo.jpg",
        "/user123/photo.jpg",
        "user123/\x00photo.jpg",
    ],
)
def test_profile_details_update_rejects_unsafe_paths(invalid_path: str) -> None:
    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(profile_pic=invalid_path)

    with pytest.raises(ValidationError):
        ProfileDetailsUpdate(normal_pics=[invalid_path])


# ---------------------------------------------------------------------------
# 2. Endpoint Ownership Enforcement Tests (POST /api/v1/profile/media)
# ---------------------------------------------------------------------------


@pytest.mark.anyio
async def test_update_profile_media_rejects_foreign_user_prefix() -> None:
    attacker_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    victim_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

    payload = ProfileImagesAndTagsUpdate(
        profile_pic=f"{victim_id}/photo_victim.jpg",
        normal_pics=[],
        ai_vibe_tags=["aesthetic"],
    )

    with pytest.raises(HTTPException) as exc_info:
        await update_profile_media_and_tags(
            request=_make_dummy_request(),
            payload=payload,
            user_id=attacker_id,
            _device=None,
        )
    assert exc_info.value.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY
    assert "Media paths must reference only your own uploaded assets" in exc_info.value.detail


@pytest.mark.anyio
async def test_update_profile_media_rejects_foreign_normal_pics() -> None:
    attacker_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    victim_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

    payload = ProfileImagesAndTagsUpdate(
        profile_pic=f"{attacker_id}/photo_attacker.jpg",
        normal_pics=[f"{victim_id}/secret_photo.jpg"],
        ai_vibe_tags=["aesthetic"],
    )

    with pytest.raises(HTTPException) as exc_info:
        await update_profile_media_and_tags(
            request=_make_dummy_request(),
            payload=payload,
            user_id=attacker_id,
            _device=None,
        )
    assert exc_info.value.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY
    assert "Media paths must reference only your own uploaded assets" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.user.profile.media.update_profile_images_and_metadata")
async def test_update_profile_media_accepts_own_prefix(
    mock_update: AsyncMock,
) -> None:
    user_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

    payload = ProfileImagesAndTagsUpdate(
        profile_pic=f"{user_id}/avatar.jpg",
        normal_pics=[f"{user_id}/gallery_1.jpg"],
        ai_vibe_tags=["aesthetic"],
    )

    res = await update_profile_media_and_tags(
        request=_make_dummy_request(),
        payload=payload,
        user_id=user_id,
        _device=None,
    )
    assert res == {"status": "success", "detail": "Profile media synchronized."}
    mock_update.assert_awaited_once_with(
        user_id=user_id,
        images=[f"{user_id}/avatar.jpg", f"{user_id}/gallery_1.jpg"],
        vibe_tags=["aesthetic"],
    )


# ---------------------------------------------------------------------------
# 3. Endpoint Ownership Enforcement Tests (PATCH /api/v1/profile/details)
# ---------------------------------------------------------------------------


@patch("app.api.user.profile.details.fetch_public_user")
@patch("app.api.user.profile.details.user_module.supabase_client")
def test_update_profile_details_rejects_foreign_profile_pic(
    mock_supabase: MagicMock,
    mock_fetch_public_user: MagicMock,
) -> None:
    _ = mock_supabase
    _ = mock_fetch_public_user
    attacker_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    victim_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

    payload = ProfileDetailsUpdate(
        profile_pic=f"{victim_id}/photo_victim.jpg",
    )

    background_tasks = MagicMock()
    with pytest.raises(HTTPException) as exc_info:
        update_profile_details(
            background_tasks=background_tasks,
            payload=payload,
            user_id=attacker_id,
            _device=None,
        )
    assert exc_info.value.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY
    assert "Media paths must reference only your own uploaded assets" in exc_info.value.detail


@patch("app.api.user.profile.details.fetch_public_user")
@patch("app.api.user.profile.details.user_module.supabase_client")
def test_update_profile_details_rejects_foreign_normal_pics(
    mock_supabase: MagicMock,
    mock_fetch_public_user: MagicMock,
) -> None:
    _ = mock_supabase
    _ = mock_fetch_public_user
    attacker_id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    victim_id = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"

    payload = ProfileDetailsUpdate(
        normal_pics=[f"{victim_id}/photo_victim.jpg"],
    )

    background_tasks = MagicMock()
    with pytest.raises(HTTPException) as exc_info:
        update_profile_details(
            background_tasks=background_tasks,
            payload=payload,
            user_id=attacker_id,
            _device=None,
        )
    assert exc_info.value.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY
    assert "Media paths must reference only your own uploaded assets" in exc_info.value.detail


# ---------------------------------------------------------------------------
# 4. DB Layer Defense-In-Depth & Signing Tests
# ---------------------------------------------------------------------------


@pytest.mark.anyio
async def test_update_profile_images_and_metadata_rejects_foreign_paths() -> None:
    user_id = "11111111-1111-1111-1111-111111111111"
    victim_path = "22222222-2222-2222-2222-222222222222/photo.jpg"

    with pytest.raises(ValueError) as exc_info:
        await update_profile_images_and_metadata(
            user_id=user_id,
            images=[victim_path],
            vibe_tags=["aesthetic"],
        )
    assert "Invalid media path for user" in str(exc_info.value)


def test_is_safe_media_path() -> None:
    assert _is_safe_media_path("user123/photo.jpg") is True
    assert _is_safe_media_path("../victim/photo.jpg") is False
    assert _is_safe_media_path("user123/../photo.jpg") is False
    assert _is_safe_media_path("user123\\photo.jpg") is False
    assert _is_safe_media_path("/user123/photo.jpg") is False
    assert _is_safe_media_path("user123/\x00photo.jpg") is False
    assert _is_safe_media_path("") is False


@patch("app.db.profiles.media.supabase_client")
def test_sign_profile_media_ignores_foreign_paths(mock_supabase: MagicMock) -> None:
    owner_id = "11111111-1111-1111-1111-111111111111"
    victim_id = "22222222-2222-2222-2222-222222222222"

    mock_storage = mock_supabase.storage.from_.return_value
    mock_storage.create_signed_urls.return_value = [
        {"path": f"{owner_id}/photo.jpg", "signedURL": "https://signed/owner.jpg"},
    ]

    row = {
        "id": owner_id,
        "profile_pic": f"{victim_id}/secret.jpg",  # Foreign path
        "normal_pics": [f"{owner_id}/photo.jpg", f"{victim_id}/secret2.jpg"],
    }

    signed_row = sign_profile_media(row)
    # Foreign profile_pic should be wiped/ignored and NOT signed
    assert signed_row["profile_pic"] is None
    # Only valid owner paths should be signed
    assert signed_row["normal_pics"] == ["https://signed/owner.jpg"]

    # Verify create_signed_urls was only called with owner's legitimate path
    mock_storage.create_signed_urls.assert_called_once_with(
        [f"{owner_id}/photo.jpg"],
        3600,
    )


@patch("app.db.profiles.media.supabase_client")
def test_sign_profile_media_bulk_ignores_foreign_paths(mock_supabase: MagicMock) -> None:
    owner_id = "11111111-1111-1111-1111-111111111111"
    victim_id = "22222222-2222-2222-2222-222222222222"

    mock_storage = mock_supabase.storage.from_.return_value
    mock_storage.create_signed_urls.return_value = [
        {"path": f"{owner_id}/pic.jpg", "signedURL": "https://signed/owner.jpg"},
    ]

    rows = [
        {"id": owner_id, "profile_pic": f"{owner_id}/pic.jpg"},
        {"id": victim_id, "profile_pic": f"{owner_id}/stolen.jpg"},  # Foreign path
        {"id": owner_id, "profile_pic": "../traversal/pic.jpg"},  # Traversal path
    ]

    sign_profile_media_bulk(rows)
    assert rows[0]["profile_pic"] == "https://signed/owner.jpg"
    assert rows[1]["profile_pic"] is None
    assert rows[2]["profile_pic"] is None
