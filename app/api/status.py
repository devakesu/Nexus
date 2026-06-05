import logging

from fastapi import APIRouter, Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()
limiter = Limiter(key_func=get_remote_address, enabled=settings.enable_rate_limiting)


@router.get("/health")
@limiter.limit(settings.rate_limit_health)
def health_check(request: Request):
    _ = request
    return {"status": "healthy"}
