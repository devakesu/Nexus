"""Online presence heartbeat and peer status lookup endpoints."""

import asyncio
import logging
from datetime import timedelta

from fastapi import APIRouter, Body, Depends, HTTPException, Path, Request

from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.core.config import settings
from app.core.limiter import limiter
from app.db.chat import (
    fetch_presence,
    fetch_user_share_flags,
    upsert_presence_heartbeat,
)
from app.db.chat_keys import has_active_match
from app.db.client import DatabaseAccessError, parse_utc_datetime, utcnow
from app.models import PresenceHeartbeatRequest, PresenceResponse

router = APIRouter()
logger = logging.getLogger(__name__)

_PRESENCE_STALE_AFTER = timedelta(seconds=90)


@router.post("/api/v1/chat/presence/heartbeat")
@limiter.limit(settings.rate_limit_discover)
async def send_presence_heartbeat(
    request: Request,
    payload: PresenceHeartbeatRequest = Body(default=PresenceHeartbeatRequest()),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Records user online presence status and updates last active timestamp."""
    _ = request
    try:
        await asyncio.to_thread(upsert_presence_heartbeat, user_id, payload.is_online)
        return {"success": True}
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure recording presence heartbeat",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err


@router.get(
    "/api/v1/chat/presence/{target_user_id}",
    response_model=PresenceResponse,
)
@limiter.limit(settings.rate_limit_discover)
async def get_presence(
    request: Request,
    target_user_id: str = Path(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> PresenceResponse:
    """Fetches target user presence status respecting privacy settings and staleness thresholds."""
    _ = request
    try:
        if not await asyncio.to_thread(has_active_match, user_id, target_user_id):
            return PresenceResponse()

        flags = await asyncio.to_thread(fetch_user_share_flags, target_user_id)
        if not flags["share_active_status"]:
            return PresenceResponse()

        presence = await asyncio.to_thread(fetch_presence, target_user_id)
        if presence is None:
            return PresenceResponse()

        raw_last_active = presence.get("last_active_at")
        if raw_last_active is None:
            return PresenceResponse()

        last_active_at = parse_utc_datetime(raw_last_active)
        is_online = bool(presence.get("is_online", False)) and (
            utcnow() - last_active_at < _PRESENCE_STALE_AFTER
        )
        return PresenceResponse(is_online=is_online, last_active_at=last_active_at)
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure fetching presence",
            extra={"user_id": user_id, "target_user_id": target_user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err
