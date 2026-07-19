import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Any, cast

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Body,
    Depends,
    Header,
    HTTPException,
    Request,
    status,
)
from postgrest.exceptions import APIError
from starlette.concurrency import run_in_threadpool

from app.api.dependencies import (
    assert_account_active,
    assert_special_category_consent,
    get_active_user_id,
    get_authenticated_user_payload,
    verify_app_check_with_replay_protection,
)
from app.core.account_phone_otp import (
    generate_otp_code,
    hash_otp,
    normalize_phone,
    verify_otp_hash,
)
from app.core.cache import redis_client
from app.core.config import settings
from app.core.crypto import compute_blind_index, encrypt_to_hex
from app.core.email import extract_user_name, send_bootstrap_welcome_email
from app.core.limiter import limiter
from app.core.moderation import NameModerationError, validate_display_name
from app.core.passwordless_email import send_login_email_otp, verify_login_email_otp
from app.core.sms import send_sms
from app.db.client import parse_utc_datetime, supabase_client
from app.db.profiles import (
    decrypt_profile_record,
    sanitize_decrypted_profile,
    sign_profile_media_bulk,
    update_profile_images_and_metadata,
)
from app.db.users import (
    fetch_profile,
    fetch_public_user,
    find_user_id_by_phone,
    get_user_email_by_id,
    is_allowed_email,
    is_disposable_email,
    set_verified_mobile,
    update_safety_data_consent,
    update_special_category_consent,
    update_user_terms,
    upsert_profile_variant,
    upsert_public_user,
)
from app.models import (
    ALLOWED_HIDDEN_FIELDS,
    AccountPhoneOtpRequestRequest,
    AccountPhoneOtpRequestResponse,
    AccountPhoneOtpVerifyRequest,
    AccountPhoneOtpVerifyResponse,
    AuthBootstrapResponse,
    CompleteOnboardingResponse,
    ConsentUpdateRequest,
    ConsentUpdateResponse,
    EmailNotificationSettingsResponse,
    EmailNotificationSettingsUpdate,
    LoginByPhoneRequestRequest,
    LoginByPhoneRequestResponse,
    LoginByPhoneVerifyRequest,
    LoginByPhoneVerifyResponse,
    MECOnboardingRequest,
    ModerationSubjectItem,
    ModerationSubjectsRequest,
    OnboardingPayload,
    PrivacySettingsResponse,
    PrivacySettingsUpdate,
    ProfileDetailsResponse,
    ProfileDetailsUpdate,
    ProfileImagesAndTagsUpdate,
    ProfileUpdateResponse,
)
from app.services.profile import recompile_and_push_vectors
from app.services.value_dimensions import recompile_value_dimensions

_VALUE_DIMENSION_TRIGGER_FIELDS = frozenset(
    {
        "interests",
        "sub_interests",
        "causes_supported",
        "tech_skills",
        "activities",
        "lifestyle",
    },
)

_AGE_CHANGE_WINDOW_DAYS = 365
_AGE_CHANGE_MAX_PER_WINDOW = 2
_NAME_CHANGE_WINDOW_DAYS = 365
_NAME_CHANGE_MAX_PER_WINDOW = 2

logger = logging.getLogger(__name__)

router = APIRouter()


def _is_consent_stale(stored_version: str | None, current_version: str) -> bool:
    """True if a consent category has never been granted, or was granted
    under an older terms version than what's currently required. Used by
    auth_bootstrap to compute mandatory_consent_required.
    """
    if not stored_version:
        return True
    try:
        return float(stored_version) < float(current_version)
    except ValueError:
        return True


async def _validate_auth_user_allowed(
    email: str,
    user_id: str,
    app_variant: str,
) -> None:
    if email:
        is_disposable = await run_in_threadpool(is_disposable_email, email)
        if is_disposable:
            try:
                await run_in_threadpool(supabase_client.auth.admin.delete_user, user_id)
            except Exception as err:  # noqa: BLE001
                logger.error("Failed to delete unauthorized user %s: %s", user_id, err)
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=(
                    "Disposable/temporary email addresses are not allowed. "
                    "Please sign in with a valid email address."
                ),
            )

    is_allowed = await run_in_threadpool(
        is_allowed_email,
        email,
        app_variant=app_variant,
    )
    if email and not is_allowed:
        try:
            await run_in_threadpool(supabase_client.auth.admin.delete_user, user_id)
        except Exception as err:  # noqa: BLE001
            logger.error("Failed to delete unauthorized user %s: %s", user_id, err)
        allowed_domains = settings.allowed_signup_domains.get(app_variant)
        if allowed_domains:
            domain_str = " or ".join(f"@{d.lstrip('@')}" for d in allowed_domains)
            detail_msg = (
                f"Only {domain_str} accounts are allowed for this app variant. "
            )
        else:
            detail_msg = "Only approved accounts are allowed for this app variant. "

        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"{detail_msg}"
                "Please sign in with your campus Google Workspace account."
            ),
        )


@router.post("/api/v1/auth/bootstrap", response_model=AuthBootstrapResponse)
@limiter.limit(settings.rate_limit_auth)
async def auth_bootstrap(
    request: Request,
    background_tasks: BackgroundTasks,
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user: dict[str, Any] = Depends(get_authenticated_user_payload),  # noqa: B008
    x_app_variant: str | None = Header(None, alias="X-App-Variant"),
):
    _ = request

    user_id = str(auth_user.get("id") or "").strip()
    email = str(auth_user.get("email") or "").strip().lower()
    phone = str(auth_user.get("phone") or "").strip()

    if not user_id or (not email and not phone):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user payload is incomplete.",
        )

    app_variant = (x_app_variant or "nexus").strip().lower()
    if app_variant not in ("nexus", "nexus_mec"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unrecognized X-App-Variant header value.",
        )

    await _validate_auth_user_allowed(email, user_id, app_variant)

    user_row, newly_created = await run_in_threadpool(
        upsert_public_user,
        user_id=user_id,
        app_variant=app_variant,
    )

    # A pending-deletion account must still be able to bootstrap far enough
    # to reach the Reactivate screen, even if it's also suspended/banned -
    # skip assert_account_active entirely in that case rather than teaching
    # it a deletion-aware exception. Every other call site keeps enforcing
    # it unmodified.
    deletion_requested_at = user_row.get("deletion_requested_at")
    if not deletion_requested_at:
        assert_account_active(user_row)

    if newly_created and email:
        background_tasks.add_task(
            send_bootstrap_welcome_email,
            email=email,
            auth_user=auth_user,
            app_variant=app_variant,
        )

    current_version = settings.current_terms_version.strip()
    mandatory_consent_required = _is_consent_stale(
        user_row.get("accepted_terms_version"), current_version,
    )
    special_category_consent_granted = not _is_consent_stale(
        user_row.get("special_category_consent_version"), current_version,
    )
    safety_data_consent_granted = not _is_consent_stale(
        user_row.get("safety_data_consent_version"), current_version,
    )

    return AuthBootstrapResponse(
        user_id=str(user_row["id"]),
        email=email if email else None,
        is_active=bool(user_row.get("is_active", True)),
        is_suspended=bool(user_row.get("is_suspended", False)),
        moderation_status=str(user_row.get("moderation_status") or "clear"),
        accepted_terms_version=user_row.get("accepted_terms_version"),
        terms_accepted_at=user_row.get("terms_accepted_at"),
        newly_created=newly_created,
        mobile=user_row.get("mobile"),
        mobile_verified_at=user_row.get("mobile_verified_at"),
        deletion_pending=bool(deletion_requested_at),
        scheduled_purge_at=user_row.get("scheduled_purge_at"),
        current_terms_version=current_version,
        special_category_consent_version=user_row.get("special_category_consent_version"),
        special_category_consent_at=user_row.get("special_category_consent_at"),
        safety_data_consent_version=user_row.get("safety_data_consent_version"),
        safety_data_consent_at=user_row.get("safety_data_consent_at"),
        mandatory_consent_required=mandatory_consent_required,
        special_category_consent_granted=special_category_consent_granted,
        safety_data_consent_granted=safety_data_consent_granted,
    )


