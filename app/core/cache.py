import logging
import secrets

import redis.asyncio as aioredis

from app.core.config import settings

logger = logging.getLogger(__name__)


def get_block_ids_cache_ttl() -> int:
    return 300 + secrets.randbelow(31)


# Single shared async Redis client - connection pool is managed internally by redis-py
redis_client = aioredis.from_url(
    settings.redis_url,
    encoding="utf-8",
    decode_responses=True,
    socket_connect_timeout=3,
    socket_timeout=3,
)


def invalidate_user_status_cache(user_id: str) -> None:
    """Evicts the cached user status record from Redis."""
    try:
        from app.core.tasks import safe_create_task
        async def _delete_key():
            await redis_client.delete(f"user:status:{user_id}")
        safe_create_task(_delete_key())
    except Exception:
        logger.exception(
            "Failed to invalidate user status cache",
            extra={"user_id": user_id},
        )
