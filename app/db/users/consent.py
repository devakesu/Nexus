"""Database terms and itemized consent status persistence layer.

Manages general terms agreement updates, special category consent (sexual orientation,
religious beliefs), safety data tracking consent, and append-only audit trail logging.
"""

import logging
from datetime import datetime, timezone
from typing import Any, cast

from fastapi import HTTPException, status
from postgrest.exceptions import APIError

from app.core.config import settings
from app.core.infra.cache import invalidate_user_status_cache
from app.db.client import parse_utc_datetime, supabase_client

logger = logging.getLogger(__name__)


def _parse_terms_timestamp(ts_raw: Any) -> datetime:
    """Parse terms timestamp.

        Args:
            ts_raw: Input ts raw parameter.

        Returns:
            datetime: Response payload or result."""
    try:
        if isinstance(ts_raw, (str, datetime)):
            return parse_utc_datetime(ts_raw)
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Unexpected terms acceptance timestamp payload.",
        ) from e
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Unexpected terms acceptance timestamp payload.",
    )


def _parse_version_tuple(version: str) -> tuple[int, ...]:
    """Parse version string like '1.0', '1.10', '2.1.3' into a tuple of integers for strict semver comparison."""
    cleaned = version.strip()
    if not cleaned:
        raise ValueError("Version string cannot be empty.")
    parts = cleaned.split(".")
    try:
        return tuple(int(p) for p in parts)
    except ValueError as e:
        raise ValueError(f"Invalid numeric version segment in '{version}'") from e


def _validate_terms_versions(version: str) -> None:
    """Validate terms versions against server configuration using strict semver comparison."""
    current_version = settings.current_terms_version.strip()
    cleaned_version = version.strip()
    try:
        _parse_version_tuple(cleaned_version)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="accepted_terms_version must be a valid numeric version string.",
        ) from None

    try:
        _parse_version_tuple(current_version)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server terms configuration is invalid.",
        ) from None

    if cleaned_version != current_version:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "accepted_terms_version must match the current server terms version."
            ),
        )


def _fetch_existing_consent_pair(
    user_id: str,
    version_column: str,
    timestamp_column: str,
) -> dict[str, Any]:
    """Fetch existing consent pair.

        Args:
            user_id: Unique UUID string of the authenticated user.
            version_column: Input version column parameter.
            timestamp_column: Input timestamp column parameter.

        Returns:
            dict[str, Any]: Response payload or result."""
    try:
        existing_result = (
            supabase_client.table("users")
            .select(f"{version_column}, {timestamp_column}")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch current consent state",
            extra={"user_id": user_id, "column": version_column},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to verify current consent state.",
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


def _update_consent_pair(
    user_id: str,
    version_column: str,
    timestamp_column: str,
    cleaned_version: str,
) -> tuple[str, datetime]:
    """Shared non-downgrade version-write for a `{category}_consent_version`/
    `{category}_consent_at`-shaped column pair - used by update_user_terms
    (the general category, columns accepted_terms_version/terms_accepted_at)
    and the special_category/safety_data consent writers below. Only ever
    moves a category's recorded version forward, never backward or sideways.
    """
    version_tuple = _parse_version_tuple(cleaned_version)

    accepted_at = datetime.now(timezone.utc)

    # Fetch existing consent state to determine upgrade vs. downgrade vs. no-op
    existing = _fetch_existing_consent_pair(user_id, version_column, timestamp_column)
    existing_version = existing.get(version_column)

    if existing_version is not None:
        try:
            existing_tuple = _parse_version_tuple(str(existing_version))
        except ValueError:
            existing_tuple = (0,)

        if existing_tuple == version_tuple:
            # Already at this version - no-op
            existing_ts = _parse_terms_timestamp(existing.get(timestamp_column))
            return str(existing_version), existing_ts

        if existing_tuple > version_tuple:
            # Attempted downgrade
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"{version_column} cannot be downgraded.",
            )

    try:
        result = (
            supabase_client.table("users")
            .update(
                {
                    version_column: cleaned_version,
                    timestamp_column: accepted_at.isoformat(),
                    "updated_at": accepted_at.isoformat(),
                },
            )
            .eq("id", user_id)
            .execute()
        )
        invalidate_user_status_cache(user_id)
    except APIError as e:
        logger.exception(
            "Failed to update consent column pair",
            extra={"user_id": user_id, "column": version_column},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to record consent.",
        ) from e

    data = result.data
    if data:
        row = data[0]
        if not isinstance(row, dict):
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Unexpected user row payload.",
            )
        row_dict = cast(dict[str, Any], row)
        stored_version = str(row_dict.get(version_column) or cleaned_version)
        stored_ts = _parse_terms_timestamp(
            row_dict.get(timestamp_column) or accepted_at.isoformat(),
        )
        return stored_version, stored_ts

    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Failed to record consent.",
    )


