import asyncio
import logging
from datetime import datetime, timezone
from typing import Annotated, Any, cast

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request

from app.api.dependencies import get_authenticated_user_id, verify_app_check_token
from app.core.config import DiscoveryTab, settings
from app.core.crypto import DecryptFailedError, decrypt_pii
from app.core.limiter import limiter
from app.db.client import DatabaseAccessError, ProfileDecodeError, supabase_client
from app.db.exclusions import (
    fetch_likes_for_user,
    invalidate_block_cache,
    mark_likes_seen,
    record_discovery_action,
    record_user_report,
    revoke_incoming_like,
)
from app.db.matches import (
    fetch_matches_for_user,
    record_match,
    record_mutual_pass,
    set_match_unmatched,
)
from app.db.orbit import build_tab_aware_orbit_node_detail
from app.db.profiles import fetch_peer_profile_by_id
from app.models import (
    LikeActionRequest,
    LikeListItem,
    LikesListResponse,
    MarkLikesSeenRequest,
    MatchActionRequest,
    MatchesListResponse,
    MatchItem,
    OrbitNodeDetailResponse,
    PeerProfileRequest,
)

router = APIRouter()
logger = logging.getLogger(__name__)


def _decrypt_profiles(profiles_data: list[Any]) -> dict[str, dict[str, Any]]:
    profile_map: dict[str, dict[str, Any]] = {}
    for p in profiles_data:
        if not isinstance(p, dict):
            continue
        p_dict = cast(dict[str, Any], p)
        pid = str(p_dict.get("id") or "")
        raw_pic = p_dict.get("profile_pic")
        if raw_pic:
            try:
                p_dict["profile_pic"] = decrypt_pii(raw_pic)
            except DecryptFailedError:
                p_dict["profile_pic"] = None
        profile_map[pid] = p_dict
    return profile_map


def _parse_matched_at(raw_ts: Any) -> datetime:
    if isinstance(raw_ts, str):
        return datetime.fromisoformat(raw_ts.replace("Z", "+00:00"))
    if isinstance(raw_ts, datetime):
        return raw_ts
    return datetime.now(tz=timezone.utc)


