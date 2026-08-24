"""Personal data export: email-OTP reauth, then a synchronous export build -
see app/db/export.py for what's included/excluded and why. Mirrors
app/api/account_deletion.py's OTP-reauth pattern exactly, since dumping a
user's full PII is a comparably sensitive operation.
"""

import logging

from fastapi import APIRouter, Body, Depends, HTTPException, Request, status
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool

from app.api.dependencies import (
    get_optional_authenticated_user_id,
    resolve_verified_user,
    verify_app_check_with_replay_protection,
)
from app.core.config import settings
from app.core.email import send_data_export_otp_email
from app.core.infra.cache import redis_client
from app.core.infra.limiter import limiter
from app.core.infra.otp import (
    OTP_VERIFIED_TTL_SECONDS,
    dummy_email_send_delay,
    generate_otp_code,
    otp_verified_redis_key,
    verify_and_consume_raw_otp,
)
from app.db.users import (
    build_user_data_export,
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







_DATA_EXPORT_OTP_MAX_ATTEMPTS = 5
_DATA_EXPORT_OTP_TTL_SECONDS = 600
_DATA_EXPORT_OTP_MAX_TARGET_ATTEMPTS = 3
_DATA_EXPORT_OTP_TARGET_WINDOW_SECONDS = 30 * 60  # 30 minutes
_DATA_EXPORT_OTP_RESEND_COOLDOWN_SECONDS = 60  # 60 seconds


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
    user_id, email = await resolve_verified_user(auth_user_id, email_in)
    if not user_id:
        await dummy_email_send_delay()
        return DataExportOtpRequestResponse(sent=True)

    target_limit_key = f"data_export:otp_limit:{user_id}"
    target_cooldown_key = f"data_export:otp_cooldown:{user_id}"

    if await redis_client.exists(target_cooldown_key):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Please wait a bit before requesting another data export code.",
        )

    target_attempts = await redis_client.get(target_limit_key)
    if target_attempts and int(target_attempts) >= _DATA_EXPORT_OTP_MAX_TARGET_ATTEMPTS:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many data export requests for this account. Please try again later.",
        )

    await redis_client.set(target_cooldown_key, "1", ex=_DATA_EXPORT_OTP_RESEND_COOLDOWN_SECONDS, nx=True)
    current_attempts = await redis_client.incr(target_limit_key)
    if current_attempts == 1:
        await redis_client.expire(target_limit_key, _DATA_EXPORT_OTP_TARGET_WINDOW_SECONDS)

    otp_code = generate_otp_code(8)
    await redis_client.setex(f"data_export:otp_code:{user_id}", _DATA_EXPORT_OTP_TTL_SECONDS, otp_code)
    await redis_client.delete(f"data_export:otp_attempts:{user_id}")
    otp_res = await send_data_export_otp_email(email, otp_code)
    if not otp_res.success:
        logger.error(
            "OTP email delivery failed: %s",
            otp_res.error,
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Could not send verification email. Please try again.",
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
    user_id, _ = await resolve_verified_user(auth_user_id, payload.email)
    if not user_id:
        raise HTTPException(status_code=400, detail="Invalid or expired verification code.")

    await verify_and_consume_raw_otp(
        otp_key=f"data_export:otp_code:{user_id}",
        attempts_key=f"data_export:otp_attempts:{user_id}",
        submitted_code=payload.code,
        max_attempts=_DATA_EXPORT_OTP_MAX_ATTEMPTS,
        ttl_seconds=_DATA_EXPORT_OTP_TTL_SECONDS,
        client=redis_client,
    )

    await redis_client.setex(
        otp_verified_redis_key("data_export", user_id),
        OTP_VERIFIED_TTL_SECONDS,
        "1",
    )
    return DataExportOtpVerifyResponse(verified=True)


@router.post("/api/v1/account/export")
@limiter.limit(settings.rate_limit_data_export)
async def export_account_data(
    request: Request,
    payload: DataExportRequestRequest | None = Body(None),
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user_id: str | None = Depends(get_optional_authenticated_user_id),
) -> JSONResponse:
    """Executes export account data operation.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            payload: Validated request body model containing parameters.
            _device: App Check attestation token dependency guard.
            auth_user_id: Verified user ID string extracted from authentication token.

        Returns:
            JSONResponse: JSON payload with Content-Disposition attachment header."""
    _ = request
    email_in = payload.email if payload else None
    user_id, _ = await resolve_verified_user(auth_user_id, email_in)
    if not user_id:
        raise HTTPException(status_code=400, detail="Invalid or expired verification code.")

    otp_key = otp_verified_redis_key("data_export", user_id)
    if not await redis_client.get(otp_key):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Please verify your email code before requesting an export.",
        )
    await redis_client.delete(otp_key)

    data = await run_in_threadpool(build_user_data_export, user_id)
    return JSONResponse(
        content=data,
        headers={"Content-Disposition": 'attachment; filename="nexus-data-export.json"'},
    )

