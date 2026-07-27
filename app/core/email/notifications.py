"""Email dispatch helper functions for notification types.

Contains template-rendering and sending logic for user welcome, feedback appeal,
feedback ticket submissions/closed, trusted contact actions, OTPs, deletion notifications,
and reactivation alerts.
"""

import logging
from datetime import datetime
from typing import Any, cast

from app.core.config import settings
from app.core.email.config import (
    ProviderResult,
    SendEmailProps,
    get_feedback_notify_email,
    redact_email,
    should_use_sendpulse,
)
from app.core.email.senders import send_email
from app.core.email.templates import render_cta_button_row, render_email_template

logger = logging.getLogger(__name__)

FEEDBACK_QUERY_TYPE_LABELS: dict[str, str] = {
    "help": "Help Request",
    "feedback": "Feedback",
    "bug_report": "Bug Report",
    "suspended": "Suspended Account Appeal",
    "security": "Security & Privacy",
    "legal_grievance": "Legal Grievance",
    "grievance": "Legal Grievance",
    "other": "Other Inquiry",
}


def _short_report_id(report_id: str) -> str:
    """Short report id.

        Args:
            report_id: Input report id parameter.

        Returns:
            str: Response payload or result."""
    return report_id.split("-")[0].upper()


def extract_user_name(email: str, auth_user: dict[str, Any] | None = None) -> str:
    """
    Tries to extract the name of the user from auth_user metadata, or falls back to
    formatting the prefix of their email address.
    """
    if auth_user:
        metadata = auth_user.get("user_metadata")
        if isinstance(metadata, dict):
            metadata_dict: dict[str, Any] = cast(dict[str, Any], metadata)
            for key in ("name", "full_name", "given_name", "display_name"):
                name_val = metadata_dict.get(key)
                if isinstance(name_val, str) and name_val.strip():
                    return name_val.strip()

    if email and "@" in email:
        prefix = email.split("@")[0]
        parts = [
            p.capitalize()
            for p in prefix.replace(".", " ")
            .replace("_", " ")
            .replace("-", " ")
            .split()
        ]
        if parts:
            return " ".join(parts)
    return "User"


async def send_bootstrap_welcome_email(
    email: str,
    auth_user: dict[str, Any] | None = None,
    app_variant: str = "nexus",
) -> ProviderResult:
    """
    Sends the welcome email to a user who completed the initial auth bootstrap.
    """
    user_name = extract_user_name(email, auth_user)

    row_1 = f"""
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #FFFFFF;
                         text-transform: uppercase;">
                N E X U S
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                        color: #9CA3AF; font-weight: 400;">
                Welcome, {user_name}! Your entry into the network has been
                authenticated. However, your mathematical coordinate orientation
                inside our vector universe is currently unmapped.
              </p>
            </td>
          </tr>
    """

    row_2 = """
          <tr>
            <td style="padding: 0 32px 32px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(255,255,255,0.01);
                     border-left: 2px solid #00ADB5;">
                <tr>
                  <td style="padding: 16px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 12px; line-height: 1.5; color: #4ECCA3;">
                    <span style="color: #6B7280;">STATUS:</span>
                    PROFILE_SETUP_PENDING<br />
                    <span style="color: #6B7280;">MATRIX:</span>
                    384_DIMENSIONAL_SEMANTIC_SPACE<br />
                    <span style="color: #6B7280;">TARGET:</span>
                    TIER_ORBIT_CONSTELLATION_GENERATION
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """

    row_3 = """
          <tr>
            <td style="padding: 0 32px 40px 32px; font-size: 14px;
                       line-height: 1.6; color: #9CA3AF;">
              <p style="margin: 0 0 24px 0;">
                To bypass the superficial, loop-driven nature of common social
                apps, Nexus projects your specific text profiles, explicit
                trends, and deep project goals directly onto a live coordinate
                canvas. To populate your custom interactive galaxy:
              </p>

              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="font-family: ui-monospace, SFMono-Regular, Menlo,
                     Monaco, Consolas, monospace; font-size: 12px;">
                <tr>
                  <td width="28" valign="top"
                       style="color: #00ADB5; padding-bottom: 12px;">[1]</td>
                  <td style="color: #E5E7EB; padding-bottom: 12px;">
                    <strong>Complete Profile Anchor:</strong> Input your personal
                    values, thoughts, and professional trajectories.
                  </td>
                </tr>
                <tr>
                  <td width="28" valign="top" style="color: #00ADB5;">[2]</td>
                  <td style="color: #E5E7EB;">
                    <strong>Unlock Spatial Discovery:</strong> Instantly
                    visualize real-time compatible connections structured across
                    concentric, proximity-based circles.
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """

    domain = (
        "nexus-mec.devakesu.com" if app_variant == "nexus_mec" else "nexus.devakesu.com"
    )
    button_row = render_cta_button_row(
        cta_text="Initialize Alignment",
        cta_url=f"https://{domain}/app",
    )

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3 + button_row,
        subject="Nexus Initialized",
        preheader_category="AUTH_GATE",
        preheader_action="SYSTEM_VERIFIED",
    )

    text_content = (
        f"Welcome, {user_name}! Your entry into the network has been authenticated. "
        "However, your mathematical coordinate orientation inside our vector universe "
        "is currently unmapped. Complete Profile Anchor to populate your custom "
        "interactive galaxy and unlock spatial discovery."
    )

    props = SendEmailProps(
        to=email,
        subject="Nexus Initialized",
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Support",
    )

    try:
        redacted = redact_email(email)
        logger.info("Sending auth bootstrap welcome email to %s", redacted)
        result = await send_email(props)
        if result.success:
            logger.info(
                "Successfully sent welcome email to %s via %s",
                redacted,
                result.provider,
            )
        else:
            logger.error(
                "Failed to send welcome email to %s: %s",
                redacted,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception while sending welcome email to %s",
            redact_email(email),
        )
        use_sp = should_use_sendpulse(email)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(
            success=False,
            provider=provider_name,
            error=str(err),
        )


