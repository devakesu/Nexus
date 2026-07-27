"""Redis caching utilities and client configuration.

Provides a shared asynchronous Redis client, helper functions for dynamic TTL calculations
with randomized jitter to prevent cache stampedes, and cache invalidation helpers.
"""

import logging
import secrets

import redis.asyncio as aioredis

from app.core.config import settings

logger = logging.getLogger(__name__)


def get_block_ids_cache_ttl() -> int:
    """Calculates TTL for user block IDs cache with randomized jitter.

    Returns:
        int: Cache expiration time in seconds (300-330s).
    """
    return 300 + secrets.randbelow(31)


# Shared async Redis client managed with internal connection pooling
redis_client = aioredis.from_url(
    settings.redis_url,
    encoding="utf-8",
    decode_responses=True,
    socket_connect_timeout=3,
    socket_timeout=3,
)


def invalidate_user_status_cache(user_id: str) -> None:
    """Evicts the cached user status record from Redis asynchronously.

    Args:
        user_id: Unique string identifier of the user whose status cache is to be evicted.
    """
    try:
        from app.core.infra.tasks import safe_create_task

        async def _delete_key() -> None:
            """Asynchronously delete the cached user status key from Redis."""
            await redis_client.delete(f"user:status:{user_id}")

        safe_create_task(_delete_key())
    except Exception:
        logger.exception(
            "Failed to invalidate user status cache",
            extra={"user_id": user_id},
        )

