"""Authenticated feedback tickets, comments, and ticket resolution endpoints."""

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

import app.api.feedback as feedback_module
from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.core.config import settings
from app.core.infra.limiter import limiter
from app.db.client import DatabaseAccessError
from app.db.feedback import (
    fetch_ticket_comments,
    fetch_ticket_status_history,
    fetch_user_tickets,
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


async def assemble_ticket_detail(
    user_id: str,
    report: dict[str, Any],
) -> FeedbackTicketDetail:
    """Assembles full feedback ticket detail including status history and comments concurrently."""
    report_id = report["id"]
    history, comments = await asyncio.gather(
        asyncio.to_thread(fetch_ticket_status_history, report_id),
        asyncio.to_thread(fetch_ticket_comments, report_id),
    )

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


_assemble_ticket_detail = assemble_ticket_detail


def _is_valid_attachment_path(path: str, own_prefix: str) -> bool:
    """Verify that an attachment path is within own prefix and has no traversal or percent encoding."""
    if not path or not path.startswith(own_prefix):
        return False
    if ".." in path or "\\" in path or "\x00" in path or "%" in path or path.startswith("/"):
        return False
    parts = path.split("/")
    return len(parts) == 2 and bool(parts[1])


async def _verify_user_storage_files(user_id: str, attachment_paths: list[str]) -> None:
    if not attachment_paths:
        return
    own_prefix = f"{user_id}/"
    filenames: list[str] = []
    for path in attachment_paths:
        if not _is_valid_attachment_path(path, own_prefix):
            raise HTTPException(
                status_code=422,
                detail="attachment_paths may only reference your own uploads.",
            )
        filenames.append(path.split("/")[1])

    try:
        objects = await asyncio.to_thread(
            lambda: feedback_module.supabase_client.storage.from_("feedback_attachments").list(user_id),
        )
        existing_names = {
            obj.get("name")
            for obj in (objects or [])
            if obj.get("name")
        }
        for fname in filenames:
            if fname not in existing_names:
                raise HTTPException(
                    status_code=400,
                    detail=f"Attachment file not found: {fname}",
                )
    except HTTPException:
        raise
    except Exception as err:
        logger.warning(
            "Failed to verify attachments in storage for user %s: %s",
            user_id,
            err,
        )
        raise HTTPException(
            status_code=400,
            detail="Attachment verification failed.",
        ) from err


@router.post("/api/v1/feedback/submit", response_model=FeedbackSubmitResponse)
@limiter.limit(settings.rate_limit_feedback)
async def submit_feedback(
    request: Request,
    background_tasks: BackgroundTasks,
    payload: FeedbackSubmitRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> FeedbackSubmitResponse:
    """Submits a new user support ticket, bug report, or feature request."""
    _ = request

    await _verify_user_storage_files(user_id, payload.attachment_paths)

    try:
        row = await asyncio.to_thread(
            feedback_module.record_feedback_submission,
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
    account_email = await asyncio.to_thread(feedback_module.fetch_user_email, user_id)

    if account_email:
        background_tasks.add_task(
            feedback_module.send_feedback_confirmation_email,
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
        feedback_module.send_feedback_admin_notification_email,
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
    """Lists all support and feedback tickets created by the caller."""
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
    """Fetches detailed status, history, and comments for a specific feedback ticket."""
    _ = request
    try:
        report = await asyncio.to_thread(feedback_module.fetch_ticket_report, user_id, report_id)
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
        return await feedback_module._assemble_ticket_detail(user_id, report)
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
    """Appends a new user or administrative comment to an open feedback ticket."""
    _ = request
    try:
        report = await asyncio.to_thread(feedback_module.fetch_ticket_report, user_id, report_id)
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
            feedback_module.add_ticket_comment,
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

    account_email = await asyncio.to_thread(feedback_module.fetch_user_email, user_id)

    background_tasks.add_task(
        feedback_module.send_feedback_comment_admin_notification_email,
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
    """Closes an active feedback ticket and marks it resolved."""
    _ = request
    try:
        report = await asyncio.to_thread(
            feedback_module.close_ticket,
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
        existing = await asyncio.to_thread(feedback_module.fetch_ticket_report, user_id, report_id)
        if existing is None:
            raise HTTPException(status_code=404, detail="Ticket not found.")
        raise HTTPException(status_code=400, detail="This ticket is already closed.")

    account_email = await asyncio.to_thread(feedback_module.fetch_user_email, user_id)

    background_tasks.add_task(
        feedback_module.send_feedback_closed_admin_notification_email,
        report_id=report_id,
        query_type=str(report.get("query_type", "help")),
        subject=str(report.get("subject", "")),
        reason=payload.reason,
        user_id=user_id,
        submitter_email=account_email,
    )

    try:
        return await feedback_module._assemble_ticket_detail(user_id, report)
    except DatabaseAccessError as err:
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err
