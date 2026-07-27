"""FastAPI status and health check router.

Provides readiness and liveness health check probe endpoints.
"""

import logging

from fastapi import APIRouter, Request

from app.core.config import settings
from app.core.infra.limiter import limiter

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/health")
@limiter.limit(settings.rate_limit_health)
def health_check(request: Request) -> dict[str, str]:
    """Basic health check endpoint returning server status.

    Args:
        request: FastAPI HTTP request instance.

    Returns:
        dict[str, str]: Dict containing status string 'healthy'.
    """
    _ = request
    return {"status": "healthy"}