@router.post(
    "/api/v1/auth/complete-onboarding",
    response_model=CompleteOnboardingResponse,
)
@limiter.limit(settings.rate_limit_auth)
def complete_onboarding(
    request: Request,
    payload: OnboardingPayload = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user: dict[str, Any] = Depends(get_authenticated_user_payload),  # noqa: B008
):
    """
    Complete the onboarding flow.

    Accepts a discriminated union payload keyed on `app_variant`:
      - 'nexus'     → NexusOnboardingRequest  (dating_intent, hobbies)
      - 'nexus_mec' → MECOnboardingRequest    (major, grad_year, campus_clubs)

    Common fields (branch, year, age, name) are stored directly on the profile.
    Variant-specific fields are stored in the variant_metadata JSONB column.
    """
    _ = request

    user_id = str(auth_user.get("id") or "").strip()
    email_raw = auth_user.get("email")
    email = str(email_raw).strip().lower() if email_raw else None

    if not user_id or (not email and not auth_user.get("phone")):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user payload is incomplete.",
        )

    user_row = fetch_public_user(user_id)
    if not user_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User bootstrap row not found. Complete bootstrap first.",
        )

    assert_account_active(user_row)

    if fetch_profile(user_id) is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Onboarding has already been completed.",
        )

    # Resolve name and variant-specific fields per flavor.
    if isinstance(payload, MECOnboardingRequest):
        # MEC: name is derived server-side from Google OAuth metadata.
        if not email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email is required for campus MEC onboarding.",
            )
        user_name = extract_user_name(email, auth_user)
        user_branch: str | None = payload.campus_branch
        user_year: int | None = payload.campus_year
        user_campus_name: str | None = payload.campus_name
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
        user_campus_name = cleaned_campus
        user_demographic_bucket = None
    else:
        # NexusOnboardingRequest: name and demographic_bucket are in the
        # payload.
        user_name = payload.name
        user_branch = None
        user_year = None
        user_campus_name = None
        user_demographic_bucket: str | None = payload.demographic_bucket

    profile_row, profile_created = upsert_profile_variant(
        user_id=user_id,
        name=user_name,
        campus_branch=user_branch,
        campus_year=user_year,
        age=payload.age,
        campus_name=user_campus_name,
        demographic_bucket=user_demographic_bucket,
    )

    # Terms/consent is deliberately not collected here - onboarding creates
    # the profile only. TermsConsentPage (a separate, dedicated step on the
    # client) records consent via /api/v1/auth/accept-terms right after.
    return CompleteOnboardingResponse(
        user_id=user_id,
        profile_created=profile_created,
        profile=profile_row,
    )


# ---------------------------------------------------------------------------
# Account phone verification - independent of Supabase Auth's Phone provider
# (disabled - it doubled as a login credential with no way to keep
# verification without also keeping phone-based sign-in). Mirrors the
# HMAC-hash-not-store OTP pattern already proven in app/api/safety_portal.py,
# but authenticated and keyed by user_id instead of an anonymous session_id.
# ---------------------------------------------------------------------------

_ACCOUNT_PHONE_OTP_TTL_SECONDS = 600
_ACCOUNT_PHONE_OTP_MAX_ATTEMPTS = 5
_ACCOUNT_PHONE_OTP_RESEND_COOLDOWN_SECONDS = 60


def _account_otp_key(user_id: str) -> str:
    return f"account_phone_otp:otp:{user_id}"


def _account_otp_attempts_key(user_id: str) -> str:
    return f"account_phone_otp:attempts:{user_id}"


def _account_otp_resend_key(user_id: str) -> str:
    return f"account_phone_otp:resend:{user_id}"


@router.post(
    "/api/v1/user/phone/otp/request",
    response_model=AccountPhoneOtpRequestResponse,
)
@limiter.limit(settings.rate_limit_account_phone_otp)
async def request_account_phone_otp(
    request: Request,
    payload: AccountPhoneOtpRequestRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user: dict[str, Any] = Depends(get_authenticated_user_payload),  # noqa: B008
) -> AccountPhoneOtpRequestResponse:
    _ = request
    user_id = str(auth_user.get("id") or "").strip()
    phone_norm = normalize_phone(payload.phone)

    resend_key = _account_otp_resend_key(user_id)
    if await redis_client.exists(resend_key):
        raise HTTPException(
            status_code=429,
            detail="Please wait a bit before requesting another code.",
        )
    await redis_client.set(
        resend_key, "1", ex=_ACCOUNT_PHONE_OTP_RESEND_COOLDOWN_SECONDS, nx=True,
    )

    code = generate_otp_code()
    await redis_client.setex(
        _account_otp_key(user_id),
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
    payload: AccountPhoneOtpVerifyRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user: dict[str, Any] = Depends(get_authenticated_user_payload),  # noqa: B008
) -> AccountPhoneOtpVerifyResponse:
    _ = request
    user_id = str(auth_user.get("id") or "").strip()
    phone_norm = normalize_phone(payload.phone)

    attempts_key = _account_otp_attempts_key(user_id)
    attempts = await redis_client.get(attempts_key)
    if attempts and int(attempts) >= _ACCOUNT_PHONE_OTP_MAX_ATTEMPTS:
        raise HTTPException(
            status_code=429,
            detail="Too many incorrect attempts. Please request a new code.",
        )

    otp_key = _account_otp_key(user_id)
    stored_hash = await redis_client.get(otp_key)
    if not stored_hash:
        raise HTTPException(
            status_code=400,
            detail="That code has expired or was never requested. Request a new one.",
        )

    if not verify_otp_hash(user_id, phone_norm, payload.code, cast(str, stored_hash)):
        await redis_client.incr(attempts_key)
        await redis_client.expire(attempts_key, _ACCOUNT_PHONE_OTP_TTL_SECONDS)
        raise HTTPException(status_code=400, detail="Incorrect code.")

    await redis_client.delete(otp_key)
    await redis_client.delete(attempts_key)

    await run_in_threadpool(set_verified_mobile, user_id, phone_norm)

    return AccountPhoneOtpVerifyResponse(
        verified=True,
        mobile=phone_norm,
        mobile_verified_at=datetime.now(timezone.utc),
    )


