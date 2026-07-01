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
