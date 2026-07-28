"""Public web contact form, attachment uploads, turnstile verification, and OTP support endpoints."""

import asyncio
import logging
import secrets
import string
from typing import Any

import httpx
from fastapi import (
    APIRouter,
    BackgroundTasks,
    Body,
    File,
    Form,
    HTTPException,
    Query,
    Request,
    UploadFile,
    status,
)
from postgrest.exceptions import APIError
from redis.exceptions import RedisError

import app.api.feedback as feedback_module
from app.api.feedback.models import ContactOtpRequest, ContactSubmitRequest
from app.core.config import settings
from app.core.infra.limiter import limiter

router = APIRouter()
logger = logging.getLogger(__name__)


async def verify_turnstile_token(
    token: str | None, client_ip: str | None = None,
) -> bool:
    """Verifies a Cloudflare Turnstile token if turnstile_secret_key is set."""
    if not settings.turnstile_secret_key:
        return True
    if not token:
        return False
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(
                "https://challenges.cloudflare.com/turnstile/v0/siteverify",
                data={
                    "secret": settings.turnstile_secret_key,
                    "response": token,
                    "remoteip": client_ip or "",
                },
            )
            data = resp.json()
            return bool(data.get("success", False))
    except Exception as err:
        logger.exception("Failed to verify Turnstile token: %s", err)
        return False


@router.post("/api/v1/contact/upload")
@limiter.limit(settings.rate_limit_feedback)
async def upload_contact_attachment(
    request: Request,
    file: UploadFile = File(...),
    session_id: str = Query(...),
    turnstile_token: str | None = Form(default=None),
) -> dict[str, str]:
    """Uploads an image attachment for unauthenticated contact form tickets."""
    _ = request
    client_ip = request.client.host if request.client else None
    if not await verify_turnstile_token(turnstile_token, client_ip):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Security verification failed. Please refresh and try again.",
        )

    if not file.filename:
        raise HTTPException(status_code=400, detail="Invalid file uploaded.")

    allowed_exts = {".png", ".jpg", ".jpeg", ".webp"}
    filename: str = file.filename
    ext = "." + filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    if ext not in allowed_exts:
        raise HTTPException(
            status_code=400,
            detail="Only image files (PNG, JPG, WEBP) are allowed.",
        )

    content = await file.read()
    if len(content) > 5 * 1024 * 1024:
        raise HTTPException(
            status_code=400,
            detail="File size exceeds maximum limit of 5MB.",
        )

    clean_session = "".join(c for c in session_id if c.isalnum() or c in ("-", "_"))[:48]
    if not clean_session:
        raise HTTPException(status_code=400, detail="Invalid session_id.")

    random_hex = secrets.token_hex(6)
    storage_path = f"web_contact/{clean_session}/{random_hex}{ext}"

    try:
        _ext_to_mime = {
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
            ".webp": "image/webp",
        }
        content_type = _ext_to_mime.get(ext, "application/octet-stream")
        await asyncio.to_thread(
            lambda: feedback_module.supabase_client.storage.from_("feedback_attachments").upload(
                path=storage_path,
                file=content,
                file_options={"content-type": content_type},
            ),
        )
    except Exception as err:
        logger.exception("Failed to upload contact attachment to bucket")
        raise HTTPException(
            status_code=500,
            detail="Failed to store attachment file.",
        ) from err

    return {"storage_path": storage_path, "filename": filename}


@router.delete("/api/v1/contact/upload")
@limiter.limit(settings.rate_limit_feedback)
async def delete_contact_attachments(
    request: Request,
    session_id: str = Query(...),
    paths: list[str] = Body(..., embed=True),
    turnstile_token: str | None = Query(default=None),
) -> dict[str, bool]:
    """Delete orphaned attachments from storage when ticket submission fails."""
    _ = request
    client_ip = request.client.host if request.client else None
    if not await verify_turnstile_token(turnstile_token, client_ip):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Security verification failed. Please refresh and try again.",
        )
    clean_session = "".join(c for c in session_id if c.isalnum() or c in ("-", "_"))[:48]
    if not clean_session:
        raise HTTPException(status_code=400, detail="Invalid session_id.")

    allowed_prefix = f"web_contact/{clean_session}/"
    safe_paths = [
        p for p in paths
        if p.startswith(allowed_prefix) and ".." not in p
    ]
    if not safe_paths:
        return {"success": True}
    try:
        await asyncio.to_thread(
            lambda: feedback_module.supabase_client.storage.from_("feedback_attachments").remove(safe_paths),
        )
    except (APIError, RuntimeError, ValueError, KeyError, AttributeError):
        logger.warning("Failed to clean up orphaned contact attachments: %s", safe_paths)
    return {"success": True}


