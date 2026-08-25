"""User authentication, onboarding, terms consent, and phone/SMS OTP endpoints."""

import logging
from datetime import datetime, timezone
from typing import Any, cast

from fastapi import APIRouter, Body, Depends, HTTPException, Request, status
from slowapi.util import get_remote_address
from starlette.concurrency import run_in_threadpool

from app.api.dependencies import (
    assert_account_active,
    get_active_user_id,
    get_authenticated_user_id,
    get_authenticated_user_payload,
    is_consent_stale,
    verify_and_get_app_check_claims,
    verify_app_check_with_replay_protection,
)
from app.core.auth.passwordless_email import (
    send_login_email_otp,
    verify_login_email_otp,
)
from app.core.auth.phone_otp import (
    generate_otp_code,
    hash_otp,
    mask_phone,
    normalize_phone,
)
from app.core.config import settings
from app.core.email import extract_user_name, send_bootstrap_welcome_email
from app.core.infra.cache import redis_client
from app.core.infra.limiter import limiter
from app.core.infra.otp import (
    dummy_email_send_delay,
    verify_and_consume_hashed_otp,
)
from app.core.security.crypto import compute_blind_index
from app.core.utils.sms import send_sms
from app.db.client import supabase_client
from app.db.users import (
    fetch_profile,
    fetch_public_user,
    find_user_id_by_phone,
    get_user_email_by_id,
    is_allowed_email,
    is_disposable_email,
    is_phone_blocklisted,
    set_verified_mobile,
    update_community_guidelines_consent,
    update_safety_data_consent,
    update_special_category_consent,
    update_user_terms,
    upsert_profile_variant,
    upsert_public_user,
)
from app.models import (
    AccountPhoneOtpRequestRequest,
    AccountPhoneOtpRequestResponse,
    AccountPhoneOtpVerifyRequest,
    AccountPhoneOtpVerifyResponse,
    AttestationResponse,
    AuthBootstrapResponse,
    CompleteOnboardingResponse,
    ConsentUpdateRequest,
    ConsentUpdateResponse,
    LoginByPhoneRequestRequest,
    LoginByPhoneRequestResponse,
    LoginByPhoneVerifyRequest,
    LoginByPhoneVerifyResponse,
    MECOnboardingRequest,
    OnboardingPayload,
)

logger = logging.getLogger(__name__)

router = APIRouter()

_ACCOUNT_PHONE_OTP_TTL_SECONDS = 600
_ACCOUNT_PHONE_OTP_MAX_ATTEMPTS = 5
_ACCOUNT_PHONE_OTP_RESEND_COOLDOWN_SECONDS = 60
_LOGIN_BY_PHONE_RESEND_COOLDOWN_SECONDS = 60
_LOGIN_BY_PHONE_MAX_PHONE_ATTEMPTS = 3
_LOGIN_BY_PHONE_PHONE_WINDOW_SECONDS = 30 * 60  # 30 minutes





async def _validate_auth_user_allowed(
    email: str | None,
    auth_user: dict[str, Any],
) -> None:
    """Validate auth user allowed.

        Args:
            email: Input email parameter.
            auth_user: Input auth user parameter."""
    app_variant = str(
        auth_user.get("app_metadata", {}).get("app_variant") or "nexus"
    ).strip()

    if (
        app_variant != "nexus"
        and settings.allowed_signup_domains.get(app_variant)
        and not email
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Email authentication is required for {app_variant} registration.",
        )

    if email:
        if is_disposable_email(email):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Sign-ups using disposable email domains are not permitted.",
            )

        if not is_allowed_email(email, app_variant):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="This email domain is not authorized for registration.",
            )