@router.get("/api/v1/likes", response_model=LikesListResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_likes_inbox(
    request: Request,
    tab: Annotated[DiscoveryTab, Query()] = "Dating",
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
) -> LikesListResponse:
    _ = request
    try:
        like_rows = await asyncio.to_thread(fetch_likes_for_user, user_id, tab)

        if not like_rows:
            return LikesListResponse(likes=[], unseen_count=0)

        actor_ids = list(
            {str(row["actor_id"]) for row in like_rows if row.get("actor_id")},
        )

        profiles_res = await asyncio.to_thread(
            lambda: supabase_client.table("profiles")
            .select("id, name, age, profile_pic")
            .in_("id", actor_ids)
            .eq("is_deactivated", False)
            .execute(),
        )

        profile_map = _decrypt_profiles(cast(list[Any], profiles_res.data or []))

        items: list[LikeListItem] = []
        for row in like_rows:
            actor_id = str(row.get("actor_id") or "")
            profile = profile_map.get(actor_id, {})
            items.append(
                LikeListItem(
                    actor_id=actor_id,
                    action=row["action"],
                    created_at=row["created_at"],
                    seen_at=row.get("seen_at"),
                    name=profile.get("name"),
                    age=profile.get("age"),
                    profile_pic=profile.get("profile_pic"),
                ),
            )

        # Unseen first → superlikes before likes → newest first
        items.sort(
            key=lambda x: (
                x.seen_at is not None,       # False(0) = unseen first
                x.action != "superlike",     # False(0) = superlike first
                -(x.created_at.timestamp()), # negative = newest first
            ),
        )
        unseen_count = sum(1 for item in items if item.seen_at is None)
        return LikesListResponse(likes=items, unseen_count=unseen_count)

    except DatabaseAccessError as err:
        logger.exception(
            "Database failure fetching likes inbox",
            extra={"user_id": user_id, "tab": tab},
        )
        raise HTTPException(
            status_code=503,
            detail="Likes service temporarily unavailable.",
        ) from err


@router.post("/api/v1/likes/mark-seen")
@limiter.limit(settings.rate_limit_discover)
async def mark_likes_as_seen(
    request: Request,
    payload: MarkLikesSeenRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
) -> dict[str, bool]:
    _ = request
    try:
        actor_ids: list[str] | None = (
            None if payload.mark_all else (payload.actor_ids or None)
        )
        await asyncio.to_thread(mark_likes_seen, user_id, actor_ids)
        return {"success": True}
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure marking likes as seen",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err


@router.post("/api/v1/profile/peer", response_model=OrbitNodeDetailResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_peer_profile(
    request: Request,
    payload: PeerProfileRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
) -> OrbitNodeDetailResponse:
    _ = request
    _ = user_id  # authenticated but not used in the query itself
    try:
        profile = await asyncio.to_thread(
            fetch_peer_profile_by_id, payload.target_id,
        )
        if not profile:
            raise HTTPException(status_code=404, detail="Profile not found.")

        # Inject orbit-shape fields not present on raw profile rows.
        # score=1.0 signals "this person liked you" to the UI.
        profile.setdefault("score", 1.0)
        profile.setdefault("x", 0.0)
        profile.setdefault("y", 0.0)
        profile.setdefault("orbit_tier", 1)

        return build_tab_aware_orbit_node_detail(
            session_tab=payload.tab,
            payload=profile,
        )

    except (DecryptFailedError, ProfileDecodeError) as err:
        logger.exception(
            "Profile decode failure in peer profile fetch",
            extra={"target_id": payload.target_id},
        )
        raise HTTPException(
            status_code=500,
            detail="Profile data integrity error.",
        ) from err
    except DatabaseAccessError as err:
        logger.exception(
            "Database failure fetching peer profile",
            extra={"target_id": payload.target_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err
    except HTTPException:
        raise


_LIKES_PASS_EXPIRY_DAYS = 14  # 2 weeks (same as orbit pass)


@router.post("/api/v1/likes/action")
@limiter.limit(settings.rate_limit_discover)
async def record_like_back_action(
    request: Request,
    payload: LikeActionRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
) -> dict[str, Any]:
    _ = request
    try:
        if payload.action == "report":
            await asyncio.to_thread(
                record_user_report,
                user_id,
                payload.target_id,
                payload.reason or "other",
                payload.reason_detail,
                payload.tab,
            )
            # record_user_report creates a block internally; also invalidate cache
            await invalidate_block_cache(user_id, payload.target_id)
        else:
            tab = None if payload.action == "block" else payload.tab
            expires = _LIKES_PASS_EXPIRY_DAYS if payload.action == "pass" else None
            await asyncio.to_thread(
                record_discovery_action,
                user_id,
                payload.target_id,
                payload.action,
                tab,
                expires,
            )
            if payload.action == "block":
                await invalidate_block_cache(user_id, payload.target_id)

        # Revoke their incoming like so it clears from the inbox
        await asyncio.to_thread(revoke_incoming_like, user_id, payload.target_id)

        matched = payload.action in ("like", "superlike")
        if matched:
            # payload.target_id is the original liker; user_id liked back
            await asyncio.to_thread(
                record_match, payload.target_id, user_id, payload.tab,
            )
        return {"success": True, "matched": matched}

    except DatabaseAccessError as err:
        logger.exception(
            "Database failure recording like-inbox action",
            extra={"user_id": user_id, "target_id": payload.target_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err


@router.get("/api/v1/matches", response_model=MatchesListResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_matches(
    request: Request,
    tab: Annotated[DiscoveryTab, Query()] = "Dating",
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
) -> MatchesListResponse:
    _ = request
    try:
        rows = await asyncio.to_thread(fetch_matches_for_user, user_id, tab)

        if not rows:
            return MatchesListResponse(matches=[])

        counterpart_ids = [
            str(r["matched_user_id"])
            for r in rows
            if r.get("matched_user_id")
        ]

        profiles_res = await asyncio.to_thread(
            lambda: supabase_client.table("profiles")
            .select("id, name, age, profile_pic")
            .in_("id", counterpart_ids)
            .eq("is_deactivated", False)
            .execute(),
        )

        profile_map = _decrypt_profiles(cast(list[Any], profiles_res.data or []))

        items: list[MatchItem] = []
        for row in rows:
            uid = str(row.get("matched_user_id") or "")
            profile = profile_map.get(uid, {})
            matched_at = _parse_matched_at(row.get("created_at"))
            items.append(
                MatchItem(
                    match_id=str(row.get("match_id") or ""),
                    matched_user_id=uid,
                    name=profile.get("name"),
                    age=profile.get("age"),
                    profile_pic=profile.get("profile_pic"),
                    matched_at=matched_at,
                ),
            )

        return MatchesListResponse(matches=items)

    except DatabaseAccessError as err:
        logger.exception(
            "Database failure fetching matches",
            extra={"user_id": user_id, "tab": tab},
        )
        raise HTTPException(
            status_code=503,
            detail="Matches service temporarily unavailable.",
        ) from err


@router.post("/api/v1/matches/action")
@limiter.limit(settings.rate_limit_discover)
async def record_match_action(
    request: Request,
    payload: MatchActionRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
) -> dict[str, bool]:
    _ = request
    try:
        if payload.action == "report":
            await asyncio.to_thread(
                record_user_report,
                user_id,
                payload.target_id,
                payload.reason or "other",
                payload.reason_detail,
                payload.tab,
            )
            await invalidate_block_cache(user_id, payload.target_id)
        elif payload.action == "block":
            await asyncio.to_thread(
                record_discovery_action,
                user_id,
                payload.target_id,
                "block",
                None,
                None,
            )
            await invalidate_block_cache(user_id, payload.target_id)
        else:  # unmatch
            await asyncio.to_thread(
                record_mutual_pass,
                user_id,
                payload.target_id,
                payload.tab,
                14,
            )

        # Dissolve the match row for all action types
        await asyncio.to_thread(
            set_match_unmatched,
            user_id,
            payload.target_id,
            payload.tab,
        )

        return {"success": True}

    except DatabaseAccessError as err:
        logger.exception(
            "Database failure recording match action",
            extra={"user_id": user_id, "target_id": payload.target_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err
