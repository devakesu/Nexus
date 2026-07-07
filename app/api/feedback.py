import asyncio
import logging
from typing import Any

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Body,
    Depends,
    HTTPException,
    Query,
    Request,
)

from app.api.dependencies import get_authenticated_user_id, verify_app_check_token
from app.core.config import settings
from app.core.email import (
    send_feedback_admin_notification_email,
    send_feedback_confirmation_email,
)
from app.core.limiter import limiter
from app.db.client import DatabaseAccessError
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
    return FeedbackTicketDetail(
        **report,
        status_history=[FeedbackStatusHistoryEntry(**h) for h in history],
        comments=[
            FeedbackCommentEntry(**c, is_own=c.get("author_id") == user_id)
            for c in comments
        ],
    )


@router.post("/api/v1/feedback/submit", response_model=FeedbackSubmitResponse)
@limiter.limit(settings.rate_limit_feedback)
async def submit_feedback(
    request: Request,
    background_tasks: BackgroundTasks,
    payload: FeedbackSubmitRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
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
    user_id: str = Depends(get_authenticated_user_id),
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
    user_id: str = Depends(get_authenticated_user_id),
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
    user_id: str = Depends(get_authenticated_user_id),
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
    user_id: str = Depends(get_authenticated_user_id),
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
