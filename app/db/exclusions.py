import json
import logging
from datetime import datetime, timedelta
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.cache import BLOCK_IDS_CACHE_TTL_SECONDS, redis_client
from app.core.config import DiscoveryTab
from app.db.client import DatabaseAccessError, supabase_client, utcnow

logger = logging.getLogger(__name__)

_PASS_EXPIRY_DAYS = 14


def _block_ids_cache_key(viewer_id: str) -> str:
    return f"discovery:block_ids:{viewer_id}"


async def get_cached_active_block_ids(viewer_id: str) -> set[str]:
    key = _block_ids_cache_key(viewer_id)

    cached = await redis_client.get(key)
    if cached:
        try:
            decoded = json.loads(cached)
            if isinstance(decoded, list):
                list_items = cast(list[object], decoded)
                return {str(x) for x in list_items if x}
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

    row_list = cast(list[object], rows)
    for row in row_list:
        if not isinstance(row, dict):
            continue

        row_dict = cast(dict[str, Any], row)
        actor_id = row_dict.get("actor_id")
        target_id = row_dict.get("target_id")

        if actor_id == viewer_id and target_id:
            excluded.add(str(target_id))
        elif target_id == viewer_id and actor_id:
            excluded.add(str(actor_id))

    return excluded


def _check_pass_expiry(
    expires_at_raw: Any,
    target_id: str,
    now: datetime,
    excluded: set[str],
) -> None:
    if expires_at_raw and isinstance(expires_at_raw, str):
        try:
            expires_at = datetime.fromisoformat(
                expires_at_raw.replace("Z", "+00:00"),
            )
            if expires_at > now:
                excluded.add(target_id)
        except ValueError:
            pass


def _process_exclusion_row(
    row: dict[str, Any],
    viewer_id: str,
    active_tab: DiscoveryTab,
    now: datetime,
    excluded: set[str],
) -> None:
    action = row.get("action")
    actor_id = row.get("actor_id")
    target_id = row.get("target_id")
    tab = row.get("tab")

    if not actor_id or not target_id:
        return

    actor_id_str = str(actor_id)
    target_id_str = str(target_id)

    if action == "block":
        if actor_id_str == viewer_id:
            excluded.add(target_id_str)
        elif target_id_str == viewer_id:
            excluded.add(actor_id_str)
        return

    if actor_id_str != viewer_id or tab != active_tab:
        return

    if action in ("hide", "like", "superlike"):
        excluded.add(target_id_str)
    elif action == "pass":
        _check_pass_expiry(row.get("expires_at"), target_id_str, now, excluded)


def fetch_active_discovery_excluded_ids(
    viewer_id: str,
    active_tab: DiscoveryTab,
) -> set[str]:
    """
    Return candidate ids that must be excluded from discovery for this viewer.

    Active exclusions:
    - block: both directions, global
    - hide: actor -> target for this tab
    - pass: actor -> target for this tab while not yet expired
    - like/superlike: actor -> target for this tab
    """
    excluded: set[str] = set()
    now = utcnow()

    try:
        res = (
            supabase_client.table("profile_discovery_actions")
            .select("actor_id, target_id, action, tab, expires_at")
            .is_("revoked_at", "null")
            .or_(
                f"and(actor_id.eq.{viewer_id},action.in.(block,hide,like,superlike,pass)),"
                f"and(target_id.eq.{viewer_id},action.eq.block)",
            )
            .execute()
        )

        rows = cast(list[Any], res.data or [])
        for row_raw in rows:
            if isinstance(row_raw, dict):
                row_dict = cast(dict[str, Any], row_raw)
                _process_exclusion_row(row_dict, viewer_id, active_tab, now, excluded)
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
        raise DatabaseAccessError(
            "Unexpected active discovery exclusion failure",
        ) from e


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


def record_discovery_action(
    actor_id: str,
    target_id: str,
    action: str,
    tab: DiscoveryTab | None = None,
) -> None:
    now = utcnow()
    is_reversal = action.startswith("un")
    base_action = action[2:] if is_reversal else action

    try:
        if is_reversal:
            q = (
                supabase_client.table("profile_discovery_actions")
                .update({"revoked_at": now.isoformat()})
                .eq("actor_id", actor_id)
                .eq("target_id", target_id)
                .eq("action", base_action)
                .is_("revoked_at", "null")
            )
            if tab is not None:
                q = q.eq("tab", tab)
            q.execute()
        else:
            payload: dict[str, Any] = {
                "actor_id": actor_id,
                "target_id": target_id,
                "action": base_action,
            }
            if tab is not None:
                payload["tab"] = tab

            if base_action == "pass":
                payload["expires_at"] = (
                    now + timedelta(days=_PASS_EXPIRY_DAYS)
                ).isoformat()

            supabase_client.table("profile_discovery_actions").insert(payload).execute()

    except APIError as e:
        logger.exception(
            "Failed to record discovery action",
            extra={
                "actor_id": actor_id,
                "target_id": target_id,
                "action": action,
                "tab": tab,
            },
        )
        raise DatabaseAccessError("Failed to record discovery action") from e


def fetch_expired_pass_candidates(
    viewer_id: str,
    active_tab: DiscoveryTab,
) -> dict[str, datetime]:
    """
    Return {candidate_id: expires_at} for passes that have expired.
    Used to apply a time-graduated score penalty after the exclusion window ends.

    Penalty schedule (days since expiry):
      ≤ 7 days  → heavy   (0.25×)
      ≤ 30 days → moderate (0.50×)
      > 30 days → light   (0.85×)
    """
    now = utcnow()
    try:
        res = (
            supabase_client.table("profile_discovery_actions")
            .select("target_id, expires_at")
            .eq("actor_id", viewer_id)
            .eq("action", "pass")
            .eq("tab", active_tab)
            .is_("revoked_at", "null")
            .not_.is_("expires_at", "null")
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        result: dict[str, datetime] = {}
        for r in rows:
            if not isinstance(r, dict):
                continue
            row_dict = cast(dict[str, Any], r)
            target_id = cast(object, row_dict.get("target_id"))
            expires_at_raw = cast(object, row_dict.get("expires_at"))
            if not target_id or not isinstance(expires_at_raw, str):
                continue
            try:
                expires_at = datetime.fromisoformat(
                    expires_at_raw.replace("Z", "+00:00"),
                )
            except ValueError:
                continue
            # Only include rows where the pass has actually expired
            if expires_at <= now:
                result[str(target_id)] = expires_at
        return result
    except Exception:
        logger.exception(
            "Failed to fetch expired pass candidates",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        return {}


async def invalidate_block_cache(viewer_id: str, target_id: str) -> None:
    try:
        await redis_client.delete(f"discovery:block_ids:{viewer_id}")
        await redis_client.delete(f"discovery:block_ids:{target_id}")
    except Exception:
        logger.exception("Failed to invalidate block cache")
