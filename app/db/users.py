import logging
from datetime import datetime, timezone
from typing import Any, cast

from fastapi import HTTPException, status
from postgrest.exceptions import APIError
from supabase_auth import User, UserResponse

from app.core.config import settings
from app.db.client import supabase_client

logger = logging.getLogger(__name__)

CURRENT_TERMS_VERSION = "v1"


def is_allowed_college_email(email: str) -> bool:
    normalized = email.strip().lower()
    return normalized.endswith(f"@{settings.allowed_email_domain}")


def _dump_user_object(user: User | dict[str, Any] | object) -> dict[str, Any]:
    if isinstance(user, User):
        return user.model_dump()

    if isinstance(user, dict):
        return cast(dict[str, Any], user)

    for method in ("model_dump", "dict"):
        func = getattr(user, method, None)
        if callable(func):
            res = func()
            if isinstance(res, dict):
                return cast(dict[str, Any], res)

    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Unexpected auth user payload.",
    )


def get_supabase_user_from_jwt(access_token: str) -> dict[str, Any]:
    try:
        response = supabase_client.auth.get_user(access_token)
    except Exception as e:
        logger.exception("Supabase token verification failed")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired access token.",
        ) from e

    user: User | dict[str, Any] | object | None = None
    if isinstance(response, dict):
        response_dict = cast(dict[str, object], response)
        user = response_dict.get("user")
    elif isinstance(response, UserResponse):
        user = response.user
    else:
        user = getattr(cast(object, response), "user", None)

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user not found.",
        )

    return _dump_user_object(user)


def fetch_public_user(user_id: str) -> dict[str, Any] | None:
    try:
        result = (
            supabase_client.table("users")
            .select(
                "id, email, is_active, is_suspended, moderation_status, "
                "accepted_terms_version, terms_accepted_at",
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

    if not data:
        return None

    row = data[0]
    if not isinstance(row, dict):
        return None

    return cast(dict[str, Any], row)


def upsert_public_user(user_id: str, email: str) -> tuple[dict[str, Any], bool]:
    existing = fetch_public_user(user_id)
    newly_created = existing is None

    try:
        result = (
            supabase_client.table("users")
            .upsert(
                {
                    "id": user_id,
                    "email": email.strip().lower(),
                    "updated_at": datetime.now(timezone.utc).isoformat(),
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
    if result.data:
        row = result.data[0]

    if not isinstance(row, dict):
        row = fetch_public_user(user_id)

    if not isinstance(row, dict):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="User account initialization returned no row.",
        )

    return cast(dict[str, Any], row), newly_created


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
    if not data:
        return None

    row = data[0]
    if not isinstance(row, dict):
        return None

    return cast(dict[str, Any], row)


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

    return cast(dict[str, Any], row), profile_created


def _parse_terms_timestamp(ts_raw: Any) -> datetime:
    if isinstance(ts_raw, str):
        return datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
    if isinstance(ts_raw, datetime):
        return ts_raw
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Unexpected terms acceptance timestamp payload.",
    )


def _validate_terms_versions(version: str) -> None:
    current_version = settings.current_terms_version.strip()
    if not version or not version.isdigit():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="accepted_terms_version must be a numeric string.",
        )

    if not current_version or not current_version.isdigit():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server terms configuration is invalid.",
        )

    if version != current_version:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "accepted_terms_version must match the current server terms version."
            ),
        )


def _fetch_existing_terms(user_id: str) -> dict[str, Any]:
    try:
        existing_result = (
            supabase_client.table("users")
            .select("accepted_terms_version, terms_accepted_at")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch current user terms state",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to verify current terms acceptance state.",
        ) from e

    if existing_result is None or existing_result.data is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User bootstrap row not found.",
        )

    if not isinstance(existing_result.data, dict):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unexpected user row payload.",
        )

    return cast(dict[str, Any], existing_result.data)


def _check_existing_terms(
    user_id: str,
    cleaned_version: str,
) -> tuple[str, datetime] | None:
    existing_row = _fetch_existing_terms(user_id)
    existing_version_raw = existing_row.get("accepted_terms_version")
    existing_ts_raw = existing_row.get("terms_accepted_at")

    if existing_version_raw is None:
        return None

    existing_version = str(existing_version_raw).strip()
    if not existing_version.isdigit():
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Stored terms version is invalid.",
        )

    if int(cleaned_version) < int(existing_version):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="accepted_terms_version cannot be downgraded.",
        )

    if int(cleaned_version) == int(existing_version):
        existing_ts = _parse_terms_timestamp(existing_ts_raw)
        return existing_version, existing_ts

    return None


def update_user_terms(
    user_id: str,
    accepted_terms_version: str,
) -> tuple[str, datetime]:
    cleaned_version = accepted_terms_version.strip()
    _validate_terms_versions(cleaned_version)

    existing_state = _check_existing_terms(user_id, cleaned_version)
    if existing_state is not None:
        return existing_state

    accepted_at = datetime.now(timezone.utc)

    try:
        result = (
            supabase_client.table("users")
            .update(
                {
                    "accepted_terms_version": cleaned_version,
                    "terms_accepted_at": accepted_at.isoformat(),
                    "updated_at": accepted_at.isoformat(),
                },
            )
            .eq("id", user_id)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to update user terms",
            extra={"user_id": user_id, "accepted_terms_version": cleaned_version},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to record terms acceptance.",
        ) from e

    data = result.data
    if not data:
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

    row_dict = cast(dict[str, Any], row)
    stored_version = str(row_dict.get("accepted_terms_version") or cleaned_version)
    stored_ts = _parse_terms_timestamp(
        row_dict.get("terms_accepted_at") or accepted_at.isoformat(),
    )

    return stored_version, stored_ts

