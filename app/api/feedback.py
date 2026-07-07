import asyncio
import logging

from fastapi import APIRouter, BackgroundTasks, Body, Depends, HTTPException, Request

from app.api.dependencies import get_authenticated_user_id, verify_app_check_token
from app.core.config import settings
from app.core.email import (
    send_feedback_admin_notification_email,
    send_feedback_confirmation_email,
)
from app.core.limiter import limiter
from app.db.client import DatabaseAccessError
from app.db.feedback import fetch_user_email, record_feedback_submission
from app.models import FeedbackSubmitRequest, FeedbackSubmitResponse

router = APIRouter()
logger = logging.getLogger(__name__)


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
            contact_email=payload.contact_email,
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
    notify_email = payload.contact_email or account_email

    if notify_email:
        background_tasks.add_task(
            send_feedback_confirmation_email,
            email=notify_email,
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
        contact_email=notify_email,
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