async def send_feedback_confirmation_email(
    email: str,
    query_type: str,
    subject: str,
    report_id: str,
    auth_user: dict[str, Any] | None = None,
) -> ProviderResult:
    """
    Sends a confirmation receipt to the user after they submit a Help,
    Feedback & Bug Report ticket.
    """
    user_name = extract_user_name(email, auth_user)
    label = FEEDBACK_QUERY_TYPE_LABELS.get(query_type, "Request")
    ticket_ref = _short_report_id(report_id)
    support_link = (
        f'<a href="mailto:support@{settings.email_domain}" style="color: pink;">'
        f"support@{settings.email_domain}</a>"
    )
    footer_html = (
        f"You're receiving this because you submitted ticket #{ticket_ref} on "
        f"Nexus. Just reply to this email to add more detail, or reach us at "
        f"{support_link}."
    )

    row_1 = f"""
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #FFFFFF;
                         text-transform: uppercase;">
                N E X U S
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                        color: #9CA3AF; font-weight: 400;">
                Thanks, {user_name} - we've received your {label.lower()} and
                it's now in our queue. Our team typically responds within
                24-48 hours.
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 32px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(255,255,255,0.01);
                     border-left: 2px solid #00ADB5;">
                <tr>
                  <td style="padding: 16px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 12px; line-height: 1.5; color: #4ECCA3;">
                    <span style="color: #6B7280;">TICKET:</span>
                    #{ticket_ref}<br />
                    <span style="color: #6B7280;">CATEGORY:</span>
                    {label.upper()}<br />
                    <span style="color: #6B7280;">SUBJECT:</span>
                    {subject}<br />
                    <span style="color: #6B7280;">STATUS:</span>
                    OPEN
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """

    row_3 = """
          <tr>
            <td style="padding: 0 32px 40px 32px; font-size: 14px;
                       line-height: 1.6; color: #9CA3AF;">
              <p style="margin: 0;">
                No action is needed from you right now. If we need more
                detail, we'll follow up by replying directly to this email
                thread.
              </p>
            </td>
          </tr>
    """

    email_subject = f"[#{ticket_ref}] We've received your {label.lower()} - Nexus Support"

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject=email_subject,
        preheader_category="SUPPORT",
        preheader_action=f"TICKET_{ticket_ref}_OPEN",
        footer_html=footer_html,
    )

    text_content = (
        f"Thanks, {user_name} - we've received your {label.lower()} "
        f"(ticket #{ticket_ref}) and it's now in our queue. Our team "
        "typically responds within 24-48 hours."
    )

    props = SendEmailProps(
        to=email,
        subject=email_subject,
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Support",
    )

    try:
        redacted = redact_email(email)
        logger.info("Sending feedback confirmation email to %s", redacted)
        result = await send_email(props)
        if not result.success:
            logger.error(
                "Failed to send feedback confirmation email to %s: %s",
                redacted,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception while sending feedback confirmation email to %s",
            redact_email(email),
        )
        use_sp = should_use_sendpulse(email)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(success=False, provider=provider_name, error=str(err))


