"""User routes, onboarding, settings, and authentication package.

Refactored from monolithic user.py to support modular auth, profile, and settings sub-routers.
Includes the root router and backward-compatible function re-exports.
"""

from fastapi import APIRouter

from app.api.user.account_deletion import router as account_deletion_router
from app.api.user.auth_otp import router as auth_otp_router
from app.api.user.devices import router as devices_router
from app.api.user.export import router as export_router
from app.api.user.profile import router as profile_router
from app.api.user.profile import update_profile_details
from app.api.user.settings import router as settings_router
from app.api.user.sync import router as sync_router
from app.db.client import supabase_client
from app.db.profiles import decrypt_profile_record

router = APIRouter()

router.include_router(auth_otp_router)
router.include_router(profile_router)
router.include_router(settings_router)
router.include_router(account_deletion_router)
router.include_router(export_router)
router.include_router(devices_router)
router.include_router(sync_router)

__all__ = [
    "decrypt_profile_record",
    "router",
    "supabase_client",
    "update_profile_details",
]

