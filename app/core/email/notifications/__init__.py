"""Transactional email notification modules.

Contains sub-modules categorized by function: welcome, feedback, safety, and account.
"""

from app.core.email.notifications.account import (
    send_account_deletion_otp_email,
    send_account_deletion_scheduled_email,
    send_account_reactivated_email,
    send_data_export_otp_email,
    send_login_otp_email,
    send_support_appeal_otp_email,
)
from app.core.email.notifications.feedback import (
    FEEDBACK_QUERY_TYPE_LABELS,
    send_feedback_admin_notification_email,
    send_feedback_closed_admin_notification_email,
    send_feedback_comment_admin_notification_email,
    send_feedback_confirmation_email,
)
from app.core.email.notifications.helpers import extract_user_name
from app.core.email.notifications.safety import send_trusted_contact_removed_email
from app.core.email.notifications.welcome import send_bootstrap_welcome_email

__all__ = [
    "FEEDBACK_QUERY_TYPE_LABELS",
    "extract_user_name",
    "send_account_deletion_otp_email",
    "send_account_deletion_scheduled_email",
    "send_account_reactivated_email",
    "send_bootstrap_welcome_email",
    "send_data_export_otp_email",
    "send_feedback_admin_notification_email",
    "send_feedback_closed_admin_notification_email",
    "send_feedback_comment_admin_notification_email",
    "send_feedback_confirmation_email",
    "send_login_otp_email",
    "send_support_appeal_otp_email",
    "send_trusted_contact_removed_email",
]
