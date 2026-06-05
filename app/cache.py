import json
import logging
import redis.asyncio as aioredis
from app.config import settings
from app.database import fetch_active_block_ids
import random

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

def _block_ids_cache_key(viewer_id: str) -> str:
    return f"discovery:block_ids:{viewer_id}"

async def get_cached_active_block_ids(viewer_id: str) -> set[str]:
    key = _block_ids_cache_key(viewer_id)

    cached = await redis_client.get(key)
    if cached:
        try:
            decoded = json.loads(cached)
            if isinstance(decoded, list):
                return {str(x) for x in decoded if str(x)}
        except json.JSONDecodeError:
            pass

    block_ids = fetch_active_block_ids(viewer_id)

    await redis_client.set(
        key,
        json.dumps(sorted(block_ids)),
        ex=BLOCK_IDS_CACHE_TTL_SECONDS,
    )
    return block_ids