@router.post("/api/v1/auth/bootstrap", response_model=AuthBootstrapResponse)
@limiter.limit(settings.rate_limit_auth)
async def auth_bootstrap(
    request: Request,
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user: dict[str, Any] = Depends(get_authenticated_user_payload),
) -> AuthBootstrapResponse:
    """Executes auth bootstrap operation.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            _device: App Check attestation token dependency guard.
            auth_user: Decoded authenticated user object from Depends.

        Returns:
            AuthBootstrapResponse: Response payload or result."""
    _ = request

    user_id = str(auth_user.get("id") or "").strip()
    email_raw = auth_user.get("email")
    email = str(email_raw).strip().lower() if email_raw else None
    phone_raw = auth_user.get("phone")
    phone = str(phone_raw).strip() if phone_raw else None

    if not user_id or (not email and not phone):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user payload is incomplete.",
        )

    await _validate_auth_user_allowed(email, auth_user)

    app_variant = str(
        auth_user.get("app_metadata", {}).get("app_variant") or "nexus"
    ).strip()

    existing_user = await run_in_threadpool(fetch_public_user, user_id)
    if existing_user is not None:
        user_row = existing_user
        newly_created = False
    else:
        user_row, newly_created = await run_in_threadpool(
            upsert_public_user,
            user_id,
            app_variant,
        )

    is_suspended = bool(user_row.get("is_suspended", False))
    deletion_pending = bool(user_row.get("deletion_requested_at") is not None)
    scheduled_purge_at_raw = user_row.get("scheduled_purge_at")
    scheduled_purge_at = (
        datetime.fromisoformat(scheduled_purge_at_raw.replace("Z", "+00:00"))
        if isinstance(scheduled_purge_at_raw, str)
        else None
    )

    current_terms_version = settings.current_terms_version.strip()
    accepted_version = user_row.get("accepted_terms_version")
    special_version = user_row.get("special_category_consent_version")
    safety_version = user_row.get("safety_data_consent_version")

    # Consent version checking: general terms acceptance gates all app access
    # for already-onboarded profiles.
    has_profile = await run_in_threadpool(fetch_profile, user_id) is not None
    mandatory_consent_required = has_profile and is_consent_stale(
        accepted_version,
        current_terms_version,
    )

    special_category_consent_granted = not is_consent_stale(
        special_version,
        current_terms_version,
    )
    safety_data_consent_granted = not is_consent_stale(
        safety_version,
        current_terms_version,
    )

    terms_accepted_at_raw = user_row.get("terms_accepted_at")
    terms_accepted_at = (
        datetime.fromisoformat(terms_accepted_at_raw.replace("Z", "+00:00"))
        if isinstance(terms_accepted_at_raw, str)
        else None
    )

    special_at_raw = user_row.get("special_category_consent_at")
    special_category_consent_at = (
        datetime.fromisoformat(special_at_raw.replace("Z", "+00:00"))
        if isinstance(special_at_raw, str)
        else None
    )

    safety_at_raw = user_row.get("safety_data_consent_at")
    safety_data_consent_at = (
        datetime.fromisoformat(safety_at_raw.replace("Z", "+00:00"))
        if isinstance(safety_at_raw, str)
        else None
    )

    mobile_raw = user_row.get("mobile")
    mobile = mask_phone(str(mobile_raw)) if mobile_raw else None
    mobile_verified_at_raw = user_row.get("mobile_verified_at")
    mobile_verified_at = (
        datetime.fromisoformat(mobile_verified_at_raw.replace("Z", "+00:00"))
        if isinstance(mobile_verified_at_raw, str)
        else None
    )

    if newly_created and email:
        welcome_key = f"welcome_email_sent:{user_id}"
        should_send = await redis_client.set(welcome_key, "1", ex=86400 * 7, nx=True)
        if should_send:
            try:
                await send_bootstrap_welcome_email(
                    email=email,
                    auth_user=auth_user,
                    app_variant=app_variant,
                )
            except Exception:
                logger.exception("Failed to send welcome email on auth bootstrap")

    return AuthBootstrapResponse(
        user_id=user_id,
        email=None,
        is_active=bool(user_row.get("is_active", True)),
        is_suspended=is_suspended,
        moderation_status=str(user_row.get("moderation_status") or "approved"),
        accepted_terms_version=accepted_version,
        terms_accepted_at=terms_accepted_at,
        newly_created=newly_created,
        mobile=mobile,
        mobile_verified_at=mobile_verified_at,
        deletion_pending=deletion_pending,
        scheduled_purge_at=scheduled_purge_at,
        current_terms_version=current_terms_version,
        special_category_consent_version=special_version,
        special_category_consent_at=special_category_consent_at,
        safety_data_consent_version=safety_version,
        safety_data_consent_at=safety_data_consent_at,
        mandatory_consent_required=mandatory_consent_required,
        special_category_consent_granted=special_category_consent_granted,
        safety_data_consent_granted=safety_data_consent_granted,
    )