async def send_feedback_admin_notification_email(  # noqa: C901
    report_id: str,
    query_type: str,
    subject: str,
    message: str,
    user_id: str,
    submitter_email: str | None,
    github_issue_url: str | None = None,
    attachment_count: int = 0,
    attachment_names: list[str] | None = None,
    app_version: str | None = None,
    platform: str | None = None,
    submitter_name: str | None = None,
    account_id_or_phone: str | None = None,
) -> ProviderResult:
    """
    Notifies the admin/support inbox of a newly submitted Help, Feedback &
    Bug Report ticket, with reply-to set to the submitter so admins can
    respond directly.
    """
    label = FEEDBACK_QUERY_TYPE_LABELS.get(query_type, "Request")
    ticket_ref = _short_report_id(report_id)
    recipient = get_feedback_notify_email()

    escaped_message = (
        message.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    )

    def _detail_row(field: str, value: str) -> str:
        """Executes detail row operation.

            Args:
                field: Input field parameter.
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
        return f'<span style="color: #6B7280;">{field}:</span> {value}'

    contact_display = (
        f'<a href="mailto:{submitter_email}" style="color: #4ECCA3;">'
        f"{submitter_email}</a>"
        if submitter_email
        else "(none on file)"
    )
    detail_lines = [
        _detail_row("TICKET", f"#{ticket_ref}"),
        _detail_row("CATEGORY", label.upper()),
        _detail_row("SUBJECT", subject),
        _detail_row("USER_ID", user_id),
        _detail_row("CONTACT", contact_display),
    ]
    if submitter_name:
        detail_lines.append(_detail_row("NAME", submitter_name))
    if account_id_or_phone:
        detail_lines.append(_detail_row("PHONE_OR_ID", account_id_or_phone))
    if platform:
        detail_lines.append(_detail_row("PLATFORM", platform))
    if app_version:
        detail_lines.append(_detail_row("APP_VERSION", app_version))
    if attachment_names:
        names_display = ", ".join(
            name.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
            for name in attachment_names
        )
        detail_lines.append(_detail_row("ATTACHMENTS", f"{len(attachment_names)}: {names_display}"))
    elif attachment_count:
        detail_lines.append(_detail_row("ATTACHMENTS", str(attachment_count)))
    if github_issue_url:
        issue_link = (
            f'<a href="{github_issue_url}" style="color: #4ECCA3;">'
            f"{github_issue_url}</a>"
        )
        detail_lines.append(_detail_row("GITHUB_ISSUE", issue_link))

    row_1 = f"""
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 22px; font-weight: 300;
                         letter-spacing: 0.1em; color: #FFFFFF;
                         text-transform: uppercase;">
                New {label}
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                        color: #9CA3AF; font-weight: 400;">
                {subject}
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 24px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(255,255,255,0.01);
                     border-left: 2px solid #00ADB5;">
                <tr>
                  <td style="padding: 16px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 12px; line-height: 1.7; color: #4ECCA3;">
                    {"<br />".join(detail_lines)}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """

    row_3 = f"""
          <tr>
            <td style="padding: 0 32px 40px 32px; font-size: 14px;
                       line-height: 1.6; color: #E5E7EB;
                       white-space: pre-wrap;">
              {escaped_message}
            </td>
          </tr>
    """

    email_subject = f"[#{ticket_ref}] [Nexus {label}] {subject}"

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject=email_subject,
        preheader_category="ADMIN",
        preheader_action=f"NEW_{query_type.upper()}",
        footer_html="",
    )

    name_line = f"Name: {submitter_name}\n" if submitter_name else ""
    phone_line = f"Phone/ID: {account_id_or_phone}\n" if account_id_or_phone else ""
    attach_line: str
    if attachment_names:
        attach_line = f"Attachments ({len(attachment_names)}): {', '.join(attachment_names)}\n"
    elif attachment_count:
        attach_line = f"Attachments: {attachment_count}\n"
    else:
        attach_line = ""
    text_content = (
        f"New {label} - #{ticket_ref}\nSubject: {subject}\n"
        f"User: {user_id}\nContact: {submitter_email or '(none on file)'}\n"
        f"{name_line}{phone_line}{attach_line}\n"
        f"{message}"
    )

    props = SendEmailProps(
        to=recipient,
        subject=email_subject,
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Support",
        reply_to=submitter_email or None,
    )

    try:
        logger.info(
            "Sending feedback admin notification to %s for ticket #%s",
            redact_email(recipient),
            ticket_ref,
        )
        result = await send_email(props)
        if not result.success:
            logger.error(
                "Failed to send feedback admin notification for ticket #%s: %s",
                ticket_ref,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception sending feedback admin notification for ticket #%s",
            ticket_ref,
        )
        use_sp = should_use_sendpulse(recipient)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(success=False, provider=provider_name, error=str(err))


async def send_feedback_comment_admin_notification_email(
    report_id: str,
    query_type: str,
    subject: str,
    comment_body: str,
    user_id: str,
    submitter_email: str | None,
) -> ProviderResult:
    """
    Notifies the admin/support inbox when a user adds a new comment to an existing
    Help, Feedback & Bug Report ticket. Uses the exact same email subject line
    as the submission email so thread grouping occurs in email clients.
    """
    label = FEEDBACK_QUERY_TYPE_LABELS.get(query_type, "Request")
    ticket_ref = _short_report_id(report_id)
    recipient = get_feedback_notify_email()

    escaped_comment = (
        comment_body.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    )

    def _detail_row(field: str, value: str) -> str:
        """Executes detail row operation.

            Args:
                field: Input field parameter.
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
        return f'<span style="color: #6B7280;">{field}:</span> {value}'

    contact_display = (
        f'<a href="mailto:{submitter_email}" style="color: #4ECCA3;">'
        f"{submitter_email}</a>"
        if submitter_email
        else "(none on file)"
    )
    detail_lines = [
        _detail_row("TICKET", f"#{ticket_ref}"),
        _detail_row("ACTION", "NEW COMMENT"),
        _detail_row("CATEGORY", label.upper()),
        _detail_row("SUBJECT", subject),
        _detail_row("USER_ID", user_id),
        _detail_row("CONTACT", contact_display),
    ]

    row_1 = f"""
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 22px; font-weight: 300;
                         letter-spacing: 0.1em; color: #FFFFFF;
                         text-transform: uppercase;">
                New Comment on {label}
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                        color: #9CA3AF; font-weight: 400;">
                {subject}
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 24px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(255,255,255,0.01);
                     border-left: 2px solid #00ADB5;">
                <tr>
                  <td style="padding: 16px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 12px; line-height: 1.7; color: #4ECCA3;">
                    {"<br />".join(detail_lines)}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """

    row_3 = f"""
          <tr>
            <td style="padding: 0 32px 40px 32px; font-size: 14px;
                       line-height: 1.6; color: #E5E7EB;
                       white-space: pre-wrap;">
              {escaped_comment}
            </td>
          </tr>
    """

    email_subject = f"[New Comment] [#{ticket_ref}] [Nexus {label}] {subject}"

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject=email_subject,
        preheader_category="ADMIN",
        preheader_action=f"COMMENT_{query_type.upper()}",
        footer_html="",
    )

    text_content = (
        f"New Comment on {label} - #{ticket_ref}\nSubject: {subject}\n"
        f"User: {user_id}\nContact: {submitter_email or '(none on file)'}\n\n"
        f"{comment_body}"
    )

    props = SendEmailProps(
        to=recipient,
        subject=email_subject,
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Support",
        reply_to=submitter_email or None,
    )

    try:
        logger.info(
            "Sending feedback comment admin notification to %s for ticket #%s",
            redact_email(recipient),
            ticket_ref,
        )
        result = await send_email(props)
        if not result.success:
            logger.error(
                "Failed to send feedback comment admin notification for ticket #%s: %s",
                ticket_ref,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception sending feedback comment admin notification for ticket #%s",
            ticket_ref,
        )
        use_sp = should_use_sendpulse(recipient)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(success=False, provider=provider_name, error=str(err))


