"""Database user authentication, registration, PII encryption, and domain validation.

Contains checks for disposable email domains, allowed email structures, Supabase JWT parsing,
and verified mobile phone lookup/blind indexing.
"""

import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, cast

from fastapi import HTTPException, status
from postgrest.exceptions import APIError
from supabase_auth import User, UserResponse

from app.core.config import settings
from app.core.infra.cache import invalidate_user_status_cache
from app.core.security.crypto import (
    DecryptFailedError,
    compute_blind_index,
    decrypt_pii,
    encrypt_to_hex,
)
from app.db.client import DatabaseAccessError, supabase_client

logger = logging.getLogger(__name__)


def _load_disposable_domains() -> set[str]:
    """Loads disposable email domains blocklist from the resources directory.

    Returns:
        set[str]: Lowercased set of prohibited disposable email domain names.
    """
    # Note: resources is located at app/resources.
    # __file__ is inside app/db/users, so .parent.parent.parent is app/
    resources_dir = Path(__file__).resolve().parent.parent.parent / "resources"
    blocklist_file = resources_dir / "disposable_email_blocklist.txt"
    try:
        with open(blocklist_file) as f:
            return {line.strip().lower() for line in f if line.strip()}
    except OSError as e:
        logger.error("Failed to load disposable email blocklist: %s", e)
        return set()


DISPOSABLE_DOMAINS: set[str] = _load_disposable_domains()


def is_disposable_email(email: str) -> bool:
    """Verifies whether an email domain is present in the disposable email blocklist.

    Args:
        email: Email address string to check.

    Returns:
        bool: True if disposable email domain, False otherwise.
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
    """Converts a Supabase User object or dictionary into a normalized dictionary representation.

    Args:
        user: Supabase User model, dictionary, or duck-typed object.

    Returns:
        dict[str, Any]: Normalized user attribute dictionary.

    Raises:
        HTTPException: If payload structure cannot be dumped into dictionary.
    """
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
    """Verifies a Supabase JWT access token and returns user details.

    Args:
        access_token: Raw Supabase JWT access token string.

    Returns:
        dict[str, Any]: Decoded user dictionary payload.

    Raises:
        HTTPException: 401 Unauthorized if token is invalid or user is not found.
    """
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
    """Executes fetch public user operation.

        Args:
            user_id: Unique UUID string of the authenticated user.

        Returns:
            dict[str, Any] | None: Response payload or result."""
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
    from app.db.users import is_phone_blocklisted

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
        invalidate_user_status_cache(user_id)
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


def set_user_suspension(
    user_id: str,
    is_suspended: bool,
    suspended_until: datetime | None = None,
    moderation_status: str | None = None,
    moderation_reason_code: str | None = None,
) -> None:
    """Updates user moderation/suspension state and immediately evicts cached user status.

    Args:
        user_id: Unique UUID string of the target user.
        is_suspended: Boolean flag indicating if the account is suspended.
        suspended_until: Optional expiration datetime for temporary suspensions.
        moderation_status: Optional moderation status string (e.g. 'flagged', 'banned', 'clear').
        moderation_reason_code: Optional reason code string for the moderation action.
    """
    update_data: dict[str, Any] = {
        "is_suspended": is_suspended,
        "suspended_until": suspended_until.isoformat() if suspended_until else None,
    }
    if moderation_status is not None:
        update_data["moderation_status"] = moderation_status
    if moderation_reason_code is not None:
        update_data["moderation_reason_code"] = moderation_reason_code

    try:
        supabase_client.table("users").update(update_data).eq("id", user_id).execute()
        invalidate_user_status_cache(user_id)
    except APIError as e:
        logger.exception("Failed to update user suspension", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to update user suspension status") from e


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


def get_user_id_by_email(email: str) -> str | None:
    """Looks up an account's user_id by email address from Supabase Auth (auth.users).
    Used for web-based unauthenticated account deletion & data export requests.
    """
    if not email:
        return None
    normalized = email.strip().lower()
    try:
        res = (
            supabase_client.rpc("get_user_id_by_email", {"email_addr": normalized})
            .execute()
        )
        if res.data and isinstance(res.data, str):
            return res.data
    except Exception:
        logger.exception("Failed to look up user_id by email", extra={"email": email})
    return None


def upsert_public_user(
    user_id: str,
    app_variant: str | None = None,
) -> tuple[dict[str, Any], bool]:
    """Executes upsert public user operation.

        Args:
            user_id: Unique UUID string of the authenticated user.
            app_variant: Input app variant parameter.

        Returns:
            tuple[dict[str, Any], bool]: Response payload or result."""
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
        invalidate_user_status_cache(user_id)
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
