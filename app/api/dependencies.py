import hashlib
import logging
import time
from datetime import datetime
from typing import Any

import jwt
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import app_check

from app.core.cache import redis_client
from app.core.config import settings
from app.core.jwks import get_live_supabase_public_key

logger = logging.getLogger(__name__)

bearer_scheme = HTTPBearer(auto_error=False)


# ---------------------------------------------------------------------------
# Token extraction
# ---------------------------------------------------------------------------


def get_bearer_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),  # noqa: B008
) -> str:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token.",
        )
    return credentials.credentials


# ---------------------------------------------------------------------------
# JWT / user identity
# ---------------------------------------------------------------------------


def get_authenticated_user_id(authorization: str | None = Header(None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
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
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token: sub claim missing.",
            )

        return user_uuid

    except jwt.ExpiredSignatureError as err:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication session expired.",
        ) from err
    except jwt.InvalidTokenError as err:
        logger.warning("JWT validation failed")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Cryptographic signature verification failed.",
        ) from err


# ---------------------------------------------------------------------------
# Account-status guard
# ---------------------------------------------------------------------------


def assert_account_active(user_row: dict[str, Any]) -> None:
    """Raise 403 if the account is inactive or suspended."""
    if not bool(user_row.get("is_active", True)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Account is inactive. Please contact support at "
                f"support@{settings.app_domain} for assistance."
            ),
        )

    if bool(user_row.get("is_suspended", False)):
        suspended_until = user_row.get("suspended_until")
        reason_code = user_row.get("moderation_reason_code")
        reason_suffix = f" (Reason: {reason_code})" if reason_code else ""
        if suspended_until:
            try:
                dt = datetime.fromisoformat(str(suspended_until).replace("Z", "+00:00"))
                formatted_time = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
            except ValueError:
                formatted_time = str(suspended_until)
            detail = (
                f"Your Account is suspended until {formatted_time}{reason_suffix}. "
                f"Please contact support at support@{settings.app_domain} for "
                "assistance."
            )
        else:
            detail = (
                f"Your Account is suspended indefinitely{reason_suffix}. Please "
                f"contact support at support@{settings.app_domain} for assistance."
            )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=detail,
        )


# ---------------------------------------------------------------------------
# Firebase App Check
# ---------------------------------------------------------------------------


def verify_app_check_token(
    x_firebase_appcheck: str | None = Header(None),
) -> None:
    if not settings.enforce_app_check:
        return

    if not x_firebase_appcheck:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=(
                "Access Denied: Missing device attestation credentials. "
                "Request must originate from an authorized device."
            ),
        )

    try:
        app_check.verify_token(x_firebase_appcheck)
    except Exception as err:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Access Denied: Cryptographic device attestation integrity "
                "check failed. Execution blocked."
            ),
        ) from err


async def verify_app_check_with_replay_protection(
    x_firebase_appcheck: str | None = Header(None),
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
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Access Denied: Missing device attestation credentials.",
        )

    try:
        claims = app_check.verify_token(x_firebase_appcheck)
    except Exception as err:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access Denied: Device attestation integrity check failed.",
        ) from err

    if not settings.enable_replay_protection:
        return

    exp = claims.get("exp")
    if not exp:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
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
    except Exception as err:
        logger.error("[REPLAY] Redis unavailable during App Check consume check.")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Security checkpoint temporarily unavailable. Please retry.",
        ) from err

    if not was_set:
        logger.warning("[REPLAY] App Check token replay attempt detected and blocked.")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Access Denied: App Check token already consumed. Obtain a fresh token."
            ),
        )
