import logging
from contextlib import asynccontextmanager

import firebase_admin
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from firebase_admin import credentials
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware
from starlette.responses import Response

from app.core.cache import redis_client
from app.core.config import settings
from app.api.discovery import router, limiter

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

app.state.limiter = limiter


def custom_rate_limit_handler(request: Request, exc: Exception) -> Response:
    if isinstance(exc, RateLimitExceeded):
        from slowapi import _rate_limit_exceeded_handler
        return _rate_limit_exceeded_handler(request, exc)
    raise exc


app.add_exception_handler(RateLimitExceeded, custom_rate_limit_handler)
app.add_middleware(SlowAPIMiddleware)

app.include_router(router)