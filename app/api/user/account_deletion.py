"""Self-serve account deletion: email-OTP reauth + typed confirmation, then
a 14-day recoverable grace window before Tier-1 anonymization. See
app/db/account_deletion.py for the full lifecycle and
app/services/reminder_scheduler.py for the purge jobs.
"""

import logging
import secrets

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Body,
    Depends,
    HTTPException,
    Request,
    status,
)
from starlette.concurrency import run_in_threadpool

from app.api.dependencies import (
    get_authenticated_user_id,
    get_optional_authenticated_user_id,
    get_optional_bearer_token,
    verify_app_check_with_replay_protection,
)
from app.core.config import settings
from app.core.email import (
    send_account_deletion_otp_email,
    send_account_deletion_scheduled_email,
    send_account_reactivated_email,
)
from app.core.infra.cache import redis_client
from app.core.infra.limiter import limiter
from app.db.users import (
    cancel_deletion,
    compute_deletion_flag_reason,
    fetch_deletion_status,
    get_user_email_by_id,
    get_user_id_by_email,
    request_deletion,
)
from app.models import (
    AccountDeletionCancelResponse,
    AccountDeletionOtpRequestRequest,
    AccountDeletionOtpRequestResponse,
    AccountDeletionOtpVerifyRequest,
    AccountDeletionOtpVerifyResponse,
    AccountDeletionRequestRequest,
    AccountDeletionRequestResponse,
    AccountDeletionSettingsResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter()

_OTP_VERIFIED_TTL_SECONDS = 600


def _otp_verified_key(user_id: str) -> str:
    """Formats Redis key string for verified account deletion OTP.

    Args:
        user_id: Target user ID.

    Returns:
        str: Redis cache key string.
    """
    return f"account_deletion:otp_verified:{user_id}"


async def _resolve_account_deletion_user(
    auth_user_id: str | None,
    email: str | None,
) -> tuple[str, str]:
    """Resolves user ID and email pair from token or request body payload.

    Args:
        auth_user_id: Optional authenticated user ID.
        email: Optional input email address string.

    Returns:
        tuple[str, str]: User ID and resolved email string pair.

    Raises:
        HTTPException: If email/user resolution fails.
    """
    if auth_user_id:
        user_email = await run_in_threadpool(get_user_email_by_id, auth_user_id)
        if not user_email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No verified email on this account. Contact support for assistance.",
            )
        return auth_user_id, user_email

    if email and email.strip():
        norm_email = email.strip().lower()
        user_id = await run_in_threadpool(get_user_id_by_email, norm_email)
        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No registered account found with this email address. Please check your email.",
            )
        return user_id, norm_email

    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail="Please enter your registered email address.",
    )


@router.post(
    "/api/v1/account/deletion/otp/request",
    response_model=AccountDeletionOtpRequestResponse,
)
@limiter.limit(settings.rate_limit_account_deletion_otp)
async def request_account_deletion_otp(
    request: Request,
    payload: AccountDeletionOtpRequestRequest | None = Body(None),
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user_id: str | None = Depends(get_optional_authenticated_user_id),
) -> AccountDeletionOtpRequestResponse:
    """Dispatches a 10-minute email OTP verification code for account deletion.

    Args:
        request: Incoming HTTP request.
        payload: Optional email payload request.
        _device: App Check attestation guard.
        auth_user_id: Optional authenticated user ID.

    Returns:
        AccountDeletionOtpRequestResponse: Response status.
    """
    _ = request
    email_in = payload.email if payload else None
    user_id, email = await _resolve_account_deletion_user(auth_user_id, email_in)

    otp_code = "".join(secrets.choice("0123456789") for _ in range(8))
    await redis_client.setex(f"account_deletion:otp_code:{user_id}", 600, otp_code)
    otp_res = await send_account_deletion_otp_email(email, otp_code)
    if not otp_res.success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to deliver verification email: {otp_res.error}",
        )
    return AccountDeletionOtpRequestResponse(sent=True)


@router.post(
    "/api/v1/account/deletion/otp/verify",
    response_model=AccountDeletionOtpVerifyResponse,
)
@limiter.limit(settings.rate_limit_account_deletion_otp)
async def verify_account_deletion_otp(
    request: Request,
    payload: AccountDeletionOtpVerifyRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user_id: str | None = Depends(get_optional_authenticated_user_id),
) -> AccountDeletionOtpVerifyResponse:
    """Verifies an email OTP code for account deletion.

    Args:
        request: Incoming HTTP request.
        payload: Verification payload containing code and email.
        _device: App Check attestation guard.
        auth_user_id: Optional authenticated user ID.

    Returns:
        AccountDeletionOtpVerifyResponse: Verification status.
    """
    _ = request
    user_id, _ = await _resolve_account_deletion_user(auth_user_id, payload.email)

    stored_otp = await redis_client.get(f"account_deletion:otp_code:{user_id}")
    if not stored_otp:
        raise HTTPException(status_code=400, detail="Invalid or expired verification code.")
    stored_otp_str = (
        stored_otp.decode("utf-8")
        if isinstance(stored_otp, bytes)
        else stored_otp
    )
    if stored_otp_str.strip() != payload.code.strip():
        raise HTTPException(status_code=400, detail="Invalid or expired verification code.")
    await redis_client.delete(f"account_deletion:otp_code:{user_id}")

    await redis_client.setex(_otp_verified_key(user_id), _OTP_VERIFIED_TTL_SECONDS, "1")
    return AccountDeletionOtpVerifyResponse(verified=True)