# ---------------------------------------------------------------------------
# Phone-as-username login. Phone is only ever a lookup key here - the code
# is always emailed to the resolved account's verified address, never sent
# via SMS, so this can't be used to sign in as someone via SIM-swap/phone
# takeover the way the old Supabase-native "Sign in with Phone" could.
# Unauthenticated (this IS the sign-in step), so App Check is the gate
# instead of a user JWT.
# ---------------------------------------------------------------------------

_LOGIN_BY_PHONE_RESEND_COOLDOWN_SECONDS = 60


def _login_by_phone_resend_key(phone_norm: str) -> str:
    return f"login_by_phone:resend:{phone_norm}"


@router.post(
    "/api/v1/auth/login-by-phone/request",
    response_model=LoginByPhoneRequestResponse,
)
@limiter.limit(settings.rate_limit_login_by_phone)
async def request_login_by_phone(
    request: Request,
    payload: LoginByPhoneRequestRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_with_replay_protection),
) -> LoginByPhoneRequestResponse:
    _ = request
    phone_norm = normalize_phone(payload.phone)

    resend_key = _login_by_phone_resend_key(phone_norm)
    if await redis_client.exists(resend_key):
        raise HTTPException(
            status_code=429,
            detail="Please wait a bit before requesting another code.",
        )
    await redis_client.set(
        resend_key, "1", ex=_LOGIN_BY_PHONE_RESEND_COOLDOWN_SECONDS, nx=True,
    )

    user_id = await run_in_threadpool(find_user_id_by_phone, phone_norm)
    exists = False
    if user_id is not None:
        email = await run_in_threadpool(get_user_email_by_id, user_id)
        if email:
            await run_in_threadpool(send_login_email_otp, email)
            exists = True

    # Always the same response, whether or not the phone matched an
    # account - see LoginByPhoneRequestResponse's docstring.
    return LoginByPhoneRequestResponse(sent=exists, exists=exists)


@router.post(
    "/api/v1/auth/login-by-phone/verify",
    response_model=LoginByPhoneVerifyResponse,
)
@limiter.limit(settings.rate_limit_login_by_phone)
async def verify_login_by_phone(
    request: Request,
    payload: LoginByPhoneVerifyRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_with_replay_protection),
) -> LoginByPhoneVerifyResponse:
    _ = request
    phone_norm = normalize_phone(payload.phone)

    user_id = await run_in_threadpool(find_user_id_by_phone, phone_norm)
    email = await run_in_threadpool(get_user_email_by_id, user_id) if user_id else None
    if not email:
        raise HTTPException(status_code=400, detail="Invalid or expired code.")

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
        access_token=session.access_token,
        refresh_token=session.refresh_token,
        expires_in=session.expires_in,
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
def accept_terms(
    request: Request,
    payload: ConsentUpdateRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user: dict[str, Any] = Depends(get_authenticated_user_payload),  # noqa: B008
):
    """Records the itemized consents shown on TermsConsentPage. Only
    general is mandatory - a decline is still logged (via the granted=False
    path in update_user_terms) before this 400s, so decline events stay
    auditable in terms_consent_log even though the request fails.
    special_category and safety_data are both optional and independently
    togglable; omitting either (None) leaves that category unchanged rather
    than declining it.
    """
    _ = request

    user_id = str(auth_user.get("id") or "").strip()
    email = str(auth_user.get("email") or "").strip().lower()
    phone = str(auth_user.get("phone") or "").strip()

    if not user_id or (not email and not phone):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user payload is incomplete.",
        )

    user_row = fetch_public_user(user_id)
    if not user_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User bootstrap row not found. Complete bootstrap first.",
        )

    assert_account_active(user_row)

    general_result = update_user_terms(
        user_id=user_id,
        accepted_terms_version=payload.terms_version,
        granted=payload.general_accepted,
    )

    if not payload.general_accepted:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "General Terms of Service & Privacy Policy consent is "
                "required to use Nexus. Your decline has been recorded."
            ),
        )

    special_result = None
    if payload.special_category_accepted is not None:
        special_result = update_special_category_consent(
            user_id=user_id,
            terms_version=payload.terms_version,
            granted=payload.special_category_accepted,
        )
        if payload.special_category_accepted:
            _unhide_special_category_fields(user_id)

    safety_result = None
    if payload.safety_data_accepted is not None:
        safety_result = update_safety_data_consent(
            user_id=user_id,
            terms_version=payload.terms_version,
            granted=payload.safety_data_accepted,
        )

    return ConsentUpdateResponse(
        user_id=user_id,
        accepted_terms_version=general_result[0] if general_result else None,
        terms_accepted_at=general_result[1] if general_result else None,
        special_category_consent_version=special_result[0] if special_result else None,
        special_category_consent_at=special_result[1] if special_result else None,
        safety_data_consent_version=safety_result[0] if safety_result else None,
        safety_data_consent_at=safety_result[1] if safety_result else None,
    )


@router.post("/api/v1/profile/media", status_code=status.HTTP_200_OK)
@limiter.limit("5/minute")
async def update_profile_media_and_tags(
    request: Request,
    payload: ProfileImagesAndTagsUpdate = Body(...),  # noqa: B008
    user_id: str = Depends(get_active_user_id),
    _device: None = Depends(verify_app_check_with_replay_protection),
):
    _ = request
    try:
        await update_profile_images_and_metadata(
            user_id=user_id,
            images=[payload.profile_pic, *payload.normal_pics],
            vibe_tags=payload.ai_vibe_tags,
        )
        return {"status": "success", "detail": "Profile media synchronized."}
    except ValueError as err:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=(
                "Target account context mismatch. Profile row modification rejected."
            ),
        ) from err
    except Exception as e:
        logger.exception("Profile media update failed for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server metadata pipeline error: Data synchronization failed.",
        ) from e


def _assert_no_decryption_failures(profile: dict[str, Any]) -> None:
    for val in profile.values():
        if (
            val == "__DECRYPTION_FAILED__"
            or val == ["__DECRYPTION_FAILED__"]
            or val == {"__DECRYPTION_FAILED__": True}
        ):
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    "Profile decryption failed due to data corruption or key mismatch."
                ),
            )


