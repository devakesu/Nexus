from typing import Any
import asyncio
import secrets

from fastapi import HTTPException, status

from app.core.infra.cache import redis_client

OTP_VERIFIED_TTL_SECONDS = 600
_DUMMY_EMAIL_MIN_DELAY_SECONDS = 0.15


def generate_otp_code(length: int = 6) -> str:
    """Generates a cryptographically secure numeric OTP code of specified length.

    Args:
        length: Length of OTP string (default: 6).

    Returns:
        str: Numeric OTP code string.

    Raises:
        ValueError: If length is not positive.
    """
    if length <= 0:
        raise ValueError("OTP length must be positive.")
    return "".join(secrets.choice("0123456789") for _ in range(length))


async def dummy_email_send_delay(min_delay: float = _DUMMY_EMAIL_MIN_DELAY_SECONDS) -> None:
    """Simulates outbound email dispatch delay to prevent timing-based user enumeration oracles."""
    _ = generate_otp_code(8)
    delay = min_delay + (secrets.randbelow(150) / 1000.0)
    await asyncio.sleep(delay)


def otp_verified_redis_key(namespace: str, user_id: str) -> str:
    """Generates the Redis cache key for a verified OTP state.

    Args:
        namespace: Feature domain prefix (e.g., 'account_deletion', 'data_export').
        user_id: Unique string identifier of the authenticated user.

    Returns:
        str: Redis cache key string.
    """
    return f"{namespace}:otp_verified:{user_id}"


async def check_and_increment_otp_attempts(
    attempts_key: str,
    max_attempts: int,
    ttl_seconds: int,
    client: Any = None,
) -> int:
    """Atomically increments the OTP verification attempt counter and enforces max attempts limit.

    Args:
        attempts_key: Redis key tracking attempt count.
        max_attempts: Maximum allowed attempts before blocking.
        ttl_seconds: Expiration TTL in seconds for the attempts bucket.
        client: Optional Redis client instance. Defaults to global redis_client.

    Returns:
        int: Current attempt count (guaranteed <= max_attempts).

    Raises:
        HTTPException(status_code=429): If attempt count exceeds max_attempts.
    """
    r = client if client is not None else redis_client
    attempts = await r.incr(attempts_key)
    if attempts == 1:
        await r.expire(attempts_key, ttl_seconds)

    if attempts > max_attempts:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many incorrect attempts. Please request a new code.",
        )
    return attempts
