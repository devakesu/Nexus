"""Self-serve account deletion: email-OTP reauth + typed confirmation, then
a 14-day recoverable grace window before Tier-1 anonymization. See
app/db/account_deletion.py for the full lifecycle and
app/services/reminder_scheduler.py for the purge jobs.
"""

import logging
import secrets

from fastapi import APIRouter, Body, Depends, HTTPException, Request, status
from starlette.concurrency import run_in_threadpool

from app.api.dependencies import (
    get_authenticated_user_id,
    get_bearer_token,
    verify_app_check_with_replay_protection,
)
from app.core.cache import redis_client
from app.core.config import settings
from app.core.email import send_account_deletion_otp_email
from app.core.limiter import limiter
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
    AccountDeletionSettingsResponse,
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
    otp_code = "".join(secrets.choice("0123456789") for _ in range(8))
    await redis_client.setex(f"account_deletion:otp_code:{user_id}", 600, otp_code)
    await send_account_deletion_otp_email(email, otp_code)
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

    stored_otp = await redis_client.get(f"account_deletion:otp_code:{user_id}")
    if not stored_otp:
        raise HTTPException(status_code=400, detail="Invalid or expired code.")
    stored_otp_str = (
        stored_otp.decode("utf-8")
        if isinstance(stored_otp, bytes)
        else stored_otp
    )
    if stored_otp_str.strip() != payload.code.strip():
        raise HTTPException(status_code=400, detail="Invalid or expired code.")
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


@router.get(
    "/api/v1/account/deletion/settings",
    response_model=AccountDeletionSettingsResponse,
)
@limiter.limit(settings.rate_limit_account_deletion)
def get_account_deletion_settings(request: Request) -> AccountDeletionSettingsResponse:
    _ = request
    return AccountDeletionSettingsResponse(
        grace_period_days=settings.account_deletion_grace_period_days,
        blocklist_cooldown_days=settings.account_deletion_blocklist_cooldown_days,
        long_tail_purge_days=settings.account_deletion_long_tail_purge_days,
        safety_evidence_active_retention_days=settings.safety_evidence_active_retention_days,
        safety_data_legal_hold_days=settings.safety_data_legal_hold_days,
    )
