import logging

from fastapi import APIRouter, Request

from app.core.config import settings
from app.core.limiter import limiter

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/health")
@limiter.limit(settings.rate_limit_health)
def health_check(request: Request):
    _ = request
    return {"status": "healthy"}
