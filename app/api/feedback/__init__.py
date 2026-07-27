"""FastAPI router for user feedback submissions, support ticket tracking, attachment uploads, and admin ticket comments.

Handles public and authenticated endpoints for submitting bug reports/feature requests,
attaching screenshot assets, managing ticket comments, and administrative status updates.
"""

from fastapi import APIRouter

from app.api.feedback.contact import (
    delete_contact_attachments,
    send_contact_otp,
    submit_contact_ticket,
    upload_contact_attachment,
    verify_turnstile_token,
)
from app.api.feedback.contact import (
    router as contact_router,
)
from app.api.feedback.models import ContactOtpRequest, ContactSubmitRequest
from app.api.feedback.tickets import (
    _assemble_ticket_detail,
    add_feedback_comment,
    close_feedback_ticket,
    get_feedback_ticket,
    list_my_feedback_tickets,
    submit_feedback,
)
from app.api.feedback.tickets import (
    router as tickets_router,
)
from app.core.email import (
    send_feedback_admin_notification_email,
    send_feedback_closed_admin_notification_email,
    send_feedback_comment_admin_notification_email,
    send_feedback_confirmation_email,
    send_support_appeal_otp_email,
)
from app.core.infra.cache import redis_client
from app.db.client import supabase_client
from app.db.feedback import (
    add_ticket_comment,
    close_ticket,
    fetch_ticket_report,
    fetch_user_email,
    record_feedback_submission,
)

router = APIRouter()

router.include_router(contact_router)
router.include_router(tickets_router)

__all__ = [
    "ContactOtpRequest",
    "ContactSubmitRequest",
    "_assemble_ticket_detail",
    "add_feedback_comment",
    "add_ticket_comment",
    "close_feedback_ticket",
    "close_ticket",
    "delete_contact_attachments",
    "fetch_ticket_report",
    "fetch_user_email",
    "get_feedback_ticket",
    "list_my_feedback_tickets",
    "record_feedback_submission",
    "redis_client",
    "router",
    "send_contact_otp",
    "send_feedback_admin_notification_email",
    "send_feedback_closed_admin_notification_email",
    "send_feedback_comment_admin_notification_email",
    "send_feedback_confirmation_email",
    "send_support_appeal_otp_email",
    "submit_contact_ticket",
    "submit_feedback",
    "supabase_client",
    "upload_contact_attachment",
    "verify_turnstile_token",
]
