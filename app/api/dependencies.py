import hashlib
import logging
import time
from typing import Optional

from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi import Depends, Header, HTTPException, status
from firebase_admin import app_check

from app.core.cache import redis_client
from app.core.config import settings

logger = logging.getLogger(__name__)

bearer_scheme = HTTPBearer(auto_error=False)

def get_bearer_token(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token.",
        )
    return credentials.credentials


def verify_app_check_token(
    x_firebase_appcheck: Optional[str] = Header(None)
) -> None:
    if not settings.enforce_app_check:
        return 

    if not x_firebase_appcheck:
        raise HTTPException(
            status_code=401, 
            detail="Access Denied: Missing device attestation credentials. Request must originate from an authorized device."
        )
        
    try:
        app_check.verify_token(x_firebase_appcheck)
    except Exception:
        raise HTTPException(
            status_code=403, 
            detail="Access Denied: Cryptographic device attestation integrity check failed. Execution blocked."
        )


async def verify_app_check_with_replay_protection(
    x_firebase_appcheck: Optional[str] = Header(None),
) -> None:
    """
    App Check verifier with one-time token consumption for sensitive routes.
    Uses atomic Redis SET NX EX to prevent replay without race conditions.
    Only active when ENFORCE_APP_CHECK and ENABLE_REPLAY_PROTECTION are both true.
    """
    if not settings.enforce_app_check:
        return

    if not x_firebase_appcheck:
        raise HTTPException(
            status_code=401,
            detail="Access Denied: Missing device attestation credentials.",
        )

    # Step 1: Cryptographic Firebase verification
    try:
        claims = app_check.verify_token(x_firebase_appcheck)
    except Exception:
        raise HTTPException(
            status_code=403,
            detail="Access Denied: Device attestation integrity check failed.",
        )

    # Step 2: Replay protection gate — only on sensitive routes
    if not settings.enable_replay_protection:
        return

    exp = claims.get("exp")
    if not exp:
        raise HTTPException(
            status_code=403,
            detail="Access Denied: App Check token missing expiry claim.",
        )

    now = int(time.time())
    ttl = max(int(exp) - now, 1)

    # SHA-256 hash of token to avoid storing raw credential in Redis
    token_hash = hashlib.sha256(x_firebase_appcheck.encode("utf-8")).hexdigest()
    redis_key = f"appcheck:consumed:{token_hash}"

    try:
        # Atomic NX+EX: sets key ONLY if it does not already exist, with TTL
        was_set = await redis_client.set(redis_key, "1", ex=ttl, nx=True)
    except Exception:
        # Redis failure should NOT silently pass for sensitive routes
        logger.error("[REPLAY] Redis unavailable during App Check consume check.")
        raise HTTPException(
            status_code=503,
            detail="Security checkpoint temporarily unavailable. Please retry.",
        )

    if not was_set:
        # Key already existed — this token was already consumed
        logger.warning("[REPLAY] App Check token replay attempt detected and blocked.")
        raise HTTPException(
            status_code=403,
            detail="Access Denied: App Check token already consumed. Obtain a fresh token.",
        )
