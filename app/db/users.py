from datetime import datetime, timezone
from typing import Any
from fastapi import HTTPException, status
from postgrest.exceptions import APIError
from app.core.config import settings
from app.db.client import supabase_client

import logging
logger = logging.getLogger(__name__)

CURRENT_TERMS_VERSION = "v1"

def is_allowed_college_email(email: str) -> bool:
    normalized = email.strip().lower()
    return normalized.endswith(f"@{settings.allowed_email_domain}")


def get_supabase_user_from_jwt(access_token: str) -> dict:
    try:
        response = supabase_client.auth.get_user(access_token)
    except Exception as e:
        logger.exception("Supabase token verification failed")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired access token.",
        ) from e

    user = getattr(response, "user", None)
    if user is None and isinstance(response, dict):
        user = response.get("user")

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user not found.",
        )

    if hasattr(user, "model_dump"):
        return user.model_dump()

    if hasattr(user, "dict"):
        return user.dict()

    if isinstance(user, dict):
        return user

    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Unexpected auth user payload.",
    )


def fetch_public_user(user_id: str) -> dict | None:
    try:
        result = (
            supabase_client.table("users")
            .select(
                "id, email, is_active, is_suspended, moderation_status, "
                "accepted_terms_version, terms_accepted_at"
            )
            .eq("id", user_id)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to fetch public user", extra={"user_id": user_id})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="User service temporarily unavailable.",
        ) from e

    data = result.data
    
    if not isinstance(data, list) or not data:
        return None

    row = data[0]
    if not isinstance(row, dict):
        return None

    return row


def upsert_public_user(user_id: str, email: str) -> tuple[dict, bool]:
    existing = fetch_public_user(user_id)
    newly_created = existing is None

    try:
        result = (
            supabase_client.table("users")
            .upsert(
                {
                    "id": user_id,
                    "email": email.strip().lower(),
                    "updated_at": datetime.utcnow().isoformat(),
                },
                on_conflict="id",
            )
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to upsert public user",
            extra={"user_id": user_id, "email": email},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to initialize user account.",
        ) from e

    row = None
    if isinstance(result.data, list) and result.data:
        row = result.data[0]
    elif isinstance(result.data, dict):
        row = result.data

    if not isinstance(row, dict):
        row = fetch_public_user(user_id)

    if not isinstance(row, dict):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="User account initialization returned no row.",
        )

    return row, newly_created


def fetch_profile(user_id: str) -> dict[str, Any] | None:
    try:
        result = (
            supabase_client.table("profiles")
            .select("id, name, branch, year, age, created_at, updated_at")
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
    if not isinstance(data, list) or not data:
        return None

    row = data[0]
    if not isinstance(row, dict):
        return None

    return row


def upsert_profile(
    user_id: str,
    name: str,
    branch: str,
    year: int,
    age: int,
) -> tuple[dict[str, Any], bool]:
    existing = fetch_profile(user_id)
    profile_created = existing is None

    try:
        result = (
            supabase_client.table("profiles")
            .upsert(
                {
                    "id": user_id,
                    "name": name.strip(),
                    "branch": branch.strip(),
                    "year": year,
                    "age": age,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                },
                on_conflict="id",
            )
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to upsert profile", extra={"user_id": user_id})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to save profile.",
        ) from e

    row = None
    if isinstance(result.data, list) and result.data:
        maybe_row = result.data[0]
        if isinstance(maybe_row, dict):
            row = maybe_row
    elif isinstance(result.data, dict):
        row = result.data

    if not isinstance(row, dict):
        row = fetch_profile(user_id)

    if not isinstance(row, dict):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Profile save returned no row.",
        )

    return row, profile_created


def update_user_terms(
    user_id: str,
    accepted_terms_version: str,
) -> tuple[str, datetime]:
    accepted_at = datetime.now(timezone.utc)

    try:
        result = (
            supabase_client.table("users")
            .update(
                {
                    "accepted_terms_version": accepted_terms_version,
                    "terms_accepted_at": accepted_at.isoformat(),
                    "updated_at": accepted_at.isoformat(),
                }
            )
            .eq("id", user_id)
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to update user terms", extra={"user_id": user_id})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to record terms acceptance.",
        ) from e

    data = result.data
    if not isinstance(data, list) or not data:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User bootstrap row not found.",
        )

    row = data[0]
    if not isinstance(row, dict):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unexpected user row payload.",
        )

    stored_version = str(row.get("accepted_terms_version") or accepted_terms_version)
    stored_ts_raw = row.get("terms_accepted_at") or accepted_at.isoformat()

    if isinstance(stored_ts_raw, str):
        stored_ts = datetime.fromisoformat(stored_ts_raw.replace("Z", "+00:00"))
    elif isinstance(stored_ts_raw, datetime):
        stored_ts = stored_ts_raw
    else:
        stored_ts = accepted_at

    return stored_version, stored_ts