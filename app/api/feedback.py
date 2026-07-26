"""FastAPI router for user feedback submissions, support ticket tracking, attachment uploads, and admin ticket comments.

Handles public and authenticated endpoints for submitting bug reports/feature requests,
attaching screenshot assets, managing ticket comments, and administrative status updates.
"""

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
    Depends,
    File,
    HTTPException,
    Query,
    Request,
    UploadFile,
    status,
)
from postgrest.exceptions import APIError
from pydantic import BaseModel, Field, field_validator
from redis.exceptions import RedisError

from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.core.cache import redis_client
from app.core.config import settings
from app.core.email import (
    send_feedback_admin_notification_email,
    send_feedback_closed_admin_notification_email,
    send_feedback_comment_admin_notification_email,
    send_feedback_confirmation_email,
    send_support_appeal_otp_email,
)
from app.core.limiter import limiter
from app.db.client import DatabaseAccessError, supabase_client
from app.db.feedback import (
    add_ticket_comment,
    close_ticket,
    fetch_ticket_comments,
    fetch_ticket_report,
    fetch_ticket_status_history,
    fetch_user_email,
    fetch_user_tickets,
    record_feedback_submission,
)
from app.models import (
    FeedbackCloseRequest,
    FeedbackCommentEntry,
    FeedbackCommentRequest,
    FeedbackStatusHistoryEntry,
    FeedbackSubmitRequest,
    FeedbackSubmitResponse,
    FeedbackTicketDetail,
    FeedbackTicketSummary,
)

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


def _assemble_ticket_detail(
    user_id: str,
    report: dict[str, Any],
) -> FeedbackTicketDetail:
    """Assemble ticket detail.

        Args:
            user_id: Unique UUID string of the authenticated user.
            report: Input report parameter.

        Returns:
            FeedbackTicketDetail: Response payload or result."""
    history = fetch_ticket_status_history(report["id"])
    comments = fetch_ticket_comments(report["id"])

    masked_history: list[FeedbackStatusHistoryEntry] = []
    for h in history:
        h_copy = dict(h)
        if h_copy.get("changed_by") and h_copy["changed_by"] != user_id:
            h_copy["changed_by"] = "staff"
        masked_history.append(FeedbackStatusHistoryEntry(**h_copy))

    masked_comments: list[FeedbackCommentEntry] = []
    for c in comments:
        c_copy = dict(c)
        is_own = c_copy.get("author_id") == user_id
        if not is_own:
            c_copy["author_id"] = "staff"
        masked_comments.append(FeedbackCommentEntry(**c_copy, is_own=is_own))

    return FeedbackTicketDetail(
        **report,
        status_history=masked_history,
        comments=masked_comments,
    )


