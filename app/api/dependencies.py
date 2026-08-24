"""FastAPI request dependency injection components and authentication guards.

Provides FastAPI dependencies for Bearer token extraction, ES256 JWT
cryptographic verification, user account status checks, and Firebase App Check.
"""

import asyncio
import hashlib
import json
import logging
import time
from typing import Any, cast

import jwt
from fastapi import Depends, Header, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import app_check
from redis.exceptions import RedisError
import sentry_sdk
from starlette.concurrency import run_in_threadpool

from app.core.config import settings
from app.core.infra.cache import redis_client
from app.core.security.jwks import get_live_supabase_public_key
from app.db.client import DatabaseAccessError, parse_utc_datetime, utcnow
from app.db.users import fetch_public_user

logger = logging.getLogger(__name__)

bearer_scheme = HTTPBearer(auto_error=False)



# ---------------------------------------------------------------------------
# Token extraction
# ---------------------------------------------------------------------------


def get_bearer_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> str:
    """Extract and validate the required HTTP Bearer token from request headers.

    Args:
        credentials: HTTP Bearer authorization credentials.

    Returns:
        str: Raw Bearer token string.

    Raises:
        HTTPException: 401 Unauthorized if Authorization header is missing.
    """
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return credentials.credentials


def get_optional_bearer_token(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> str | None:
    """Extract optional HTTP Bearer token from request headers if present.

    Args:
        credentials: Captured Authorization header credentials.

    Returns:
        str | None: Raw JWT Bearer token string if present, or None.
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
    """Decode and verify a JWT payload using configured ES256 (JWKS) or HS256 algorithm.

    Args:
        token: Raw JWT string.
        secret: Symmetric HS256 secret or JWKS dict fallback.
        public_key: Verified JWKS ES256 public key object.

    Returns:
        dict[str, Any]: Decoded JWT claims dictionary.

    Raises:
        jwt.InvalidTokenError: If token signature or claim verification fails.
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
    request: Request,
    token: str = Depends(get_bearer_token),
) -> dict[str, Any]:
    """Executes get authenticated user payload operation.

        Args:
            token: Input token parameter.

        Returns:
            dict[str, Any]: Response payload or result."""
    try:
        secret = settings.supabase_jwt_secret
        public_key = None
        if settings.is_jwks:
            public_key = await get_live_supabase_public_key(token)
            try:
                payload = _decode_jwt(token, secret, public_key)
            except jwt.InvalidSignatureError:
                logger.info(
                    "JWT signature verification failed with cached JWKS; forcing cache refresh and retrying.",
                )
                public_key = await get_live_supabase_public_key(token, force_refresh=True)
                payload = _decode_jwt(token, secret, public_key)
        else:
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

        request.state.authenticated_user_payload = payload
        request.state.user_id = user_uuid
        sentry_sdk.set_user({"id": user_uuid})
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


_MAX_BACKGROUND_TASKS = 1000
_background_tasks: set[asyncio.Task[None]] = set()
_local_presence_last_seen: dict[str, float] = {}
_LOCAL_PRESENCE_THROTTLE_SECONDS = 30.0


def _should_trigger_presence(user_id: str) -> bool:
    """In-memory process-local throttle gate to prevent queue exhaustion under high request volume."""
    now = time.monotonic()
    last = _local_presence_last_seen.get(user_id, 0.0)
    if now - last < _LOCAL_PRESENCE_THROTTLE_SECONDS:
        return False
    _local_presence_last_seen[user_id] = now
    if len(_local_presence_last_seen) > 10000:
        cutoff = now - _LOCAL_PRESENCE_THROTTLE_SECONDS
        stale_keys = [k for k, v in _local_presence_last_seen.items() if v < cutoff]
        for k in stale_keys:
            _local_presence_last_seen.pop(k, None)
    return True