@router.post("/api/v1/contact/otp/send")
@limiter.limit(settings.rate_limit_auth)
async def send_contact_otp(
    request: Request,
    payload: ContactOtpRequest = Body(...),
) -> dict[str, bool]:
    """Dispatches an email OTP code to verify contact form submission identity."""
    client_ip = request.client.host if request.client else None
    if not await verify_turnstile_token(payload.turnstile_token, client_ip):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Security verification failed. Please refresh and try again.",
        )

    email = payload.email.strip().lower()
    if not email or "@" not in email:
        raise HTTPException(status_code=400, detail="A valid email is required.")

    otp_code = "".join(secrets.choice(string.digits) for _ in range(6))
    otp_key = f"appeal:otp:{email}"

    try:
        await feedback_module.redis_client.set(otp_key, otp_code, ex=600)
    except Exception as err:
        logger.exception("Failed to store appeal OTP in Redis")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Support service temporarily unavailable.",
        ) from err

    email_res = await feedback_module.send_support_appeal_otp_email(email, otp_code)
    if not email_res.success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send verification email.",
        )

    return {"success": True}


async def _verify_and_consume_otp(email: str, otp_code: str) -> None:
    otp_key = f"appeal:otp:{email}"
    try:
        stored_otp = await feedback_module.redis_client.get(otp_key)
    except (RedisError, RuntimeError) as err:
        logger.exception("Failed to fetch appeal OTP from Redis")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Support service temporarily unavailable.",
        ) from err

    if not stored_otp or stored_otp != otp_code:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired verification code.",
        )

    try:
        await feedback_module.redis_client.delete(otp_key)
    except (RedisError, RuntimeError) as err:
        logger.warning("Failed to delete appeal OTP key %s: %s", otp_key, err)


async def _get_user_id_by_email(email: str) -> str | None:
    try:
        rpc_res = await asyncio.to_thread(
            lambda: feedback_module.supabase_client.rpc(
                "get_user_id_by_email", {"email_addr": email},
            ).execute(),
        )
        if rpc_res.data and isinstance(rpc_res.data, str):
            return rpc_res.data
    except (APIError, RuntimeError, ValueError) as err:
        logger.warning("Optional user lookup by email failed: %s", err)
    return None


async def _cleanup_attachments_on_failure(attachment_paths: list[str] | None) -> None:
    if not attachment_paths:
        return
    try:
        safe_paths = [
            p for p in attachment_paths
            if p.startswith("web_contact/") and ".." not in p
        ]
        await asyncio.to_thread(
            lambda: feedback_module.supabase_client.storage.from_("feedback_attachments").remove(safe_paths),
        )
    except (APIError, RuntimeError, ValueError):
        logger.warning("Failed to clean up attachments after ticket insert failure")


@router.post("/api/v1/contact/submit")
@limiter.limit(settings.rate_limit_auth)
async def submit_contact_ticket(
    request: Request,
    background_tasks: BackgroundTasks,
    payload: ContactSubmitRequest = Body(...),
) -> dict[str, Any]:
    """Submits a contact form inquiry ticket after OTP verification."""
    _ = request
    if not payload.turnstile_token and not payload.otp_code:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Security verification failed. Please refresh and try again.",
        )

    email = payload.email.strip().lower()
    otp_code = payload.otp_code.strip()

    await _verify_and_consume_otp(email, otp_code)
    user_id = await _get_user_id_by_email(email)

    valid_types = {"help", "feedback", "bug_report", "suspended", "security", "legal_grievance", "grievance", "other"}
    query_type = payload.query_type.strip().lower()
    if query_type not in valid_types:
        query_type = "help"

    subject = payload.subject.strip()
    message = payload.message.strip()

    metadata: dict[str, Any] = {
        "source": "web_contact_form",
    }
    if payload.name:
        metadata["submitter_name"] = payload.name.strip()
    if payload.account_id_or_phone:
        metadata["account_id_or_phone"] = payload.account_id_or_phone.strip()

    try:
        report_row = await asyncio.to_thread(
            feedback_module.record_feedback_submission,
            user_id=user_id,
            query_type=query_type,
            subject=subject,
            message=message,
            github_issue_url=payload.github_issue_url,
            attachment_paths=payload.attachment_paths,
            app_version=None,
            platform=None,
            device_info={},
            contact_email=email,
            metadata=metadata,
        )
    except (APIError, RuntimeError, ValueError) as err:
        logger.exception("Failed to record contact ticket in DB")
        await _cleanup_attachments_on_failure(payload.attachment_paths)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to submit support ticket. Please try again.",
        ) from err

    report_id = str(report_row["id"])
    background_tasks.add_task(
        feedback_module.send_feedback_confirmation_email,
        email=email,
        query_type=query_type,
        subject=subject,
        report_id=report_id,
    )
    background_tasks.add_task(
        feedback_module.send_feedback_admin_notification_email,
        report_id=report_id,
        query_type=query_type,
        subject=subject,
        message=message,
        user_id=user_id or "unauthenticated_guest",
        submitter_email=email,
        github_issue_url=payload.github_issue_url,
        attachment_count=len(payload.attachment_paths),
        attachment_names=[
            p.split("/")[-1]
            for p in payload.attachment_paths
        ] if payload.attachment_paths else None,
        submitter_name=payload.name.strip() if payload.name else None,
        account_id_or_phone=payload.account_id_or_phone.strip() if payload.account_id_or_phone else None,
    )

    return {
        "success": True,
        "ticket_id": report_id,
        "status": str(report_row.get("status", "open")),
    }
