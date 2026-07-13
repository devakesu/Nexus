import logging
import secrets
import string
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, cast

from fastapi import HTTPException, status
from postgrest.exceptions import APIError
from supabase_auth import User, UserResponse

from app.core.cache import redis_client
from app.core.config import settings
from app.core.crypto import (
    DecryptFailedError,
    compute_blind_index,
    decrypt_pii,
    encrypt_to_hex,
)
from app.db.client import parse_utc_datetime, supabase_client

logger = logging.getLogger(__name__)

def _load_disposable_domains() -> set[str]:
    """
    Load disposable email domains blocklist from the resources directory.
    """
    resources_dir = Path(__file__).resolve().parent.parent / "resources"
    blocklist_file = resources_dir / "disposable_email_blocklist.txt"
    try:
        with open(blocklist_file) as f:
            return {line.strip().lower() for line in f if line.strip()}
    except OSError as e:
        logger.error("Failed to load disposable email blocklist: %s", e)
        return set()


DISPOSABLE_DOMAINS: set[str] = _load_disposable_domains()


def is_disposable_email(email: str) -> bool:
    """
    Check if the email domain is listed in the disposable email blocklist.
    """
    normalized_email = email.strip().lower()
    if "@" in normalized_email:
        domain = normalized_email.split("@")[-1]
        return domain in DISPOSABLE_DOMAINS
    return False


def is_allowed_email(email: str, app_variant: str = "nexus") -> bool:
    """
    Validate that the email is permitted for the given app variant.

    Domain rules are stored in settings.allowed_signup_domains as a
    {variant: [domains]} dict (e.g. {"nexus_mec": ["mec.edu.in"]}).

    - If the variant is present in the dict → email must end with one of the domains.
    - If the variant is 'nexus' (main) → allowed without any domain restrictions.
    - If any other variant is absent from the dict → open fallback.
    """
    normalized_email = email.strip().lower()

    if app_variant == "nexus":
        return True

    domains = settings.allowed_signup_domains.get(app_variant)
    if not domains:
        # No restriction configured for this variant.
        return True

    for domain in domains:
        normalized_domain = domain.strip().lower().lstrip("@")
        if normalized_email.endswith(f"@{normalized_domain}"):
            return True
    return False


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


def _decrypt_mobile(row: dict[str, Any]) -> dict[str, Any]:
    """Decrypts the mobile column in place, leaving it as None if never set
    or if decryption fails (e.g. stale key) rather than raising - a
    fetch_public_user caller shouldn't 500 just because mobile can't be
    read.
    """
    raw = row.get("mobile")
    if not raw:
        row["mobile"] = None
        return row
    try:
        row["mobile"] = decrypt_pii(raw) or None
    except DecryptFailedError:
        logger.warning(
            "Failed to decrypt mobile for user", extra={"user_id": row.get("id")},
        )
        row["mobile"] = None
    return row


def fetch_public_user(user_id: str) -> dict[str, Any] | None:
    try:
        result = (
            supabase_client.table("users")
            .select(
                "id, app_variant, is_active, is_suspended, "
                "suspended_until, moderation_status, moderation_reason_code, "
                "accepted_terms_version, terms_accepted_at, "
                "special_category_consent_version, special_category_consent_at, "
                "safety_data_consent_version, safety_data_consent_at, "
                "mobile, mobile_verified_at, "
                "deletion_requested_at, scheduled_purge_at",
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

    return _decrypt_mobile(cast(dict[str, Any], row))


def set_verified_mobile(user_id: str, phone: str) -> None:
    """Persists a phone number as verified after a successful account
    phone-OTP check (app/core/account_phone_otp.py). This is the only
    writer of these columns - never client-writable (see
    20260731000000_account_phone_verification.sql,
    20260731010000_mobile_blind_index.sql).

    The blind index is what lets /api/v1/auth/login-by-phone resolve a
    phone number to an account; the partial unique index on it means a
    second account verifying an already-claimed number fails here with a
    clear conflict rather than silently creating an ambiguous lookup.
    """
    from app.db.account_deletion import is_phone_blocklisted

    blind_index = compute_blind_index(phone)
    if is_phone_blocklisted(blind_index):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=(
                "This phone number is restricted. Contact customer support "
                "for details or assistance."
            ),
        )

    now = datetime.now(timezone.utc).isoformat()
    try:
        supabase_client.table("users").update(
            {
                "mobile": encrypt_to_hex(phone),
                "mobile_verified_at": now,
                "mobile_blind_index": blind_index,
            },
        ).eq("id", user_id).execute()
    except APIError as e:
        if e.code == "23505":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This phone number is already linked to another account.",
            ) from e
        logger.exception(
            "Failed to persist verified mobile", extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to save verified phone number. Please try again.",
        ) from e


def find_user_id_by_phone(phone: str) -> str | None:
    """Resolves a verified phone number to the account that claimed it, via
    the blind index - used by the phone-as-username login flow. Returns
    None if no account has verified this number (callers must respond the
    same way as a match to avoid leaking which numbers are registered, the
    same anti-enumeration principle as app/api/safety_portal.py).
    """
    try:
        result = (
            supabase_client.table("users")
            .select("id")
            .eq("mobile_blind_index", compute_blind_index(phone))
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception("Failed to look up user by phone")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Service temporarily unavailable. Please try again later.",
        ) from e

    data = result.data
    if not data:
        return None
    row = data[0]
    return str(row["id"]) if isinstance(row, dict) and row.get("id") else None