def is_account_suspended(user_row: dict[str, Any]) -> bool:
    """Returns True if user is actively suspended and suspension has not expired."""
    if not bool(user_row.get("is_suspended", False)):
        return False
    suspended_until = user_row.get("suspended_until")
    if not suspended_until:
        return True
    try:
        dt = parse_utc_datetime(str(suspended_until))
        return utcnow() < dt
    except ValueError:
        return True


async def _update_presence_if_needed(user_id: str) -> None:
    """Updates the user's presence heartbeat, throttled to once per 60 seconds."""
    redis_key = f"user:presence:last_beat:{user_id}"
    try:
        # Set with ex=60 and nx=True to ensure it only executes once every 60 seconds
        was_set = await redis_client.set(redis_key, "1", ex=60, nx=True)
        if not was_set:
            return
        user_row = await get_cached_public_user(user_id)
        if user_row:
            if (
                not bool(user_row.get("is_active", True))
                or user_row.get("deletion_requested_at")
                or str(user_row.get("moderation_status") or "").lower() == "banned"
                or is_account_suspended(user_row)
            ):
                return

            from app.db.chat import upsert_presence_heartbeat
            await run_in_threadpool(upsert_presence_heartbeat, user_id, True)
    except (RedisError, DatabaseAccessError) as e:
        logger.warning("Failed to update general presence heartbeat: %s", e)


async def get_authenticated_user_id(
    payload: dict[str, Any] = Depends(get_authenticated_user_payload),
) -> str:
    """Executes get authenticated user id operation.

        Args:
            payload: Validated request body model containing parameters.

        Returns:
            str: Response payload or result."""
    user_id = payload["sub"]
    if _should_trigger_presence(user_id):
        if len(_background_tasks) < _MAX_BACKGROUND_TASKS:
            task = asyncio.create_task(_update_presence_if_needed(user_id))
            _background_tasks.add(task)
            task.add_done_callback(_background_tasks.discard)
        else:
            logger.warning(
                "Background presence task queue at capacity (%d); dropping presence update for user %s",
                _MAX_BACKGROUND_TASKS,
                user_id,
            )
    return user_id


async def get_optional_authenticated_user_id(
    token: str | None = Depends(get_optional_bearer_token),
) -> str | None:
    """Extract and verify optional HTTP Bearer token from request headers.

    Args:
        token: Input optional Bearer token string.

    Returns:
        str | None: Verified user UUID string if token is present and valid, or None if no token provided.

    Raises:
        HTTPException: 401 Unauthorized if a token was provided but is invalid or expired.
    """
    if not token:
        return None
    try:
        secret = settings.supabase_jwt_secret
        public_key = None
        if settings.is_jwks:
            public_key = await get_live_supabase_public_key(token)
            try:
                payload = _decode_jwt(token, secret, public_key)
            except jwt.InvalidSignatureError:
                public_key = await get_live_supabase_public_key(token, force_refresh=True)
                payload = _decode_jwt(token, secret, public_key)
        else:
            payload = _decode_jwt(token, secret, public_key)
        user_uuid: str | None = payload.get("sub")
        if not user_uuid:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token: sub claim missing.",
            )
        if user_uuid:
            sentry_sdk.set_user({"id": user_uuid})
        return user_uuid
    except jwt.ExpiredSignatureError as err:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication session expired.",
        ) from err
    except (jwt.PyJWTError, ValueError, AttributeError, KeyError) as err:
        logger.warning("Optional JWT validation failed: %s", err)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Cryptographic signature verification failed.",
        ) from err


async def get_cached_public_user(user_id: str) -> dict[str, Any] | None:
    """Executes get cached public user operation.

        Args:
            user_id: Unique UUID string of the authenticated user.

        Returns:
            dict[str, Any] | None: Response payload or result."""
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
    """Executes get active user id operation.

        Args:
            user_id: Unique UUID string of the authenticated user.

        Returns:
            str: Response payload or result."""
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


_SUSPENSION_REASON_MAP: dict[str, str] = {
    "spam": "spam or promotional activity",
    "harassment": "harassment or abusive behavior",
    "csam": "content policy violations",
    "fraud": "suspicious activity",
    "inappropriate_content": "inappropriate content",
    "terms_violation": "violating our Terms of Service",
}


