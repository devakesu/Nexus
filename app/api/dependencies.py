"""FastAPI request dependency injection components and authentication guards.

Provides FastAPI dependencies for Bearer token extraction, ES256 JWT cryptographic verification,
user account status checks (suspension/deletion), and Firebase App Check device attestation.
"""

import asyncio
import hashlib
import json
import logging
import time
from typing import Any, cast

import jwt
from fastapi import Depends, Header, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import app_check
from starlette.concurrency import run_in_threadpool

from app.core.cache import redis_client
from app.core.config import settings
from app.core.jwks import get_live_supabase_public_key
from app.db.client import parse_utc_datetime
from app.db.users import fetch_public_user

logger = logging.getLogger(__name__)

bearer_scheme = HTTPBearer(auto_error=False)



# ---------------------------------------------------------------------------
# Token extraction
# ---------------------------------------------------------------------------


def get_bearer_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),  # noqa: B008
) -> str:
    """Get bearer token.

        Args:
            credentials: get bearer token.

        Returns:
            str: Result value.
        """
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token.",
        )
    return credentials.credentials


def get_optional_bearer_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),  # noqa: B008
) -> str | None:
    """Get optional bearer token.

        Args:
            credentials: get optional bearer token.

        Returns:
            str | None: Result value.
        """
    if credentials is None or credentials.scheme.lower() != "bearer":
        return None
    return credentials.credentials


# ---------------------------------------------------------------------------
# JWT / user identity
# ---------------------------------------------------------------------------



def _decode_jwt(
    token: str,
    secret: str | dict[str, Any],
    public_key: Any,
) -> dict[str, Any]:
    """Decode jwt.

        Args:
            token: decode jwt.
            secret: decode jwt.
            public_key: decode jwt.

        Returns:
            dict[str, Any]: Result value.
        """
    if settings.is_jwks:
        return jwt.decode(
            token,
            public_key,
            algorithms=["ES256"],
            audience="authenticated",
        )
    if not isinstance(secret, str):
        raise jwt.InvalidTokenError(
            "Symmetric HS256 secret key config mismatch.",
        )
    return jwt.decode(
        token,
        secret,
        algorithms=["HS256"],
        audience="authenticated",
    )


async def get_authenticated_user_payload(
    token: str = Depends(get_bearer_token),
) -> dict[str, Any]:
    """Get authenticated user payload.

        Args:
            token: get authenticated user payload.

        Returns:
            dict[str, Any]: Result value.
        """
    try:
        secret = settings.supabase_jwt_secret
        public_key = None
        if settings.is_jwks:
            public_key = await get_live_supabase_public_key(token)

        payload = _decode_jwt(token, secret, public_key)

        user_uuid: str | None = payload.get("sub")
        if not user_uuid:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token: sub claim missing.",
            )

        # Map id to user_uuid for compatibility
        if "id" not in payload and user_uuid:
            payload["id"] = user_uuid

        return payload

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


_background_tasks: set[asyncio.Task[None]] = set()


async def _update_presence_if_needed(user_id: str) -> None:
    """Updates the user's presence heartbeat, throttled to once per 60 seconds."""
    redis_key = f"user:presence:last_beat:{user_id}"
    try:
        # Set with ex=60 and nx=True to ensure it only executes once every 60 seconds
        was_set = await redis_client.set(redis_key, "1", ex=60, nx=True)
        if was_set:
            from app.db.chat import upsert_presence_heartbeat
            await run_in_threadpool(upsert_presence_heartbeat, user_id, True)
    except Exception as e:  # noqa: BLE001
        logger.warning("Failed to update general presence heartbeat: %s", e)


async def get_authenticated_user_id(
    payload: dict[str, Any] = Depends(get_authenticated_user_payload),  # noqa: B008
) -> str:
    """Get authenticated user id.

        Args:
            payload: get authenticated user id.

        Returns:
            str: Result value.
        """
    user_id = payload["sub"]
    task = asyncio.create_task(_update_presence_if_needed(user_id))
    _background_tasks.add(task)
    task.add_done_callback(_background_tasks.discard)
    return user_id


async def get_optional_authenticated_user_id(
    token: str | None = Depends(get_optional_bearer_token),
) -> str | None:
    """Get optional authenticated user id.

        Args:
            token: get optional authenticated user id.

        Returns:
            str | None: Result value.
        """
    if not token:
        return None
    try:
        secret = settings.supabase_jwt_secret
        public_key = None
        if settings.is_jwks:
            public_key = await get_live_supabase_public_key(token)
        payload = _decode_jwt(token, secret, public_key)
        user_uuid: str | None = payload.get("sub")
        return user_uuid
    except Exception:
        return None



async def get_cached_public_user(user_id: str) -> dict[str, Any] | None:
    """Get cached public user.

        Args:
            user_id: get cached public user.

        Returns:
            dict[str, Any] | None: Result value.
        """
    redis_key = f"user:status:{user_id}"
    try:
        cached = await redis_client.get(redis_key)
        if cached:
            res = json.loads(cached)
            if isinstance(res, dict):
                return cast(dict[str, Any], res)
    except Exception:
        logger.exception("Failed to fetch user status from Redis cache")

    user_row = await run_in_threadpool(fetch_public_user, user_id)
    if user_row:
        try:
            await redis_client.set(redis_key, json.dumps(user_row), ex=60)
        except Exception:
            logger.exception("Failed to write user status to Redis cache")
    return user_row


