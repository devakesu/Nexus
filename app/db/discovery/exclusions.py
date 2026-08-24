import asyncio
import contextlib
import json
import logging
from datetime import datetime, timedelta
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import DiscoveryTab
from app.core.infra.cache import get_block_ids_cache_ttl, redis_client
from app.db.client import (
    DatabaseAccessError,
    normalize_uuid,
    parse_utc_datetime,
    supabase_client,
    utcnow,
)

logger = logging.getLogger(__name__)

_PASS_EXPIRY_DAYS = 14


def _block_ids_cache_key(viewer_id: str) -> str:
    """Formats Redis key string for cached block ID sets.

    Args:
        viewer_id: User ID of viewer.

    Returns:
        str: Redis cache key string.
    """
    return f"discovery:block_ids:{viewer_id}"



async def get_cached_active_block_ids(viewer_id: str) -> set[str]:
    """Executes get cached active block ids operation.

        Args:
            viewer_id: Input viewer id parameter.

        Returns:
            set[str]: Response payload or result."""
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
        ex=get_block_ids_cache_ttl(),
    )
    return block_ids


def _collect_blocked_counterparty_ids(rows: object, viewer_id: str) -> set[str]:
    """Collect blocked counterparty ids.

        Args:
            rows: Input rows parameter.
            viewer_id: Input viewer id parameter.

        Returns:
            set[str]: Response payload or result."""
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
    """Check pass expiry.

        Args:
            expires_at_raw: Input expires at raw parameter.
            target_id: Input target id parameter.
            now: Input now parameter.
            excluded: Input excluded parameter."""
    if expires_at_raw and isinstance(expires_at_raw, str):
        with contextlib.suppress(Exception):
            expires_at = parse_utc_datetime(expires_at_raw)
            if expires_at > now:
                excluded.add(target_id)


def _process_exclusion_row(
    row: dict[str, Any],
    viewer_id: str,
    active_tab: DiscoveryTab,
    now: datetime,
    excluded: set[str],
) -> None:
    """Process exclusion row.

        Args:
            row: Input row parameter.
            viewer_id: Input viewer id parameter.
            active_tab: Active discovery tab category ('Dating', 'BFF', or 'Networking').
            now: Input now parameter.
            excluded: Input excluded parameter."""
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
    viewer_id = normalize_uuid(viewer_id)
    excluded: set[str] = set()
    now = utcnow()

    try:
        # nosec: viewer_id validated via normalize_uuid
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

        # Exclude users with active matches in this orbit
        # nosec: viewer_id validated via normalize_uuid
        matches_res = (
            supabase_client.table("matches")
            .select("liker_id, liked_back_id")
            .or_(f"liker_id.eq.{viewer_id},liked_back_id.eq.{viewer_id}")
            .eq("tab", active_tab)
            .is_("unmatched_at", "null")
            .execute()
        )
        for row_raw in cast(list[Any], matches_res.data or []):
            if isinstance(row_raw, dict):
                row_dict = cast(dict[str, Any], row_raw)
                liker = str(row_dict.get("liker_id") or "")
                liked_back = str(row_dict.get("liked_back_id") or "")
                counterpart = liked_back if liker == viewer_id else liker
                if counterpart:
                    excluded.add(counterpart)

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
    viewer_id = normalize_uuid(viewer_id)
    try:
        # nosec: viewer_id validated via normalize_uuid
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


def has_active_discovery_action(
    actor_id: str,
    target_id: str,
    action: str,
    tab: DiscoveryTab | None = None,
) -> bool:
    """
    Check if there is an active, un-revoked discovery action of a specific type
    from actor_id targeting target_id.
    """
    try:
        actor_id = normalize_uuid(actor_id)
        target_id = normalize_uuid(target_id)

        q = (
            supabase_client.table("profile_discovery_actions")
            .select("id")
            .eq("actor_id", actor_id)
            .eq("target_id", target_id)
            .eq("action", action)
            .is_("revoked_at", "null")
        )
        if tab is not None:
            q = q.eq("tab", tab)

        res = q.limit(1).execute()
        return bool(res.data)
    except Exception:
        logger.exception(
            "Error checking active discovery action status",
            extra={
                "actor_id": actor_id,
                "target_id": target_id,
                "action": action,
                "tab": tab,
            },
        )
        return False


