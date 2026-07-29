"""FastAPI backend application factory, middleware configuration, and router initialization.

Configures application lifecycle, CORS policies, GZip compression, Sentry SDK initialization,
Firebase Admin SDK setup, rate limiting, exception handlers, and router mount points.
"""

import logging
from contextlib import asynccontextmanager, suppress
from os.path import dirname, exists, join
from typing import Any, cast

import firebase_admin
import sentry_sdk
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from starlette.exceptions import HTTPException as StarletteHTTPException
from starlette.responses import Response

from app.api.chat import router as chat_router
from app.api.discovery import router as discovery_router
from app.api.feedback import router as feedback_router
from app.api.legal import router as legal_router
from app.api.root import render_error_page
from app.api.root import router as root_router
from app.api.safety.endpoints import router as safety_router
from app.api.spotify import router as spotify_router
from app.api.status import router as status_router
from app.api.user import router as user_router
from app.api.well_known import router as well_known_router
from app.core.config import settings
from app.core.infra.cache import redis_client
from app.core.infra.limiter import limiter
from app.core.infra.sentry import scrub_event
from app.core.security.security import (
    RequestSizeLimitMiddleware,
    SecurityHeadersMiddleware,
)
from app.services.reminder_scheduler import (
    start_reminder_scheduler,
    stop_reminder_scheduler,
)

logger = logging.getLogger(__name__)

# Optional - a no-op if unset, unlike enforce_app_check's hard-fail style
# below. Until this runs, the capture_exception/capture_message calls
# already present in app/core/tasks.py, app/core/email.py, and
# app/db/chat_keys.py are silent no-ops (the SDK is a no-op until init()
# binds a client) - this is what turns them on.
if settings.sentry_backend_dsn:
    sentry_sdk.init(
        dsn=settings.sentry_backend_dsn,
        environment=settings.sentry_environment,
        traces_sample_rate=settings.sentry_traces_sample_rate,
        send_default_pii=False,
        before_send=scrub_event,
    )

if settings.firebase_service_account:
    # Use public API firebase_admin.get_app() to check initialization
    firebase_any: Any = firebase_admin
    try:
        firebase_any.get_app()
    except ValueError:
        try:
            cred = firebase_any.credentials.Certificate(
                settings.firebase_service_account,
            )
            firebase_any.initialize_app(cred)
        except Exception as err:
            logger.critical("Firebase SDK initialization failed", exc_info=True)
            raise RuntimeError(
                "CRITICAL: Firebase SDK initialization failed. Check logs for details.",
            ) from err
elif settings.enforce_app_check:
    raise RuntimeError(
        "CRITICAL: Firebase service account unpopulated. "
        "Required when ENFORCE_APP_CHECK is true.",
    )


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Manage application startup and shutdown lifecycle events.

    On startup:
    - Verifies Redis connectivity if replay protection is enabled.
    - Starts the account deletion reminder scheduler.

    On shutdown:
    - Stops the reminder scheduler.
    - Gracefully closes the Redis connection pool.

    Args:
        _app: FastAPI application instance.
    """
    import anyio.to_thread

    # Expand threadpool capacity for sync database operations to avoid thread exhaustion
    with suppress(Exception):
        anyio_to_thread: Any = anyio.to_thread
        anyio_to_thread.current_default_thread_limiter().total_tokens = 100

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

    start_reminder_scheduler()

    yield

    stop_reminder_scheduler()
    with suppress(Exception):
        await redis_client.aclose()


app = FastAPI(
    title="Nexus Matchmaking Engine",
    version=settings.app_version,
    docs_url="/api/v1/docs" if settings.debug else None,
    redoc_url=None,
    lifespan=lifespan,
)

origins = [o.strip() for o in settings.allowed_origins.split(",") if o.strip()]
allow_credentials = True
if "*" in origins:
    if settings.debug:
        allow_credentials = False
    else:
        raise RuntimeError(
            "CRITICAL: Wildcard origin '*' is not allowed "
            "when allow_credentials is True.",
        )

app.add_middleware(SecurityHeadersMiddleware)
app.add_middleware(RequestSizeLimitMiddleware)
app.add_middleware(GZipMiddleware, minimum_size=1000)
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=allow_credentials,
    allow_methods=["GET", "POST", "PUT", "PATCH", "OPTIONS"],
    allow_headers=[
        "Authorization",
        "Content-Type",
        "X-Firebase-AppCheck",
        "X-App-Variant",
    ],
)

app.state.limiter = limiter

static_path = join(dirname(__file__), "static")
if exists(static_path):
    app.mount("/static", StaticFiles(directory=static_path), name="static")


def custom_rate_limit_handler(request: Request, exc: Exception) -> Response:
    """Handle RateLimitExceeded exceptions by returning a 429 JSON response.

    Injects standard SlowAPI rate limit headers into the response if available.

    Args:
        request: Incoming FastAPI HTTP request.
        exc: The RateLimitExceeded exception instance.

    Returns:
        Response: A 429 JSONResponse containing the rate limit details and headers.
    """
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


async def http_exception_handler(request: Request, exc: Exception) -> Response:
    """Handle HTTP exceptions for both API requests and browser HTML requests.

    Renders a styled HTML error page if the Accept header indicates 'text/html',
    otherwise returns a standard JSON error response.

    Args:
        request: Incoming FastAPI HTTP request.
        exc: The HTTP exception object.

    Returns:
        Response: HTML error response or JSONResponse with status code and detail.
    """
    status_code = getattr(exc, "status_code", 500)
    detail = getattr(exc, "detail", None)
    accept = request.headers.get("accept", "")

    # If request accepts HTML (e.g. browser page navigation), render space error page
    if "text/html" in accept:
        msg = detail if isinstance(detail, str) else None
        return await render_error_page(code=status_code, message=msg)

    # Otherwise fallback to standard JSON error response for API callers
    return JSONResponse(
        status_code=status_code,
        content={"detail": detail or "An error occurred"},
        headers=getattr(exc, "headers", None),
    )


app.add_exception_handler(HTTPException, http_exception_handler)
app.add_exception_handler(StarletteHTTPException, http_exception_handler)
app.add_exception_handler(RateLimitExceeded, custom_rate_limit_handler)
app.add_middleware(SlowAPIMiddleware)
app.include_router(root_router)
app.include_router(chat_router)
app.include_router(discovery_router)
app.include_router(feedback_router)
app.include_router(legal_router)
app.include_router(safety_router)
app.include_router(spotify_router)
app.include_router(user_router)
app.include_router(status_router)
app.include_router(well_known_router)


if settings.debug:
    try:
        from app.api.dev_temp import router as dev_router

        app.include_router(dev_router)
    except ImportError:
        pass
