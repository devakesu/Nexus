from datetime import datetime, timedelta
import logging

from fastapi import APIRouter, Body, Depends, HTTPException, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from Nexus_Engine import engine
from app.api.user import get_authenticated_user_id
from app.core.config import settings
from app.core.crypto import DecryptFailedError
from app.db.client import DatabaseAccessError, ProfileDecodeError, utcnow
from app.db.orbit import build_tab_aware_orbit_node_detail
from app.db.profiles import fetch_stage_1_candidates
from app.db.sessions import (
    create_discovery_session,
    fetch_discovery_node_detail,
    fetch_spatial_viewport,
    get_discovery_session,
)
from app.api.dependencies import verify_app_check_token
from app.models import (
    DiscoveryRequest,
    OrbitDiscoverResponse,
    OrbitNodeDetailRequest,
    OrbitNodeDetailResponse,
    OrbitNodeOut,
)

logger = logging.getLogger(__name__)

router = APIRouter()
limiter = Limiter(key_func=get_remote_address, enabled=settings.enable_rate_limiting)

@router.post("/api/v1/discover", response_model=OrbitDiscoverResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_discovery_orbit(
    request: Request,
    payload: DiscoveryRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
):
    _ = request
    active_tab = payload.tab
    filters = payload.filters

    try:
        session_id: str
        expires_at: datetime

        if payload.session_id:
            session = get_discovery_session(
                session_id=payload.session_id,
                viewer_id=user_id,
                active_tab=active_tab,
            )
            if not session:
                raise HTTPException(status_code=404, detail="Discovery session not found.")

            expires_at_raw = session.get("expires_at")
            if isinstance(expires_at_raw, str):
                expires_at = datetime.fromisoformat(expires_at_raw.replace("Z", "+00:00"))
            elif isinstance(expires_at_raw, datetime):
                expires_at = expires_at_raw
            else:
                raise HTTPException(status_code=500, detail="Discovery session expiry malformed.")

            if expires_at <= utcnow():
                raise HTTPException(status_code=410, detail="Discovery session expired. Please refresh.")

            session_id = payload.session_id
        else:
            viewer, candidate_pool = fetch_stage_1_candidates(
                viewer_id=user_id,
                active_tab=active_tab,
                filters=filters,
                candidate_limit=200,
            )

            if not viewer or not isinstance(viewer, dict):
                raise HTTPException(status_code=404, detail="Target user profile unpopulated.")

            ranked_orbit = engine.discover_orbit(
                viewer,
                active_tab,
                candidate_pool,
                orbit_limit=200,
            )

            ranked_orbit.sort(
                key=lambda x: (
                    -float(x.get("score") or 0.0),
                    str(x.get("profile", {}).get("id") or ""),
                )
            )

            session_id = create_discovery_session(
                viewer_id=user_id,
                active_tab=active_tab,
                filters=filters.model_dump(mode="json"),
                ranked_items=ranked_orbit,
                expires_in_minutes=15,
            )

            expires_at = utcnow() + timedelta(minutes=15)

        nodes, total_nodes = await fetch_spatial_viewport(
            session_id=session_id,
            viewer_id=user_id,
            center_x=0.0,
            center_y=0.0,
            radius=300.0,
        )

        return OrbitDiscoverResponse(
            session_id=session_id,
            expires_at=expires_at,
            total_nodes=total_nodes,
            nodes=[
                OrbitNodeOut(
                    id=node["id"],
                    name=node.get("name"),
                    score=float(node.get("score") or 0.0),
                    x=float(node.get("x") or 0.0),
                    y=float(node.get("y") or 0.0),
                    orbit_tier=int(node.get("orbit_tier") or 0),
                )
                for node in nodes
            ],
        )

    except (DecryptFailedError, ProfileDecodeError):
        logger.exception(
            "Encrypted profile decode failure during orbit discovery bootstrap",
            extra={"user_id": user_id, "active_tab": active_tab},
        )
        raise HTTPException(status_code=500, detail="Profile data integrity error.")
    except DatabaseAccessError:
        logger.exception(
            "Database access failure during orbit discovery bootstrap",
            extra={"user_id": user_id, "active_tab": active_tab},
        )
        raise HTTPException(status_code=503, detail="Discovery service temporarily unavailable.")
    except HTTPException:
        raise
    except Exception:
        logger.exception(
            "Unexpected orbit discovery bootstrap failure",
            extra={"user_id": user_id, "active_tab": active_tab},
        )
        raise HTTPException(status_code=500, detail="Unexpected internal error.")


@router.post("/api/v1/discover/node-details", response_model=OrbitNodeDetailResponse)
@limiter.limit(settings.rate_limit_discover)
async def get_discovery_node_detail(
    request: Request,
    payload: OrbitNodeDetailRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
):
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

        return build_tab_aware_orbit_node_detail(
            session_tab=session_tab,
            payload=detail_payload,
        )

    except (DecryptFailedError, ProfileDecodeError):
        logger.exception(
            "Encrypted profile decode failure during orbit node detail fetch",
            extra={
                "user_id": user_id,
                "session_id": payload.session_id,
                "candidate_id": payload.candidate_id,
            },
        )
        raise HTTPException(status_code=500, detail="Profile data integrity error.")
    except DatabaseAccessError:
        logger.exception(
            "Database access failure during orbit node detail fetch",
            extra={
                "user_id": user_id,
                "session_id": payload.session_id,
                "candidate_id": payload.candidate_id,
            },
        )
        raise HTTPException(status_code=503, detail="Discovery detail service temporarily unavailable.")
    except HTTPException:
        raise
    except Exception:
        logger.exception(
            "Unexpected orbit node detail failure",
            extra={
                "user_id": user_id,
                "session_id": payload.session_id,
                "candidate_id": payload.candidate_id,
            },
        )
        raise HTTPException(status_code=500, detail="Unexpected internal error.")
