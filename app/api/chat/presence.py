"""Online presence heartbeat and peer status lookup endpoints."""

import asyncio
import json
import logging
from datetime import datetime, timedelta
from typing import Any, cast

from fastapi import APIRouter, Body, Depends, HTTPException, Path, Request

from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.core.config import settings
from app.core.infra.cache import redis_client
from app.core.infra.limiter import limiter
from app.db.chat import (
    batch_fetch_presence_from_db,
    batch_fetch_user_share_flags,
    fetch_active_matches_for_targets,
    upsert_presence_heartbeat,
)
from app.db.client import DatabaseAccessError, parse_utc_datetime, utcnow
from app.models import BatchPresenceRequest, PresenceHeartbeatRequest, PresenceResponse

router = APIRouter()
logger = logging.getLogger(__name__)

_PRESENCE_STALE_AFTER = timedelta(seconds=90)
_COARSE_PRESENCE_INTERVAL_MINUTES = 30


def _coarsen_last_active_timestamp(
    dt: datetime, interval_minutes: int = _COARSE_PRESENCE_INTERVAL_MINUTES,
) -> datetime:
    """Rounds last_active_at down to the nearest coarse interval to prevent timing side-channels."""
    discard = timedelta(
        minutes=dt.minute % interval_minutes,
        seconds=dt.second,
        microseconds=dt.microsecond,
    )
    return dt - discard


async def _resolve_batch_presence(
    user_id: str,
    target_user_ids: list[str],
) -> dict[str, PresenceResponse]:
    """Resolves presence for a batch of target users using single batched DB queries and Redis MGET."""
    if not target_user_ids:
        return {}

    # Initialize all requested IDs with empty default PresenceResponse
    response_map: dict[str, PresenceResponse] = {
        tid: PresenceResponse() for tid in target_user_ids
    }

    # 1. Batch check active matches in a single DB query
    matched_target_ids = await asyncio.to_thread(
        fetch_active_matches_for_targets, user_id, target_user_ids,
    )
    if not matched_target_ids:
        return response_map

    # 2. Block checks from Redis cache
    from app.db.discovery import get_cached_active_block_ids

    viewer_block_ids = await get_cached_active_block_ids(user_id)
    candidate_ids = [
        tid
        for tid in target_user_ids
        if tid in matched_target_ids and tid not in viewer_block_ids
    ]
    if not candidate_ids:
        return response_map

    target_blocks_list = await asyncio.gather(
        *[get_cached_active_block_ids(tid) for tid in candidate_ids],
    )
    unblocked_candidate_ids: list[str] = [
        tid
        for tid, t_blocks in zip(candidate_ids, target_blocks_list, strict=True)
        if user_id not in t_blocks
    ]
    if not unblocked_candidate_ids:
        return response_map

    # 3. Batch check user privacy share flags in a single DB query
    flags_map = await asyncio.to_thread(
        batch_fetch_user_share_flags, unblocked_candidate_ids,
    )
    share_allowed_ids = [
        tid
        for tid in unblocked_candidate_ids
        if flags_map.get(tid, {}).get("share_active_status", True)
    ]
    if not share_allowed_ids:
        return response_map

    # 4. Batch fetch presence from Redis (MGET) with single DB fallback for cache misses
    redis_keys = [f"presence:{tid}" for tid in share_allowed_ids]
    presence_map: dict[str, dict[str, Any] | None] = {}
    missing_ids: list[str] = []

    try:
        redis_results = cast(list[Any], await redis_client.mget(redis_keys))
        for tid, raw in zip(share_allowed_ids, redis_results, strict=True):
            if raw:
                try:
                    parsed = json.loads(raw)
                    if isinstance(parsed, dict):
                        presence_map[tid] = cast(dict[str, Any], parsed)
                        continue
                except Exception:
                    pass
            missing_ids.append(tid)
    except Exception as e:
        logger.warning("Redis mget failed for batch presence: %s", e)
        missing_ids = share_allowed_ids

    if missing_ids:
        db_results = await asyncio.to_thread(
            batch_fetch_presence_from_db, missing_ids,
        )
        presence_map.update(db_results)

    # 5. Build responses for share-allowed candidates
    now = utcnow()
    for tid in share_allowed_ids:
        p = presence_map.get(tid)
        if not p:
            continue
        raw_last_active = p.get("last_active_at")
        if not raw_last_active:
            continue
        try:
            last_active_at = parse_utc_datetime(str(raw_last_active))
        except (ValueError, TypeError):
            continue
        is_online = bool(p.get("is_online", False)) and (
            now - last_active_at < _PRESENCE_STALE_AFTER
        )
        coarsened = _coarsen_last_active_timestamp(last_active_at)
        response_map[tid] = PresenceResponse(
            is_online=is_online,
            last_active_at=coarsened,
        )

    return response_map


async def _resolve_single_presence(
    user_id: str, target_user_id: str,
) -> PresenceResponse:
    batch_res = await _resolve_batch_presence(user_id, [target_user_id])
    return batch_res.get(target_user_id, PresenceResponse())


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


_MAX_BATCH_PRESENCE_IDS = 50


@router.post("/api/v1/chat/presence/batch")
@limiter.limit(settings.rate_limit_discover)
async def batch_get_presence(
    request: Request,
    payload: BatchPresenceRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, PresenceResponse]:
    """Fetches presence status for multiple target user IDs in one request."""
    _ = request
    if len(payload.user_ids) > _MAX_BATCH_PRESENCE_IDS:
        raise HTTPException(
            status_code=400,
            detail="Too many user IDs.",
        )
    try:
        return await _resolve_batch_presence(user_id, payload.user_ids)
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure fetching batch presence",
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
        return await _resolve_single_presence(user_id, target_user_id)
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure fetching presence",
            extra={"user_id": user_id, "target_user_id": target_user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Chats service temporarily unavailable.",
        ) from err