@router.post("/api/v1/feedback/submit", response_model=FeedbackSubmitResponse)
@limiter.limit(settings.rate_limit_feedback)
async def submit_feedback(
    request: Request,
    background_tasks: BackgroundTasks,
    payload: FeedbackSubmitRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> FeedbackSubmitResponse:
    """Submits a new user support ticket, bug report, or feature request.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            background_tasks: FastAPI BackgroundTasks queue for asynchronous task execution.
            payload: Validated request body model containing parameters.
            _device: App Check attestation token dependency guard.
            user_id: Unique UUID string of the authenticated user.

        Returns:
            FeedbackSubmitResponse: Response payload or result."""
    _ = request

    own_prefix = f"{user_id}/"
    for path in payload.attachment_paths:
        if not path.startswith(own_prefix):
            raise HTTPException(
                status_code=422,
                detail="attachment_paths may only reference your own uploads.",
            )

    try:
        row = await asyncio.to_thread(
            record_feedback_submission,
            user_id=user_id,
            query_type=payload.query_type,
            subject=payload.subject,
            message=payload.message,
            github_issue_url=payload.github_issue_url,
            attachment_paths=payload.attachment_paths,
            app_version=payload.app_version,
            platform=payload.platform,
            device_info=payload.device_info,
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error submitting feedback",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    report_id = str(row["id"])
    account_email = await asyncio.to_thread(fetch_user_email, user_id)

    if account_email:
        background_tasks.add_task(
            send_feedback_confirmation_email,
            email=account_email,
            query_type=payload.query_type,
            subject=payload.subject,
            report_id=report_id,
        )
    else:
        logger.warning(
            "No email on file; skipping feedback confirmation email",
            extra={"user_id": user_id, "report_id": report_id},
        )

    background_tasks.add_task(
        send_feedback_admin_notification_email,
        report_id=report_id,
        query_type=payload.query_type,
        subject=payload.subject,
        message=payload.message,
        user_id=user_id,
        submitter_email=account_email,
        github_issue_url=payload.github_issue_url,
        attachment_count=len(payload.attachment_paths),
        app_version=payload.app_version,
        platform=payload.platform,
    )

    return FeedbackSubmitResponse(
        id=report_id,
        status=str(row.get("status", "open")),
        created_at=row["created_at"],
    )


@router.get("/api/v1/feedback/mine", response_model=list[FeedbackTicketSummary])
@limiter.limit(settings.rate_limit_discover)
async def list_my_feedback_tickets(
    request: Request,
    limit: int | None = Query(default=None, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> list[FeedbackTicketSummary]:
    """Lists all support and feedback tickets created by the caller.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            limit: Input limit parameter.
            offset: Input offset parameter.
            _device: App Check attestation token dependency guard.
            user_id: Unique UUID string of the authenticated user.

        Returns:
            list[FeedbackTicketSummary]: Response payload or result."""
    _ = request
    try:
        rows = await asyncio.to_thread(fetch_user_tickets, user_id, limit, offset)
    except DatabaseAccessError as err:
        logger.exception("Database error listing tickets", extra={"user_id": user_id})
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err
    return [FeedbackTicketSummary(**row) for row in rows]


@router.get("/api/v1/feedback/{report_id}", response_model=FeedbackTicketDetail)
@limiter.limit(settings.rate_limit_discover)
async def get_feedback_ticket(
    request: Request,
    report_id: str,
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> FeedbackTicketDetail:
    """Fetches detailed status, history, and comments for a specific feedback ticket.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            report_id: Input report id parameter.
            _device: App Check attestation token dependency guard.
            user_id: Unique UUID string of the authenticated user.

        Returns:
            FeedbackTicketDetail: Response payload or result."""
    _ = request
    try:
        report = await asyncio.to_thread(fetch_ticket_report, user_id, report_id)
    except DatabaseAccessError as err:
        logger.exception(
            "Database error fetching ticket",
            extra={"user_id": user_id, "report_id": report_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    if report is None:
        raise HTTPException(status_code=404, detail="Ticket not found.")

    try:
        return await asyncio.to_thread(_assemble_ticket_detail, user_id, report)
    except DatabaseAccessError as err:
        logger.exception(
            "Database error assembling ticket detail",
            extra={"user_id": user_id, "report_id": report_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err


@router.post(
    "/api/v1/feedback/{report_id}/comments",
    response_model=FeedbackCommentEntry,
)
@limiter.limit(settings.rate_limit_feedback)
async def add_feedback_comment(
    request: Request,
    report_id: str,
    background_tasks: BackgroundTasks,
    payload: FeedbackCommentRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> FeedbackCommentEntry:
    """Appends a new user or administrative comment to an open feedback ticket.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            report_id: Input report id parameter.
            background_tasks: FastAPI BackgroundTasks queue for asynchronous task execution.
            payload: Validated request body model containing parameters.
            _device: App Check attestation token dependency guard.
            user_id: Unique UUID string of the authenticated user.

        Returns:
            FeedbackCommentEntry: Response payload or result."""
    _ = request
    try:
        report = await asyncio.to_thread(fetch_ticket_report, user_id, report_id)
    except DatabaseAccessError as err:
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    if report is None:
        raise HTTPException(status_code=404, detail="Ticket not found.")
    if report["status"] == "closed":
        raise HTTPException(
            status_code=400,
            detail="This ticket is closed and no longer accepting comments.",
        )

    try:
        row = await asyncio.to_thread(
            add_ticket_comment,
            report_id,
            user_id,
            payload.body,
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error adding ticket comment",
            extra={"user_id": user_id, "report_id": report_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    account_email = await asyncio.to_thread(fetch_user_email, user_id)

    background_tasks.add_task(
        send_feedback_comment_admin_notification_email,
        report_id=report_id,
        query_type=str(report.get("query_type", "help")),
        subject=str(report.get("subject", "")),
        comment_body=payload.body,
        user_id=user_id,
        submitter_email=account_email,
    )

    return FeedbackCommentEntry(**row, is_own=True)


@router.post("/api/v1/feedback/{report_id}/close", response_model=FeedbackTicketDetail)
@limiter.limit(settings.rate_limit_feedback)
async def close_feedback_ticket(
    request: Request,
    report_id: str,
    background_tasks: BackgroundTasks,
    payload: FeedbackCloseRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> FeedbackTicketDetail:
    """Closes an active feedback ticket and marks it resolved.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            report_id: Input report id parameter.
            background_tasks: FastAPI BackgroundTasks queue for asynchronous task execution.
            payload: Validated request body model containing parameters.
            _device: App Check attestation token dependency guard.
            user_id: Unique UUID string of the authenticated user.

        Returns:
            FeedbackTicketDetail: Response payload or result."""
    _ = request
    try:
        report = await asyncio.to_thread(
            close_ticket,
            user_id,
            report_id,
            payload.reason,
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error closing ticket",
            extra={"user_id": user_id, "report_id": report_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    if report is None:
        # Either the ticket doesn't exist/isn't owned by this user, or it's
        # already closed - disambiguate for a clearer client-side message.
        existing = await asyncio.to_thread(fetch_ticket_report, user_id, report_id)
        if existing is None:
            raise HTTPException(status_code=404, detail="Ticket not found.")
        raise HTTPException(status_code=400, detail="This ticket is already closed.")

    account_email = await asyncio.to_thread(fetch_user_email, user_id)

    background_tasks.add_task(
        send_feedback_closed_admin_notification_email,
        report_id=report_id,
        query_type=str(report.get("query_type", "help")),
        subject=str(report.get("subject", "")),
        reason=payload.reason,
        user_id=user_id,
        submitter_email=account_email,
    )

    try:
        return await asyncio.to_thread(_assemble_ticket_detail, user_id, report)
    except DatabaseAccessError as err:
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err


class ContactOtpRequest(BaseModel):
    """Contactotprequest class representation."""
    email: str = Field(..., description="Email address for verification")
    turnstile_token: str | None = Field(default=None, description="Cloudflare Turnstile token")


class ContactSubmitRequest(BaseModel):
    """Contactsubmitrequest class representation."""
    email: str = Field(..., description="Email address of the submitter")
    otp_code: str = Field(
        ..., min_length=6, max_length=6, description="6-digit verification OTP code",
    )
    query_type: str = Field(
        default="help",
        description="Category: help, feedback, bug_report, suspended, security, or other",
    )
    subject: str = Field(..., min_length=3, max_length=150)
    message: str = Field(..., min_length=10, max_length=5000)
    name: str | None = Field(default=None, max_length=100)
    account_id_or_phone: str | None = Field(default=None, max_length=100)
    github_issue_url: str | None = Field(default=None, max_length=300)
    attachment_paths: list[str] = Field(
        default_factory=list,
        description="Optional attachment storage paths (max 5)",
    )
    turnstile_token: str | None = Field(default=None)

    @field_validator("attachment_paths")
    @classmethod
    def validate_attachment_paths(cls, v: list[str]) -> list[str]:
        """Executes validate attachment paths operation.

            Args:
                v: Input v parameter.

            Returns:
                list[str]: Response payload or result."""
        if len(v) > 5:
            raise ValueError("attachment_paths supports at most 5 files")
        # Validate path format to prevent directory traversal and invalid paths
        for path in v:
            path_str = str(path).strip()
            if ".." in path_str or path_str.startswith("/") or "\\" in path_str:
                raise ValueError("Invalid attachment path format")
            ext = path_str.split(".")[-1].lower() if "." in path_str else ""
            allowed_exts = {"jpg", "jpeg", "png", "webp", "gif", "pdf", "txt", "log"}
            if ext not in allowed_exts:
                raise ValueError(f"File extension .{ext} is not allowed")
        return v


@router.post("/api/v1/contact/upload")
@limiter.limit(settings.rate_limit_feedback)
async def upload_contact_attachment(
    request: Request,
    file: UploadFile = File(...),
    session_id: str = Query(default=""),
) -> dict[str, str]:
    """Uploads a screenshot or file attachment for a support ticket.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            file: Input file parameter.
            session_id: Input session id parameter.

        Returns:
            dict[str, str]: Response payload or result."""
    _ = request
    if not file.filename:
        raise HTTPException(status_code=400, detail="Filename is required.")

    # Validate session_id to prevent path traversal
    clean_session = "".join(c for c in session_id if c.isalnum() or c in ("-", "_"))[:48]
    if not clean_session:
        clean_session = secrets.token_hex(8)

    filename = file.filename.strip()
    ext = filename.split(".")[-1].lower() if "." in filename else ""
    allowed_exts = {"jpg", "jpeg", "png", "webp", "gif", "pdf", "txt", "log"}
    if ext not in allowed_exts:
        raise HTTPException(
            status_code=400,
            detail=f"File type .{ext} is not allowed.",
        )

    content = await file.read()
    if len(content) > 8 * 1024 * 1024:
        raise HTTPException(
            status_code=400,
            detail="File size exceeds maximum allowed limit of 8MB.",
        )

    file_id = secrets.token_hex(6)
    clean_name = "".join(c for c in filename if c.isalnum() or c in (".", "_", "-"))
    # Scoped to a unique session subfolder to avoid filename collisions across users
    storage_path = f"web_contact/{clean_session}/{file_id}_{clean_name}"

    try:
        # Map extensions to the MIME types allowed by the feedback_attachments bucket policy.
        _ext_to_mime = {
            "jpg": "image/jpeg",
            "jpeg": "image/jpeg",
            "png": "image/png",
            "webp": "image/webp",
            "gif": "image/gif",
            "pdf": "application/pdf",
            "txt": "text/plain",
            "log": "text/plain",
        }
        content_type = _ext_to_mime.get(ext, "application/octet-stream")
        await asyncio.to_thread(
            lambda: supabase_client.storage.from_("feedback_attachments").upload(
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
) -> dict[str, bool]:
    """Delete orphaned attachments from storage when ticket submission fails.

    Only paths scoped to the provided session_id subfolder are deleted —
    callers cannot delete files from other sessions.
    """
    _ = request
    # Sanitize the caller-supplied session_id the same way the upload endpoint does
    clean_session = "".join(c for c in session_id if c.isalnum() or c in ("-", "_"))[:48]
    if not clean_session:
        raise HTTPException(status_code=400, detail="Invalid session_id.")

    # Only allow deleting paths that belong to this specific session subfolder
    allowed_prefix = f"web_contact/{clean_session}/"
    safe_paths = [
        p for p in paths
        if p.startswith(allowed_prefix) and ".." not in p
    ]
    if not safe_paths:
        return {"success": True}
    try:
        await asyncio.to_thread(
            lambda: supabase_client.storage.from_("feedback_attachments").remove(safe_paths),
        )
    except (APIError, RuntimeError, ValueError, KeyError, AttributeError):
        logger.warning("Failed to clean up orphaned contact attachments: %s", safe_paths)
        # Best-effort; don't fail the response
    return {"success": True}


@router.post("/api/v1/contact/otp/send")
@limiter.limit(settings.rate_limit_auth)
async def send_contact_otp(
    request: Request,
    payload: ContactOtpRequest = Body(...),
) -> dict[str, bool]:
    """Dispatches an email OTP code to verify contact form submission identity.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            payload: Validated request body model containing parameters.

        Returns:
            dict[str, bool]: Response payload or result."""
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
        await redis_client.set(otp_key, otp_code, ex=600)
    except Exception as err:
        logger.exception("Failed to store appeal OTP in Redis")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Support service temporarily unavailable.",
        ) from err

    email_res = await send_support_appeal_otp_email(email, otp_code)
    if not email_res.success:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send verification email.",
        )

    return {"success": True}


@router.post("/api/v1/contact/submit")
@limiter.limit(settings.rate_limit_auth)
async def submit_contact_ticket(  # noqa: C901
    request: Request,
    background_tasks: BackgroundTasks,
    payload: ContactSubmitRequest = Body(...),
) -> dict[str, Any]:
    """Submits a contact form inquiry ticket after OTP verification.

    Args:
        request: FastAPI HTTP request object used for rate limiting.
        background_tasks: FastAPI BackgroundTasks queue for notification email dispatch.
        payload: Contact form submission payload.

    Returns:
        dict[str, Any]: Ticket creation status and short reference ID.
    """
    _ = request
    if not payload.turnstile_token and not payload.otp_code:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Security verification failed. Please refresh and try again.",
        )

    email = payload.email.strip().lower()
    otp_code = payload.otp_code.strip()

    otp_key = f"appeal:otp:{email}"
    try:
        stored_otp = await redis_client.get(otp_key)
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
        await redis_client.delete(otp_key)
    except (RedisError, RuntimeError) as err:
        logger.warning("Failed to delete appeal OTP key %s: %s", otp_key, err)

    user_id: str | None = None
    try:
        rpc_res = await asyncio.to_thread(
            lambda: supabase_client.rpc(
                "get_user_id_by_email", {"email_addr": email},
            ).execute(),
        )
        if rpc_res.data and isinstance(rpc_res.data, str):
            user_id = rpc_res.data
    except (APIError, RuntimeError, ValueError) as err:
        logger.warning("Optional user lookup by email failed: %s", err)

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
            record_feedback_submission,
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
        # Clean up uploaded files from storage since the ticket wasn't recorded
        if payload.attachment_paths:
            try:
                safe_paths = [
                    p for p in payload.attachment_paths
                    if p.startswith("web_contact/") and ".." not in p
                ]
                await asyncio.to_thread(
                    lambda: supabase_client.storage.from_("feedback_attachments").remove(safe_paths),
                )
            except (APIError, RuntimeError, ValueError):
                logger.warning("Failed to clean up attachments after ticket insert failure")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to submit support ticket. Please try again.",
        ) from err

    report_id = str(report_row["id"])
    background_tasks.add_task(
        send_feedback_confirmation_email,
        email=email,
        query_type=query_type,
        subject=subject,
        report_id=report_id,
    )
    background_tasks.add_task(
        send_feedback_admin_notification_email,
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

