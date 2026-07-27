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
    """Inserts a match record when a mutual like-back action occurs.

    Args:
        liker_id: User ID executing the like-back.
        liked_back_id: Original liker user ID.
        tab: Active discovery tab ("Dating", "BFF", "Networking").

    Returns:
        str: Created match record ID string.
    """

    try:
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
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            raise DatabaseAccessError("Match insert returned no row")
        return str(cast(dict[str, Any], rows[0])["id"])
    except APIError as e:
        logger.exception(
            "Failed to record match",
            extra={"liker_id": liker_id, "liked_back_id": liked_back_id, "tab": tab},
        )
        raise DatabaseAccessError("Failed to record match") from e


def fetch_matches_for_user(user_id: str, tab: str = "Dating") -> list[dict[str, Any]]:
    """
    Return active match rows for user_id.
    Each row includes match_id, matched_user_id (the counterpart), and created_at.
    """
    user_id = str(uuid.UUID(user_id)).lower()
    try:
        res = (
            supabase_client.table("matches")
            .select("id, liker_id, liked_back_id, created_at")
            .or_(f"liker_id.eq.{user_id},liked_back_id.eq.{user_id}")
            .eq("tab", tab)
            .is_("unmatched_at", "null")
            .order("created_at", desc=True)
            .limit(1000)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        result: list[dict[str, Any]] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            row_dict = cast(dict[str, Any], row)
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


def set_match_unmatched(user_id: str, target_id: str, tab: str = "Dating") -> None:
    """Mark the match between user_id and target_id as dissolved."""
    user_id = str(uuid.UUID(user_id)).lower()
    target_id = str(uuid.UUID(target_id)).lower()
    now = utcnow()
    try:
        (
            supabase_client.table("matches")
            .update({"unmatched_at": now.isoformat(), "unmatched_by": user_id})
            .or_(
                f"and(liker_id.eq.{user_id},liked_back_id.eq.{target_id}),"
                f"and(liker_id.eq.{target_id},liked_back_id.eq.{user_id})",
            )
            .eq("tab", tab)
            .is_("unmatched_at", "null")
            .execute()
        )
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