def _rolling_change_window_status(
    table: str,
    user_id: str,
    window_days: int,
    max_changes: int,
) -> tuple[int, bool, datetime | None]:
    """Return (used_count, eligible, next_eligible_at) for a rolling-window
    change-log table (profile_name_change_log / profile_age_change_log).

    Shared by both the GET (informational) and PATCH (enforcement) paths
    for age and name, so the count/eligibility math only lives in one place.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=window_days)
    try:
        res = (
            supabase_client.table(table)
            .select("changed_at")
            .eq("user_id", user_id)
            .gte("changed_at", cutoff.isoformat())
            .order("changed_at")
            .execute()
        )
    except Exception as e:
        logger.exception(
            "Failed to check rolling change-window eligibility",
            extra={"user_id": user_id, "table": table},
        )
        raise HTTPException(
            status_code=500,
            detail="Internal server error.",
        ) from e

    rows = cast("list[dict[str, Any]]", getattr(res, "data", None) or [])
    used = len(rows)
    eligible = used < max_changes
    next_eligible = (
        parse_utc_datetime(rows[0]["changed_at"]) + timedelta(days=window_days)
        if not eligible
        else None
    )
    return used, eligible, next_eligible


def _build_ordered_images(profile: dict[str, Any]) -> list[str]:
    profile_pic = profile.get("profile_pic")
    normal_pics = profile.get("normal_pics")
    ordered_images: list[str] = []
    if profile_pic and isinstance(profile_pic, str) and profile_pic.strip():
        ordered_images.append(profile_pic)
    if isinstance(normal_pics, list):
        for p in cast(list[object], normal_pics):
            if isinstance(p, str) and p.strip():
                ordered_images.append(p)
    return ordered_images


@router.get("/api/v1/profile/details", response_model=ProfileDetailsResponse)
def get_profile_details(
    user_id: str = Depends(get_active_user_id),
) -> dict[str, Any]:
    try:
        select_cols = (
            "id, name, age, campus_year, campus_branch, campus_name, "
            "display_gender, display_sexuality, pronouns, bio, search_bucket, "
            "hometown, current_place, partner_values, children_plans, "
            "religious_beliefs, lifestyle, drinking, smoking, role_at, "
            "role_type, dating_target_buckets, dating_for, friends_target_buckets, "
            "professional_target_buckets, looking_for, activities, "
            "causes_supported, top_artists, tech_skills, languages, "
            "pets, interests, sub_interests, profile_pic, normal_pics, "
            "ai_vibe_tags, is_dating_active, is_friends_active, "
            "is_professional_active"
        )
        res = (
            supabase_client.table("profiles")
            .select(select_cols)
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        data = getattr(res, "data", None)
        if data is None:
            raise HTTPException(status_code=404, detail="Profile not found")

        if not isinstance(data, dict):
            raise HTTPException(
                status_code=500,
                detail="Invalid profile data structure",
            )

        profile = decrypt_profile_record(cast(dict[str, Any], data))

        # Check if any field failed decryption
        _assert_no_decryption_failures(profile)

        ordered_images = _build_ordered_images(profile)

        age_changes_used_in_window, age_change_eligible, age_next_eligible_dt = (
            _rolling_change_window_status(
                "profile_age_change_log",
                user_id,
                _AGE_CHANGE_WINDOW_DAYS,
                _AGE_CHANGE_MAX_PER_WINDOW,
            )
        )
        (
            name_changes_used_in_window,
            name_change_eligible,
            name_next_eligible_dt,
        ) = _rolling_change_window_status(
            "profile_name_change_log",
            user_id,
            _NAME_CHANGE_WINDOW_DAYS,
            _NAME_CHANGE_MAX_PER_WINDOW,
        )

        return {
            "name": profile.get("name"),
            "age": profile.get("age"),
            "campus_year": profile.get("campus_year"),
            "campus_branch": profile.get("campus_branch"),
            "campus_name": profile.get("campus_name"),
            "display_gender": profile.get("display_gender"),
            "display_sexuality": profile.get("display_sexuality"),
            "pronouns": profile.get("pronouns"),
            "bio": profile.get("bio") or "",
            "search_bucket": profile.get("search_bucket") or "NB",
            "hometown": profile.get("hometown"),
            "current_place": profile.get("current_place"),
            "partner_values": profile.get("partner_values"),
            "children_plans": profile.get("children_plans"),
            "religious_beliefs": profile.get("religious_beliefs"),
            "lifestyle": profile.get("lifestyle"),
            "drinking": profile.get("drinking"),
            "smoking": profile.get("smoking"),
            "role_at": profile.get("role_at"),
            "role_type": profile.get("role_type") or [],
            "dating_target_buckets": profile.get("dating_target_buckets") or [],
            "dating_for": profile.get("dating_for") or [],
            "friends_target_buckets": profile.get("friends_target_buckets") or [],
            "professional_target_buckets": (
                profile.get("professional_target_buckets") or []
            ),
            "looking_for": profile.get("looking_for") or [],
            "activities": profile.get("activities") or [],
            "causes_supported": profile.get("causes_supported") or [],
            "top_artists": profile.get("top_artists") or [],
            "tech_skills": profile.get("tech_skills") or [],
            "languages": profile.get("languages") or [],
            "pets": profile.get("pets") or [],
            "interests": profile.get("interests") or {},
            "sub_interests": profile.get("sub_interests") or {},
            "ordered_images": ordered_images,
            "ai_vibe_tags": profile.get("ai_vibe_tags") or [],
            "is_dating_active": bool(profile.get("is_dating_active", False)),
            "is_friends_active": bool(profile.get("is_friends_active", False)),
            "is_professional_active": bool(
                profile.get("is_professional_active", False),
            ),
            "age_changes_used_in_window": age_changes_used_in_window,
            "age_change_eligible": age_change_eligible,
            "age_next_eligible_at": (
                age_next_eligible_dt.isoformat() if age_next_eligible_dt else None
            ),
            "name_changes_used_in_window": name_changes_used_in_window,
            "name_change_eligible": name_change_eligible,
            "name_next_eligible_at": (
                name_next_eligible_dt.isoformat() if name_next_eligible_dt else None
            ),
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to get profile details")
        raise HTTPException(
            status_code=500,
            detail="Internal server error.",
        ) from e


@router.post(
    "/api/v1/users/moderation-subjects",
    response_model=list[ModerationSubjectItem],
)
def get_moderation_subjects(
    payload: ModerationSubjectsRequest = Body(...),  # noqa: B008
    user_id: str = Depends(get_active_user_id),
) -> list[dict[str, Any]]:
    """
    Returns basic decrypted profile info for users the caller has actively
    blocked or hidden.

    Validates each requested target_id against profile_discovery_actions
    before returning data.
    """
    try:
        validated_res = (
            supabase_client.table("profile_discovery_actions")
            .select("target_id")
            .eq("actor_id", user_id)
            .in_("target_id", payload.target_ids)
            .in_("action", ["block", "hide"])
            .is_("revoked_at", "null")
            .execute()
        )
        valid_ids: list[str] = list(
            {
                row["target_id"]
                for row in cast(
                    list[dict[str, Any]],
                    validated_res.data or [],
                )
            },
        )
        if not valid_ids:
            return []

        profiles_res = (
            supabase_client.table("profiles")
            .select(
                "id, name, age, campus_year, campus_name, campus_branch, "
                "hometown, current_place, profile_pic",
            )
            .in_("id", valid_ids)
            .execute()
        )

        results: list[dict[str, Any]] = []
        for row in cast(list[dict[str, Any]], profiles_res.data or []):
            try:
                decrypted = decrypt_profile_record(dict(row))
                decrypted = sanitize_decrypted_profile(decrypted)
            except Exception:  # noqa: BLE001
                decrypted = sanitize_decrypted_profile(dict(row))
            results.append(
                {
                    "id": decrypted.get("id"),
                    "name": decrypted.get("name"),
                    "age": decrypted.get("age"),
                    "campus_year": decrypted.get("campus_year"),
                    "campus_name": decrypted.get("campus_name"),
                    "campus_branch": decrypted.get("campus_branch"),
                    "hometown": decrypted.get("hometown"),
                    "current_place": decrypted.get("current_place"),
                    "profile_pic": decrypted.get("profile_pic"),
                },
            )
        sign_profile_media_bulk(results)
        return results
    except Exception as e:
        logger.exception("Failed to fetch moderation subjects")
        raise HTTPException(status_code=500, detail="Internal server error.") from e


def _resolve_field(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    field_name: str,
) -> Any:
    payload_val = getattr(payload, field_name, None)
    return payload_val if payload_val is not None else profile.get(field_name)


def _validate_common_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_name = _resolve_field(profile, payload, "name")
    val_age = _resolve_field(profile, payload, "age")
    val_sub_interests = _resolve_field(profile, payload, "sub_interests")
    val_profile_pic = _resolve_field(profile, payload, "profile_pic")
    val_normal_pics = _resolve_field(profile, payload, "normal_pics")
    val_bio = _resolve_field(profile, payload, "bio")

    if not isinstance(val_name, str) or not val_name.strip():
        missing.append("name")
    if val_age is None:
        missing.append("age")

    sub_count = (
        sum(len(v) for v in cast(dict[str, list[str]], val_sub_interests).values())
        if isinstance(val_sub_interests, dict)
        else 0
    )
    if val_sub_interests != {"__DECRYPTION_FAILED__": True} and sub_count < 2:
        missing.append("interests")
    if val_profile_pic != "__DECRYPTION_FAILED__" and (
        not isinstance(val_profile_pic, str) or not val_profile_pic.strip()
    ):
        missing.append("profile_pic")
    if val_normal_pics != ["__DECRYPTION_FAILED__"] and (
        not isinstance(val_normal_pics, list)
        or len(cast(list[Any], val_normal_pics)) < 1
    ):
        missing.append("normal_pics")
    if val_bio == "__DECRYPTION_FAILED__":
        pass
    else:
        if not isinstance(val_bio, str) or sum(c.isalpha() for c in val_bio) < 3:
            missing.append("bio")


def _validate_dating_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_drinking = _resolve_field(profile, payload, "drinking")
    val_smoking = _resolve_field(profile, payload, "smoking")
    val_dating_target_buckets = _resolve_field(
        profile,
        payload,
        "dating_target_buckets",
    )
    val_dating_for = _resolve_field(profile, payload, "dating_for")
    val_partner_values = _resolve_field(profile, payload, "partner_values")

    if not isinstance(val_drinking, str) or not val_drinking.strip():
        missing.append("drinking")
    if not isinstance(val_smoking, str) or not val_smoking.strip():
        missing.append("smoking")
    if (
        not isinstance(val_dating_target_buckets, list)
        or len(cast(list[Any], val_dating_target_buckets)) < 1
    ):
        missing.append("dating_target_buckets")
    if not isinstance(val_dating_for, list) or len(cast(list[Any], val_dating_for)) < 1:
        missing.append("dating_for")
    if (
        not isinstance(val_partner_values, list)
        or len(cast(list[Any], val_partner_values)) < 1
    ):
        missing.append("partner_values")


def _validate_friends_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_friends_target_buckets = _resolve_field(
        profile,
        payload,
        "friends_target_buckets",
    )
    val_sub_interests = _resolve_field(profile, payload, "sub_interests")
    val_causes_supported = _resolve_field(profile, payload, "causes_supported")

    if (
        not isinstance(val_friends_target_buckets, list)
        or len(cast(list[Any], val_friends_target_buckets)) < 1
    ):
        missing.append("friends_target_buckets")
    sub_count = (
        sum(len(v) for v in cast(dict[str, list[str]], val_sub_interests).values())
        if isinstance(val_sub_interests, dict)
        else 0
    )
    if sub_count < 2:
        missing.append("sub_interests")
    if (
        not isinstance(val_causes_supported, list)
        or len(cast(list[Any], val_causes_supported)) < 1
    ):
        missing.append("causes_supported")


def _validate_professional_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_professional_target_buckets = _resolve_field(
        profile,
        payload,
        "professional_target_buckets",
    )
    val_looking_for = _resolve_field(profile, payload, "looking_for")
    val_tech_skills = _resolve_field(profile, payload, "tech_skills")

    if (
        not isinstance(val_professional_target_buckets, list)
        or len(cast(list[Any], val_professional_target_buckets)) < 1
    ):
        missing.append("professional_target_buckets")
    if (
        not isinstance(val_looking_for, list)
        or len(cast(list[Any], val_looking_for)) < 1
    ):
        missing.append("looking_for")
    if (
        not isinstance(val_tech_skills, list)
        or len(cast(list[Any], val_tech_skills)) < 1
    ):
        missing.append("tech_skills")


def _validate_tab_activation(
    tab_name: str,
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
) -> list[str]:
    """
    Validates required profile fields for activating a specific tab.
    Supports 'Dating', 'Friends', or 'Professional'.
    """
    missing: list[str] = []
    _validate_common_activation(profile, payload, missing)

    if tab_name == "Dating":
        _validate_dating_activation(profile, payload, missing)
    elif tab_name == "Friends":
        _validate_friends_activation(profile, payload, missing)
    elif tab_name == "Professional":
        _validate_professional_activation(profile, payload, missing)

    return missing


# The "I don't want to say" choice within each field's own choice set -
# selecting these is a decline, not a disclosure, so it never requires
# special-category consent (only actually disclosing a real value does).
_SPECIAL_CATEGORY_OPT_OUT_VALUES = {
    "display_sexuality": "Prefer not to say",
    "religious_beliefs": "Prefer not to say",
}


def _sets_special_category_data(payload: ProfileDetailsUpdate) -> bool:
    return any(
        (val := getattr(payload, field, None)) is not None and val != opt_out
        for field, opt_out in _SPECIAL_CATEGORY_OPT_OUT_VALUES.items()
    )


@router.patch("/api/v1/profile/details", response_model=ProfileUpdateResponse)
def update_profile_details(  # noqa: C901
    background_tasks: BackgroundTasks,
    payload: ProfileDetailsUpdate = Body(...),  # noqa: B008
    user_id: str = Depends(get_active_user_id),
    _device: None = Depends(verify_app_check_with_replay_protection),
) -> dict[str, Any]:
    # Sexual orientation / religious belief are optional profile fields, but
    # DPDP/GDPR ask for separate, explicit consent before we accept a real
    # disclosed value for either - see TermsConsentPage's now-optional third
    # checkbox. Declining that consent doesn't block the rest of the profile,
    # only these two fields (and only when actually setting them, not when
    # picking the "prefer not to say"/"not specified" opt-out).
    if _sets_special_category_data(payload):
        consent_user_row = fetch_public_user(user_id)
        if not consent_user_row:
            raise HTTPException(
                status_code=404,
                detail="User bootstrap row not found.",
            )
        assert_special_category_consent(consent_user_row)

    # Fetch existing campus fields if campus_year or campus_name are affected by
    # the payload.
    if "campus_year" in payload.model_fields_set or payload.campus_name is not None:
        try:
            campus_res = (
                supabase_client.table("profiles")
                .select("campus_name, campus_year")
                .eq("id", user_id)
                .maybe_single()
                .execute()
            )
            campus_data = cast(
                dict[str, Any],
                getattr(campus_res, "data", None) or {},
            )
            decrypted_campus = decrypt_profile_record(campus_data)
            existing_campus_name = decrypted_campus.get("campus_name")
            existing_campus_year = decrypted_campus.get("campus_year")
        except Exception as e:
            logger.exception("Failed to fetch current profile for campus validation")
            raise HTTPException(
                status_code=500,
                detail="Internal server error during campus validation.",
            ) from e

        # Determine the final/incoming values after this update
        incoming_campus_name = (
            payload.campus_name.strip()
            if payload.campus_name is not None
            else (existing_campus_name or "")
        )

        incoming_campus_year = (
            payload.campus_year
            if "campus_year" in payload.model_fields_set
            else existing_campus_year
        )

        # Validate that if the final campus_name is not empty, it contains at
        # least three alphabetic characters.
        if incoming_campus_name and incoming_campus_name != "__DECRYPTION_FAILED__":
            letters_count = sum(c.isalpha() for c in incoming_campus_name)
            if letters_count < 3:
                raise HTTPException(
                    status_code=400,
                    detail="Institute name must contain at least three letters.",
                )

        # Restrict adding/keeping campus_year if campus_name is empty
        is_empty_or_failed = (
            not incoming_campus_name
            or not incoming_campus_name.strip()
            or incoming_campus_name == "__DECRYPTION_FAILED__"
        )
        if incoming_campus_year is not None and is_empty_or_failed:
            raise HTTPException(
                status_code=400,
                detail="Cannot select a campus year when institute is empty.",
            )

    update_data: dict[str, Any] = {}

    # Resolve to the current stored name/age before running any moderation
    # or rate-limit checks, so a resubmission of the *same* value (e.g. the
    # Display Name field firing its blur callback with unchanged text) is a
    # silent no-op instead of burning one of the limited change slots.
    new_name: str | None = None
    new_age: int | None = None
    if payload.name is not None or payload.age is not None:
        try:
            identity_res = (
                supabase_client.table("profiles")
                .select("name, age")
                .eq("id", user_id)
                .maybe_single()
                .execute()
            )
        except Exception as e:
            logger.exception(
                "Failed to fetch current name/age for change comparison",
                extra={"user_id": user_id},
            )
            raise HTTPException(
                status_code=500,
                detail="Internal server error.",
            ) from e

        identity_data = cast(
            "dict[str, Any]",
            getattr(identity_res, "data", None) or {},
        )

        if payload.name is not None:
            candidate_name = payload.name.strip()
            current_name = cast("str | None", identity_data.get("name"))
            if candidate_name != current_name:
                new_name = candidate_name
                try:
                    validate_display_name(new_name)
                except NameModerationError as e:
                    raise HTTPException(status_code=422, detail=e.detail) from e

                _, name_eligible, name_next_eligible = _rolling_change_window_status(
                    "profile_name_change_log",
                    user_id,
                    _NAME_CHANGE_WINDOW_DAYS,
                    _NAME_CHANGE_MAX_PER_WINDOW,
                )
                if not name_eligible:
                    if name_next_eligible is None:
                        name_next_eligible = datetime.now(timezone.utc)
                    raise HTTPException(
                        status_code=403,
                        detail=(
                            "You've used both name changes allowed this year. "
                            f"You can change your name again on "
                            f"{name_next_eligible:%B %d, %Y}."
                        ),
                    )

        if payload.age is not None:
            current_age = cast("int | None", identity_data.get("age"))
            if payload.age != current_age:
                # Variant-aware range check: ProfileDetailsUpdate.age allows
                # the union bound (18-80) since Pydantic has no per-request
                # variant context, so the real per-variant bound (18-80 for
                # nexus, 18-27 for everything else, matching
                # NexusOnboardingRequest/MECOnboardingRequest) is enforced
                # here against the account's real app_variant - never a
                # client-supplied one. A DB trigger backs this up (see
                # 20260803000000_widen_profile_age_range.sql), but this is
                # the primary check, so a bad value gets a clean 400 instead
                # of falling through to the RPC's generic 500 path.
                caller_row = fetch_public_user(user_id)
                caller_variant = (caller_row or {}).get("app_variant") or "nexus"
                max_age = 80 if caller_variant == "nexus" else 27
                if payload.age > max_age:
                    raise HTTPException(
                        status_code=400,
                        detail=(
                            f"Age must be between 18 and {max_age} for "
                            "your account type."
                        ),
                    )
                new_age = payload.age
                _, age_eligible, age_next_eligible = _rolling_change_window_status(
                    "profile_age_change_log",
                    user_id,
                    _AGE_CHANGE_WINDOW_DAYS,
                    _AGE_CHANGE_MAX_PER_WINDOW,
                )
                if not age_eligible:
                    if age_next_eligible is None:
                        age_next_eligible = datetime.now(timezone.utc)
                    raise HTTPException(
                        status_code=403,
                        detail=(
                            "You've used both age changes allowed this year. "
                            f"You can change your age again on "
                            f"{age_next_eligible:%B %d, %Y}."
                        ),
                    )

    if payload.campus_branch is not None:
        update_data["campus_branch"] = encrypt_to_hex(payload.campus_branch.strip())
        update_data["campus_branch_blind_index"] = compute_blind_index(
            payload.campus_branch,
        )
    if "campus_year" in payload.model_fields_set:
        update_data["campus_year"] = payload.campus_year
    if payload.campus_name is not None:
        update_data["campus_name"] = encrypt_to_hex(payload.campus_name.strip())
    if payload.search_bucket is not None:
        update_data["search_bucket"] = payload.search_bucket
    if payload.dating_target_buckets is not None:
        update_data["dating_target_buckets"] = payload.dating_target_buckets
    if payload.dating_for is not None:
        update_data["dating_for"] = payload.dating_for
    if payload.friends_target_buckets is not None:
        update_data["friends_target_buckets"] = payload.friends_target_buckets
    if payload.professional_target_buckets is not None:
        update_data["professional_target_buckets"] = payload.professional_target_buckets

    scalar_fields = [
        "display_gender",
        "display_sexuality",
        "pronouns",
        "bio",
        "hometown",
        "current_place",
        "children_plans",
        "religious_beliefs",
        "lifestyle",
        "drinking",
        "smoking",
        "role_at",
    ]
    for field in scalar_fields:
        val = getattr(payload, field, None)
        if val is not None:
            update_data[field] = encrypt_to_hex(val)

    if payload.profile_pic is not None:
        update_data["profile_pic"] = encrypt_to_hex(payload.profile_pic)
    if payload.normal_pics is not None:
        update_data["normal_pics"] = encrypt_to_hex(json.dumps(payload.normal_pics))

    if payload.drinking is not None:
        update_data["drinking_blind_index"] = compute_blind_index(payload.drinking)
    if payload.smoking is not None:
        update_data["smoking_blind_index"] = compute_blind_index(payload.smoking)
    if payload.children_plans is not None:
        update_data["children_plans_blind_index"] = compute_blind_index(
            payload.children_plans,
        )
    if payload.religious_beliefs is not None:
        update_data["religious_beliefs_blind_index"] = compute_blind_index(
            payload.religious_beliefs,
        )

    array_fields = [
        "looking_for",
        "activities",
        "causes_supported",
        "top_artists",
        "tech_skills",
        "languages",
        "pets",
        "role_type",
        "partner_values",
    ]
    for field in array_fields:
        val = getattr(payload, field, None)
        if val is not None:
            update_data[field] = encrypt_to_hex(json.dumps(val))

    for field in ("interests", "sub_interests"):
        val = getattr(payload, field, None)
        if val is not None:
            update_data[field] = encrypt_to_hex(json.dumps(val))

    need_profile_fetch = (
        (payload.is_dating_active is True)
        or (payload.is_friends_active is True)
        or (payload.is_professional_active is True)
        or (payload.bio is not None)
    )
    profile = None
    if need_profile_fetch:
        profile_res = (
            supabase_client.table("profiles")
            .select(
                "name,age,profile_pic,normal_pics,interests,sub_interests,"
                "drinking,smoking,partner_values,dating_target_buckets,dating_for,"
                "friends_target_buckets,causes_supported,"
                "professional_target_buckets,looking_for,tech_skills,"
                "bio,is_dating_active,is_friends_active,is_professional_active",
            )
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        profile_data = getattr(profile_res, "data", None)
        if not profile_data or not isinstance(profile_data, dict):
            raise HTTPException(status_code=404, detail="Profile not found")
        profile = decrypt_profile_record(cast(dict[str, Any], profile_data))

    if profile is not None:
        dating_active = (
            payload.is_dating_active
            if payload.is_dating_active is not None
            else profile.get("is_dating_active", False)
        )
        friends_active = (
            payload.is_friends_active
            if payload.is_friends_active is not None
            else profile.get("is_friends_active", False)
        )
        professional_active = (
            payload.is_professional_active
            if payload.is_professional_active is not None
            else profile.get("is_professional_active", False)
        )

        is_activating = (
            (payload.is_dating_active is True)
            or (payload.is_friends_active is True)
            or (payload.is_professional_active is True)
        )

        if not is_activating and (
            dating_active or friends_active or professional_active
        ):
            final_bio = (
                payload.bio
                if payload.bio is not None
                else profile.get("bio")
            )
            if final_bio == "__DECRYPTION_FAILED__":
                pass
            else:
                if (
                    not isinstance(final_bio, str)
                    or sum(c.isalpha() for c in final_bio) < 3
                ):
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=(
                            "Bio is required when orbits are active and "
                            "must contain at least three alphabetic characters."
                        ),
                    )

    if payload.is_dating_active is not None:
        if payload.is_dating_active:
            if profile is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Profile must be loaded for dating tab activation",
                )
            missing = _validate_tab_activation("Dating", profile, payload)
            if missing:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={
                        "message": "Dating profile incomplete",
                        "missing_fields": missing,
                    },
                )
            update_data["is_dating_active"] = True
        else:
            update_data["is_dating_active"] = False

    if payload.is_friends_active is not None:
        if payload.is_friends_active:
            if profile is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Profile must be loaded for friends tab activation",
                )
            missing = _validate_tab_activation("Friends", profile, payload)
            if missing:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={
                        "message": "Friends profile incomplete",
                        "missing_fields": missing,
                    },
                )
            update_data["is_friends_active"] = True
        else:
            update_data["is_friends_active"] = False

    if payload.is_professional_active is not None:
        if payload.is_professional_active:
            if profile is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Profile must be loaded for professional tab activation",
                )
            missing = _validate_tab_activation("Professional", profile, payload)
            if missing:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={
                        "message": "Professional profile incomplete",
                        "missing_fields": missing,
                    },
                )
            update_data["is_professional_active"] = True
        else:
            update_data["is_professional_active"] = False

    if not update_data and new_age is None and new_name is None:
        return {"status": "success", "detail": "No fields to update."}

    has_other_updates = bool(update_data)
    if has_other_updates:
        update_data["updated_at"] = datetime.now(timezone.utc).isoformat()

    try:
        if new_age is not None:
            try:
                supabase_client.rpc(
                    "apply_age_change",
                    {
                        "p_user_id": user_id,
                        "p_new_age": new_age,
                        "p_min_interval_days": _AGE_CHANGE_WINDOW_DAYS,
                        "p_max_changes": _AGE_CHANGE_MAX_PER_WINDOW,
                    },
                ).execute()
            except APIError as e:
                if e.message == "age_change_limit_reached":
                    raise HTTPException(
                        status_code=403,
                        detail=(
                            "You've used both age changes allowed this year."
                        ),
                    ) from e
                if e.message == "profile_not_found":
                    raise HTTPException(
                        status_code=404,
                        detail="Profile not found. Complete onboarding first.",
                    ) from e
                logger.exception(
                    "Unexpected apply_age_change failure",
                    extra={"user_id": user_id},
                )
                raise HTTPException(
                    status_code=500,
                    detail="Internal server error.",
                ) from e

        if new_name is not None:
            try:
                supabase_client.rpc(
                    "apply_name_change",
                    {
                        "p_user_id": user_id,
                        "p_new_name": new_name,
                        "p_min_interval_days": _NAME_CHANGE_WINDOW_DAYS,
                        "p_max_changes": _NAME_CHANGE_MAX_PER_WINDOW,
                    },
                ).execute()
            except APIError as e:
                if e.message == "name_change_limit_reached":
                    raise HTTPException(
                        status_code=403,
                        detail=(
                            "You've used both name changes allowed this year."
                        ),
                    ) from e
                if e.message == "profile_not_found":
                    raise HTTPException(
                        status_code=404,
                        detail="Profile not found. Complete onboarding first.",
                    ) from e
                logger.exception(
                    "Unexpected apply_name_change failure",
                    extra={"user_id": user_id},
                )
                raise HTTPException(
                    status_code=500,
                    detail="Internal server error.",
                ) from e

        if update_data:
            res = (
                supabase_client.table("profiles")
                .update(update_data)
                .eq("id", user_id)
                .execute()
            )
            if not getattr(res, "data", None):
                raise HTTPException(
                    status_code=404,
                    detail="Profile not found. Complete onboarding first.",
                )

        plaintext_bio = (payload.bio or "").strip()
        background_tasks.add_task(recompile_and_push_vectors, user_id, plaintext_bio)

        if payload.model_fields_set & _VALUE_DIMENSION_TRIGGER_FIELDS:
            background_tasks.add_task(recompile_value_dimensions, user_id)

        return {"status": "success", "detail": "Profile details synchronized."}
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to update profile details")
        raise HTTPException(
            status_code=500,
            detail="Internal server error.",
        ) from e


def _to_privacy_settings_response(data: dict[str, Any]) -> PrivacySettingsResponse:
    raw: list[str] = list(data.get("hidden_profile_fields") or [])
    # Defensively strip any field names that are no longer in the allowed set.
    hidden: list[str] = [f for f in raw if f in ALLOWED_HIDDEN_FIELDS]
    return PrivacySettingsResponse(
        hidden_fields=hidden,
        share_active_status=bool(data.get("share_active_status", True)),
        share_read_receipts=bool(data.get("share_read_receipts", True)),
    )


@router.get(
    "/api/v1/profile/privacy-settings",
    response_model=PrivacySettingsResponse,
)
def get_privacy_settings(
    user_id: str = Depends(get_active_user_id),
) -> PrivacySettingsResponse:
    try:
        res = (
            supabase_client.table("profiles")
            .select("hidden_profile_fields, share_active_status, share_read_receipts")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        data = getattr(res, "data", None)
        if data is None:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_privacy_settings_response(data)
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to fetch privacy settings for user %s", user_id)
        raise HTTPException(status_code=500, detail="Internal server error.") from e


@router.patch(
    "/api/v1/profile/privacy-settings",
    response_model=PrivacySettingsResponse,
)
def update_privacy_settings(
    payload: PrivacySettingsUpdate = Body(...),  # noqa: B008
    user_id: str = Depends(get_active_user_id),
) -> PrivacySettingsResponse:
    update_data: dict[str, Any] = {}
    if payload.hidden_fields is not None:
        update_data["hidden_profile_fields"] = payload.hidden_fields
    if payload.share_active_status is not None:
        update_data["share_active_status"] = payload.share_active_status
    if payload.share_read_receipts is not None:
        update_data["share_read_receipts"] = payload.share_read_receipts
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update.")

    try:
        res = (
            supabase_client.table("profiles")
            .update(update_data)
            .eq("id", user_id)
            .select("hidden_profile_fields, share_active_status, share_read_receipts")
            .execute()
        )
        rows = cast(list[dict[str, Any]], getattr(res, "data", None) or [])
        if not rows:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_privacy_settings_response(rows[0])
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to update privacy settings for user %s", user_id)
        raise HTTPException(status_code=500, detail="Internal server error.") from e


_EMAIL_NOTIFICATION_COLUMNS = (
    "email_notify_matches, email_notify_messages, email_notify_digest, "
    "email_notify_product_updates, email_notify_promotions"
)


def _to_email_notification_settings_response(
    data: dict[str, Any],
) -> EmailNotificationSettingsResponse:
    return EmailNotificationSettingsResponse(
        email_notify_matches=bool(data.get("email_notify_matches", True)),
        email_notify_messages=bool(data.get("email_notify_messages", True)),
        email_notify_digest=bool(data.get("email_notify_digest", True)),
        email_notify_product_updates=bool(
            data.get("email_notify_product_updates", True),
        ),
        email_notify_promotions=bool(data.get("email_notify_promotions", True)),
    )


@router.get(
    "/api/v1/profile/email-notification-settings",
    response_model=EmailNotificationSettingsResponse,
)
def get_email_notification_settings(
    user_id: str = Depends(get_active_user_id),
) -> EmailNotificationSettingsResponse:
    try:
        res = (
            supabase_client.table("profiles")
            .select(_EMAIL_NOTIFICATION_COLUMNS)
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        data = getattr(res, "data", None)
        if data is None:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_email_notification_settings_response(data)
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(
            "Failed to fetch email notification settings for user %s",
            user_id,
        )
        raise HTTPException(status_code=500, detail="Internal server error.") from e


@router.patch(
    "/api/v1/profile/email-notification-settings",
    response_model=EmailNotificationSettingsResponse,
)
def update_email_notification_settings(
    payload: EmailNotificationSettingsUpdate = Body(...),  # noqa: B008
    user_id: str = Depends(get_active_user_id),
) -> EmailNotificationSettingsResponse:
    update_data = payload.model_dump(exclude_none=True)
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update.")

    try:
        res = (
            supabase_client.table("profiles")
            .update(update_data)
            .eq("id", user_id)
            .select(_EMAIL_NOTIFICATION_COLUMNS)
            .execute()
        )
        rows = cast(list[dict[str, Any]], getattr(res, "data", None) or [])
        if not rows:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_email_notification_settings_response(rows[0])
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(
            "Failed to update email notification settings for user %s",
            user_id,
        )
        raise HTTPException(status_code=500, detail="Internal server error.") from e