def _resolve_onboarding_profile_fields(
    payload: OnboardingPayload,
    email: str | None,
    auth_user: dict[str, Any],
) -> tuple[str, str | None, int | None, str | None, str | None]:
    if isinstance(payload, MECOnboardingRequest):
        if not email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email is required for campus NEXUS_MEC onboarding.",
            )
        user_name = extract_user_name(email, auth_user)
        user_campus_name = payload.campus_name
        if not user_campus_name or not user_campus_name.strip():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Institute name is required.",
            )
        cleaned_campus = user_campus_name.strip()
        if sum(c.isalpha() for c in cleaned_campus) < 3:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Institute name must contain at least three letters.",
            )
        return (
            user_name,
            payload.campus_branch,
            payload.campus_year,
            cleaned_campus,
            None,
        )

    return (
        payload.name,
        None,
        None,
        None,
        payload.demographic_bucket,
    )


@router.post(
    "/api/v1/auth/complete-onboarding",
    response_model=CompleteOnboardingResponse,
)
@limiter.limit(settings.rate_limit_auth)
async def complete_onboarding(
    request: Request,
    payload: OnboardingPayload = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user: dict[str, Any] = Depends(get_authenticated_user_payload),
):
    """Complete the onboarding flow."""
    _ = request

    user_id = str(auth_user.get("id") or "").strip()
    email_raw = auth_user.get("email")
    email = str(email_raw).strip().lower() if email_raw else None

    if not user_id or (not email and not auth_user.get("phone")):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user payload is incomplete.",
        )

    user_row = await run_in_threadpool(fetch_public_user, user_id)
    if not user_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User bootstrap row not found. Complete onboarding bootstrap first.",
        )

    assert_account_active(user_row)

    if not user_row.get("accepted_terms_version"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Accept terms before completing onboarding.",
        )

    if await run_in_threadpool(fetch_profile, user_id) is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Onboarding has already been completed.",
        )

    expected_variant = str(user_row.get("app_variant") or "nexus")
    if payload.app_variant != expected_variant:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid onboarding payload for account variant '{expected_variant}'.",
        )

    max_age = 80 if expected_variant == "nexus" else 27
    if payload.age > max_age:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Age must be between 18 and {max_age} for your account type.",
        )

    (
        user_name,
        user_branch,
        user_year,
        user_campus_name,
        user_demographic_bucket,
    ) = _resolve_onboarding_profile_fields(payload, email, auth_user)

    profile_row, profile_created = await run_in_threadpool(
        upsert_profile_variant,
        user_id=user_id,
        name=user_name,
        campus_branch=user_branch,
        campus_year=user_year,
        age=payload.age,
        campus_name=user_campus_name,
        demographic_bucket=user_demographic_bucket,
    )

    return CompleteOnboardingResponse(
        user_id=user_id,
        profile_created=profile_created,
        profile=profile_row,
    )


def _otp_redis_key(user_id: str, suffix: str) -> str:
    """Formats Redis key string for account phone OTP operations."""
    return f"account_phone_otp:{suffix}:{user_id}"


@router.post(
    "/api/v1/user/phone/otp/request",
    response_model=AccountPhoneOtpRequestResponse,
)
@limiter.limit(settings.rate_limit_account_phone_otp)
async def request_account_phone_otp(
    request: Request,
    payload: AccountPhoneOtpRequestRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_active_user_id),
) -> AccountPhoneOtpRequestResponse:
    """Executes request account phone otp operation."""
    _ = request
    phone_norm = normalize_phone(payload.phone)

    resend_key = _otp_redis_key(user_id, "resend")
    phone_resend_key = f"account_phone_otp:resend_phone:{phone_norm}"
    if await redis_client.exists(resend_key) or await redis_client.exists(phone_resend_key):
        raise HTTPException(
            status_code=429,
            detail="Please wait a bit before requesting another code.",
        )
    await redis_client.set(
        resend_key, "1", ex=_ACCOUNT_PHONE_OTP_RESEND_COOLDOWN_SECONDS, nx=True,
    )
    await redis_client.set(
        phone_resend_key, "1", ex=_ACCOUNT_PHONE_OTP_RESEND_COOLDOWN_SECONDS, nx=True,
    )

    code = generate_otp_code()
    await redis_client.setex(
        _otp_redis_key(user_id, "otp"),
        _ACCOUNT_PHONE_OTP_TTL_SECONDS,
        hash_otp(user_id, phone_norm, code),
    )
    await send_sms(
        phone_norm,
        f"Your Nexus verification code is {code}. It expires in 10 minutes. "
        "Do not share this code.",
    )

    return AccountPhoneOtpRequestResponse(sent=True)


