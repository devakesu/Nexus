"""Personal data export: email-OTP reauth, then a synchronous export build -
see app/db/export.py for what's included/excluded and why. Mirrors
app/api/account_deletion.py's OTP-reauth pattern exactly, since dumping a
user's full PII is a comparably sensitive operation.
"""

import logging
import secrets
from typing import Any

from fastapi import APIRouter, Body, Depends, HTTPException, Request, status
from starlette.concurrency import run_in_threadpool

from app.api.dependencies import (
    get_authenticated_user_id,
    verify_app_check_with_replay_protection,
)
from app.core.cache import redis_client
from app.core.config import settings
from app.core.email import send_data_export_otp_email
from app.core.limiter import limiter
from app.db.export import build_user_data_export
from app.db.users import get_user_email_by_id
from app.models import (
    DataExportOtpRequestResponse,
    DataExportOtpVerifyRequest,
    DataExportOtpVerifyResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter()

_OTP_VERIFIED_TTL_SECONDS = 600


def _otp_verified_key(user_id: str) -> str:
    return f"data_export:otp_verified:{user_id}"


@router.post(
    "/api/v1/account/export/otp/request",
    response_model=DataExportOtpRequestResponse,
)
@limiter.limit(settings.rate_limit_data_export_otp)
async def request_data_export_otp(
    request: Request,
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_authenticated_user_id),
) -> DataExportOtpRequestResponse:
    _ = request
    email = await run_in_threadpool(get_user_email_by_id, user_id)
    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No verified email on this account. Contact support for assistance.",
        )
    otp_code = "".join(secrets.choice("0123456789") for _ in range(8))
    await redis_client.setex(f"data_export:otp_code:{user_id}", 600, otp_code)
    await send_data_export_otp_email(email, otp_code)
    return DataExportOtpRequestResponse(sent=True)


@router.post(
    "/api/v1/account/export/otp/verify",
    response_model=DataExportOtpVerifyResponse,
)
@limiter.limit(settings.rate_limit_data_export_otp)
async def verify_data_export_otp(
    request: Request,
    payload: DataExportOtpVerifyRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_authenticated_user_id),
) -> DataExportOtpVerifyResponse:
    _ = request
    email = await run_in_threadpool(get_user_email_by_id, user_id)
    if not email:
        raise HTTPException(status_code=400, detail="Invalid or expired code.")

    stored_otp = await redis_client.get(f"data_export:otp_code:{user_id}")
    if not stored_otp:
        raise HTTPException(status_code=400, detail="Invalid or expired code.")
    stored_otp_str = (
        stored_otp.decode("utf-8")
        if isinstance(stored_otp, bytes)
        else stored_otp
    )
    if stored_otp_str.strip() != payload.code.strip():
        raise HTTPException(status_code=400, detail="Invalid or expired code.")
    await redis_client.delete(f"data_export:otp_code:{user_id}")

    await redis_client.setex(_otp_verified_key(user_id), _OTP_VERIFIED_TTL_SECONDS, "1")
    return DataExportOtpVerifyResponse(verified=True)


@router.post("/api/v1/account/export")
@limiter.limit(settings.rate_limit_data_export)
async def export_account_data(
    request: Request,
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(get_authenticated_user_id),
) -> dict[str, Any]:
    _ = request
    otp_key = _otp_verified_key(user_id)
    if not await redis_client.get(otp_key):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Please verify your email before requesting an export.",
        )
    await redis_client.delete(otp_key)

    return await run_in_threadpool(build_user_data_export, user_id)
