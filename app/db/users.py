import logging
import random
import string
from datetime import datetime, timedelta, timezone
from typing import Any, cast

from fastapi import HTTPException, status
from postgrest.exceptions import APIError
from supabase_auth import User, UserResponse

from app.core.config import settings
from app.core.crypto import encrypt_pii
from app.db.client import supabase_client

logger = logging.getLogger(__name__)


def is_allowed_email(email: str, app_variant: str = "nexus") -> bool:
    """
    Validate that the email is permitted for the given app variant.

    Domain rules are stored in settings.allowed_email_domains as a
    {variant: domain} dict (e.g. {"nexus_mec": "mec.edu.in"}).

    - If the variant is present in the dict → email must end with @<domain>.
    - If the variant is 'nexus' (main) → allowed except for any domains
      reserved for flavor variants.
    - If any other variant is absent from the dict → open fallback.
    """
    normalized_email = email.strip().lower()

    if app_variant == "nexus":
        # Block users from registering/logging into the main Nexus app
        # using restricted flavor domains
        for domain in settings.allowed_email_domains.values():
            normalized_domain = domain.strip().lower().lstrip("@")
            if normalized_email.endswith(f"@{normalized_domain}"):
                return False
        return True

    domain = settings.allowed_email_domains.get(app_variant)
    if not domain:
        # No restriction configured for this variant.
        return True

    normalized_domain = domain.strip().lower().lstrip("@")
    return normalized_email.endswith(f"@{normalized_domain}")


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
            detail="Invalid or expired access token. Please try logging in again.",
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
                "id, email, app_variant, is_active, is_suspended, suspended_until, "
                "moderation_status, moderation_reason_code, accepted_terms_version, "
                "terms_accepted_at",
            )
            .eq("id", user_id)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to fetch public user", extra={"user_id": user_id})
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="User service temporarily unavailable. Please try again later.",
        ) from e

    data = result.data

    if not data:
        return None

    row = data[0]
    if not isinstance(row, dict):
        return None

    return cast(dict[str, Any], row)


