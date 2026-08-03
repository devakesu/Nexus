"""Transactional email dispatch, dual-provider failover (Brevo & SendPulse), and template generation.

Provides email dispatch capabilities with automatic fallback between Brevo and SendPulse,
HTML-to-text fallback generation, PII sanitization for email logs, and HTML email templates.

All symbols are re-exported from their sub-modules for full backward compatibility.
"""

from app.core.email.config import (
    ProviderResult,
    SendEmailProps,
    get_feedback_notify_email,
    get_sender_email,
    get_sender_name,
    get_support_email,
    has_brevo,
    has_sendpulse,
    redact,
    redact_email,
    strip_tags,
)
from app.core.email.notifications import (
    FEEDBACK_QUERY_TYPE_LABELS,
    extract_user_name,
    send_account_deletion_otp_email,
    send_account_deletion_scheduled_email,
    send_account_reactivated_email,
    send_bootstrap_welcome_email,
    send_data_export_otp_email,
    send_feedback_admin_notification_email,
    send_feedback_closed_admin_notification_email,
    send_feedback_comment_admin_notification_email,
    send_feedback_confirmation_email,
    send_login_otp_email,
    send_support_appeal_otp_email,
    send_trusted_contact_removed_email,
)
from app.core.email.senders import send_email, send_via_brevo, send_via_sendpulse
from app.core.email.templates import render_cta_button_row, render_email_template

__all__ = [
    "FEEDBACK_QUERY_TYPE_LABELS",
    "ProviderResult",
    "SendEmailProps",
    "extract_user_name",
    "get_feedback_notify_email",
    "get_sender_email",
    "get_sender_name",
    "get_support_email",
    "has_brevo",
    "has_sendpulse",
    "redact",
    "redact_email",
    "render_cta_button_row",
    "render_email_template",
    "send_account_deletion_otp_email",
    "send_account_deletion_scheduled_email",
    "send_account_reactivated_email",
    "send_bootstrap_welcome_email",
    "send_data_export_otp_email",
    "send_email",
    "send_feedback_admin_notification_email",
    "send_feedback_closed_admin_notification_email",
    "send_feedback_comment_admin_notification_email",
    "send_feedback_confirmation_email",
    "send_login_otp_email",
    "send_support_appeal_otp_email",
    "send_trusted_contact_removed_email",
    "send_via_brevo",
    "send_via_sendpulse",
    "strip_tags",
]