def get_user_email_by_id(user_id: str) -> str | None:
    """Looks up an account's Supabase Auth email by id (auth.users, not
    public.users - email was dropped from public.users in
    20260729000000_drop_users_email_mobile.sql). Used to know where to send
    the phone-login OTP - only ever to the account's real, already-verified
    email, never derived from anything client-supplied.
    """
    try:
        response = supabase_client.auth.admin.get_user_by_id(user_id)
    except Exception:
        logger.exception(
            "Failed to look up user email by id", extra={"user_id": user_id},
        )
        return None
    user = getattr(response, "user", None)
    email = getattr(user, "email", None) if user is not None else None
    return str(email) if email else None


def upsert_public_user(
    user_id: str,
    app_variant: str | None = None,
) -> tuple[dict[str, Any], bool]:
    payload: dict[str, Any] = {
        "id": user_id,
    }
    if app_variant is not None:
        payload["app_variant"] = app_variant

    try:
        result = (
            supabase_client.table("users")
            .upsert(
                payload,
                on_conflict="id",
            )
            .select(
                "id, app_variant, is_active, is_suspended, "
                "suspended_until, moderation_status, moderation_reason_code, "
                "accepted_terms_version, terms_accepted_at, "
                "special_category_consent_version, special_category_consent_at, "
                "safety_data_consent_version, safety_data_consent_at, "
                "mobile, mobile_verified_at, "
                "deletion_requested_at, scheduled_purge_at, xmax",
            )
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to upsert public user",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to initialize user account.",
        ) from e

    row = result.data[0] if result.data else None

    if isinstance(row, dict):
        xmax_val = row.get("xmax")
        row_copy = dict(row)
        row_copy.pop("xmax", None)
        row_copy = _decrypt_mobile(row_copy)
    else:
        # fetch_public_user already decrypts mobile - don't decrypt twice.
        fetched = fetch_public_user(user_id)
        if not isinstance(fetched, dict):
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="User account initialization returned no row.",
            )
        xmax_val = None
        row_copy = fetched

    newly_created = xmax_val is not None and str(xmax_val) == "0"

    return row_copy, newly_created


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


def upsert_profile_variant(  # noqa: C901
    user_id: str,
    name: str,
    campus_branch: str | None,
    campus_year: int | None,
    age: int,
    campus_name: str | None = None,
    lifestyle: str | None = None,
) -> tuple[dict[str, Any], bool]:
    """Upsert a profile row with variant-specific columns."""
    existing = fetch_profile(user_id)
    profile_created = existing is None

    encrypted_lifestyle = encrypt_to_hex(lifestyle) if lifestyle is not None else None
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
        "lifestyle": encrypted_lifestyle,
        "updated_at": now_iso,
    }
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


# ---------------------------------------------------------------------------
# Cross-flavor import / export handshake
# ---------------------------------------------------------------------------

_SYNC_CODE_CHARS = (
    string.ascii_uppercase.replace("O", "").replace("I", "")
    + string.digits.replace("0", "").replace("1", "")
)
_SYNC_CODE_LENGTH = 6
_SYNC_CODE_TTL_MINUTES = 15


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


def _validate_import(
    source: dict[str, Any],
    target: dict[str, Any],
    target_variant: str,
    source_user: dict[str, Any] | None,
) -> tuple[str, str]:
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
    cleaned_version = version.strip()
    try:
        float(cleaned_version)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="accepted_terms_version must be a numeric string.",
        ) from None

    try:
        float(current_version)
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
    # Cast to float to prevent any potential SQL/PostgREST injection
    version_val = float(cleaned_version)

    accepted_at = datetime.now(timezone.utc)

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
            # NOTE: version_val is cast to float above to prevent injection.
            # column names come only from this module's own hardcoded call
            # sites below, never from request input.
            .or_(
                f"{version_column}.is.null,{version_column}::numeric.lt.{version_val}",
            )
            .execute()
        )
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

    # Either the user doesn't exist, or they already accepted this (or a
    # higher) version, or it was a downgrade. Fetch to see the state.
    existing = _fetch_existing_consent_pair(user_id, version_column, timestamp_column)
    existing_version = existing.get(version_column)
    if existing_version is not None:
        if float(cleaned_version) < float(existing_version):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"{version_column} cannot be downgraded.",
            )
        existing_ts = _parse_terms_timestamp(existing.get(timestamp_column))
        return str(existing_version), existing_ts
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
    except APIError:
        logger.exception(
            "Failed to write terms_consent_log row",
            extra={"user_id": user_id, "category": category, "granted": granted},
        )


def update_user_terms(
    user_id: str,
    accepted_terms_version: str,
    granted: bool = True,
) -> tuple[str, datetime] | None:
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


def update_special_category_consent(
    user_id: str,
    terms_version: str,
    granted: bool,
) -> tuple[str, datetime] | None:
    cleaned_version = terms_version.strip()
    _validate_terms_versions(cleaned_version)
    if not granted:
        _clear_consent_pair(
            user_id, "special_category_consent_version", "special_category_consent_at",
        )
        _log_consent_event(user_id, "special_category", False, cleaned_version)
        return None
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
    cleaned_version = terms_version.strip()
    _validate_terms_versions(cleaned_version)
    if not granted:
        _clear_consent_pair(
            user_id, "safety_data_consent_version", "safety_data_consent_at",
        )
        _log_consent_event(user_id, "safety_data", False, cleaned_version)
        return None
    result = _update_consent_pair(
        user_id,
        "safety_data_consent_version",
        "safety_data_consent_at",
        cleaned_version,
    )
    _log_consent_event(user_id, "safety_data", True, cleaned_version)
    return result
