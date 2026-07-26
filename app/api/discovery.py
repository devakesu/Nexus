"""FastAPI router for discovery radar orbits, candidate retrieval, actions (like/pass/report), and viewport queries.

Exposes endpoints for loading candidate orbits across Dating, BFF, and Networking tabs,
querying profile details, and recording interaction actions.
"""

import asyncio
import logging

from fastapi import APIRouter, Body, Depends, HTTPException, Request

from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.core.config import settings
from app.core.crypto import DecryptFailedError
from app.core.limiter import limiter
from app.core.tasks import safe_create_task
from app.db.client import DatabaseAccessError, ProfileDecodeError
from app.db.exclusions import (
    invalidate_block_cache,
    record_discovery_action,
    record_user_report,
)
from app.db.orbit import build_tab_aware_orbit_node_detail
from app.db.sessions import fetch_discovery_node_detail, fetch_spatial_viewport
from app.models import (
    DiscoveryActionRequest,
    DiscoveryActionResponse,
    DiscoveryRequest,
    DiscoveryViewportRequest,
    DiscoveryViewportResponse,
    OrbitDiscoverResponse,
    OrbitNodeDetailRequest,
    OrbitNodeDetailResponse,
    OrbitNodeOut,
)
from app.services.discovery import create_new_discovery_session, get_or_validate_session
from app.services.fcm_sender import send_like_notification

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post("/api/v1/discover", response_model=OrbitDiscoverResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_discovery_orbit(
    request: Request,
    payload: DiscoveryRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
):
    """Get discovery orbit.

        Args:
            request: get discovery orbit.
            payload: get discovery orbit.
            _device: get discovery orbit.
            user_id: get discovery orbit.
        """
    _ = request
    active_tab = payload.tab
    filters = payload.filters

    try:
        if payload.session_id:
            session_id, expires_at = await asyncio.to_thread(
                get_or_validate_session,
                payload.session_id,
                user_id,
                active_tab,
            )
        else:
            session_id, expires_at = await asyncio.to_thread(
                create_new_discovery_session,
                user_id,
                active_tab,
                filters,
            )

        nodes, total_nodes = await fetch_spatial_viewport(
            session_id=session_id,
            viewer_id=user_id,
            center_x=0.0,
            center_y=0.0,
            radius=1000.0,
        )

        return OrbitDiscoverResponse(
            session_id=session_id,
            expires_at=expires_at,
            total_nodes=total_nodes,
            nodes=[
                OrbitNodeOut(
                    id=node["id"],
                    name=node.get("name"),
                    profile_pic=node.get("profile_pic"),
                    score=float(node.get("score") or 0.0),
                    x=float(node.get("x") or 0.0),
                    y=float(node.get("y") or 0.0),
                    orbit_tier=int(node.get("orbit_tier") or 0),
                )
                for node in nodes
            ],
        )

    except (DecryptFailedError, ProfileDecodeError) as err:
        logger.exception(
            "Encrypted profile decode failure during orbit discovery bootstrap",
            extra={"user_id": user_id, "active_tab": active_tab},
        )
        raise HTTPException(
            status_code=500,
            detail="Profile data integrity error.",
        ) from err
    except DatabaseAccessError as err:
        logger.exception(
            "Database access failure during orbit discovery bootstrap",
            extra={"user_id": user_id, "active_tab": active_tab},
        )
        raise HTTPException(
            status_code=503,
            detail="Discovery service temporarily unavailable.",
        ) from err
    except HTTPException:
        raise
    except Exception as err:
        logger.exception(
            "Unexpected orbit discovery bootstrap failure",
            extra={"user_id": user_id, "active_tab": active_tab},
        )
        raise HTTPException(
            status_code=500,
            detail="Unexpected internal error.",
        ) from err


@router.post("/api/v1/discover/node-detail", response_model=OrbitNodeDetailResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_discovery_node_detail(
    request: Request,
    payload: OrbitNodeDetailRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
):
    """Get discovery node detail.

        Args:
            request: get discovery node detail.
            payload: get discovery node detail.
            _device: get discovery node detail.
            user_id: get discovery node detail.
        """
    _ = request

    try:
        detail_result = await fetch_discovery_node_detail(
            session_id=payload.session_id,
            viewer_id=user_id,
            candidate_id=payload.candidate_id,
        )

        if not detail_result:
            raise HTTPException(status_code=404, detail="Discovery node not found.")

        session_tab, detail_payload = detail_result
        hidden_fields = set(detail_payload.pop("hidden_profile_fields", None) or [])

        return build_tab_aware_orbit_node_detail(
            session_tab=session_tab,
            payload=detail_payload,
            hidden_fields=hidden_fields,
        )

    except (DecryptFailedError, ProfileDecodeError) as err:
        logger.exception(
            "Encrypted profile decode failure during orbit node detail fetch",
            extra={
                "user_id": user_id,
                "session_id": payload.session_id,
                "candidate_id": payload.candidate_id,
            },
        )
        raise HTTPException(
            status_code=500,
            detail="Profile data integrity error.",
        ) from err
    except DatabaseAccessError as err:
        logger.exception(
            "Database access failure during orbit node detail fetch",
            extra={
                "user_id": user_id,
                "session_id": payload.session_id,
                "candidate_id": payload.candidate_id,
            },
        )
        raise HTTPException(
            status_code=503,
            detail="Discovery detail service temporarily unavailable.",
        ) from err
    except HTTPException:
        raise
    except Exception as err:
        logger.exception(
            "Unexpected orbit node detail failure",
            extra={
                "user_id": user_id,
                "session_id": payload.session_id,
                "candidate_id": payload.candidate_id,
            },
        )
        raise HTTPException(
            status_code=500,
            detail="Unexpected internal error.",
        ) from err


@router.post("/api/v1/discover/viewport", response_model=DiscoveryViewportResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_discovery_viewport(
    request: Request,
    payload: DiscoveryViewportRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
):
    """Get discovery viewport.

        Args:
            request: get discovery viewport.
            payload: get discovery viewport.
            _device: get discovery viewport.
            user_id: get discovery viewport.
        """
    _ = request

    try:
        session_id, expires_at = await asyncio.to_thread(
            get_or_validate_session,
            payload.session_id,
            user_id,
        )

        nodes, total_nodes = await fetch_spatial_viewport(
            session_id=session_id,
            viewer_id=user_id,
            center_x=payload.center_x,
            center_y=payload.center_y,
            radius=payload.radius,
        )

        return DiscoveryViewportResponse(
            session_id=session_id,
            expires_at=expires_at,
            total_nodes=total_nodes,
            nodes=[
                OrbitNodeOut(
                    id=node["id"],
                    name=node.get("name"),
                    profile_pic=node.get("profile_pic"),
                    score=float(node.get("score") or 0.0),
                    x=float(node.get("x") or 0.0),
                    y=float(node.get("y") or 0.0),
                    orbit_tier=int(node.get("orbit_tier") or 0),
                )
                for node in nodes
            ],
        )

    except (DecryptFailedError, ProfileDecodeError) as err:
        logger.exception(
            "Encrypted profile decode failure during orbit viewport fetch",
            extra={"user_id": user_id, "session_id": payload.session_id},
        )
        raise HTTPException(
            status_code=500,
            detail="Profile data integrity error.",
        ) from err
    except DatabaseAccessError as err:
        logger.exception(
            "Database access failure during orbit viewport fetch",
            extra={"user_id": user_id, "session_id": payload.session_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Discovery viewport service temporarily unavailable.",
        ) from err
    except HTTPException:
        raise
    except Exception as err:
        logger.exception(
            "Unexpected orbit viewport failure",
            extra={"user_id": user_id, "session_id": payload.session_id},
        )
        raise HTTPException(
            status_code=500,
            detail="Unexpected internal error.",
        ) from err


async def _validate_discovery_action(
    user_id: str,
    payload: DiscoveryActionRequest,
) -> None:
    """Validate discovery action.

        Args:
            user_id: validate discovery action.
            payload: validate discovery action.

        Returns:
            None: Result value.
        """
    from app.db.exclusions import has_active_discovery_action
    from app.db.sessions import is_candidate_in_active_session

    is_reversal = payload.action.startswith("un")
    base_action = payload.action[2:] if is_reversal else payload.action

    if is_reversal:
        # Reversal actions must be validated against an active action.
        is_valid = await asyncio.to_thread(
            has_active_discovery_action,
            user_id,
            payload.target_id,
            base_action,
            payload.tab,
        )
        if not is_valid:
            raise HTTPException(
                status_code=400,
                detail=(
                    f"No active '{base_action}' action found "
                    "targeting this user to reverse."
                ),
            )
    else:
        # Forward actions must be validated against active session.
        is_valid = await asyncio.to_thread(
            is_candidate_in_active_session,
            user_id,
            payload.target_id,
        )
        if not is_valid:
            raise HTTPException(
                status_code=400,
                detail="Target user is not in any active discovery session.",
            )


@router.post("/api/v1/discover/action", response_model=DiscoveryActionResponse)
@limiter.limit(settings.rate_limit_discover)
async def handle_discovery_action(
    request: Request,
    payload: DiscoveryActionRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
):
    """Handle discovery action.

        Args:
            request: handle discovery action.
            payload: handle discovery action.
            _device: handle discovery action.
            user_id: handle discovery action.
        """
    _ = request
    try:
        await _validate_discovery_action(user_id, payload)

        if payload.action == "report":
            await asyncio.to_thread(
                record_user_report,
                reporter_id=user_id,
                target_id=payload.target_id,
                reason=payload.reason or "other",
                reason_detail=payload.reason_detail,
                tab=payload.tab,
            )
            await invalidate_block_cache(user_id, payload.target_id)
        else:
            await asyncio.to_thread(
                record_discovery_action,
                actor_id=user_id,
                target_id=payload.target_id,
                action=payload.action,
                tab=payload.tab,
            )
            if payload.action in ("block", "unblock"):
                await invalidate_block_cache(user_id, payload.target_id)
            elif payload.action in ("like", "superlike"):
                safe_create_task(
                    send_like_notification(
                        actor_id=user_id,
                        target_id=payload.target_id,
                        is_superlike=payload.action == "superlike",
                    ),
                )
        return DiscoveryActionResponse(success=True)

    except DatabaseAccessError as err:
        logger.exception(
            "Database access failure during discovery action handling",
            extra={"user_id": user_id, "target_id": payload.target_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Discovery action service temporarily unavailable.",
        ) from err
    except HTTPException:
        raise
    except Exception as err:
        logger.exception(
            "Unexpected failure handling discovery action",
            extra={"user_id": user_id, "target_id": payload.target_id},
        )
        raise HTTPException(
            status_code=500,
            detail="Unexpected internal error.",
        ) from err
