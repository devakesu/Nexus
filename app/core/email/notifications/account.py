import logging
from datetime import datetime

import app.core.email as email_pkg
from app.core.config import settings
from app.core.email.config import (
    ProviderResult,
    SendEmailProps,
    redact_email,
    should_use_sendpulse,
)
from app.core.email.templates import render_email_template

logger = logging.getLogger(__name__)


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
        result = await email_pkg.send_email(props)
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
        result = await email_pkg.send_email(props)
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
        result = await email_pkg.send_email(props)
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
        result = await email_pkg.send_email(props)
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
        result = await email_pkg.send_email(props)
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
