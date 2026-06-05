import json
import logging
import random
import redis.asyncio as aioredis

from app.core.config import settings
from app.db.exclusions import fetch_active_block_ids

logger = logging.getLogger(__name__)

BLOCK_IDS_CACHE_TTL_SECONDS = 300 + random.randint(0, 30)

# Single shared async Redis client — connection pool is managed internally by redis-py
redis_client = aioredis.from_url(
    settings.redis_url,
    encoding="utf-8",
    decode_responses=True,
    socket_connect_timeout=3,
    socket_timeout=3,
)