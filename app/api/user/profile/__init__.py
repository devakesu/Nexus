"""Profile media updates, details GET/PATCH endpoints, and moderation subjects lookup package."""

from fastapi import APIRouter

from app.api.user.profile.details import (
    get_profile_details,
    update_profile_details,
)
from app.api.user.profile.details import (
    router as details_router,
)
from app.api.user.profile.helpers import (
    _assert_no_decryption_failures,
    _build_ordered_images,
    _rolling_change_window_status,
)
from app.api.user.profile.media import (
    router as media_router,
)
from app.api.user.profile.media import (
    update_profile_media_and_tags,
)
from app.api.user.profile.moderation import (
    get_moderation_subjects,
)
from app.api.user.profile.moderation import (
    router as moderation_router,
)

router = APIRouter()
router.include_router(details_router)
router.include_router(media_router)
router.include_router(moderation_router)

__all__ = [
    "_assert_no_decryption_failures",
    "_build_ordered_images",
    "_rolling_change_window_status",
    "get_moderation_subjects",
    "get_profile_details",
    "router",
    "update_profile_details",
    "update_profile_media_and_tags",
]