@router.post(
    "/api/v1/user/phone/otp/verify",
    response_model=AccountPhoneOtpVerifyResponse,
)
@limiter.limit(settings.rate_limit_account_phone_otp)
async def verify_account_phone_otp(
    request: Request,
    payload: AccountPhoneOtpVerifyRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_active_user_id),
) -> AccountPhoneOtpVerifyResponse:
    """Executes verify account phone otp operation."""
    _ = request
    phone_norm = normalize_phone(payload.phone)

    await verify_and_consume_hashed_otp(
        otp_key=_otp_redis_key(user_id, "otp"),
        attempts_key=_otp_redis_key(user_id, "attempts"),
        user_identifier=user_id,
        phone_norm=phone_norm,
        submitted_code=payload.code,
        max_attempts=_ACCOUNT_PHONE_OTP_MAX_ATTEMPTS,
        ttl_seconds=_ACCOUNT_PHONE_OTP_TTL_SECONDS,
        client=redis_client,
    )

    await run_in_threadpool(set_verified_mobile, user_id, phone_norm)

    return AccountPhoneOtpVerifyResponse(
        verified=True,
        mobile=phone_norm,
        mobile_verified_at=datetime.now(timezone.utc),
    )


def _login_by_phone_resend_key(ip: str, phone_norm: str) -> str:
    """Generates a Redis key for phone login cooldown scoped by client IP and phone."""
    return f"login_by_phone:resend:{ip}:{phone_norm}"


def _login_by_phone_ip_resend_key(ip: str) -> str:
    """Generates a Redis key for phone login cooldown scoped by client IP."""
    return f"login_by_phone:resend:ip:{ip}"


def _login_by_phone_phone_limit_key(phone_norm: str) -> str:
    """Generates a Redis key for phone login rate limiting scoped globally to the target phone number."""
    return f"login_by_phone:limit:phone:{phone_norm}"


@router.post(
    "/api/v1/auth/login-by-phone/request",
    response_model=LoginByPhoneRequestResponse,
)
@limiter.limit(settings.rate_limit_login_by_phone)
async def request_login_by_phone(
    request: Request,
    payload: LoginByPhoneRequestRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
) -> LoginByPhoneRequestResponse:
    """Executes request login by phone operation."""
    client_ip = get_remote_address(request)
    phone_norm = normalize_phone(payload.phone)

    # Tier 1: Per-IP resend cooldown (prevents rapid spamming from a single IP without locking out victim on another IP)
    ip_resend_key = _login_by_phone_ip_resend_key(client_ip)
    phone_ip_resend_key = _login_by_phone_resend_key(client_ip, phone_norm)

    if await redis_client.exists(ip_resend_key) or await redis_client.exists(phone_ip_resend_key):
        raise HTTPException(
            status_code=429,
            detail="Please wait a bit before requesting another code.",
        )

    # Tier 2: Global per-phone rate limit (caps total dispatches across all IPs to max 3 attempts per 30 minutes)
    phone_limit_key = _login_by_phone_phone_limit_key(phone_norm)
    phone_attempts = await redis_client.get(phone_limit_key)
    if phone_attempts and int(phone_attempts) >= _LOGIN_BY_PHONE_MAX_PHONE_ATTEMPTS:
        raise HTTPException(
            status_code=429,
            detail="Too many login attempts for this phone number. Please try again later.",
        )

    # Set Tier 1 cooldowns (60s)
    await redis_client.set(
        ip_resend_key, "1", ex=_LOGIN_BY_PHONE_RESEND_COOLDOWN_SECONDS, nx=True,
    )
    await redis_client.set(
        phone_ip_resend_key, "1", ex=_LOGIN_BY_PHONE_RESEND_COOLDOWN_SECONDS, nx=True,
    )

    # Increment Tier 2 attempt counter with 30-minute expiration window
    current_attempts = await redis_client.incr(phone_limit_key)
    if current_attempts == 1:
        await redis_client.expire(phone_limit_key, _LOGIN_BY_PHONE_PHONE_WINDOW_SECONDS)

    blind_index = compute_blind_index(phone_norm)
    if await run_in_threadpool(is_phone_blocklisted, blind_index):
        await dummy_email_send_delay()
        return LoginByPhoneRequestResponse(sent=True)

    user_id = await run_in_threadpool(find_user_id_by_phone, phone_norm)
    if user_id is not None:
        email = await run_in_threadpool(get_user_email_by_id, user_id)
        if email:
            await run_in_threadpool(send_login_email_otp, email)
        else:
            await dummy_email_send_delay()
    else:
        await dummy_email_send_delay()

    return LoginByPhoneRequestResponse(sent=True)