def record_discovery_action(
    actor_id: str,
    target_id: str,
    action: str,
    tab: DiscoveryTab | None = None,
    expires_days: int | None = None,
) -> None:
    """Executes record discovery action operation.

        Args:
            actor_id: Input actor id parameter.
            target_id: Input target id parameter.
            action: Input action parameter.
            tab: Discovery category tab ('Dating', 'BFF', or 'Networking').
            expires_days: Input expires days parameter."""
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
                days = expires_days if expires_days is not None else _PASS_EXPIRY_DAYS
                payload["expires_at"] = (now + timedelta(days=days)).isoformat()

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


def record_user_report(
    reporter_id: str,
    target_id: str,
    reason: str,
    reason_detail: str | None = None,
    tab: DiscoveryTab | None = None,
    conversation_id: str | None = None,
    evidence: list[dict[str, Any]] | None = None,
) -> None:
    """
    Insert a user report row and ensure a mutual block exists.
    The block is created silently if one already exists (idempotent).
    """
    report_id: str | None = None
    try:
        report_payload: dict[str, Any] = {
            "reporter_id": reporter_id,
            "target_id": target_id,
            "reason": reason,
        }
        if reason_detail:
            report_payload["reason_detail"] = reason_detail.strip()
        if tab is not None:
            report_payload["tab"] = tab

        metadata: dict[str, Any] = {}
        if conversation_id:
            metadata["conversation_id"] = conversation_id
        if evidence:
            metadata["chat_evidence"] = evidence
        if metadata:
            report_payload["metadata"] = metadata

        res = (
            supabase_client.table("user_reports")
            .insert(report_payload)
            .select("id")
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if rows and isinstance(rows[0], dict):
            report_id = str(cast(dict[str, Any], rows[0]).get("id") or "")
    except APIError as e:
        if getattr(e, "code", None) == "23505":
            logger.info(
                "Duplicate pending report ignored (idempotent no-op)",
                extra={"reporter_id": reporter_id, "target_id": target_id},
            )
            return
        logger.exception(
            "Failed to insert user report",
            extra={"reporter_id": reporter_id, "target_id": target_id},
        )
        raise DatabaseAccessError("Failed to insert user report") from e

    # Ensure the reporter is blocked from seeing the target (and vice versa).
    # Store report provenance in metadata for admin traceability.
    # Upsert to ensure any pre-existing or revoked block is restored to active.
    block_metadata: dict[str, Any] = {"source": "report", "report_reason": reason}
    if report_id:
        block_metadata["report_id"] = report_id

    try:
        supabase_client.table("profile_discovery_actions").upsert(
            {
                "actor_id": reporter_id,
                "target_id": target_id,
                "action": "block",
                "revoked_at": None,
                "metadata": block_metadata,
            },
            on_conflict="actor_id,target_id,action",
        ).execute()
    except Exception:
        logger.exception(
            "Failed to upsert auto-block for report",
            extra={"reporter_id": reporter_id, "target_id": target_id},
        )


def fetch_expired_pass_candidates(
    viewer_id: str,
    active_tab: DiscoveryTab,
) -> dict[str, datetime]:
    """
    Return {candidate_id: expires_at} for passes that have expired.
    Used to apply a time-graduated score penalty after the exclusion window ends.

    Penalty schedule (days since expiry):
      ≤ 7 days  → heavy   (0.25x)
      ≤ 30 days → moderate (0.50x)
      > 30 days → light   (0.85x)
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
                expires_at = parse_utc_datetime(expires_at_raw)
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
    """Invalidates block redis caches and active discovery sessions for both users.

    Args:
        viewer_id: Input viewer id parameter.
        target_id: Input target id parameter.
    """
    try:
        await redis_client.delete(f"discovery:block_ids:{viewer_id}")
        await redis_client.delete(f"discovery:block_ids:{target_id}")
    except Exception:
        logger.exception("Failed to invalidate block cache")

    try:
        from app.db.sessions.auth_sessions import invalidate_viewer_discovery_sessions

        await asyncio.to_thread(invalidate_viewer_discovery_sessions, viewer_id)
        await asyncio.to_thread(invalidate_viewer_discovery_sessions, target_id)
    except Exception:
        logger.exception("Failed to invalidate discovery sessions on block")


def fetch_likes_for_user(
    viewer_id: str,
    tab: str = "Dating",
) -> list[dict[str, Any]]:
    """
    Return like/superlike rows targeting viewer_id in the given tab.
    Unseen rows (seen_at IS NULL) sort first; within each group newest first.
    """
    try:
        res = (
            supabase_client.table("profile_discovery_actions")
            .select("actor_id, action, created_at, seen_at, actor:profiles!actor_id(is_deactivated)")
            .eq("target_id", viewer_id)
            .eq("tab", tab)
            .in_("action", ["like", "superlike"])
            .is_("revoked_at", "null")
            .eq("actor.is_deactivated", False)
            .order("created_at", desc=True)
            .limit(1000)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        return [cast(dict[str, Any], r) for r in rows if isinstance(r, dict)]
    except APIError as e:
        logger.exception(
            "Failed to fetch likes for user",
            extra={"viewer_id": viewer_id, "tab": tab},
        )
        raise DatabaseAccessError("Failed to fetch likes") from e


def mark_likes_seen(
    viewer_id: str,
    actor_ids: list[str] | None = None,
    tab: str | None = None,
) -> None:
    """
    Stamp seen_at on unseen likes for viewer_id.
    Pass actor_ids to mark only specific senders; omit (None) to mark all.
    Optionally filter by discovery tab.
    """
    now = utcnow()
    try:
        q = (
            supabase_client.table("profile_discovery_actions")
            .update({"seen_at": now.isoformat()})
            .eq("target_id", viewer_id)
            .in_("action", ["like", "superlike"])
            .is_("revoked_at", "null")
            .is_("seen_at", "null")
        )
        if actor_ids:
            q = q.in_("actor_id", actor_ids)
        if tab:
            q = q.eq("tab", tab)
        q.execute()
    except APIError as e:
        logger.exception(
            "Failed to mark likes as seen",
            extra={"viewer_id": viewer_id},
        )
        raise DatabaseAccessError("Failed to mark likes as seen") from e


def revoke_incoming_like(viewer_id: str, actor_id: str) -> bool:
    """
    Revoke actor_id's like/superlike targeting viewer_id (clears it from the inbox).
    """
    now = utcnow()
    try:
        res = (
            supabase_client.table("profile_discovery_actions")
            .update({"revoked_at": now.isoformat()})
            .eq("actor_id", actor_id)
            .eq("target_id", viewer_id)
            .in_("action", ["like", "superlike"])
            .is_("revoked_at", "null")
            .execute()
        )
        return bool(res.data)
    except APIError as e:
        logger.exception(
            "Failed to revoke incoming like",
            extra={"viewer_id": viewer_id, "actor_id": actor_id},
        )
        raise DatabaseAccessError("Failed to revoke incoming like") from e


def unrevoke_incoming_like(viewer_id: str, actor_id: str) -> None:
    """Restores revoked_at to null if subsequent match creation fails."""
    try:
        supabase_client.table("profile_discovery_actions").update(
            {"revoked_at": None},
        ).eq("actor_id", actor_id).eq("target_id", viewer_id).in_(
            "action", ["like", "superlike"],
        ).execute()
    except Exception:
        logger.exception(
            "Failed to restore incoming like",
            extra={"viewer_id": viewer_id, "actor_id": actor_id},
        )


def fetch_active_like_action(
    actor_id: str,
    target_id: str,
) -> dict[str, Any] | None:
    """Fetches an active, unrevoked like or superlike action between actor and target."""
    try:
        valid_actor_id = normalize_uuid(actor_id)
    except Exception:
        valid_actor_id = str(actor_id)
    try:
        valid_target_id = normalize_uuid(target_id)
    except Exception:
        valid_target_id = str(target_id)

    try:
        res = (
            supabase_client.table("profile_discovery_actions")
            .select("id, tab, action, actor_id, target_id, created_at, revoked_at")
            .eq("actor_id", valid_actor_id)
            .eq("target_id", valid_target_id)
            .in_("action", ["like", "superlike"])
            .is_("revoked_at", "null")
            .limit(1)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        return cast(dict[str, Any], rows[0]) if (rows and isinstance(rows[0], dict)) else None
    except APIError as e:
        logger.exception(
            "Failed to fetch active like action",
            extra={"actor_id": valid_actor_id, "target_id": valid_target_id},
        )
        raise DatabaseAccessError("Failed to fetch active like action") from e

