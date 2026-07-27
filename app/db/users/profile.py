"""Database user profiles CRUD persistence layer.

Provides profile fetch, upsert, branch/campus name encryption, and change logs seeding.
"""

import logging
from datetime import datetime, timezone
from typing import Any, cast

from fastapi import HTTPException, status
from postgrest.exceptions import APIError

from app.core.crypto import compute_blind_index, encrypt_to_hex
from app.db.client import supabase_client

logger = logging.getLogger(__name__)


def fetch_profile(user_id: str) -> dict[str, Any] | None:
    """Executes fetch profile operation.

        Args:
            user_id: Unique UUID string of the authenticated user.

        Returns:
            dict[str, Any] | None: Response payload or result."""
    try:
        result = (
            supabase_client.table("profiles")
            .select(
                "id, name, campus_branch, campus_year, campus_name, "
                "age, created_at, updated_at",
            )
            .eq("id", user_id)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to fetch profile", extra={"user_id": user_id})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Profile service temporarily unavailable.",
        ) from e

    data = result.data
    if not data:
        return None

    row = data[0]
    if not isinstance(row, dict):
        return None

    return cast(dict[str, Any], row)


def upsert_profile_variant(  # noqa: C901
    user_id: str,
    name: str,
    campus_branch: str | None,
    campus_year: int | None,
    age: int,
    campus_name: str | None = None,
    demographic_bucket: str | None = None,
) -> tuple[dict[str, Any], bool]:
    """Upsert a profile row with variant-specific columns."""
    existing = fetch_profile(user_id)
    profile_created = existing is None

    encrypted_branch = encrypt_to_hex(campus_branch.strip()) if campus_branch else None
    branch_blind = compute_blind_index(campus_branch) if campus_branch else None
    encrypted_campus_name = encrypt_to_hex(campus_name.strip()) if campus_name else None
    now_iso = datetime.now(timezone.utc).isoformat()

    upsert_payload: dict[str, Any] = {
        "id": user_id,
        "name": name.strip(),
        "campus_branch": encrypted_branch,
        "campus_branch_blind_index": branch_blind,
        "campus_year": campus_year,
        "campus_name": encrypted_campus_name,
        "age": age,
        "updated_at": now_iso,
    }
    if demographic_bucket is not None:
        upsert_payload["search_bucket"] = demographic_bucket
    if profile_created:
        # Onboarding's initial name/age counts as "change #1" for the
        # twice-a-year rolling rate limits on both fields - see
        # 20260728000000_profile_identity_change_limits.sql and
        # 20260730000000_age_change_rolling_log.sql.
        upsert_payload["age_updated_at"] = now_iso

    try:
        result = (
            supabase_client.table("profiles")
            .upsert(upsert_payload, on_conflict="id")
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to upsert profile variant", extra={"user_id": user_id})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to save profile.",
        ) from e

    row = None
    if result.data:
        maybe_row = result.data[0]
        if isinstance(maybe_row, dict):
            row = maybe_row

    if not isinstance(row, dict):
        row = fetch_profile(user_id)

    if not isinstance(row, dict):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Profile save returned no row.",
        )

    if profile_created:
        try:
            supabase_client.table("profile_name_change_log").insert(
                {"user_id": user_id, "changed_at": now_iso},
            ).execute()
        except APIError:
            logger.warning(
                "Failed to seed initial name-change marker; onboarding proceeds",
                extra={"user_id": user_id},
            )
        try:
            supabase_client.table("profile_age_change_log").insert(
                {"user_id": user_id, "changed_at": now_iso},
            ).execute()
        except APIError:
            logger.warning(
                "Failed to seed initial age-change marker; onboarding proceeds",
                extra={"user_id": user_id},
            )

    return cast(dict[str, Any], row), profile_created
