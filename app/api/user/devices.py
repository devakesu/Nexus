"""FastAPI router for push notification device registration and token lifecycle management.

Provides endpoints to register and unregister Firebase Cloud Messaging (FCM) device tokens.
"""

import asyncio
import logging
import uuid

from fastapi import APIRouter, Body, Depends, HTTPException, Request

from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.core.config import settings
from app.core.infra.limiter import limiter
from app.db.client import (
    normalize_uuid,
    supabase_client,
    validate_device_id,
    validate_fcm_token,
)
from app.models import RegisterDeviceRequest

router = APIRouter()
logger = logging.getLogger(__name__)


def _upsert_device_token(
    user_id: str,
    fcm_token: str,
    platform: str,
    device_id: str | None,
) -> None:
    """Upserts FCM device token record in database.

    If a device_id is provided, deactivates older tokens associated with the
    same physical device before registering the new token.

    Args:
        user_id: Target user ID string.
        fcm_token: FCM device token string.
        platform: Operating system platform string ('android' | 'ios').
        device_id: Optional client device ID string.
    """
    valid_user_id = normalize_uuid(user_id)
    valid_fcm_token = validate_fcm_token(fcm_token)
    valid_device_id = validate_device_id(device_id) if device_id else None

    if valid_device_id:
        try:
            supabase_client.table("user_devices").update(
                {"is_active": False},
            ).eq("user_id", valid_user_id).eq("device_id", valid_device_id).neq("fcm_token", valid_fcm_token).execute()
        except Exception:
            logger.warning(
                "Failed to deactivate prior device tokens for device %s",
                valid_device_id,
                exc_info=True,
            )

    supabase_client.table("user_devices").upsert(
        {
            "user_id": valid_user_id,
            "fcm_token": valid_fcm_token,
            "platform": platform,
            "device_id": valid_device_id or str(uuid.uuid4()),
            "is_active": True,
            "last_seen_at": "now()",
        },
        on_conflict="fcm_token",
    ).execute()


def _deactivate_device_token(
    user_id: str,
    fcm_token: str,
    device_id: str | None = None,
) -> bool:
    """Deactivates active FCM device token records.

    Args:
        user_id: Target user ID string.
        fcm_token: Target FCM token string.
        device_id: Optional client device ID string.

    Returns:
        bool: True if an active record was updated.
    """
    valid_user_id = normalize_uuid(user_id)
    valid_fcm_token = validate_fcm_token(fcm_token)
    valid_device_id = validate_device_id(device_id) if device_id else None

    query = supabase_client.table("user_devices").update(
        {"is_active": False},
    ).eq("user_id", valid_user_id)

    if valid_device_id:
        # nosec: valid_device_id and valid_fcm_token validated against strict patterns preventing PostgREST filter injection
        res = query.or_(f"device_id.eq.{valid_device_id},fcm_token.eq.{valid_fcm_token}").execute()
    else:
        res = query.eq("fcm_token", valid_fcm_token).execute()

    return bool(res.data)


@router.post("/api/v1/devices/register")
@limiter.limit(settings.rate_limit_auth)
async def register_device(
    request: Request,
    payload: RegisterDeviceRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Registers or updates a device's FCM push token for notification delivery.

    Args:
        request: Incoming HTTP request.
        payload: FCM device token payload.
        _device: App Check attestation token guard.
        user_id: Verified caller user ID.

    Returns:
        dict[str, bool]: Success status dict.
    """
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
    payload: RegisterDeviceRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Unregisters and deactivates a device's FCM push token upon logout.

    Args:
        request: Incoming HTTP request.
        payload: FCM device token payload.
        _device: App Check attestation token guard.
        user_id: Verified caller user ID.

    Returns:
        dict[str, bool]: Success status dict.
    """
    _ = request
    try:
        await asyncio.to_thread(
            _deactivate_device_token,
            user_id,
            payload.fcm_token,
            payload.device_id,
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

