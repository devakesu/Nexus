"""FastAPI router for incoming likes, match listings, unmatching, and user block management.

Provides endpoints for fetching incoming likes, viewing mutual matches, initiating unmatches,
and managing blocked user lists.
"""

import asyncio
import logging
import uuid
from contextlib import suppress
from datetime import datetime, timezone
from typing import Annotated, Any, cast

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request

from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.core.config import DiscoveryTab, settings
from app.core.infra.limiter import limiter
from app.core.infra.tasks import safe_create_task
from app.core.security.crypto import DecryptFailedError
from app.db.chat import close_conversation_for_match_action
from app.db.client import (
    DatabaseAccessError,
    ProfileDecodeError,
    parse_utc_datetime,
    supabase_client,
)
from app.db.discovery import (
    build_tab_aware_orbit_node_detail,
    fetch_likes_for_user,
    fetch_matches_for_user,
    get_cached_active_block_ids,
    invalidate_block_cache,
    mark_likes_seen,
    record_discovery_action,
    record_match,
    record_mutual_pass,
    record_user_report,
    revoke_incoming_like,
    set_match_unmatched,
    unrevoke_incoming_like,
)
from app.db.profiles import decrypt_profile_rows as _decrypt_profiles
from app.db.profiles import fetch_peer_profile_by_id
from app.models import (
    LikeActionRequest,
    LikeActionResponse,
    LikeListItem,
    LikesListResponse,
    MarkLikesSeenRequest,
    MatchActionRequest,
    MatchActionResponse,
    MatchesListResponse,
    MatchItem,
    OrbitNodeDetailResponse,
    PeerProfileRequest,
)
from app.services.fcm_sender import send_match_notification

router = APIRouter()
logger = logging.getLogger(__name__)


def _parse_matched_at(raw_ts: Any) -> datetime:
    """Parse matched at.

        Args:
            raw_ts: Input raw ts parameter.

        Returns:
            datetime: Response payload or result."""
    with suppress(Exception):
        if isinstance(raw_ts, (str, datetime)):
            return parse_utc_datetime(raw_ts)
    return datetime.now(tz=timezone.utc)


