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
    get_optional_authenticated_user_id,
    verify_app_check_with_replay_protection,
)
from app.core.config import settings
from app.core.email import send_data_export_otp_email
from app.core.infra.cache import redis_client
from app.core.infra.limiter import limiter
from app.db.users import (
    build_user_data_export,
    get_user_email_by_id,
    get_user_id_by_email,
)
from app.models import (
    DataExportOtpRequestRequest,
    DataExportOtpRequestResponse,
    DataExportOtpVerifyRequest,
    DataExportOtpVerifyResponse,
    DataExportRequestRequest,
)

logger = logging.getLogger(__name__)

router = APIRouter()

_OTP_VERIFIED_TTL_SECONDS = 600


def _otp_verified_key(user_id: str) -> str:
    """Otp verified key.

        Args:
            user_id: Unique UUID string of the authenticated user.

        Returns:
            str: Response payload or result."""
    return f"data_export:otp_verified:{user_id}"


async def _resolve_data_export_user(
    auth_user_id: str | None,
    email: str | None,
) -> tuple[str, str]:
    """Resolve data export user.

        Args:
            auth_user_id: Verified user ID string extracted from authentication token.
            email: Email address string.

        Returns:
            tuple[str, str]: Response payload or result."""
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
    "/api/v1/account/export/otp/request",
    response_model=DataExportOtpRequestResponse,
)
@limiter.limit(settings.rate_limit_data_export_otp)
async def request_data_export_otp(
    request: Request,
    payload: DataExportOtpRequestRequest | None = Body(None),
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user_id: str | None = Depends(get_optional_authenticated_user_id),
) -> DataExportOtpRequestResponse:
    """Executes request data export otp operation.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            payload: Validated request body model containing parameters.
            _device: App Check attestation token dependency guard.
            auth_user_id: Verified user ID string extracted from authentication token.

        Returns:
            DataExportOtpRequestResponse: Response payload or result."""
    _ = request
    email_in = payload.email if payload else None
    user_id, email = await _resolve_data_export_user(auth_user_id, email_in)

    otp_code = "".join(secrets.choice("0123456789") for _ in range(8))
    await redis_client.setex(f"data_export:otp_code:{user_id}", 600, otp_code)
    otp_res = await send_data_export_otp_email(email, otp_code)
    if not otp_res.success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to deliver verification email: {otp_res.error}",
        )
    return DataExportOtpRequestResponse(sent=True)


@router.post(
    "/api/v1/account/export/otp/verify",
    response_model=DataExportOtpVerifyResponse,
)
@limiter.limit(settings.rate_limit_data_export_otp)
async def verify_data_export_otp(
    request: Request,
    payload: DataExportOtpVerifyRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user_id: str | None = Depends(get_optional_authenticated_user_id),
) -> DataExportOtpVerifyResponse:
    """Executes verify data export otp operation.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            payload: Validated request body model containing parameters.
            _device: App Check attestation token dependency guard.
            auth_user_id: Verified user ID string extracted from authentication token.

        Returns:
            DataExportOtpVerifyResponse: Response payload or result."""
    _ = request
    user_id, _ = await _resolve_data_export_user(auth_user_id, payload.email)

    stored_otp = await redis_client.get(f"data_export:otp_code:{user_id}")
    if not stored_otp:
        raise HTTPException(status_code=400, detail="Invalid or expired verification code.")
    stored_otp_str = (
        stored_otp.decode("utf-8")
        if isinstance(stored_otp, bytes)
        else stored_otp
    )
    if stored_otp_str.strip() != payload.code.strip():
        raise HTTPException(status_code=400, detail="Invalid or expired verification code.")
    await redis_client.delete(f"data_export:otp_code:{user_id}")

    await redis_client.setex(_otp_verified_key(user_id), _OTP_VERIFIED_TTL_SECONDS, "1")
    return DataExportOtpVerifyResponse(verified=True)


@router.post("/api/v1/account/export")
@limiter.limit(settings.rate_limit_data_export)
async def export_account_data(
    request: Request,
    payload: DataExportRequestRequest | None = Body(None),
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user_id: str | None = Depends(get_optional_authenticated_user_id),
) -> dict[str, Any]:
    """Executes export account data operation.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            payload: Validated request body model containing parameters.
            _device: App Check attestation token dependency guard.
            auth_user_id: Verified user ID string extracted from authentication token.

        Returns:
            dict[str, Any]: Response payload or result."""
    _ = request
    email_in = payload.email if payload else None
    user_id, _ = await _resolve_data_export_user(auth_user_id, email_in)

    otp_key = _otp_verified_key(user_id)
    if not await redis_client.get(otp_key):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Please verify your email code before requesting an export.",
        )
    await redis_client.delete(otp_key)

    return await run_in_threadpool(build_user_data_export, user_id)

