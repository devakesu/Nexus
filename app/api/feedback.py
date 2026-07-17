import asyncio
import logging
import secrets
import string
from typing import Any

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Body,
    Depends,
    HTTPException,
    Query,
    Request,
    status,
)
from pydantic import BaseModel, Field

from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.core.cache import redis_client
from app.core.config import settings
from app.core.email import (
    send_feedback_admin_notification_email,
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


def _assemble_ticket_detail(
    user_id: str,
    report: dict[str, Any],
) -> FeedbackTicketDetail:
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
    payload: FeedbackSubmitRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> FeedbackSubmitResponse:
    _ = request

    # Attachments must live under the caller's own folder in the
    # feedback_attachments bucket (storage RLS also enforces this on
    # upload) - reject anything else outright rather than trusting the
    # client-supplied path list at face value.
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
    payload: FeedbackCommentRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> FeedbackCommentEntry:
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

    return FeedbackCommentEntry(**row, is_own=True)


@router.post("/api/v1/feedback/{report_id}/close", response_model=FeedbackTicketDetail)
@limiter.limit(settings.rate_limit_feedback)
async def close_feedback_ticket(
    request: Request,
    report_id: str,
    payload: FeedbackCloseRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> FeedbackTicketDetail:
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

    try:
        return await asyncio.to_thread(_assemble_ticket_detail, user_id, report)
    except DatabaseAccessError as err:
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err


class SupportAppealOtpRequest(BaseModel):
    email: str = Field(..., description="Email address of the account to appeal")


class SupportAppealSubmitRequest(BaseModel):
    email: str = Field(..., description="Email address of the account")
    otp_code: str = Field(
        ..., min_length=6, max_length=6, description="6-digit verification OTP code",
    )
    subject: str = Field(..., min_length=3, max_length=150)
    message: str = Field(..., min_length=10, max_length=5000)


@router.post("/api/v1/feedback/appeal-otp/send")
@limiter.limit(settings.rate_limit_auth)
async def send_appeal_otp(
    request: Request,
    payload: SupportAppealOtpRequest = Body(...),  # noqa: B008
) -> dict[str, bool]:
    _ = request
    email = payload.email.strip().lower()
    if not email:
        raise HTTPException(status_code=400, detail="Email is required.")

    try:
        rpc_res = await asyncio.to_thread(
            lambda: supabase_client.rpc(
                "get_user_id_by_email", {"email_addr": email},
            ).execute()
        )
        user_id = rpc_res.data
    except Exception as err:
        logger.exception("Failed to resolve user ID by email via RPC")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Support service temporarily unavailable.",
        ) from err

    if not user_id:
        logger.info("Appeal OTP requested for non-existent email: %s", email)
        return {"success": True}

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


@router.post("/api/v1/feedback/appeal/submit")
@limiter.limit(settings.rate_limit_auth)
async def submit_appeal_ticket(
    request: Request,
    background_tasks: BackgroundTasks,
    payload: SupportAppealSubmitRequest = Body(...),  # noqa: B008
) -> dict[str, Any]:
    _ = request
    email = payload.email.strip().lower()
    otp_code = payload.otp_code.strip()

    otp_key = f"appeal:otp:{email}"
    try:
        stored_otp = await redis_client.get(otp_key)
    except Exception as err:
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
    except Exception as err:
        logger.warning("Failed to delete appeal OTP key %s: %s", otp_key, err)

    try:
        rpc_res = await asyncio.to_thread(
            lambda: supabase_client.rpc(
                "get_user_id_by_email", {"email_addr": email},
            ).execute()
        )
        user_id = rpc_res.data
    except Exception as err:
        logger.exception("Failed to resolve user ID by email via RPC")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Support service temporarily unavailable.",
        ) from err

    if not user_id or not isinstance(user_id, str):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No account associated with this email address.",
        )

    query_type = "help"
    subject = payload.subject.strip()
    message = payload.message.strip()

    try:
        report_row = await asyncio.to_thread(
            record_feedback_submission,
            user_id=user_id,
            query_type=query_type,
            subject=subject,
            message=message,
            github_issue_url=None,
            attachment_paths=[],
            app_version=None,
            platform=None,
            device_info={},
            contact_email=email,
            metadata={"source": "unauthenticated_appeal"},
        )
    except Exception as err:
        logger.exception("Failed to record support appeal ticket in DB")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Failed to submit appeal ticket. Please try again.",
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
        user_id=user_id,
        submitter_email=email,
    )

    return {
        "success": True,
        "ticket_id": report_id,
    }