def upsert_public_user(
    user_id: str,
    email: str | None = None,
    mobile: str | None = None,
    app_variant: str | None = None,
) -> tuple[dict[str, Any], bool]:
    existing = fetch_public_user(user_id)
    newly_created = existing is None

    payload: dict[str, Any] = {
        "id": user_id,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    if email is not None:
        payload["email"] = email.strip().lower()
    if mobile is not None:
        payload["mobile"] = mobile.strip()
    if app_variant is not None:
        payload["app_variant"] = app_variant

    try:
        result = (
            supabase_client.table("users")
            .upsert(
                payload,
                on_conflict="id",
            )
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to upsert public user",
            extra={"user_id": user_id, "email": email, "mobile": mobile},
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


def upsert_profile(
    user_id: str,
    name: str,
    campus_branch: str,
    age: int,
    campus_year: int | None = None,
    campus_name: str | None = None,
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
                    "campus_branch": campus_branch.strip(),
                    "campus_year": campus_year,
                    "campus_name": campus_name.strip() if campus_name else None,
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


def upsert_profile_variant(
    user_id: str,
    name: str,
    campus_branch: str | None,
    campus_year: int | None,
    age: int,
    app_variant: str,
    campus_name: str | None = None,
    lifestyle: str | None = None,
) -> tuple[dict[str, Any], bool]:
    """
    Upsert a profile row that includes variant-specific columns.

    This extends the base upsert_profile() with the new variant columns
    added in the variant_sync migration.
    """
    _ = app_variant
    existing = fetch_profile(user_id)
    profile_created = existing is None

    # Encrypt the lifestyle string for BYTEA storage
    encrypted_lifestyle = None
    if lifestyle is not None:
        enc_bytes = encrypt_pii(lifestyle)
        if enc_bytes:
            encrypted_lifestyle = f"\\x{enc_bytes.hex()}"

    try:
        result = (
            supabase_client.table("profiles")
            .upsert(
                {
                    "id": user_id,
                    "name": name.strip(),
                    "campus_branch": (
                        campus_branch.strip()
                        if campus_branch is not None
                        else None
                    ),
                    "campus_year": campus_year,
                    "campus_name": (
                        campus_name.strip()
                        if campus_name is not None
                        else None
                    ),
                    "age": age,
                    "lifestyle": encrypted_lifestyle,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                },
                on_conflict="id",
            )
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

    return cast(dict[str, Any], row), profile_created


# ---------------------------------------------------------------------------
# Cross-flavor import / export handshake
# ---------------------------------------------------------------------------

_SYNC_CODE_CHARS = string.ascii_uppercase + string.digits
_SYNC_CODE_LENGTH = 6
_SYNC_CODE_TTL_MINUTES = 15


def generate_export_code(user_id: str) -> tuple[str, datetime]:
    """
    Generate and store a one-time 6-char alphanumeric export code for the
    given profile (must be a flavor-variant user).

    The code is valid for 15 minutes. Any previous code is silently overwritten.
    Returns (code, expires_at).
    """
    code = "".join(random.choices(_SYNC_CODE_CHARS, k=_SYNC_CODE_LENGTH))  # noqa: S311
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
    "role",
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
    "search_buckets",
    "dating_target_buckets",
    "friends_target_buckets",
    "professional_target_buckets",
    "campus_branch_blind_index",
    "smoking_blind_index",
    "drinking_blind_index",
    "role_blind_index",
]


def execute_import(target_user_id: str, sync_code: str) -> list[str]:  # noqa: C901
    """
    Execute the cross-flavor import handshake.

    Direction: flavor account (source) → main nexus account (target).

    Steps:
      1. Look up source profile by import_sync_code (service role bypasses RLS).
      2. Validate the code is not expired.
      3. Validate the target has not already imported data.
      4. Validate the source is a non-main flavor (prevents main→main imports).
      5. Copy encrypted PII fields from source to target.
      6. Set has_imported_data = True on target.
      7. Nullify import_sync_code on source to prevent re-use.

    Returns the list of field names actually copied.
    Raises HTTPException on any validation or database error.
    """
    now = datetime.now(timezone.utc)

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

    source = cast(dict[str, Any], source_res.data[0])

    # --- 2. Validate expiry ---
    expires_raw = source.get("import_sync_expires_at")
    if not expires_raw:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Export code has no expiry. Please generate a new code.",
        )
    if isinstance(expires_raw, str):
        expires_at = datetime.fromisoformat(expires_raw.replace("Z", "+00:00"))
    else:
        expires_at = cast(datetime, expires_raw)
    if expires_at.tzinfo is None:
        expires_at = expires_at.replace(tzinfo=timezone.utc)

    if now > expires_at:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Export code has expired. "
                "Please generate a new one from the flavor app."
            ),
        )

    # --- 3. Prevent re-import on target ---
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

    target = cast(dict[str, Any], target_res.data[0])

    if target.get("has_imported_data"):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "This account has already imported data. Import can only happen once."
            ),
        )

    # --- 4. Ensure target is the main variant, source is a flavor ---
    source_user = fetch_public_user(source["id"])
    source_variant = source_user.get("app_variant", "nexus") if source_user else "nexus"

    target_user = fetch_public_user(target_user_id)
    target_variant = target_user.get("app_variant", "nexus") if target_user else "nexus"

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

    # --- 5. Copy encrypted fields ---
    copy_payload: dict[str, Any] = {}
    copied_fields: list[str] = []
    for field in _IMPORTABLE_FIELDS:
        value = source.get(field)
        if value is not None:
            copy_payload[field] = value
            copied_fields.append(field)

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
        # Non-fatal: log but don't fail the import — target already updated.
        logger.error(
            "Failed to nullify source import_sync_code after import (non-fatal)",
            extra={"source_id": source.get("id"), "error": str(e)},
        )

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
    try:
        val_float = float(version)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="accepted_terms_version must be a numeric string.",
        ) from None

    try:
        curr_float = float(current_version)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server terms configuration is invalid.",
        ) from None

    if val_float != curr_float:
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


def update_user_terms(
    user_id: str,
    accepted_terms_version: str,
) -> tuple[str, datetime]:
    cleaned_version = accepted_terms_version.strip()
    _validate_terms_versions(cleaned_version)

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
            .or_(
                f"accepted_terms_version.is.null,accepted_terms_version.lt.{cleaned_version}",
            )
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
    if data:
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

    # Either the user doesn't exist, or they already accepted this (or higher) version,
    # or it was a downgrade. Let's fetch to see the state.
    existing = _fetch_existing_terms(user_id)
    existing_version = existing.get("accepted_terms_version")
    if existing_version is not None:
        if int(cleaned_version) < int(existing_version):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="accepted_terms_version cannot be downgraded.",
            )
        existing_ts = _parse_terms_timestamp(existing.get("terms_accepted_at"))
        return str(existing_version), existing_ts
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Failed to record terms acceptance.",
    )
