import logging
from contextlib import asynccontextmanager, suppress
from typing import Any, cast

import firebase_admin
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from starlette.responses import Response

from app.api.discovery import router as discovery_router
from app.api.likes import router as likes_router
from app.api.status import router as status_router
from app.api.sync import router as sync_router
from app.api.user import router as user_router
from app.core.cache import redis_client
from app.core.config import settings
from app.core.limiter import limiter

logger = logging.getLogger(__name__)

if settings.enforce_app_check:
    if not settings.firebase_service_account_path:
        raise RuntimeError(
            "CRITICAL: Firebase service account path unpopulated. "
            "Required when ENFORCE_APP_CHECK is true.",
        )

    # Use public API firebase_admin.get_app() to check initialization
    firebase_any: Any = firebase_admin
    try:
        firebase_any.get_app()
    except ValueError:
        try:
            cred = firebase_any.credentials.Certificate(
                settings.firebase_service_account_path,
            )
            firebase_any.initialize_app(cred)
        except Exception as err:
            logger.critical("Firebase SDK initialization failed", exc_info=True)
            raise RuntimeError(
                "CRITICAL: Firebase SDK initialization failed. Check logs for details.",
            ) from err


@asynccontextmanager
async def lifespan(_app: FastAPI):
    if settings.enable_replay_protection:
        try:
            ping_func = cast(Any, redis_client).ping
            await ping_func()
            logger.info("Redis connection established at startup")
        except Exception as err:
            logger.critical("Redis unreachable during startup", exc_info=True)
            raise RuntimeError(
                "CRITICAL: Redis unreachable. "
                "Cannot start with replay protection enabled.",
            ) from err

    yield

    with suppress(Exception):
        await redis_client.aclose()


app = FastAPI(
    title="Nexus MEC Matchmaking Engine",
    version="1.4.0",
    docs_url="/api/v1/docs",
    redoc_url=None,
    lifespan=lifespan,
)

origins = [o.strip() for o in settings.allowed_origins.split(",") if o.strip()]
if "*" in origins and len(origins) > 1:
    raise RuntimeError(
        "CRITICAL: Wildcard origin cannot be mixed with specific origins.",
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PATCH", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "X-Firebase-AppCheck",
        "X-App-Variant",
    ],
)

app.state.limiter = limiter


def custom_rate_limit_handler(request: Request, exc: Exception) -> Response:
    detail = getattr(exc, "detail", "")
    response = JSONResponse(
        {"error": f"Rate limit exceeded: {detail}"},
        status_code=429,
    )
    limiter_obj = getattr(request.app.state, "limiter", None)
    view_rate_limit = getattr(request.state, "view_rate_limit", None)
    if limiter_obj and view_rate_limit:
        inject_headers = getattr(limiter_obj, "_inject_headers", None)
        if callable(inject_headers):
            response = cast(Response, inject_headers(response, view_rate_limit))
    return response


app.add_exception_handler(RateLimitExceeded, custom_rate_limit_handler)
app.add_middleware(SlowAPIMiddleware)

app.include_router(discovery_router)
app.include_router(likes_router)
app.include_router(user_router)
app.include_router(sync_router)
app.include_router(status_router)

try:
    from app.api.dev_temp import router as dev_router
    app.include_router(dev_router)
except ImportError:
    pass
