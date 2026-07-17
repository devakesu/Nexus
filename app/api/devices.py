import asyncio
import logging
import uuid

from fastapi import APIRouter, Body, Depends, HTTPException, Request

from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.core.config import settings
from app.core.limiter import limiter
from app.db.client import supabase_client
from app.models import RegisterDeviceRequest

router = APIRouter()
logger = logging.getLogger(__name__)


def _upsert_device_token(
    user_id: str,
    fcm_token: str,
    platform: str,
    device_id: str | None,
) -> None:
    supabase_client.table("user_devices").upsert(
        {
            "user_id": user_id,
            "fcm_token": fcm_token,
            "platform": platform,
            "device_id": device_id or str(uuid.uuid4()),
            "is_active": True,
            "last_seen_at": "now()",
        },
        on_conflict="fcm_token",
    ).execute()


def _deactivate_device_token(user_id: str, fcm_token: str) -> None:
    supabase_client.table("user_devices").update(
        {"is_active": False},
    ).eq("user_id", user_id).eq("fcm_token", fcm_token).execute()


@router.post("/api/v1/devices/register")
@limiter.limit(settings.rate_limit_auth)
async def register_device(
    request: Request,
    payload: RegisterDeviceRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    _ = request
    try:
        await asyncio.to_thread(
            _upsert_device_token,
            user_id,
            payload.fcm_token,
            payload.platform,
            payload.device_id,
        )
        return {"success": True}
    except Exception as err:
        logger.exception(
            "Database error registering device token",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err


@router.post("/api/v1/devices/unregister")
@limiter.limit(settings.rate_limit_auth)
async def unregister_device(
    request: Request,
    payload: RegisterDeviceRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    _ = request
    try:
        await asyncio.to_thread(
            _deactivate_device_token,
            user_id,
            payload.fcm_token,
        )
        return {"success": True}
    except Exception as err:
        logger.exception(
            "Database error deactivating device token",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err
