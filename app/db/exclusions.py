import json
import logging

from postgrest.exceptions import APIError
from app.core.cache import BLOCK_IDS_CACHE_TTL_SECONDS
from app.core.config import DiscoveryTab
from app.db.client import supabase_client, DatabaseAccessError, utcnow
from app.core.cache import redis_client

logger = logging.getLogger(__name__)

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



def _collect_blocked_counterparty_ids(rows: object, viewer_id: str) -> set[str]:
    excluded: set[str] = set()

    if not isinstance(rows, list):
        return excluded

    for row in rows:
        if not isinstance(row, dict):
            continue

        actor_id = row.get("actor_id")
        target_id = row.get("target_id")

        if actor_id == viewer_id and target_id:
            excluded.add(str(target_id))
        elif target_id == viewer_id and actor_id:
            excluded.add(str(actor_id))

    return excluded


def _collect_target_ids(rows: object) -> set[str]:
    target_ids: set[str] = set()

    if not isinstance(rows, list):
        return target_ids

    for row in rows:
        if isinstance(row, dict) and row.get("target_id"):
            target_ids.add(str(row["target_id"]))

    return target_ids


def fetch_active_discovery_excluded_ids(
    viewer_id: str,
    active_tab: DiscoveryTab,
) -> set[str]:
    """
    Return candidate ids that must be excluded from discovery for this viewer.

    Active exclusions:
    - block: both directions, global
    - hide: actor -> target for this tab
    - pass: actor -> target for this tab while not expired
    - optionally like/superlike depending on product policy
    """
    excluded: set[str] = set()
    now_iso = utcnow().isoformat()

    try:
        block_res = (
            supabase_client.table("profile_discovery_actions")
            .select("actor_id, target_id")
            .eq("action", "block")
            .is_("revoked_at", "null")
            .or_(f"actor_id.eq.{viewer_id},target_id.eq.{viewer_id}")
            .execute()
        )
        excluded.update(_collect_blocked_counterparty_ids(block_res.data, viewer_id))

        hide_res = (
            supabase_client.table("profile_discovery_actions")
            .select("target_id")
            .eq("actor_id", viewer_id)
            .eq("tab", active_tab)
            .eq("action", "hide")
            .is_("revoked_at", "null")
            .execute()
        )
        excluded.update(_collect_target_ids(hide_res.data))

        engagement_res = (
            supabase_client.table("profile_discovery_actions")
            .select("target_id")
            .eq("actor_id", viewer_id)
            .eq("tab", active_tab)
            .in_("action", ["like", "superlike"])
            .is_("revoked_at", "null")
            .execute()
        )
        excluded.update(_collect_target_ids(engagement_res.data))

        pass_res = (
            supabase_client.table("profile_discovery_actions")
            .select("target_id")
            .eq("actor_id", viewer_id)
            .eq("tab", active_tab)
            .eq("action", "pass")
            .is_("revoked_at", "null")
            .gt("expires_at", now_iso)
            .execute()
        )
        excluded.update(_collect_target_ids(pass_res.data))

        return excluded

    except APIError as e:
        logger.exception(
            "Failed to fetch active discovery exclusions",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError("Failed to fetch active discovery exclusions") from e
    except Exception as e:
        logger.exception(
            "Unexpected active discovery exclusion failure",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError("Unexpected active discovery exclusion failure") from e


def fetch_active_block_ids(viewer_id: str) -> set[str]:
    """
    Return ids of users with an active block in either direction.
    Used for lightweight re-check at snapshot page read time.
    """
    try:
        res = (
            supabase_client.table("profile_discovery_actions")
            .select("actor_id, target_id")
            .eq("action", "block")
            .is_("revoked_at", "null")
            .or_(f"actor_id.eq.{viewer_id},target_id.eq.{viewer_id}")
            .execute()
        )

        return _collect_blocked_counterparty_ids(res.data, viewer_id)

    except APIError as e:
        logger.exception(
            "Failed to fetch active block ids",
            extra={"viewer_id": viewer_id},
        )
        raise DatabaseAccessError("Failed to fetch active block ids") from e
    except Exception as e:
        logger.exception(
            "Unexpected block id fetch failure",
            extra={"viewer_id": viewer_id},
        )
        raise DatabaseAccessError("Unexpected block id fetch failure") from e
