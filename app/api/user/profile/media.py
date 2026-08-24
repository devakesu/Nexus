"""Profile media uploads and vibe tag synchronization endpoint."""

import logging

from fastapi import APIRouter, Body, Depends, HTTPException, Request, status

from app.api.dependencies import (
    get_active_user_id,
    verify_app_check_with_replay_protection,
)
from app.core.infra.limiter import limiter
from app.db.profiles import update_profile_images_and_metadata
from app.models import ProfileImagesAndTagsUpdate

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post("/api/v1/profile/media", status_code=status.HTTP_200_OK)
@limiter.limit("5/minute")
async def update_profile_media_and_tags(
    request: Request,
    payload: ProfileImagesAndTagsUpdate = Body(...),
    user_id: str = Depends(get_active_user_id),
    _device: None = Depends(verify_app_check_with_replay_protection),
):
    """Update user's profile image paths and AI vibe tags."""
    _ = request
    own_prefix = f"{user_id}/"
    for pic in [payload.profile_pic, *payload.normal_pics]:
        if not pic.startswith(own_prefix) or ".." in pic or "\\" in pic or "\x00" in pic:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Media paths must reference only your own uploaded assets.",
            )
    try:
        await update_profile_images_and_metadata(
            user_id=user_id,
            images=[payload.profile_pic, *payload.normal_pics],
            vibe_tags=payload.ai_vibe_tags,
        )
        return {"status": "success", "detail": "Profile media synchronized."}
    except ValueError as err:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=(
                "Target account context mismatch. Profile row modification rejected."
            ),
        ) from err
    except Exception as e:
        logger.exception("Profile media update failed for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server metadata pipeline error: Data synchronization failed.",
        ) from e
