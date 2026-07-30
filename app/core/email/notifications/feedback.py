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
    Feedback & Bug Report ticket, with a warm, friendly tone and aesthetic design.
    """
    user_name = extract_user_name(email, auth_user)
    label = FEEDBACK_QUERY_TYPE_LABELS.get(query_type, "Request")
    ticket_ref = short_report_id(report_id)
    footer_html = f"""
          You are receiving this notice because ticket #{ticket_ref} was submitted for your Nexus account.
          <br>
          <a href="https://{settings.app_domain}/legal" target="_blank"
             style="color: #9CA3AF; text-decoration: underline;">Privacy, Terms &amp; Legal</a>
    """

    row_1 = f"""
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <div style="display: inline-block; background-color: rgba(0, 173, 181, 0.15);
                          border: 1px solid rgba(0, 173, 181, 0.4); border-radius: 6px;
                          padding: 6px 12px; margin-bottom: 16px; font-family: ui-monospace,
                          SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                          font-size: 11px; font-weight: bold; color: #00ADB5;
                          letter-spacing: 0.1em;">
                💌 TICKET RECEIVED &amp; QUEUED ✨
              </div>
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #4ECCA3;
                         text-transform: uppercase;">
                We're On It! 🤝✨
              </h1>
              <p style="margin: 0 0 12px 0; font-size: 16px; line-height: 1.6;
                         color: #FFFFFF; font-weight: 400;">
                Hi {user_name}! 👋 Thank you for reaching out to Nexus Support.
              </p>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                We've successfully logged your {label.lower()} and our support specialists are already reviewing your ticket.
                We aim to respond as quickly as possible, usually within <strong>24 to 48 hours</strong>. ⏳
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 32px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(0,173,181,0.06);
                     border-left: 4px solid #00ADB5; border-radius: 4px;">
                <tr>
                  <td style="padding: 18px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 13px; line-height: 1.7; color: #4ECCA3;">
                    <span style="color: #9CA3AF;">TICKET_REF:</span> 🎫 #{ticket_ref}<br />
                    <span style="color: #9CA3AF;">CATEGORY:</span> {label.upper()} 📋<br />
                    <span style="color: #9CA3AF;">SUBJECT:</span> {subject}<br />
                    <span style="color: #9CA3AF;">STATUS:</span> 🟡 OPEN &amp; QUEUED 📥
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
              <div style="background-color: rgba(255, 255, 255, 0.03); border: 1px solid rgba(255, 255, 255, 0.08); border-radius: 8px; padding: 16px; margin-bottom: 24px;">
                <p style="margin: 0 0 8px 0; color: #E5E7EB; font-weight: 500; font-size: 14px;">
                  💡 Helpful info while you wait:
                </p>
                <p style="margin: 0; color: #9CA3AF; font-size: 13px; line-height: 1.5;">
                  • No extra steps required! If you'd like to add extra details, screenshots, or context to this ticket, simply reply directly to this email.<br />
                  • Our care team will reply to this thread as soon as an update is available.
                </p>
              </div>
              <p style="margin: 0; text-align: center; color: #00ADB5; font-weight: bold; font-size: 15px;">
                Thanks for your patience and for helping us make Nexus better! 💖<br />
                <span style="font-weight: normal; font-size: 13px; color: #9CA3AF;">The Nexus Support Team 🌟</span>
              </p>
            </td>
          </tr>
    """

    email_subject = f"[#{ticket_ref}] We've received your {label.lower()}! 💬 - Nexus Support"

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject=email_subject,
        preheader_category="SUPPORT",
        preheader_action=f"TICKET_{ticket_ref}_OPEN",
        footer_html=footer_html,
    )

    text_content = (
        f"Hi {user_name}! 👋\n\n"
        f"Thank you for reaching out to Nexus Support! We've received your {label.lower()} (Ticket #{ticket_ref}) "
        f"and our team is reviewing it. We typically respond within 24-48 hours. ⏳\n\n"
        f"Ticket Reference: #{ticket_ref}\n"
        f"Category: {label}\n"
        f"Subject: {subject}\n"
        f"Status: OPEN & QUEUED\n\n"
        f"If you need to add extra details or attachments, just reply directly to this email.\n\n"
        f"Warm regards,\nNexus Support Team 💖"
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
