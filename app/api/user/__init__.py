"""User routes, onboarding, settings, and authentication package.

Refactored from monolithic user.py to support modular auth, profile, and settings sub-routers.
Includes the root router and backward-compatible function re-exports.
"""

from fastapi import APIRouter

from app.api.user.auth_otp import router as auth_otp_router
from app.api.user.profile import router as profile_router
from app.api.user.profile import update_profile_details
from app.api.user.settings import router as settings_router

router = APIRouter()

router.include_router(auth_otp_router)
router.include_router(profile_router)
router.include_router(settings_router)

__all__ = [
    "router",
    "update_profile_details",
]
