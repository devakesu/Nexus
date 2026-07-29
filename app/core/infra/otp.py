"""OTP verification Redis key formatting and TTL configuration constants.

Centralizes Redis key construction and TTL constants for email/SMS OTP verification states.
"""

OTP_VERIFIED_TTL_SECONDS = 600


def otp_verified_redis_key(namespace: str, user_id: str) -> str:
    """Generates the Redis cache key for a verified OTP state.

    Args:
        namespace: Feature domain prefix (e.g., 'account_deletion', 'data_export').
        user_id: Unique string identifier of the authenticated user.

    Returns:
        str: Redis cache key string.
    """
    return f"{namespace}:otp_verified:{user_id}"
