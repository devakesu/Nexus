from datetime import datetime
import logging
from contextlib import asynccontextmanager
from typing import Optional

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
from app.database import DatabaseAccessError, ProfileDecodeError, create_discovery_session, fetch_discovery_session_page, fetch_stage_1_candidates, get_discovery_session, utcnow
from app.jwks import get_live_supabase_public_key
from app.models import DiscoverResponse, DiscoveryFilters, DiscoveryRequest, FeedItemOut

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


def get_authenticated_user_id(authorization: Optional[str] = Header(None)) -> str:
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

        user_uuid: Optional[str] = payload.get("sub")
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

@app.post("/api/v1/discover", response_model=DiscoverResponse)
@limiter.limit(settings.rate_limit_discover)
def get_recommendations(
    request: Request,
    payload: DiscoveryRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
):
    _ = request
    active_tab = payload.tab
    filters = payload.filters or DiscoveryFilters()
    limit = min(max(payload.limit or 20, 1), 20)
    cursor = max(payload.cursor or 0, 0)

    try:
        if payload.session_id:
            session = get_discovery_session(
                session_id=payload.session_id,
                viewer_id=user_id,
                active_tab=active_tab,
            )
            if not session:
                raise HTTPException(status_code=404, detail="Discovery session not found.")

            expires_at = session.get("expires_at")
            if isinstance(expires_at, str):
                expires_at = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))

            if not isinstance(expires_at, datetime):
                raise HTTPException(status_code=500, detail="Discovery session expiry malformed.")

            if expires_at <= utcnow():
                raise HTTPException(status_code=410, detail="Discovery session expired. Please refresh.")

            page_rows, total_count = fetch_discovery_session_page(
                session_id=payload.session_id,
                viewer_id=user_id,
                start_position=cursor,
                limit=limit,
            )

            sanitized_feed = [
                FeedItemOut(
                    id=row["id"],
                    name=row["name"],
                    branch=row["branch"],
                    year=row["year"],
                    display_gender=row.get("display_gender"),
                    display_sexuality=row.get("display_sexuality"),
                    role=row.get("role"),
                    score=row.get("score"),
                )
                for row in page_rows
            ]

            next_cursor = (
                page_rows[-1]["position"] + 1
                if page_rows
                else cursor
            )
            has_more = next_cursor < total_count

            return DiscoverResponse(
                session_id=payload.session_id,
                feed=sanitized_feed,
                has_more=has_more,
                next_cursor=next_cursor if has_more else None,
            )

        viewer, candidate_pool = fetch_stage_1_candidates(
            viewer_id=user_id,
            active_tab=active_tab,
            filters=filters,
            candidate_limit=200,
        )

        if not viewer or not isinstance(viewer, dict):
            raise HTTPException(status_code=404, detail="Target user profile unpopulated.")

        ranked = engine.discover_feed(
            viewer,
            active_tab,
            candidate_pool,
            feed_limit=200,
        )

        ranked.sort(
            key=lambda x: (
                -float(x.get("score") or 0),
                str(x.get("profile", {}).get("id") or "")
            )
        )

        session_id = create_discovery_session(
            viewer_id=user_id,
            active_tab=active_tab,
            filters=filters.model_dump(mode="json"),
            ranked_items=ranked,
            expires_in_minutes=15,
        )

        page_rows, total_count = fetch_discovery_session_page(
            session_id=session_id,
            viewer_id=user_id,
            start_position=0,
            limit=limit,
        )

        sanitized_feed = [
            FeedItemOut(
                id=row["id"],
                name=row["name"],
                branch=row["branch"],
                year=row["year"],
                display_gender=row.get("display_gender"),
                display_sexuality=row.get("display_sexuality"),
                role=row.get("role"),
                score=row.get("score"),
            )
            for row in page_rows
        ]

        next_cursor = (
            page_rows[-1]["position"] + 1
            if page_rows
            else 0
        )
        has_more = next_cursor < total_count

        return DiscoverResponse(
            session_id=session_id,
            feed=sanitized_feed,
            has_more=has_more,
            next_cursor=next_cursor if has_more else None,
        )

    except (DecryptFailedError, ProfileDecodeError):
        logger.exception(
            "Encrypted profile decode failure during discovery",
            extra={"user_id": user_id, "active_tab": active_tab},
        )
        raise HTTPException(status_code=500, detail="Profile data integrity error.")
    except DatabaseAccessError:
        logger.exception(
            "Database access failure during discovery",
            extra={"user_id": user_id, "active_tab": active_tab},
        )
        raise HTTPException(status_code=503, detail="Discovery service temporarily unavailable.")
    except HTTPException:
        raise
    except Exception:
        logger.exception(
            "Unexpected discovery failure",
            extra={"user_id": user_id, "active_tab": active_tab},
        )
        raise HTTPException(status_code=500, detail="Unexpected internal error.")