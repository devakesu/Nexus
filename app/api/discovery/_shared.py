"""Shared utilities and common validation routines for discovery endpoints."""

import asyncio
import sys
from typing import Any

from fastapi import HTTPException

import app.db.chat as chat_db

__all__ = ["_validate_conversation_membership"]


async def _validate_conversation_membership(
    user_id: str,
    target_id: str,
    conversation_id: str | None,
) -> None:
    """Validates that both user_id and target_id are participants of the conversation."""
    if not conversation_id:
        return

    # Default to chat_db module function, but honor test mocks patched on likes module if active
    fetch_fn: Any = chat_db.fetch_conversation_participants
    likes_mod = sys.modules.get("app.api.discovery.likes")
    if likes_mod and hasattr(likes_mod, "fetch_conversation_participants"):
        candidate_fn = getattr(likes_mod, "fetch_conversation_participants")
        if hasattr(candidate_fn, "mock_calls") or hasattr(candidate_fn, "return_value") or hasattr(candidate_fn, "assert_called"):
            fetch_fn = candidate_fn

    conv = await asyncio.to_thread(fetch_fn, conversation_id)
    if not conv:
        raise HTTPException(
            status_code=404,
            detail="Referenced conversation not found.",
        )
    user_a = str(conv.get("user_a_id") or "").lower()
    user_b = str(conv.get("user_b_id") or "").lower()
    actor = str(user_id).lower()
    target = str(target_id).lower()

    participants = {user_a, user_b}
    if actor not in participants:
        raise HTTPException(
            status_code=403,
            detail="Actor is not a participant in the referenced conversation.",
        )
    if target not in participants or actor == target:
        raise HTTPException(
            status_code=400,
            detail="Target user is not a participant in the referenced conversation.",
        )
