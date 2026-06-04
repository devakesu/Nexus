import logging
import redis.asyncio as aioredis
from app.config import settings

logger = logging.getLogger(__name__)

# Single shared async Redis client — connection pool is managed internally by redis-py
redis_client = aioredis.from_url(
    settings.redis_url,
    encoding="utf-8",
    decode_responses=True,
    socket_connect_timeout=3,
    socket_timeout=3,
)