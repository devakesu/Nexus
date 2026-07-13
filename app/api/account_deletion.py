"""Self-serve account deletion: email-OTP reauth + typed confirmation, then
a 14-day recoverable grace window before Tier-1 anonymization. See
app/db/account_deletion.py for the full lifecycle and
app/services/reminder_scheduler.py for the purge jobs.
"""

import logging

from fastapi import APIRouter, Body, Depends, HTTPException, Request, status
from starlette.concurrency import run_in_threadpool

from app.api.dependencies import (
    get_authenticated_user_id,
    get_bearer_token,
    verify_app_check_with_replay_protection,
)
from app.core.cache import redis_client
from app.core.config import settings
from app.core.limiter import limiter
from app.core.passwordless_email import send_login_email_otp, verify_login_email_otp
from app.db.account_deletion import (
    cancel_deletion,
    compute_deletion_flag_reason,
    fetch_deletion_status,
    request_deletion,
)
from app.db.users import get_user_email_by_id
from app.models import (
    AccountDeletionCancelResponse,
    AccountDeletionOtpRequestResponse,
    AccountDeletionOtpVerifyRequest,
    AccountDeletionOtpVerifyResponse,
    AccountDeletionRequestRequest,
    AccountDeletionRequestResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter()

_OTP_VERIFIED_TTL_SECONDS = 600


def _otp_verified_key(user_id: str) -> str:
    return f"account_deletion:otp_verified:{user_id}"


@router.post(
    "/api/v1/account/deletion/otp/request",
    response_model=AccountDeletionOtpRequestResponse,
)
@limiter.limit(settings.rate_limit_account_deletion_otp)
async def request_account_deletion_otp(
    request: Request,
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_authenticated_user_id),
) -> AccountDeletionOtpRequestResponse:
    _ = request
    email = await run_in_threadpool(get_user_email_by_id, user_id)
    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No verified email on this account. Contact support for assistance.",
        )
    await run_in_threadpool(send_login_email_otp, email)
    return AccountDeletionOtpRequestResponse(sent=True)


@router.post(
    "/api/v1/account/deletion/otp/verify",
    response_model=AccountDeletionOtpVerifyResponse,
)
@limiter.limit(settings.rate_limit_account_deletion_otp)
async def verify_account_deletion_otp(
    request: Request,
    payload: AccountDeletionOtpVerifyRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_authenticated_user_id),
) -> AccountDeletionOtpVerifyResponse:
    _ = request
    email = await run_in_threadpool(get_user_email_by_id, user_id)
    if not email:
        raise HTTPException(status_code=400, detail="Invalid or expired code.")

    try:
        await run_in_threadpool(verify_login_email_otp, email, payload.code)
    except Exception as e:
        raise HTTPException(status_code=400, detail="Invalid or expired code.") from e

    await redis_client.setex(_otp_verified_key(user_id), _OTP_VERIFIED_TTL_SECONDS, "1")
    return AccountDeletionOtpVerifyResponse(verified=True)


@router.post(
    "/api/v1/account/deletion/request",
    response_model=AccountDeletionRequestResponse,
)
@limiter.limit(settings.rate_limit_account_deletion)
async def request_account_deletion(
    request: Request,
    payload: AccountDeletionRequestRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_authenticated_user_id),
    access_token: str = Depends(get_bearer_token),
) -> AccountDeletionRequestResponse:
    _ = request

    existing = await run_in_threadpool(fetch_deletion_status, user_id)
    if existing and existing.get("deletion_requested_at"):
        # Idempotent - a second submit while already pending just returns
        # the existing schedule instead of erroring.
        return AccountDeletionRequestResponse(
            scheduled_purge_at=existing["scheduled_purge_at"],
        )

    otp_key = _otp_verified_key(user_id)
    if not await redis_client.get(otp_key):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Please verify your email before requesting deletion.",
        )
    await redis_client.delete(otp_key)

    if payload.confirmation_text.strip().upper() != "DELETE":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Type DELETE to confirm.",
        )

    # Suspended/banned users must still be able to request deletion - they
    # are exactly who deletion_flagged_reason_code exists to catch, so this
    # deliberately does not call assert_account_active.
    flagged_reason = await run_in_threadpool(compute_deletion_flag_reason, user_id)
    scheduled_purge_at = await run_in_threadpool(
        request_deletion, user_id, flagged_reason, access_token,
    )
    return AccountDeletionRequestResponse(scheduled_purge_at=scheduled_purge_at)


@router.post(
    "/api/v1/account/deletion/cancel",
    response_model=AccountDeletionCancelResponse,
)
@limiter.limit(settings.rate_limit_account_deletion)
async def cancel_account_deletion(
    request: Request,
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_authenticated_user_id),
) -> AccountDeletionCancelResponse:
    _ = request
    existing = await run_in_threadpool(fetch_deletion_status, user_id)
    if not existing or not existing.get("deletion_requested_at"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No pending deletion to cancel.",
        )
    await run_in_threadpool(cancel_deletion, user_id)
    return AccountDeletionCancelResponse(reactivated=True)
