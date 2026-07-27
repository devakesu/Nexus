"""Cross-flavor data import and export handshakes persistence layer.

Handles sync code generation, validation, profile retrieval by code, and field copying
from flavor variant source profiles to the main Nexus target profile.
"""

import logging
import secrets
import string
from datetime import datetime, timedelta, timezone
from typing import Any, cast

from fastapi import HTTPException, status
from postgrest.exceptions import APIError

from app.core.cache import redis_client
from app.db.client import parse_utc_datetime, supabase_client
from app.db.users.auth import fetch_public_user

logger = logging.getLogger(__name__)

_SYNC_CODE_CHARS = (
    string.ascii_uppercase.replace("O", "").replace("I", "")
    + string.digits.replace("0", "").replace("1", "")
)
_SYNC_CODE_LENGTH = 6
_SYNC_CODE_TTL_MINUTES = 15

# Fields copied during import (all backend-encrypted BYTEA fields).
_IMPORTABLE_FIELDS = [
    "display_gender",
    "display_sexuality",
    "pronouns",
    "hometown",
    "current_place",
    "partner_values",
    "children_plans",
    "religious_beliefs",
    "lifestyle",
    "drinking",
    "smoking",
    "role_at",
    "looking_for",
    "activities",
    "causes_supported",
    "top_artists",
    "tech_skills",
    "languages",
    "ai_vibe_tags",
    "pets",
    "interests",
    "sub_interests",
    "value_dimensions",
    "search_bucket",
    "dating_target_buckets",
    "friends_target_buckets",
    "professional_target_buckets",
    "campus_branch_blind_index",
    "smoking_blind_index",
    "drinking_blind_index",
    "children_plans_blind_index",
    "religious_beliefs_blind_index",
]


async def generate_export_code(user_id: str) -> tuple[str, datetime]:
    """
    Generate and store a one-time 6-char alphanumeric export code for the
    given profile (must be a flavor-variant user).

    The code is valid for 15 minutes. Any previous code is silently overwritten.
    Returns (code, expires_at).
    """
    try:
        # Fetch the old code if any to clean up Redis attempts tracker
        res = (
            supabase_client.table("profiles")
            .select("import_sync_code")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        old_code = None
        if res and isinstance(res.data, dict):
            old_code = res.data.get("import_sync_code")
        if isinstance(old_code, str) and old_code:
            await redis_client.delete(f"import:code_attempts:{old_code}")
    except Exception:
        logger.exception("Failed to clean up old export code attempts in Redis")

    code = "".join(secrets.choice(_SYNC_CODE_CHARS) for _ in range(_SYNC_CODE_LENGTH))
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=_SYNC_CODE_TTL_MINUTES)

    try:
        supabase_client.table("profiles").update(
            {
                "import_sync_code": code,
                "import_sync_expires_at": expires_at.isoformat(),
                "updated_at": datetime.now(timezone.utc).isoformat(),
            },
        ).eq("id", user_id).execute()
    except APIError as e:
        logger.exception(
            "Failed to generate export code",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to generate export code.",
        ) from e

    return code, expires_at


def _validate_import(
    source: dict[str, Any],
    target: dict[str, Any],
    target_variant: str,
    source_user: dict[str, Any] | None,
) -> tuple[str, str]:
    """Validate import.

        Args:
            source: Input source parameter.
            target: Input target parameter.
            target_variant: Input target variant parameter.
            source_user: Input source user parameter.

        Returns:
            tuple[str, str]: Response payload or result."""
    # --- 2. Validate expiry ---
    now = datetime.now(timezone.utc)
    expires_raw = source.get("import_sync_expires_at")
    if not expires_raw:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Export code has no expiry. Please generate a new code.",
        )
    expires_at = parse_utc_datetime(expires_raw)

    if now > expires_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Export code has expired. "
                "Please generate a new one from the flavor app."
            ),
        )

    # --- 3. Prevent re-import on target ---
    if target.get("has_imported_data"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "This account has already imported data. Import can only happen once."
            ),
        )

    # --- 4. Ensure target is the main variant, source is a flavor ---
    source_variant = source_user.get("app_variant", "nexus") if source_user else "nexus"

    if target_variant != "nexus":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Import is only allowed into the main Nexus account.",
        )

    if source_variant == "nexus":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Export codes must originate from a flavor variant account.",
        )
    return source_variant, source["id"]


def _fetch_import_profiles(
    sync_code: str,
    target_user_id: str,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Fetch import profiles.

        Args:
            sync_code: Input sync code parameter.
            target_user_id: UUID string of the target user profile.

        Returns:
            tuple[dict[str, Any], dict[str, Any]]: Response payload or result."""
    # --- 1. Fetch source profile by sync code ---
    try:
        source_res = (
            supabase_client.table("profiles")
            .select(
                ", ".join(
                    [
                        "id",
                        "import_sync_expires_at",
                        *_IMPORTABLE_FIELDS,
                    ],
                ),
            )
            .eq("import_sync_code", sync_code)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to look up import sync code")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Import service temporarily unavailable.",
        ) from e

    if not source_res.data:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or already-used export code.",
        )

    try:
        target_res = (
            supabase_client.table("profiles")
            .select("id, has_imported_data")
            .eq("id", target_user_id)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch target profile",
            extra={"target_user_id": target_user_id},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Import service temporarily unavailable.",
        ) from e

    if not target_res.data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Target profile not found. Complete onboarding first.",
        )

    return (
        cast(dict[str, Any], source_res.data[0]),
        cast(dict[str, Any], target_res.data[0]),
    )


def execute_import(
    target_user_id: str,
    sync_code: str,
    target_variant: str = "nexus",
) -> list[str]:
    """
    Execute the cross-flavor import handshake.

    Direction: flavor account (source) → main nexus account (target).
    """
    now = datetime.now(timezone.utc)

    source, target = _fetch_import_profiles(sync_code, target_user_id)

    source_user = fetch_public_user(source["id"])
    source_variant, _ = _validate_import(source, target, target_variant, source_user)

    # --- 5. Copy encrypted fields ---
    copy_payload: dict[str, Any] = {}
    copied_fields: list[str] = []
    for field in _IMPORTABLE_FIELDS:
        value = source.get(field)
        if value is not None:
            copy_payload[field] = value
            copied_fields.append(field)

    # --- 6. Set has_imported_data = True on target ---
    copy_payload["has_imported_data"] = True
    copy_payload["updated_at"] = now.isoformat()

    try:
        supabase_client.table("profiles").update(copy_payload).eq(
            "id",
            target_user_id,
        ).execute()
    except APIError as e:
        logger.exception(
            "Failed to apply import payload",
            extra={"target_user_id": target_user_id, "source_id": source.get("id")},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to apply imported data.",
        ) from e

    # --- 7. Nullify the source code to prevent re-use ---
    try:
        supabase_client.table("profiles").update(
            {
                "import_sync_code": None,
                "import_sync_expires_at": None,
                "updated_at": now.isoformat(),
            },
        ).eq("id", source.get("id")).execute()
    except APIError as e:
        logger.exception(
            "Failed to nullify source import_sync_code after import",
            extra={"source_id": source.get("id")},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to finalize import. Please try again.",
        ) from e

    logger.info(
        "Cross-flavor import completed",
        extra={
            "target_user_id": target_user_id,
            "source_id": source.get("id"),
            "source_variant": source_variant,
            "copied_field_count": len(copied_fields),
        },
    )
    return copied_fields