@router.post(
    "/api/v1/auth/login-by-phone/verify",
    response_model=LoginByPhoneVerifyResponse,
)
@limiter.limit(settings.rate_limit_login_by_phone)
async def verify_login_by_phone(
    request: Request,
    payload: LoginByPhoneVerifyRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
) -> LoginByPhoneVerifyResponse:
    """Executes verify login by phone operation."""
    _ = request
    phone_norm = normalize_phone(payload.phone)

    blind_index = compute_blind_index(phone_norm)
    if await run_in_threadpool(is_phone_blocklisted, blind_index):
        raise HTTPException(status_code=400, detail="Invalid or expired code.")

    user_id = await run_in_threadpool(find_user_id_by_phone, phone_norm)
    email = await run_in_threadpool(get_user_email_by_id, user_id) if user_id else None
    if not email or not user_id:
        raise HTTPException(status_code=400, detail="Invalid or expired code.")

    user_row = await run_in_threadpool(fetch_public_user, user_id)
    if not user_row:
        raise HTTPException(status_code=400, detail="Invalid or expired code.")

    assert_account_active(user_row)

    try:
        auth_response = await run_in_threadpool(
            verify_login_email_otp, email, payload.code,
        )
    except Exception as e:
        raise HTTPException(
            status_code=400, detail="Invalid or expired code.",
        ) from e

    session = auth_response.session
    if session is None:
        raise HTTPException(status_code=400, detail="Invalid or expired code.")

    return LoginByPhoneVerifyResponse(
        refresh_token=session.refresh_token,
    )


def _unhide_special_category_fields(user_id: str) -> None:
    try:
        res = (
            supabase_client.table("profiles")
            .select("hidden_profile_fields")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        data_dict = cast(dict[str, Any], getattr(res, "data", None) or {})
        hidden = cast(list[str], data_dict.get("hidden_profile_fields") or [])
        new_hidden = [
            f for f in hidden
            if f not in ("display_sexuality", "religious_beliefs")
        ]
        if len(new_hidden) != len(hidden):
            supabase_client.table("profiles").update(
                {"hidden_profile_fields": new_hidden},
            ).eq("id", user_id).execute()
    except Exception:
        logger.exception("Failed to update hidden fields on terms acceptance")


@router.post(
    "/api/v1/auth/accept-terms",
    response_model=ConsentUpdateResponse,
)
@limiter.limit(settings.rate_limit_auth)
async def accept_terms(
    request: Request,
    payload: ConsentUpdateRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user: dict[str, Any] = Depends(get_authenticated_user_payload),
):
    """Records user acceptance of application Terms of Service and Privacy Policy."""
    _ = request

    user_id = str(auth_user.get("id") or "").strip()
    email = str(auth_user.get("email") or "").strip().lower()
    phone = str(auth_user.get("phone") or "").strip()

    if not user_id or (not email and not phone):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user payload is incomplete.",
        )

    user_row = await run_in_threadpool(fetch_public_user, user_id)
    if not user_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User bootstrap row not found. Complete onboarding bootstrap first.",
        )

    assert_account_active(user_row)

    general_result = await run_in_threadpool(
        update_user_terms,
        user_id=user_id,
        accepted_terms_version=payload.terms_version,
        granted=payload.general_accepted,
    )

    await run_in_threadpool(
        update_community_guidelines_consent,
        user_id=user_id,
        terms_version=payload.terms_version,
        granted=payload.community_guidelines_accepted,
    )

    if not payload.general_accepted:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "General Terms of Service & Privacy Policy consent is "
                "required to use Nexus. Your decline has been recorded."
            ),
        )

    if not payload.community_guidelines_accepted:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Community Guidelines acceptance is required to use Nexus. "
                "Your decline has been recorded."
            ),
        )

    special_result = None
    if payload.special_category_accepted is not None:
        special_result = await run_in_threadpool(
            update_special_category_consent,
            user_id=user_id,
            terms_version=payload.terms_version,
            granted=payload.special_category_accepted,
        )
        if payload.special_category_accepted:
            await run_in_threadpool(_unhide_special_category_fields, user_id)

    safety_result = None
    if payload.safety_data_accepted is not None:
        safety_result = await run_in_threadpool(
            update_safety_data_consent,
            user_id=user_id,
            terms_version=payload.terms_version,
            granted=payload.safety_data_accepted,
        )

    # Proactively invalidate user:status cache so consent updates take effect immediately
    try:
        await redis_client.delete(f"user:status:{user_id}")
    except Exception:
        logger.warning("Failed to invalidate user status cache on consent update", exc_info=True)

    return ConsentUpdateResponse(
        user_id=user_id,
        accepted_terms_version=general_result[0] if general_result else None,
        terms_accepted_at=general_result[1] if general_result else None,
        special_category_consent_version=special_result[0] if special_result else None,
        special_category_consent_at=special_result[1] if special_result else None,
        safety_data_consent_version=safety_result[0] if safety_result else None,
        safety_data_consent_at=safety_result[1] if safety_result else None,
    )