def _clear_consent_pair(
    user_id: str,
    version_column: str,
    timestamp_column: str,
) -> None:
    """Unconditionally nulls a consent column pair - used when a category is
    declined/revoked. Unlike _update_consent_pair this isn't version-gated:
    declining always takes effect regardless of what was previously stored.
    """
    try:
        supabase_client.table("users").update(
            {version_column: None, timestamp_column: None},
        ).eq("id", user_id).execute()
        invalidate_user_status_cache(user_id)
    except APIError as e:
        logger.exception(
            "Failed to clear consent column pair",
            extra={"user_id": user_id, "column": version_column},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to record consent.",
        ) from e


def _log_consent_event(
    user_id: str,
    category: str,
    granted: bool,
    terms_version: str,
) -> None:
    """Best-effort write to the append-only audit trail
    (20260802000000_terms_consent_expansion.sql) - logged for every accept
    *and* decline. A logging failure must not block the consent
    accept/decline itself from taking effect, so this only logs, never
    raises.
    """
    try:
        supabase_client.table("terms_consent_log").insert(
            {
                "user_id": user_id,
                "category": category,
                "granted": granted,
                "terms_version": terms_version,
            },
        ).execute()
    except Exception:
        logger.exception(
            "Failed to write terms_consent_log row",
            extra={"user_id": user_id, "category": category, "granted": granted},
        )


def update_user_terms(
    user_id: str,
    accepted_terms_version: str,
    granted: bool = True,
) -> tuple[str, datetime] | None:
    """Executes update user terms operation.

        Args:
            user_id: Unique UUID string of the authenticated user.
            accepted_terms_version: Input accepted terms version parameter.
            granted: Input granted parameter.

        Returns:
            tuple[str, datetime] | None: Response payload or result."""
    cleaned_version = accepted_terms_version.strip()
    _validate_terms_versions(cleaned_version)
    if not granted:
        _clear_consent_pair(user_id, "accepted_terms_version", "terms_accepted_at")
        _log_consent_event(user_id, "general", False, cleaned_version)
        return None
    result = _update_consent_pair(
        user_id, "accepted_terms_version", "terms_accepted_at", cleaned_version,
    )
    _log_consent_event(user_id, "general", True, cleaned_version)
    return result


def update_community_guidelines_consent(
    user_id: str,
    terms_version: str,
    granted: bool = True,
) -> None:
    """Executes update community guidelines consent audit logging operation.

    Args:
        user_id: Unique UUID string of the authenticated user.
        terms_version: Input terms version parameter.
        granted: Input granted parameter.
    """
    cleaned_version = terms_version.strip()
    _validate_terms_versions(cleaned_version)
    _log_consent_event(user_id, "community_guidelines", granted, cleaned_version)



def _verify_general_terms_accepted(user_id: str) -> None:
    """Ensure that the user has accepted general terms before itemized/special consents can be granted."""
    existing = _fetch_existing_consent_pair(
        user_id,
        "accepted_terms_version",
        "terms_accepted_at",
    )
    if not existing.get("accepted_terms_version"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="General terms must be accepted before special category or safety data consent can be granted.",
        )


def update_special_category_consent(
    user_id: str,
    terms_version: str,
    granted: bool,
) -> tuple[str, datetime] | None:
    """Executes update special category consent operation.

        Args:
            user_id: Unique UUID string of the authenticated user.
            terms_version: Input terms version parameter.
            granted: Input granted parameter.

        Returns:
            tuple[str, datetime] | None: Response payload or result."""
    cleaned_version = terms_version.strip()
    _validate_terms_versions(cleaned_version)
    if not granted:
        _clear_consent_pair(
            user_id, "special_category_consent_version", "special_category_consent_at",
        )
        _log_consent_event(user_id, "special_category", False, cleaned_version)
        return None

    _verify_general_terms_accepted(user_id)

    result = _update_consent_pair(
        user_id,
        "special_category_consent_version",
        "special_category_consent_at",
        cleaned_version,
    )
    _log_consent_event(user_id, "special_category", True, cleaned_version)
    return result


def update_safety_data_consent(
    user_id: str,
    terms_version: str,
    granted: bool,
) -> tuple[str, datetime] | None:
    """Executes update safety data consent operation.

        Args:
            user_id: Unique UUID string of the authenticated user.
            terms_version: Input terms version parameter.
            granted: Input granted parameter.

        Returns:
            tuple[str, datetime] | None: Response payload or result."""
    cleaned_version = terms_version.strip()
    _validate_terms_versions(cleaned_version)
    if not granted:
        _clear_consent_pair(
            user_id, "safety_data_consent_version", "safety_data_consent_at",
        )
        _log_consent_event(user_id, "safety_data", False, cleaned_version)
        return None

    _verify_general_terms_accepted(user_id)

    result = _update_consent_pair(
        user_id,
        "safety_data_consent_version",
        "safety_data_consent_at",
        cleaned_version,
    )
    _log_consent_event(user_id, "safety_data", True, cleaned_version)
    return result
