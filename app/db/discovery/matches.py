"""Database mutual match and unmatch persistence layer.

Handles recording mutual matches, creating conversation references, and processing unmatch actions
with cooldown period exclusions.
"""

import logging
import uuid
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import DiscoveryTab
from app.db.client import DatabaseAccessError, supabase_client, utcnow
from app.db.discovery import record_discovery_action

logger = logging.getLogger(__name__)

_UNMATCH_PASS_DAYS = 14  # 2 weeks - both users are hidden from each other's orbit


def record_match(
    liker_id: str,
    liked_back_id: str,
    tab: DiscoveryTab = "Dating",
) -> str:
    """Inserts a match record when a mutual like-back action occurs, returning
    the existing match ID if already matched concurrently.

    Args:
        liker_id: User ID executing the like-back.
        liked_back_id: Original liker user ID.
        tab: Active discovery tab ("Dating", "Friends", "Professional").

    Returns:
        str: Match record ID string.
    """
    liker_id = str(uuid.UUID(liker_id)).lower()
    liked_back_id = str(uuid.UUID(liked_back_id)).lower()

    try:
        # Check if an active match already exists between the pair in either direction
        existing = (
            supabase_client.table("matches")
            .select("id")
            .or_(
                f"and(liker_id.eq.{liker_id},liked_back_id.eq.{liked_back_id}),"
                f"and(liker_id.eq.{liked_back_id},liked_back_id.eq.{liker_id})",
            )
            .eq("tab", tab)
            .is_("unmatched_at", "null")
            .limit(1)
            .execute()
        )
        existing_rows = cast(list[dict[str, Any]], existing.data or [])
        if existing_rows and existing_rows[0].get("id"):
            return str(existing_rows[0]["id"])

        res = (
            supabase_client.table("matches")
            .upsert(
                {
                    "liker_id": liker_id,
                    "liked_back_id": liked_back_id,
                    "tab": tab,
                },
                on_conflict="liker_id, liked_back_id, tab",
            )
            .execute()
        )
        rows = cast(list[dict[str, Any]], res.data or [])
        if rows and rows[0].get("id"):
            return str(rows[0]["id"])

        raise DatabaseAccessError("Match insert returned no row")
    except APIError as e:
        # If symmetric constraint or duplicate constraint violated by concurrent insert, return winning match
        if getattr(e, "code", None) == "23505":
            try:
                existing_win = (
                    supabase_client.table("matches")
                    .select("id")
                    .or_(
                        f"and(liker_id.eq.{liker_id},liked_back_id.eq.{liked_back_id}),"
                        f"and(liker_id.eq.{liked_back_id},liked_back_id.eq.{liker_id})",
                    )
                    .eq("tab", tab)
                    .is_("unmatched_at", "null")
                    .limit(1)
                    .execute()
                )
                win_rows = cast(list[dict[str, Any]], existing_win.data or [])
                if win_rows and win_rows[0].get("id"):
                    return str(win_rows[0]["id"])
            except Exception:
                pass
        logger.exception(
            "Failed to record match",
            extra={"liker_id": liker_id, "liked_back_id": liked_back_id, "tab": tab},
        )
        raise DatabaseAccessError("Failed to record match") from e


def fetch_matches_for_user(
    user_id: str,
    tab: str = "Dating",
    limit: int = 1000,
    before_created_at: str | None = None,
) -> list[dict[str, Any]]:
    """Return active match rows for user_id.
    Each row includes match_id, matched_user_id (the counterpart), and created_at.

    Args:
        user_id: Target user UUID string.
        tab: Active discovery tab category ('Dating', 'Friends', 'Professional').
        limit: Maximum number of rows to retrieve (default 1000).
        before_created_at: Optional ISO timestamp cursor for keyset pagination.

    Returns:
        list[dict[str, Any]]: List of match dictionaries.
    """
    user_id = str(uuid.UUID(user_id)).lower()
    try:
        query = (
            supabase_client.table("matches")
            .select("id, liker_id, liked_back_id, created_at")
            .or_(f"liker_id.eq.{user_id},liked_back_id.eq.{user_id}")
            .eq("tab", tab)
            .is_("unmatched_at", "null")
            .order("created_at", desc=True)
        )
        if before_created_at:
            query = query.lt("created_at", before_created_at)

        res = query.limit(limit).execute()
        rows = cast(list[dict[str, Any]], res.data or [])

        if len(rows) == limit:
            logger.warning(
                "fetch_matches_for_user reached fetch limit of %d matches for user %s on tab %s",
                limit,
                user_id,
                tab,
                extra={"user_id": user_id, "tab": tab, "limit": limit},
            )

        result: list[dict[str, Any]] = []
        for row_dict in rows:
            liker_id = str(row_dict.get("liker_id") or "")
            liked_back_id = str(row_dict.get("liked_back_id") or "")
            counterpart_id = liked_back_id if liker_id == user_id else liker_id
            result.append(
                {
                    "match_id": str(row_dict.get("id") or ""),
                    "matched_user_id": counterpart_id,
                    "created_at": row_dict.get("created_at"),
                },
            )
        return result
    except APIError as e:
        logger.exception(
            "Failed to fetch matches",
            extra={"user_id": user_id, "tab": tab},
        )
        raise DatabaseAccessError("Failed to fetch matches") from e


def set_match_unmatched(
    user_id: str,
    target_id: str,
    tab: DiscoveryTab | str | None = None,
) -> None:
    """Mark the match between user_id and target_id as dissolved.
    If tab is None, dissolves active matches across all tabs between the two users.
    """
    user_id = str(uuid.UUID(user_id)).lower()
    target_id = str(uuid.UUID(target_id)).lower()
    now = utcnow()
    try:
        q = (
            supabase_client.table("matches")
            .update({"unmatched_at": now.isoformat(), "unmatched_by": user_id})
            .or_(
                f"and(liker_id.eq.{user_id},liked_back_id.eq.{target_id}),"
                f"and(liker_id.eq.{target_id},liked_back_id.eq.{user_id})",
            )
            .is_("unmatched_at", "null")
        )
        if tab is not None:
            q = q.eq("tab", str(tab))
        q.execute()
    except APIError as e:
        logger.exception(
            "Failed to set match unmatched",
            extra={"user_id": user_id, "target_id": target_id},
        )
        raise DatabaseAccessError("Failed to set match unmatched") from e


def record_mutual_pass(user_a: str, user_b: str, tab: DiscoveryTab, days: int) -> None:
    """Record a pass in both directions so neither user appears in the other's orbit."""
    record_discovery_action(user_a, user_b, "pass", tab, days)
    record_discovery_action(user_b, user_a, "pass", tab, days)
