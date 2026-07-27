import logging
from typing import Any

import app.core.email as email_pkg
from app.core.config import settings
from app.core.email.config import (
    ProviderResult,
    SendEmailProps,
    get_feedback_notify_email,
    redact_email,
    should_use_sendpulse,
)
from app.core.email.notifications.helpers import extract_user_name, short_report_id
from app.core.email.templates import render_email_template

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
    ticket_ref = short_report_id(report_id)
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
        result = await email_pkg.send_email(props)
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
    ticket_ref = short_report_id(report_id)
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
        result = await email_pkg.send_email(props)
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
    ticket_ref = short_report_id(report_id)
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
        result = await email_pkg.send_email(props)
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
    ticket_ref = short_report_id(report_id)
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
        result = await email_pkg.send_email(props)
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
