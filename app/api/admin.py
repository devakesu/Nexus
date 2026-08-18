"""Internal administrative and webhook endpoints."""

import hmac
import logging
from typing import Any

from fastapi import APIRouter, Depends, Header, HTTPException, Request, status

from app.core.config import settings
from app.core.security.jwks import clear_jwks_cache

logger = logging.getLogger(__name__)

router = APIRouter(tags=["admin"])


def verify_internal_admin_token(
    authorization: str | None = Header(default=None),
    x_admin_key: str | None = Header(default=None, alias="X-Admin-Key"),
) -> None:
    """Verifies that an incoming request has a valid administrative authorization secret.

    Accepts Bearer token in Authorization header or X-Admin-Key header matching
    the dedicated internal admin_api_key secret.

    Args:
        authorization: Optional Bearer authorization header string.
        x_admin_key: Optional X-Admin-Key header string.

    Raises:
        HTTPException: If credentials are missing, malformed, or invalid.
    """
    token: str | None = None
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization.split(" ", 1)[1].strip()
    elif x_admin_key:
        token = x_admin_key.strip()

    admin_key = settings.admin_api_key.strip() if settings.admin_api_key else ""

    if not token or not admin_key or not hmac.compare_digest(token, admin_key):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Unauthorized admin access.",
        )


@router.post("/admin/jwks/flush", response_model=dict[str, Any])
async def flush_jwks_cache_endpoint(
    request: Request,
    _auth: None = Depends(verify_internal_admin_token),
) -> dict[str, Any]:
    """Flushes the in-memory JWKS cache to immediately evict rotated or stale keys.

    Callable by key-rotation webhooks or internal operations tooling.
    """
    _ = request
    clear_jwks_cache()
    logger.info("JWKS in-memory cache flushed via internal admin endpoint")
    return {"flushed": True, "message": "JWKS cache successfully cleared."}