async def send_feedback_closed_admin_notification_email(
    report_id: str,
    query_type: str,
    subject: str,
    reason: str,
    user_id: str,
    submitter_email: str | None,
) -> ProviderResult:
    """
    Notifies the admin/support inbox when a user closes a Help, Feedback &
    Bug Report ticket. Uses the exact same email subject line as the submission
    email so thread grouping occurs in email clients.
    """
    label = FEEDBACK_QUERY_TYPE_LABELS.get(query_type, "Request")
    ticket_ref = _short_report_id(report_id)
    recipient = get_feedback_notify_email()

    escaped_reason = (
        reason.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    )

    def _detail_row(field: str, value: str) -> str:
        """Executes detail row operation.

            Args:
                field: Input field parameter.
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
        return f'<span style="color: #6B7280;">{field}:</span> {value}'

    contact_display = (
        f'<a href="mailto:{submitter_email}" style="color: #4ECCA3;">'
        f"{submitter_email}</a>"
        if submitter_email
        else "(none on file)"
    )
    detail_lines = [
        _detail_row("TICKET", f"#{ticket_ref}"),
        _detail_row("STATUS", "CLOSED BY USER"),
        _detail_row("CATEGORY", label.upper()),
        _detail_row("SUBJECT", subject),
        _detail_row("USER_ID", user_id),
        _detail_row("CONTACT", contact_display),
    ]

    row_1 = f"""
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 22px; font-weight: 300;
                         letter-spacing: 0.1em; color: #FFFFFF;
                         text-transform: uppercase;">
                {label} Closed #{ticket_ref}
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                        color: #9CA3AF; font-weight: 400;">
                {subject}
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 24px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(255,255,255,0.01);
                     border-left: 2px solid #00ADB5;">
                <tr>
                  <td style="padding: 16px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 12px; line-height: 1.7; color: #4ECCA3;">
                    {"<br />".join(detail_lines)}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """

    row_3 = f"""
          <tr>
            <td style="padding: 0 32px 40px 32px; font-size: 14px;
                       line-height: 1.6; color: #E5E7EB;
                       white-space: pre-wrap;">
              Reason for closing: {escaped_reason}
            </td>
          </tr>
    """

    email_subject = f"[Closed] [#{ticket_ref}] [Nexus {label}] {subject}"

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject=email_subject,
        preheader_category="ADMIN",
        preheader_action=f"CLOSE_{query_type.upper()}",
        footer_html="",
    )

    text_content = (
        f"Ticket Closed by User - {label} #{ticket_ref}\nSubject: {subject}\n"
        f"User: {user_id}\nContact: {submitter_email or '(none on file)'}\n\n"
        f"Reason for closing:\n{reason}"
    )

    props = SendEmailProps(
        to=recipient,
        subject=email_subject,
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Support",
        reply_to=submitter_email or None,
    )

    try:
        logger.info(
            "Sending feedback closed admin notification to %s for ticket #%s",
            redact_email(recipient),
            ticket_ref,
        )
        result = await send_email(props)
        if not result.success:
            logger.error(
                "Failed to send feedback closed admin notification for ticket #%s: %s",
                ticket_ref,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception sending feedback closed admin notification for ticket #%s",
            ticket_ref,
        )
        use_sp = should_use_sendpulse(recipient)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(success=False, provider=provider_name, error=str(err))


async def send_trusted_contact_removed_email(
    email: str,
    user_name: str,
    contact_name: str,
) -> ProviderResult:
    """Notifies a Nexus user that one of their Meetup Safety trusted
    contacts removed themselves via the self-service portal - one of three
    channels (alongside SMS and push) so this isn't missed the way a single
    email could be.
    """
    row_1 = f"""
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #FFFFFF;
                         text-transform: uppercase;">
                N E X U S
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                        color: #9CA3AF; font-weight: 400;">
                Hi {user_name} - <strong style="color: #FFFFFF;">
                {contact_name}</strong> removed themselves as one of your
                Meetup Safety trusted contacts.
              </p>
            </td>
          </tr>
    """

    row_2 = """
          <tr>
            <td style="padding: 0 32px 32px 32px; font-size: 14px;
                       line-height: 1.6; color: #9CA3AF;">
              <p style="margin: 0;">
                They will no longer receive check-in reminders or SOS
                alerts on your behalf. This can't be reversed by you - if
                you'd still like them as a trusted contact, you'll need to
                ask them directly. In the meantime, consider adding a
                replacement from Safety Center in the app.
              </p>
            </td>
          </tr>
    """

    html_content = render_email_template(
        rows_html=row_1 + row_2,
        subject="A trusted contact removed themselves - Nexus",
        preheader_category="SAFETY",
        preheader_action="CONTACT_REMOVED",
        footer_html=(
            f"You're receiving this because you added {contact_name} as a "
            "Meetup Safety trusted contact on Nexus."
        ),
    )
    text_content = (
        f"Hi {user_name} - {contact_name} removed themselves as one of "
        "your Meetup Safety trusted contacts. They will no longer receive "
        "check-in or SOS alerts on your behalf."
    )

    props = SendEmailProps(
        to=email,
        subject="A trusted contact removed themselves - Nexus",
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Safety",
    )

    try:
        redacted = redact_email(email)
        logger.info("Sending trusted-contact-removed email to %s", redacted)
        result = await send_email(props)
        if not result.success:
            logger.error(
                "Failed to send trusted-contact-removed email to %s: %s",
                redacted,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception sending trusted-contact-removed email to %s",
            redact_email(email),
        )
        use_sp = should_use_sendpulse(email)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(success=False, provider=provider_name, error=str(err))


async def send_account_deletion_otp_email(email: str, otp_code: str) -> ProviderResult:
    """Sends a specialized OTP email notifying the user that an account
    deletion has been requested, rather than a generic sign-in template.
    """
    row_1 = """
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #EF4444;
                         text-transform: uppercase;">
                Account Deletion
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                You have requested to delete your Nexus account. Please use the
                verification code below to confirm this request.
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 32px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(239,68,68,0.05);
                     border-left: 2px solid #EF4444;">
                <tr>
                  <td style="padding: 16px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 24px; line-height: 1.5; color: #EF4444;
                             font-weight: bold; text-align: center;
                             letter-spacing: 0.25em;">
                    {otp_code}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """

    row_3 = """
          <tr>
            <td style="padding: 0 32px 40px 32px; font-size: 14px;
                       line-height: 1.6; color: #9CA3AF;">
              <p style="margin: 0 0 24px 0;">
                This code will expire in 10 minutes. If you did not request
                this account deletion, please secure your account immediately.
              </p>
            </td>
          </tr>
    """

    footer_html = f"""
          You are receiving this security-related communication because an
          account deletion request was initiated for your Nexus account.
          If you did not request this, please contact support immediately at
          <a href="mailto:support@{settings.email_domain}" style="color: #EF4444;">
          support@{settings.email_domain}</a>.
          <br>
          <a href="https://{settings.app_domain}/legal" target="_blank"
             style="color: white">Privacy, Terms & Legal</a>
    """

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject="Confirm Account Deletion Request",
        preheader_category="DANGER_ZONE",
        preheader_action="DELETION_OTP",
        footer_html=footer_html,
    )

    text_content = (
        f"You requested to delete your Nexus account. Use code {otp_code} to verify. "
        "This code will expire in 10 minutes."
    )

    props = SendEmailProps(
        to=email,
        subject="Confirm Account Deletion Request",
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Support",
    )

    try:
        redacted = redact_email(email)
        logger.info("Sending account-deletion-otp email to %s", redacted)
        result = await send_email(props)
        if not result.success:
            logger.error(
                "Failed to send account-deletion-otp email to %s: %s",
                redacted,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception sending account-deletion-otp email to %s",
            redact_email(email),
        )
        use_sp = should_use_sendpulse(email)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(success=False, provider=provider_name, error=str(err))


async def send_data_export_otp_email(email: str, otp_code: str) -> ProviderResult:
    """Sends a specialized OTP email notifying the user that a personal
    data export has been requested, rather than a generic sign-in template.
    """
    row_1 = """
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #3B82F6;
                         text-transform: uppercase;">
                Data Export Request
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                You have requested a full download of your Nexus account data.
                Please use the verification code below to confirm this request.
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 32px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(59,130,246,0.05);
                     border-left: 2px solid #3B82F6;">
                <tr>
                  <td style="padding: 16px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 24px; line-height: 1.5; color: #3B82F6;
                             font-weight: bold; text-align: center;
                             letter-spacing: 0.25em;">
                    {otp_code}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """

    row_3 = """
          <tr>
            <td style="padding: 0 32px 40px 32px; font-size: 14px;
                       line-height: 1.6; color: #9CA3AF;">
              <p style="margin: 0 0 24px 0;">
                This code will expire in 10 minutes. If you did not request
                this data export, please secure your account immediately.
              </p>
            </td>
          </tr>
    """

    footer_html = f"""
          You are receiving this security-related communication because a
          personal data export request was initiated for your Nexus account.
          If you did not request this, please contact support immediately at
          <a href="mailto:support@{settings.email_domain}" style="color: #3B82F6;">
          support@{settings.email_domain}</a>.
          <br>
          <a href="https://{settings.app_domain}/legal" target="_blank"
             style="color: white">Privacy, Terms & Legal</a>
    """

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject="Confirm Data Export Request",
        preheader_category="SECURITY",
        preheader_action="EXPORT_OTP",
        footer_html=footer_html,
    )

    text_content = (
        f"You requested to export your Nexus data. Use code {otp_code} to verify. "
        "This code will expire in 10 minutes."
    )

    props = SendEmailProps(
        to=email,
        subject="Confirm Data Export Request",
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Support",
    )

    try:
        redacted = redact_email(email)
        logger.info("Sending data-export-otp email to %s", redacted)
        result = await send_email(props)
        if not result.success:
            logger.error(
                "Failed to send data-export-otp email to %s: %s",
                redacted,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception sending data-export-otp email to %s",
            redact_email(email),
        )
        use_sp = should_use_sendpulse(email)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(success=False, provider=provider_name, error=str(err))


async def send_support_appeal_otp_email(
    email: str,
    otp_code: str,
) -> ProviderResult:
    """Sends a verification OTP email to a user attempting to submit
    a support appeal ticket while logged out or suspended.
    """
    row_1 = """
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #7C3AED;
                         text-transform: uppercase;">
                Support Verification
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                You are verifying your email address to submit a support appeal.
                Please use the verification code below to complete your ticket.
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 32px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(124,58,237,0.05);
                     border-left: 2px solid #7C3AED;">
                <tr>
                  <td style="padding: 16px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 24px; line-height: 1.5; color: #7C3AED;
                             font-weight: bold; text-align: center;
                             letter-spacing: 0.25em;">
                    {otp_code}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """

    row_3 = """
          <tr>
            <td style="padding: 0 32px 40px 32px; font-size: 14px;
                       line-height: 1.6; color: #9CA3AF;">
              <p style="margin: 0 0 24px 0;">
                This code will expire in 10 minutes. If you did not initiate
                this request, please disregard this email.
              </p>
            </td>
          </tr>
    """

    footer_html = f"""
          You are receiving this communication to verify your identity for a
          support request on your Nexus account.
          If you did not request this, please contact support immediately at
          <a href="mailto:support@{settings.email_domain}" style="color: #7C3AED;">
          support@{settings.email_domain}</a>.
          <br>
          <a href="https://{settings.app_domain}/legal" target="_blank"
             style="color: white">Privacy, Terms & Legal</a>
    """

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject="Confirm Support Verification",
        preheader_category="SECURITY",
        preheader_action="SUPPORT_OTP",
        footer_html=footer_html,
    )

    text_content = (
        f"Use code {otp_code} to verify your email for your support request. "
        "This code will expire in 10 minutes."
    )

    props = SendEmailProps(
        to=email,
        subject="Confirm Support Verification",
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Support",
    )

    try:
        redacted = redact_email(email)
        logger.info("Sending support-appeal-otp email to %s", redacted)
        result = await send_email(props)
        if not result.success:
            logger.error(
                "Failed to send support-appeal-otp email to %s: %s",
                redacted,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception sending support-appeal-otp email to %s",
            redact_email(email),
        )
        use_sp = should_use_sendpulse(email)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(success=False, provider=provider_name, error=str(err))


async def send_account_deletion_scheduled_email(
    email: str,
    scheduled_purge_at: str | datetime,
    grace_period_days: int = 14,
) -> ProviderResult:
    """Sends notification email to user when account deletion is triggered and grace period starts."""
    if isinstance(scheduled_purge_at, datetime):
        purge_date_str = scheduled_purge_at.strftime("%Y-%m-%d %H:%M UTC")
    else:
        purge_date_str = str(scheduled_purge_at)

    row_1 = f"""
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #EF4444;
                         text-transform: uppercase;">
                Account Deletion Scheduled
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                Your request to delete your Nexus account has been initiated. Your account enters a
                {grace_period_days}-day grace period before your data is permanently anonymized and purged.
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 32px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(239,68,68,0.05);
                     border-left: 2px solid #EF4444;">
                <tr>
                  <td style="padding: 16px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 12px; line-height: 1.6; color: #EF4444;">
                    <span style="color: #6B7280;">STATUS:</span> GRACE_PERIOD_ACTIVE<br />
                    <span style="color: #6B7280;">GRACE_WINDOW:</span> {grace_period_days} DAYS<br />
                    <span style="color: #6B7280;">SCHEDULED_PURGE:</span> {purge_date_str}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """

    row_3 = f"""
          <tr>
            <td style="padding: 0 32px 40px 32px; font-size: 14px;
                       line-height: 1.6; color: #9CA3AF;">
              <p style="margin: 0 0 16px 0;">
                During the grace period, your profile is hidden from discovery and matches. If you change
                your mind, you can restore your account at any time before <strong>{purge_date_str}</strong> by
                logging into Nexus and choosing to cancel deletion.
              </p>
              <p style="margin: 0; color: #EF4444;">
                <strong>Security Alert:</strong> If you did not request account deletion, please sign in
                immediately to cancel the deletion request and change your password, or contact support.
              </p>
            </td>
          </tr>
    """

    footer_html = f"""
          You are receiving this security notification because an account deletion grace period was started
          for your Nexus account. If you did not request this action, please contact support immediately at
          <a href="mailto:support@{settings.email_domain}" style="color: #EF4444;">
          support@{settings.email_domain}</a>.
          <br>
          <a href="https://{settings.app_domain}/legal" target="_blank"
             style="color: white">Privacy, Terms & Legal</a>
    """

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject="Account Deletion Scheduled - Grace Period Started",
        preheader_category="DANGER_ZONE",
        preheader_action="DELETION_SCHEDULED",
        footer_html=footer_html,
    )

    text_content = (
        f"Your Nexus account deletion request has been initiated. Your {grace_period_days}-day grace period "
        f"has started, and permanent purge is scheduled for {purge_date_str}. "
        "Log in to Nexus during the grace period to cancel deletion if you change your mind. "
        "If you did not initiate this request, log in immediately or contact support."
    )

    props = SendEmailProps(
        to=email,
        subject="Account Deletion Scheduled - Grace Period Started",
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Support",
    )

    try:
        redacted = redact_email(email)
        logger.info("Sending account-deletion-scheduled email to %s", redacted)
        result = await send_email(props)
        if not result.success:
            logger.error(
                "Failed to send account-deletion-scheduled email to %s: %s",
                redacted,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception sending account-deletion-scheduled email to %s",
            redact_email(email),
        )
        use_sp = should_use_sendpulse(email)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(success=False, provider=provider_name, error=str(err))


async def send_account_reactivated_email(email: str) -> ProviderResult:
    """Sends notification email to user when account deletion is cancelled and account is reactivated."""
    row_1 = """
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #4ECCA3;
                         text-transform: uppercase;">
                Account Reactivated
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                Welcome back! Your Nexus account has been successfully reactivated and your account deletion request
                has been canceled.
              </p>
            </td>
          </tr>
    """

    row_2 = """
          <tr>
            <td style="padding: 0 32px 32px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(78,204,163,0.05);
                     border-left: 2px solid #4ECCA3;">
                <tr>
                  <td style="padding: 16px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 12px; line-height: 1.6; color: #4ECCA3;">
                    <span style="color: #6B7280;">STATUS:</span> ACTIVE<br />
                    <span style="color: #6B7280;">DELETION_REQUEST:</span> CANCELLED
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """

    row_3 = """
          <tr>
            <td style="padding: 0 32px 40px 32px; font-size: 14px;
                       line-height: 1.6; color: #9CA3AF;">
              <p style="margin: 0 0 16px 0;">
                Your profile, matches, and conversations have been fully restored. You can now continue using Nexus normally.
              </p>
              <p style="margin: 0;">
                <strong>Security Notice:</strong> If you did not perform this reactivation, please update your account
                password immediately and contact Nexus Support.
              </p>
            </td>
          </tr>
    """

    footer_html = f"""
          You are receiving this notice because an account reactivation was performed for your Nexus account.
          If you did not initiate this action, please contact support immediately at
          <a href="mailto:support@{settings.email_domain}" style="color: #4ECCA3;">
          support@{settings.email_domain}</a>.
          <br>
          <a href="https://{settings.app_domain}/legal" target="_blank"
             style="color: white">Privacy, Terms & Legal</a>
    """

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject="Account Reactivated - Nexus",
        preheader_category="ACCOUNT",
        preheader_action="REACTIVATED",
        footer_html=footer_html,
    )

    text_content = (
        "Your Nexus account has been successfully reactivated and your account deletion request has been canceled. "
        "Your profile, matches, and conversations have been restored. "
        "If you did not initiate this reactivation, please contact support immediately."
    )

    props = SendEmailProps(
        to=email,
        subject="Account Reactivated - Nexus",
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Support",
    )

    try:
        redacted = redact_email(email)
        logger.info("Sending account-reactivated email to %s", redacted)
        result = await send_email(props)
        if not result.success:
            logger.error(
                "Failed to send account-reactivated email to %s: %s",
                redacted,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception sending account-reactivated email to %s",
            redact_email(email),
        )
        use_sp = should_use_sendpulse(email)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(success=False, provider=provider_name, error=str(err))
