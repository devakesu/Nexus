import asyncio
import logging
import uuid
from datetime import datetime, timezone
from typing import Annotated, Any, cast

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request

from app.api.dependencies import get_authenticated_user_id, verify_app_check_token
from app.core.config import DiscoveryTab, settings
from app.core.crypto import DecryptFailedError
from app.core.limiter import limiter
from app.core.tasks import safe_create_task
from app.db.chat import close_conversation_for_match_action
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
from app.db.profiles import decrypt_profile_rows as _decrypt_profiles
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
from app.services.fcm_sender import send_match_notification

router = APIRouter()
logger = logging.getLogger(__name__)


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
        await asyncio.to_thread(mark_likes_seen, user_id, actor_ids, payload.tab)
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
    try:
        target_id = str(uuid.UUID(payload.target_id)).lower()
        user_id_normalized = str(uuid.UUID(user_id)).lower()

        # Verify access: either target liked the viewer, or they are matched
        query_like = supabase_client.table(
            "profile_discovery_actions",
        ).select("id")
        query_like = query_like.eq("actor_id", target_id)
        query_like = query_like.eq("target_id", user_id_normalized)
        query_like = query_like.in_("action", ["like", "superlike"])
        query_like = query_like.is_("revoked_at", "null")
        access_check_res = await asyncio.to_thread(query_like.execute)
        has_like = bool(access_check_res.data)

        has_match = False
        if not has_like:
            query_match = supabase_client.table("matches").select("id")
            query_match = query_match.or_(
                f"and(liker_id.eq.{target_id},"
                f"liked_back_id.eq.{user_id_normalized}),"
                f"and(liker_id.eq.{user_id_normalized},"
                f"liked_back_id.eq.{target_id}),",
            )
            query_match = query_match.is_("unmatched_at", "null")
            match_check_res = await asyncio.to_thread(query_match.execute)
            has_match = bool(match_check_res.data)

        if not has_like and not has_match:
            raise HTTPException(
                status_code=403,
                detail="Access denied. Viewer not permitted.",
            )

        profile = await asyncio.to_thread(
            fetch_peer_profile_by_id, target_id,
        )
        if not profile:
            raise HTTPException(status_code=404, detail="Profile not found.")

        hidden_fields = set(profile.pop("hidden_profile_fields", None) or [])

        # Inject orbit-shape fields not present on raw profile rows.
        # score=1.0 signals "this person liked you" to the UI.
        profile.setdefault("score", 1.0)
        profile.setdefault("x", 0.0)
        profile.setdefault("y", 0.0)
        profile.setdefault("orbit_tier", 1)

        return build_tab_aware_orbit_node_detail(
            session_tab=payload.tab,
            payload=profile,
            hidden_fields=hidden_fields,
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

        matched = payload.action in ("like", "superlike")
        match_id: str | None = None
        if matched:
            try:
                # payload.target_id is the original liker; user_id liked back
                match_id = await asyncio.to_thread(
                    record_match, payload.target_id, user_id, payload.tab,
                )
                safe_create_task(
                    send_match_notification(
                        user_a_id=payload.target_id,
                        user_b_id=user_id,
                    ),
                )
            except DatabaseAccessError as err:
                orig = err.__cause__
                if orig and "No active incoming like found" in str(orig):
                    raise HTTPException(
                        status_code=400,
                        detail="No active incoming like found.",
                    ) from err
                raise

        # Revoke their incoming like so it clears from the inbox
        if payload.action in ("like", "superlike", "pass", "block", "report"):
            await asyncio.to_thread(revoke_incoming_like, user_id, payload.target_id)

        return {"success": True, "matched": matched, "match_id": match_id}

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

        # Close the associated chat conversation, if one was ever started.
        await asyncio.to_thread(
            close_conversation_for_match_action,
            user_id,
            payload.target_id,
            payload.tab,
            payload.action,
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