def _build_suspension_error_detail(user_row: dict[str, Any]) -> str:
    suspended_until = user_row.get("suspended_until")
    reason_code = user_row.get("moderation_reason_code")
    user_reason = (
        _SUSPENSION_REASON_MAP.get(
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
        return (
            f"Your Account is suspended until {formatted_time}{reason_suffix}. "
            f"Please contact support at support@{settings.email_domain} for "
            "assistance."
        )
    return (
        f"Your Account is suspended indefinitely{reason_suffix}. Please "
        f"contact support at support@{settings.email_domain} for assistance."
    )


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

    if user_row.get("deletion_requested_at"):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is pending deletion.",
        )

    if str(user_row.get("moderation_status") or "").lower() == "banned":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is permanently banned.",
        )

    if is_account_suspended(user_row):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=_build_suspension_error_detail(user_row),
        )


# ---------------------------------------------------------------------------
# Safety-data consent guard
# ---------------------------------------------------------------------------


def is_consent_stale(
    stored_version: str | None,
    current_version: str | None = None,
) -> bool:
    """True if a consent category has never been granted, or was granted
    under an older terms version than what's currently required.
    """
    if not stored_version:
        return True
    req_version = (current_version or settings.current_terms_version).strip()
    try:
        return float(str(stored_version)) < float(req_version)
    except ValueError:
        return True


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
    if is_consent_stale(cast(str | None, stored_version)):
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
    if is_consent_stale(cast(str | None, stored_version)):
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
    """Executes verify app check token operation.

        Args:
            x_firebase_appcheck: Input x firebase appcheck parameter."""
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


async def _verify_app_check_with_replay_impl(
    x_firebase_appcheck: str | None,
    strict: bool = False,
) -> None:
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
        if strict:
            logger.exception(
                "[REPLAY] Redis unavailable during App Check consume check on critical route; failing closed.",
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Service temporarily unavailable. Replay protection service offline.",
            ) from err
        logger.exception(
            "[REPLAY] Redis unavailable during App Check consume check; failing open for safety availability.",
        )
        return

    if not was_set:
        logger.warning("[REPLAY] App Check token replay attempt detected and blocked.")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Access Denied: App Check token already consumed. Obtain a fresh token."
            ),
        )


async def verify_app_check_with_replay_protection(
    x_firebase_appcheck: str | None = Header(None),
) -> None:
    """App Check verifier with one-time token consumption (fails open on Redis outage for standard routes)."""
    await _verify_app_check_with_replay_impl(x_firebase_appcheck, strict=False)


async def verify_app_check_with_strict_replay_protection(
    x_firebase_appcheck: str | None = Header(None),
) -> None:
    """App Check verifier with one-time token consumption (fails closed with 503 on Redis outage for critical routes)."""
    await _verify_app_check_with_replay_impl(x_firebase_appcheck, strict=True)


async def resolve_verified_user(
    auth_user_id: str | None,
    email: str | None,
) -> tuple[str | None, str]:
    """Resolves target user ID and normalized email address from token or request body.

    Args:
        auth_user_id: Optional authenticated user ID string.
        email: Optional input email address string.

    Returns:
        tuple[str | None, str]: Resolved user ID (or None if not found) and normalized email.

    Raises:
        HTTPException: 400 if no email is provided or authenticated account has no email.
    """
    from app.db.users import get_user_email_by_id, get_user_id_by_email

    if auth_user_id:
        user_email = await run_in_threadpool(get_user_email_by_id, auth_user_id)
        if not user_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No verified email on this account. Contact support for assistance.",
            )
        return auth_user_id, user_email

    if email and email.strip():
        norm_email = email.strip().lower()
        user_id = await run_in_threadpool(get_user_id_by_email, norm_email)
        return user_id, norm_email

    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail="Please enter your registered email address.",
    )
