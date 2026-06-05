from datetime import datetime, timedelta
import logging
from contextlib import asynccontextmanager

import firebase_admin
import jwt
from fastapi import Body, Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from firebase_admin import credentials
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from slowapi.util import get_remote_address
from starlette.responses import Response

from Nexus_Engine import engine
from app.cache import redis_client
from app.check import verify_app_check_token
from app.config import settings
from app.crypto import DecryptFailedError
from app.database import (
    DatabaseAccessError,
    ProfileDecodeError,
    build_tab_aware_orbit_node_detail,
    create_discovery_session,
    fetch_discovery_node_detail,
    fetch_spatial_viewport,
    fetch_stage_1_candidates,
    get_discovery_session,
    get_discovery_session_for_viewer,
    utcnow,
)
from app.jwks import get_live_supabase_public_key
from app.models import DiscoveryRequest, OrbitDiscoverResponse, OrbitNodeDetailRequest, OrbitNodeDetailResponse, OrbitNodeOut

logger = logging.getLogger(__name__)

if settings.enforce_app_check:
    if not settings.firebase_service_account_path:
        raise RuntimeError(
            "CRITICAL: Firebase service account path unpopulated. Required when ENFORCE_APP_CHECK is true."
        )

    if not firebase_admin._apps:
        try:
            cred = credentials.Certificate(settings.firebase_service_account_path)
            firebase_admin.initialize_app(cred)
        except Exception:
            logger.critical("Firebase SDK initialization failed", exc_info=True)
            raise RuntimeError(
                "CRITICAL: Firebase SDK initialization failed. Check logs for details."
            )


@asynccontextmanager
async def lifespan(app: FastAPI):
    if settings.enable_replay_protection:
        try:
            await redis_client.ping()
            logger.info("Redis connection established at startup")
        except Exception:
            logger.critical("Redis unreachable during startup", exc_info=True)
            raise RuntimeError(
                "CRITICAL: Redis unreachable. Cannot start with replay protection enabled."
            )

    yield

    try:
        await redis_client.aclose()
    except Exception:
        logger.warning("Redis client close failed during shutdown", exc_info=True)


app = FastAPI(
    title="Nexus MEC Matchmaking Engine",
    version="1.4.0",
    docs_url="/api/v1/docs",
    redoc_url=None,
    lifespan=lifespan,
)

origins = [o.strip() for o in settings.allowed_origins.split(",") if o.strip()]
if "*" in origins and len(origins) > 1:
    raise RuntimeError("CRITICAL: Wildcard origin cannot be mixed with specific origins.")

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["POST", "GET", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Firebase-AppCheck"],
)

limiter = Limiter(key_func=get_remote_address, enabled=settings.enable_rate_limiting)
app.state.limiter = limiter


def custom_rate_limit_handler(request: Request, exc: Exception) -> Response:
    if isinstance(exc, RateLimitExceeded):
        return _rate_limit_exceeded_handler(request, exc)
    raise exc


app.add_exception_handler(RateLimitExceeded, custom_rate_limit_handler)
app.add_middleware(SlowAPIMiddleware)


def get_authenticated_user_id(authorization: str | None = Header(None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Missing or malformed Authorization header credentials.",
        )

    token = authorization.split(" ", 1)[1]

    try:
        public_key = get_live_supabase_public_key(token)
        payload = jwt.decode(
            token,
            public_key,
            algorithms=["ES256"],
            audience="authenticated",
        )

        user_uuid: str | None = payload.get("sub")
        if not user_uuid:
            raise HTTPException(status_code=401, detail="Invalid token: sub claim missing.")

        return user_uuid

    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Authentication session expired.")
    except jwt.InvalidTokenError:
        logger.warning("JWT validation failed")
        raise HTTPException(
            status_code=401,
            detail="Cryptographic signature verification failed.",
        )


@app.get("/health")
@limiter.limit(settings.rate_limit_health)
def health_check(request: Request):
    _ = request
    return {"status": "healthy"}

@app.post("/api/v1/discover", response_model=OrbitDiscoverResponse)
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
    
    
@app.post("/api/v1/discover/node-details", response_model=OrbitNodeDetailResponse)
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