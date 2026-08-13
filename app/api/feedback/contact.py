"""Public web contact form, attachment uploads, turnstile verification, and OTP support endpoints."""

import asyncio
import hmac
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
from app.api.feedback.models import (
    ContactOtpRequest,
    ContactSubmitRequest,
    ErrorSessionCreateRequest,
)
from app.core.config import settings
from app.core.infra.limiter import limiter

router = APIRouter()
logger = logging.getLogger(__name__)

_CONTACT_OTP_MAX_ATTEMPTS = 5
_CONTACT_OTP_TTL_SECONDS = 600
_CONTACT_MAX_ATTACHMENTS = 5


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

    try:
        existing_objects = await asyncio.to_thread(
            lambda: feedback_module.supabase_client.storage.from_("feedback_attachments").list(
                f"web_contact/{clean_session}",
            ),
        )
        if existing_objects and len(existing_objects) >= _CONTACT_MAX_ATTACHMENTS:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Maximum attachment limit of {_CONTACT_MAX_ATTACHMENTS} files reached for this session.",
            )
    except HTTPException:
        raise
    except Exception as err:
        logger.warning("Failed to check attachment count for session %s: %s", clean_session, err)

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
    attempts_key = f"appeal:otp_attempts:{email}"

    try:
        await feedback_module.redis_client.set(otp_key, otp_code, ex=_CONTACT_OTP_TTL_SECONDS)
        await feedback_module.redis_client.delete(attempts_key)
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
    attempts_key = f"appeal:otp_attempts:{email}"
    try:
        attempts = await feedback_module.redis_client.get(attempts_key)
        if attempts and int(attempts) >= _CONTACT_OTP_MAX_ATTEMPTS:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Too many incorrect attempts. Please request a new code.",
            )
        stored_otp = await feedback_module.redis_client.get(otp_key)
    except HTTPException:
        raise
    except (RedisError, RuntimeError) as err:
        logger.exception("Failed to fetch appeal OTP from Redis")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Support service temporarily unavailable.",
        ) from err

    stored_otp_str = (
        stored_otp.decode("utf-8")
        if isinstance(stored_otp, bytes)
        else (stored_otp or "")
    )
    if not stored_otp or not hmac.compare_digest(stored_otp_str.strip(), otp_code.strip()):
        try:
            await feedback_module.redis_client.incr(attempts_key)
            await feedback_module.redis_client.expire(attempts_key, _CONTACT_OTP_TTL_SECONDS)
        except (RedisError, RuntimeError):
            pass
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired verification code.",
        )

    try:
        await feedback_module.redis_client.delete(otp_key)
        await feedback_module.redis_client.delete(attempts_key)
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


async def _validate_contact_attachments(attachment_paths: list[str]) -> None:
    """Validates that attachment paths are well-formed and exist in feedback_attachments."""
    if not attachment_paths:
        return
    if len(attachment_paths) > _CONTACT_MAX_ATTACHMENTS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Cannot submit more than {_CONTACT_MAX_ATTACHMENTS} attachments.",
        )

    session_files: dict[str, list[str]] = {}
    for path in attachment_paths:
        if not path.startswith("web_contact/") or ".." in path or "\\" in path:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid attachment path.",
            )
        parts = path.split("/")
        if len(parts) != 3:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid attachment path format.",
            )
        prefix, session_id, filename = parts
        if prefix != "web_contact" or not session_id or not filename:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid attachment path format.",
            )
        clean_session = "".join(c for c in session_id if c.isalnum() or c in ("-", "_"))[:48]
        if clean_session != session_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid session identifier in attachment path.",
            )
        session_files.setdefault(clean_session, []).append(filename)

    for session_id, filenames in session_files.items():
        try:
            objects = await asyncio.to_thread(
                lambda: feedback_module.supabase_client.storage.from_("feedback_attachments").list(
                    f"web_contact/{session_id}",
                ),
            )
            existing_names = {
                obj.get("name")
                for obj in (objects or [])
                if obj.get("name")
            }
            for fname in filenames:
                if fname not in existing_names:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"Attachment file not found: {fname}",
                    )
        except HTTPException:
            raise
        except Exception as err:
            logger.warning("Failed to verify attachments in storage for session %s: %s", session_id, err)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Attachment verification failed.",
            ) from err


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

    if payload.attachment_paths:
        await _validate_contact_attachments(payload.attachment_paths)

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


@router.post("/api/v1/contact/error-session")
@limiter.limit(settings.rate_limit_feedback)
async def create_error_session(
    request: Request,
    payload: ErrorSessionCreateRequest = Body(...),
) -> dict[str, Any]:
    """Stores a temporary error report session in Redis (10 min TTL) for secure web contact prefilling."""
    _ = request
    session_uuid = secrets.token_hex(16)
    session_id = f"err_sess_{session_uuid}"
    key = f"contact:error_session:{session_id}"

    data = {
        "query_type": payload.query_type,
        "subject": payload.subject,
        "message": payload.message,
        "email": payload.email,
        "name": payload.name,
        "sentry_event_id": payload.sentry_event_id,
        "app_version": payload.app_version,
        "platform": payload.platform,
    }

    try:
        import json
        await feedback_module.redis_client.set(key, json.dumps(data), ex=600)
    except Exception as err:
        logger.exception("Failed to store error session in Redis")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to store error session.",
        ) from err

    return {"session_id": session_id, "expires_in": 600}


@router.get("/api/v1/contact/error-session/{session_id}")
@limiter.limit(settings.rate_limit_feedback)
async def get_error_session(
    request: Request,
    session_id: str,
) -> dict[str, Any]:
    """Retrieves and atomically deletes a temporary error report session from Redis."""
    _ = request
    clean_id = "".join(c for c in session_id if c.isalnum() or c in ("-", "_"))[:64]
    key = f"contact:error_session:{clean_id}"

    try:
        raw_data = await feedback_module.redis_client.get(key)
        if not raw_data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Error session expired or invalid.",
            )
        import json
        data = json.loads(raw_data)
        await feedback_module.redis_client.delete(key)
        return data
    except HTTPException:
        raise
    except Exception as err:
        logger.exception("Failed to fetch error session from Redis")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve error session.",
        ) from err

