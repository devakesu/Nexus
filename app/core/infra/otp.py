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
    try:
        attempts_int = int(attempts)
    except (TypeError, ValueError):
        attempts_int = 1

    if attempts_int == 1:
        await r.expire(attempts_key, ttl_seconds)

    if attempts_int > max_attempts:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many incorrect attempts. Please request a new code.",
        )
    return attempts_int


async def verify_and_consume_hashed_otp(
    otp_key: str,
    attempts_key: str,
    user_identifier: str,
    phone_norm: str,
    submitted_code: str,
    max_attempts: int,
    ttl_seconds: int,
    client: Any = None,
    verify_func: Any = None,
    expired_detail: str = "That code has expired or was never requested. Request a new one.",
    incorrect_detail: str = "Incorrect code.",
) -> bool:
    """Atomically checks attempts, verifies a hashed OTP, and cleans up Redis keys on success."""
    if verify_func is None:
        from app.core.auth.phone_otp import verify_otp_hash
        verifier = verify_otp_hash
    else:
        verifier = verify_func

    r = client if client is not None else redis_client
    await check_and_increment_otp_attempts(
        attempts_key,
        max_attempts,
        ttl_seconds,
        client=r,
    )

    stored_hash = await r.get(otp_key)
    if not stored_hash:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=expired_detail,
        )

    stored_hash_str = (
        stored_hash.decode("utf-8")
        if isinstance(stored_hash, bytes)
        else str(stored_hash)
    )

    if not verifier(user_identifier, phone_norm, submitted_code, stored_hash_str):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=incorrect_detail,
        )

    await r.delete(otp_key)
    await r.delete(attempts_key)
    return True


async def verify_and_consume_raw_otp(
    otp_key: str,
    attempts_key: str,
    submitted_code: str,
    max_attempts: int,
    ttl_seconds: int,
    client: Any = None,
    invalid_detail: str = "Invalid or expired verification code.",
) -> bool:
    """Atomically checks attempts, verifies a raw OTP code via constant-time comparison, and cleans up keys.

    Args:
        otp_key: Redis key where raw OTP string is stored.
        attempts_key: Redis key tracking attempt count.
        submitted_code: User-submitted plaintext numeric code.
        max_attempts: Maximum allowed incorrect attempts before lockout.
        ttl_seconds: Expiration TTL in seconds for attempts key.
        client: Optional Redis client instance. Defaults to global redis_client.
        invalid_detail: Error message detail when code is missing, expired, or incorrect.

    Returns:
        bool: True upon successful verification and consumption.

    Raises:
        HTTPException(429): If attempt count exceeds max_attempts.
        HTTPException(400): If code is expired or invalid.
    """
    import hmac

    r = client if client is not None else redis_client
    await check_and_increment_otp_attempts(
        attempts_key,
        max_attempts,
        ttl_seconds,
        client=r,
    )

    stored_otp = await r.get(otp_key)
    if not stored_otp:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=invalid_detail,
        )

    stored_otp_str = (
        stored_otp.decode("utf-8")
        if isinstance(stored_otp, bytes)
        else str(stored_otp)
    )

    if not hmac.compare_digest(stored_otp_str.strip(), submitted_code.strip()):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=invalid_detail,
        )

    await r.delete(otp_key)
    await r.delete(attempts_key)
    return True