async def get_active_user_id(
    user_id: str = Depends(get_authenticated_user_id),
) -> str:
    """Get active user id.

        Args:
            user_id: get active user id.

        Returns:
            str: Result value.
        """
    user_row = await get_cached_public_user(user_id)
    if not user_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User account not found. Please complete bootstrap first.",
        )
    assert_account_active(user_row)
    return user_id


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
                f"support@{settings.email_domain} for assistance."
            ),
        )

    if bool(user_row.get("is_suspended", False)):
        suspended_until = user_row.get("suspended_until")
        reason_code = user_row.get("moderation_reason_code")
        # Map internal codes to generic user-facing categories
        reason_map = {
            "spam": "spam or promotional activity",
            "harassment": "harassment or abusive behavior",
            "csam": "content policy violations",
            "fraud": "suspicious activity",
            "inappropriate_content": "inappropriate content",
            "terms_violation": "violating our Terms of Service",
        }
        user_reason = (
            reason_map.get(
                str(reason_code).strip().lower(),
                "violating community guidelines",
            )
            if reason_code
            else None
        )
        reason_suffix = f" (Reason: {user_reason})" if user_reason else ""
        if suspended_until:
            try:
                dt = parse_utc_datetime(str(suspended_until))
                formatted_time = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
            except ValueError:
                formatted_time = str(suspended_until)
            detail = (
                f"Your Account is suspended until {formatted_time}{reason_suffix}. "
                f"Please contact support at support@{settings.email_domain} for "
                "assistance."
            )
        else:
            detail = (
                f"Your Account is suspended indefinitely{reason_suffix}. Please "
                f"contact support at support@{settings.email_domain} for assistance."
            )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=detail,
        )


# ---------------------------------------------------------------------------
# Safety-data consent guard
# ---------------------------------------------------------------------------


def assert_safety_consent(user_row: dict[str, Any]) -> None:
    """Raise 412 if the account hasn't (or no longer has) given consent to
    Meetup Safety/SOS/Digital Witness location-data processing - see
    20260802000000_terms_consent_expansion.sql. Unlike assert_account_active
    this is 412 (Precondition Failed), not 403, and carries a stable
    machine-readable detail string ("safety_consent_required") so the
    client can distinguish it from a generic auth failure and show an
    inline consent prompt instead of an error. This is the only
    server-side enforcement point for safety consent added so far -
    broader per-endpoint coverage is a separate future effort, same
    scoping as assert_account_active's own partial rollout.
    """
    stored_version = user_row.get("safety_data_consent_version")
    current_version = settings.current_terms_version.strip()
    is_stale = True
    if stored_version:
        try:
            is_stale = float(str(stored_version)) < float(current_version)
        except ValueError:
            is_stale = True
    if is_stale:
        raise HTTPException(
            status_code=status.HTTP_412_PRECONDITION_FAILED,
            detail="safety_consent_required",
        )


async def require_safety_consent(
    user_id: str = Depends(get_active_user_id),
) -> str:
    """Drop-in replacement for Depends(get_active_user_id) on
    endpoints that create/process Meetup Safety data (trusted contacts,
    session start, SOS alerts, evidence registration) - fetches the user
    row and runs assert_safety_consent before returning the same user_id,
    so route handlers need no other change beyond swapping the dependency.
    """
    user_row = await get_cached_public_user(user_id)
    if not user_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User bootstrap row not found.",
        )
    assert_safety_consent(user_row)
    return user_id


# ---------------------------------------------------------------------------
# Special-category-data consent guard (sexual orientation / religious belief)
# ---------------------------------------------------------------------------


def assert_special_category_consent(user_row: dict[str, Any]) -> None:
    """Raise 412 if the account hasn't (or no longer has) given consent to
    sexual-orientation/religious-belief processing - see
    20260802000000_terms_consent_expansion.sql. Unlike general consent,
    this category is optional (the underlying profile fields are themselves
    optional/skippable), so this is only called when a caller is actually
    about to set one of those fields to a real disclosed value - not a
    blanket per-request check like assert_account_active. Same 412 +
    stable machine-readable detail string convention as
    assert_safety_consent, so the client can show an inline consent prompt
    instead of a generic error.
    """
    stored_version = user_row.get("special_category_consent_version")
    current_version = settings.current_terms_version.strip()
    is_stale = True
    if stored_version:
        try:
            is_stale = float(str(stored_version)) < float(current_version)
        except ValueError:
            is_stale = True
    if is_stale:
        raise HTTPException(
            status_code=status.HTTP_412_PRECONDITION_FAILED,
            detail="special_category_consent_required",
        )


# ---------------------------------------------------------------------------
# Firebase App Check
# ---------------------------------------------------------------------------


def verify_app_check_token(
    x_firebase_appcheck: str | None = Header(None),
) -> None:
    """Verify app check token.

        Args:
            x_firebase_appcheck: verify app check token.

        Returns:
            None: Result value.
        """
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