@router.post(
    "/api/v1/account/deletion/request",
    response_model=AccountDeletionRequestResponse,
)
@limiter.limit(settings.rate_limit_account_deletion)
async def request_account_deletion(
    request: Request,
    background_tasks: BackgroundTasks,
    payload: AccountDeletionRequestRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user_id: str | None = Depends(get_optional_authenticated_user_id),
    access_token: str | None = Depends(get_optional_bearer_token),
) -> AccountDeletionRequestResponse:
    """Schedules account for deletion after OTP verification and typed confirmation ('DELETE').

    Args:
        request: Incoming HTTP request.
        background_tasks: FastAPI background tasks queue.
        payload: Account deletion request payload.
        _device: App Check attestation guard.
        auth_user_id: Optional authenticated user ID.
        access_token: Optional bearer token.

    Returns:
        AccountDeletionRequestResponse: Scheduled purge timestamp response.
    """
    _ = request
    user_id, email = await _resolve_account_deletion_user(auth_user_id, payload.email)

    existing = await run_in_threadpool(fetch_deletion_status, user_id)
    if existing and existing.get("deletion_requested_at"):
        return AccountDeletionRequestResponse(
            scheduled_purge_at=existing["scheduled_purge_at"],
        )

    otp_key = _otp_verified_key(user_id)
    if not await redis_client.get(otp_key):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Please verify your email code before requesting deletion.",
        )
    await redis_client.delete(otp_key)

    if payload.confirmation_text.strip().upper() != "DELETE":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Type DELETE to confirm.",
        )

    flagged_reason = await run_in_threadpool(compute_deletion_flag_reason, user_id)
    scheduled_purge_at = await run_in_threadpool(
        request_deletion, user_id, flagged_reason, access_token or "",
    )
    background_tasks.add_task(
        send_account_deletion_scheduled_email,
        email=email,
        scheduled_purge_at=scheduled_purge_at,
        grace_period_days=settings.account_deletion_grace_period_days,
    )
    return AccountDeletionRequestResponse(scheduled_purge_at=scheduled_purge_at)


@router.post(
    "/api/v1/account/deletion/cancel",
    response_model=AccountDeletionCancelResponse,
)
@limiter.limit(settings.rate_limit_account_deletion)
async def cancel_account_deletion(
    request: Request,
    background_tasks: BackgroundTasks,
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_authenticated_user_id),
) -> AccountDeletionCancelResponse:
    """Cancels a pending account deletion request during the 14-day grace window.

    Args:
        request: Incoming HTTP request.
        background_tasks: FastAPI background tasks queue.
        _device: App Check attestation guard.
        user_id: Verified caller user ID.

    Returns:
        AccountDeletionCancelResponse: Reactivated status response.
    """
    _ = request
    existing = await run_in_threadpool(fetch_deletion_status, user_id)
    if not existing or not existing.get("deletion_requested_at"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No pending deletion to cancel.",
        )
    user_email = await run_in_threadpool(get_user_email_by_id, user_id)
    await run_in_threadpool(cancel_deletion, user_id)
    if user_email:
        background_tasks.add_task(
            send_account_reactivated_email,
            email=user_email,
        )
    return AccountDeletionCancelResponse(reactivated=True)


@router.get(
    "/api/v1/account/deletion/settings",
    response_model=AccountDeletionSettingsResponse,
)
@limiter.limit(settings.rate_limit_account_deletion)
def get_account_deletion_settings(request: Request) -> AccountDeletionSettingsResponse:
    """Returns configuration settings for account deletion grace periods and data retention.

    Args:
        request: Incoming HTTP request.

    Returns:
        AccountDeletionSettingsResponse: System settings parameters.
    """
    _ = request
    return AccountDeletionSettingsResponse(
        grace_period_days=settings.account_deletion_grace_period_days,
        blocklist_cooldown_days=settings.account_deletion_blocklist_cooldown_days,
        long_tail_purge_days=settings.account_deletion_long_tail_purge_days,
        safety_evidence_active_retention_days=settings.safety_evidence_active_retention_days,
        safety_data_legal_hold_days=settings.safety_data_legal_hold_days,
    )

