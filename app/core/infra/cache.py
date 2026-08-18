"""Redis caching utilities and client configuration.

Provides a shared asynchronous Redis client, helper functions for dynamic TTL calculations
with randomized jitter to prevent cache stampedes, and cache invalidation helpers.
"""

import logging
import secrets
from typing import Any, cast

import redis
import redis.asyncio as aioredis
from redis.asyncio.connection import BlockingConnectionPool

from app.core.config import settings

logger = logging.getLogger(__name__)


def get_block_ids_cache_ttl() -> int:
    """Calculates TTL for user block IDs cache with randomized jitter.

    Returns:
        int: Cache expiration time in seconds (300-330s).
    """
    return 300 + secrets.randbelow(31)


# Shared async Redis client managed with internal connection pooling
pool = cast(Any, BlockingConnectionPool).from_url(
    settings.redis_url,
    max_connections=75,
    timeout=3.0,
    socket_connect_timeout=10,
    socket_timeout=10,
    decode_responses=True,
    encoding="utf-8",
)
redis_client = aioredis.Redis(connection_pool=pool)

# Synchronous Redis client for synchronous cache invalidations and operations outside event loops
sync_pool = cast(Any, redis.BlockingConnectionPool).from_url(
    settings.redis_url,
    max_connections=20,
    timeout=3.0,
    socket_connect_timeout=5,
    socket_timeout=5,
    decode_responses=True,
    encoding="utf-8",
)
sync_redis_client = redis.Redis(connection_pool=sync_pool)


def invalidate_user_status_cache(user_id: str) -> None:
    """Evicts the cached user status record from Redis synchronously.

    Args:
        user_id: Unique string identifier of the user whose status cache is to be evicted.
    """
    try:
        sync_redis_client.delete(f"user:status:{user_id}")
    except Exception:
        logger.exception(
            "Failed to invalidate user status cache",
            extra={"user_id": user_id},
        )