@router.get("/api/v1/likes", response_model=LikesListResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_likes_inbox(
    request: Request,
    tab: Annotated[DiscoveryTab, Query()] = "Dating",
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> LikesListResponse:
    """Fetches incoming likes received by the caller filtered by discovery tab.

        Args:
            request: FastAPI HTTP request object used for rate limiting.
            tab: Discovery tab category ('Dating', 'BFF', 'Networking').
            limit: Maximum number of incoming likes to return.
            _device: App Check attestation token dependency guard.
            user_id: Verified UUID string of authenticated recipient.

        Returns:
            LikesInboxResponse: List of liker profile cards and timestamps."""
    _ = request
    try:
        like_rows = await asyncio.to_thread(fetch_likes_for_user, user_id, tab)

        if not like_rows:
            return LikesListResponse(likes=[], unseen_count=0)

        actor_ids = list(
            {str(row["actor_id"]) for row in like_rows if row.get("actor_id")},
        )

        block_ids = await get_cached_active_block_ids(user_id)
        actor_ids = [aid for aid in actor_ids if aid not in block_ids]

        profiles_res = await asyncio.to_thread(
            lambda: (
                supabase_client.table("profiles")
                .select("id, name, age, profile_pic")
                .in_("id", actor_ids)
                .eq("is_deactivated", False)
                .execute()
            ),
        )

        profile_map = _decrypt_profiles(cast(list[Any], profiles_res.data or []))

        items: list[LikeListItem] = []
        for row in like_rows:
            actor_id = str(row.get("actor_id") or "")
            if actor_id in block_ids or actor_id not in profile_map:
                continue
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
                x.seen_at is not None,  # False(0) = unseen first
                x.action != "superlike",  # False(0) = superlike first
                -(x.created_at.timestamp()),  # negative = newest first
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
    payload: MarkLikesSeenRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Marks unseen incoming likes as viewed in the user inbox.

        Args:
            request: FastAPI HTTP request object used for rate limiting.
            tab: Discovery tab category.
            _device: App Check attestation token dependency guard.
            user_id: Verified UUID string of authenticated recipient.

        Returns:
            dict[str, bool]: Success status dict."""
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


async def _verify_peer_access_and_infer_tab(
    target_id: str,
    user_id_normalized: str,
    default_tab: DiscoveryTab,
) -> DiscoveryTab:
    """Verify peer access and infer tab.

        Args:
            target_id: Input target id parameter.
            user_id_normalized: Input user id normalized parameter.
            default_tab: Input default tab parameter.

        Returns:
            DiscoveryTab: Response payload or result."""
    if target_id == user_id_normalized:
        raise HTTPException(
            status_code=403,
            detail="Access denied. Viewer not permitted.",
        )

    block_ids = await get_cached_active_block_ids(user_id_normalized)
    if target_id in block_ids:
        raise HTTPException(
            status_code=403,
            detail="Access denied. Viewer not permitted.",
        )

    query_like = supabase_client.table(
        "profile_discovery_actions",
    ).select("id, tab")
    query_like = query_like.eq("actor_id", target_id)
    query_like = query_like.eq("target_id", user_id_normalized)
    query_like = query_like.in_("action", ["like", "superlike"])
    query_like = query_like.is_("revoked_at", "null")
    query_like = query_like.limit(1)
    access_check_res = await asyncio.to_thread(query_like.execute)
    has_like = bool(access_check_res.data)

    has_match = False
    match_check_res = None
    if not has_like:
        query_match = supabase_client.table("matches").select("id, tab")
        query_match = query_match.or_(
            f"and(liker_id.eq.{target_id},"
            f"liked_back_id.eq.{user_id_normalized}),"
            f"and(liker_id.eq.{user_id_normalized},"
            f"liked_back_id.eq.{target_id})",
        )
        query_match = query_match.is_("unmatched_at", "null")
        query_match = query_match.limit(1)
        match_check_res = await asyncio.to_thread(query_match.execute)
        has_match = bool(match_check_res.data)

    if not has_like and not has_match:
        raise HTTPException(
            status_code=403,
            detail="Access denied. Viewer not permitted.",
        )

    inferred_tab = default_tab
    if has_like and access_check_res.data:
        like_row = access_check_res.data[0]
        if isinstance(like_row, dict) and like_row.get("tab"):
            inferred_tab = cast(DiscoveryTab, like_row["tab"])
    elif has_match and match_check_res and match_check_res.data:
        match_row = match_check_res.data[0]
        if isinstance(match_row, dict) and match_row.get("tab"):
            inferred_tab = cast(DiscoveryTab, match_row["tab"])

    return inferred_tab


@router.post("/api/v1/profile/peer", response_model=OrbitNodeDetailResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_peer_profile(
    request: Request,
    payload: PeerProfileRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> OrbitNodeDetailResponse:
    """Retrieves decrypted profile information of a peer with verified access control.

        Args:
            request: FastAPI HTTP request object used for rate limiting.
            target_user_id: UUID string of peer candidate or match.
            tab: Optional discovery tab filter.
            _device: App Check attestation token dependency guard.
            user_id: Verified UUID string of requesting user.

        Returns:
            dict[str, Any]: Decrypted peer profile payload.

        Raises:
            HTTPException: 403 if access permission is denied, 404 if profile missing."""
    _ = request
    try:
        target_id = str(uuid.UUID(payload.target_id)).lower()
        user_id_normalized = str(uuid.UUID(user_id)).lower()

        inferred_tab = await _verify_peer_access_and_infer_tab(
            target_id=target_id,
            user_id_normalized=user_id_normalized,
            default_tab=payload.tab,
        )

        profile = await asyncio.to_thread(
            fetch_peer_profile_by_id,
            target_id,
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

        # Check viewer connection status dynamically
        from app.db.spotify import get_connection

        viewer_conn = await asyncio.to_thread(get_connection, user_id_normalized)
        viewer_connected = viewer_conn is not None and not viewer_conn.get(
            "disconnected_at",
        )
        profile["viewer_spotify_connected"] = viewer_connected

        # If both are connected, calculate the playlist match grade!
        candidate_connected = bool(
            profile.get("artist_affinity") or profile.get("genre_affinity"),
        )
        profile["candidate_spotify_connected"] = candidate_connected

        if viewer_connected and candidate_connected:
            viewer_profile = await asyncio.to_thread(
                fetch_peer_profile_by_id,
                user_id_normalized,
            )
            if viewer_profile:
                from Nexus_Engine.engine import calculate_playlist_match_grade

                grade = calculate_playlist_match_grade(
                    viewer_profile.get("artist_affinity"),
                    profile.get("artist_affinity"),
                    viewer_profile.get("genre_affinity"),
                    profile.get("genre_affinity"),
                )
                profile["music_match_grade"] = grade

        return build_tab_aware_orbit_node_detail(
            session_tab=inferred_tab,
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


@router.post("/api/v1/likes/action", response_model=LikeActionResponse)
@limiter.limit(settings.rate_limit_discover)
async def record_like_back_action(  # noqa: C901
    request: Request,
    payload: LikeActionRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> LikeActionResponse:
    """Processes a response swipe to an incoming like (accepting into match or rejecting).

        Args:
            request: FastAPI HTTP request object used for rate limiting.
            payload: Like back action payload.
            _device: App Check attestation token dependency guard.
            user_id: Verified UUID string of swiping user.

        Returns:
            dict[str, Any]: Match creation outcome payload."""
    _ = request
    try:
        # 1. Claim & revoke incoming like first to prevent race conditions or duplicate matches
        claimed_like = False
        if payload.action in ("like", "superlike", "pass", "block"):
            claimed_like = await asyncio.to_thread(revoke_incoming_like, user_id, payload.target_id)
            if not claimed_like:
                raise HTTPException(
                    status_code=400,
                    detail="No active incoming like found.",
                )

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
            await asyncio.to_thread(
                set_match_unmatched,
                user_id,
                payload.target_id,
                payload.tab,
            )
            await asyncio.to_thread(
                close_conversation_for_match_action,
                user_id,
                payload.target_id,
                payload.tab,
                "report",
            )
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
                await asyncio.to_thread(
                    set_match_unmatched,
                    user_id,
                    payload.target_id,
                    payload.tab,
                )
                await asyncio.to_thread(
                    close_conversation_for_match_action,
                    user_id,
                    payload.target_id,
                    payload.tab,
                    "block",
                )

        matched = payload.action in ("like", "superlike")
        match_id: str | None = None
        if matched:
            try:
                # payload.target_id is the original liker; user_id liked back
                match_id = await asyncio.to_thread(
                    record_match,
                    payload.target_id,
                    user_id,
                    payload.tab,
                )
            except Exception as err:
                if claimed_like:
                    await asyncio.to_thread(unrevoke_incoming_like, user_id, payload.target_id)
                if isinstance(err, DatabaseAccessError):
                    orig = err.__cause__
                    if orig and "No active incoming like found" in str(orig):
                        raise HTTPException(
                            status_code=400,
                            detail="No active incoming like found.",
                        ) from err
                raise

            safe_create_task(
                send_match_notification(
                    user_a_id=payload.target_id,
                    user_b_id=user_id,
                ),
            )
            # Revoke reciprocal like in the other direction if present
            await asyncio.to_thread(
                revoke_incoming_like,
                payload.target_id,
                user_id,
            )

        return LikeActionResponse(success=True, matched=matched, match_id=match_id)

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
    user_id: str = Depends(get_active_user_id),
) -> MatchesListResponse:
    """Retrieves active mutual matches for the user across discovery tabs.

        Args:
            request: FastAPI HTTP request object used for rate limiting.
            tab: Discovery tab category filter.
            _device: App Check attestation token dependency guard.
            user_id: Verified UUID string of authenticated user.

        Returns:
            MatchesListResponse: List of active match summaries."""
    _ = request
    try:
        rows = await asyncio.to_thread(fetch_matches_for_user, user_id, tab)

        if not rows:
            return MatchesListResponse(matches=[])

        block_ids = await get_cached_active_block_ids(user_id)
        counterpart_ids = [
            str(r["matched_user_id"]) for r in rows if r.get("matched_user_id")
        ]
        counterpart_ids = [cid for cid in counterpart_ids if cid not in block_ids]

        profiles_res = await asyncio.to_thread(
            lambda: (
                supabase_client.table("profiles")
                .select("id, name, age, profile_pic")
                .in_("id", counterpart_ids)
                .eq("is_deactivated", False)
                .execute()
            ),
        )

        profile_map = _decrypt_profiles(cast(list[Any], profiles_res.data or []))

        items: list[MatchItem] = []
        for row in rows:
            uid = str(row.get("matched_user_id") or "")
            if uid in block_ids or uid not in profile_map:
                continue
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


@router.post("/api/v1/matches/action", response_model=MatchActionResponse)
@limiter.limit(settings.rate_limit_discover)
async def record_match_action(
    request: Request,
    payload: MatchActionRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> MatchActionResponse:
    """Executes match management actions such as unmatching or blocking a matched user.

        Args:
            request: FastAPI HTTP request object used for rate limiting.
            payload: Match action payload specifying target user and action type.
            _device: App Check attestation token dependency guard.
            user_id: Verified UUID string of caller.

        Returns:
            dict[str, bool]: Success status dict."""
    _ = request
    try:
        # 1. Dissolve the match row and close associated chat conversation first
        await asyncio.to_thread(
            set_match_unmatched,
            user_id,
            payload.target_id,
            payload.tab,
        )

        await asyncio.to_thread(
            close_conversation_for_match_action,
            user_id,
            payload.target_id,
            payload.tab,
            payload.action,
        )

        # 2. Record action-specific exclusions/reports/blocks
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

        return MatchActionResponse()

    except DatabaseAccessError as err:
        logger.exception(
            "Database failure recording match action",
            extra={"user_id": user_id, "target_id": payload.target_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err