@router.post(
    "/api/v1/auth/revoke-all-sessions",
    response_model=dict[str, bool],
)
@limiter.limit(settings.rate_limit_auth)
async def revoke_all_sessions(
    request: Request,
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_authenticated_user_id),
) -> dict[str, bool]:
    """Globally revokes all active Supabase auth sessions and deactivates all registered FCM device tokens.

    Args:
        request: Incoming HTTP request.
        _device: App Check attestation token guard.
        user_id: Verified caller user ID.

    Returns:
        dict[str, bool]: Success dictionary.
    """
    _ = request
    # 1. Global sign out in Supabase auth admin
    try:
        await run_in_threadpool(supabase_client.auth.admin.sign_out, user_id, "global")
    except Exception:
        logger.warning("Supabase admin global sign-out failed for user %s", user_id, exc_info=True)

    # 2. Deactivate all device push notification tokens
    try:
        await run_in_threadpool(
            lambda: supabase_client.table("user_devices").update(
                {"is_active": False},
            ).eq("user_id", user_id).execute()
        )
    except Exception:
        logger.warning("Failed to deactivate user_devices for user %s", user_id, exc_info=True)

    # 3. Invalidate Redis user status cache and presence
    await redis_client.delete(f"user:status:{user_id}")
    await redis_client.delete(f"user:presence:last_beat:{user_id}")

    return {"success": True}


@router.get(
    "/api/v1/auth/attestation",
    response_model=AttestationResponse,
)
@limiter.limit(settings.rate_limit_auth)
async def get_attestation_status(
    request: Request,
    claims: dict[str, Any] | None = Depends(verify_and_get_app_check_claims),
) -> AttestationResponse:
    """Verifies caller App Check token and returns authentic attestation telemetry.

    Args:
        request: Incoming HTTP request.
        claims: Verified App Check claims dict or None if unenforced dev mode.

    Returns:
        AttestationResponse: Device integrity and App Check attestation status.
    """
    _ = request
    now_iso = datetime.now(timezone.utc).isoformat()

    if claims is not None:
        app_id = claims.get("app_id") or claims.get("sub")
        iss = str(claims.get("iss", "Firebase App Check"))
        is_debug = "debug" in iss.lower() or (settings.debug and "debug" in str(claims.get("provider", "")))
        provider = "debug" if is_debug else "Play Integrity / App Attest"

        details: dict[str, Any] = {
            "provider": provider,
            "issuer": iss,
            "enforced": settings.enforce_app_check,
        }
        if "iat" in claims:
            details["iat"] = claims["iat"]
        if "exp" in claims:
            details["exp"] = claims["exp"]
        if "aud" in claims:
            details["aud"] = claims["aud"]

        return AttestationResponse(
            verified=True,
            appCheck=True,
            appId=app_id,
            timestamp=now_iso,
            details=details,
        )

    return AttestationResponse(
        verified=True,
        appCheck=False,
        appId=None,
        timestamp=now_iso,
        details={
            "provider": "development" if settings.debug else "unverified",
            "issuer": "Nexus Backend (App Check unenforced)",
            "enforced": False,
        },
    )


