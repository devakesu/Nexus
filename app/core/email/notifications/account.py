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
from app.core.email.templates import render_cta_button_row, render_email_template

logger = logging.getLogger(__name__)


async def send_login_otp_email(
    email: str,
    otp_code: str,
) -> ProviderResult:
    """Sends a friendly, aesthetic sign-in OTP email for Nexus login flows."""
    row_1 = """
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <div style="display: inline-block; background-color: rgba(59, 130, 246, 0.15);
                          border: 1px solid rgba(59, 130, 246, 0.4); border-radius: 6px;
                          padding: 6px 12px; margin-bottom: 16px; font-family: ui-monospace,
                          SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                          font-size: 11px; font-weight: bold; color: #3B82F6;
                          letter-spacing: 0.1em;">
                🔐 SECURE SIGN-IN VERIFICATION
              </div>
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #3B82F6;
                         text-transform: uppercase;">
                Your Login Code 🔑✨
              </h1>
              <p style="margin: 0 0 12px 0; font-size: 16px; line-height: 1.6;
                         color: #FFFFFF; font-weight: 400;">
                Hi there! 👋 Welcome back to Nexus.
              </p>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                Here is your 6-digit login verification code. Please enter this code on the sign-in screen to securely access your account.
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 24px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(59,130,246,0.08);
                     border-left: 4px solid #3B82F6; border-radius: 4px;">
                <tr>
                  <td style="padding: 20px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 28px; line-height: 1.5; color: #3B82F6;
                             font-weight: bold; text-align: center;
                             letter-spacing: 0.3em;">
                    🔑 {otp_code}
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
                ⏱️ This login code will expire in <strong>10 minutes</strong>.
              </p>
              <div style="background-color: rgba(255, 255, 255, 0.03); border: 1px solid rgba(255, 255, 255, 0.08); border-radius: 8px; padding: 16px;">
                <p style="margin: 0; color: #9CA3AF; font-size: 13px; line-height: 1.5;">
                  💡 <strong>Didn't request this code?</strong> No worries at all! Someone may have entered your email address by mistake when trying to log in. You can safely ignore and delete this email — your account remains completely secure.
                </p>
              </div>
            </td>
          </tr>
    """

    footer_html = f"""
          You are receiving this communication because a sign-in attempt was initiated using your email address on Nexus.
          If you have questions, please reach out to us at
          <a href="mailto:support@{settings.email_domain}" style="color: #3B82F6;">
          support@{settings.email_domain}</a>.
          <br>
          <a href="https://{settings.app_domain}/legal" target="_blank"
             style="color: white">Privacy, Terms & Legal</a>
    """

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject="🔑 Your Nexus Login Code",
        preheader_category="AUTH",
        preheader_action="LOGIN_OTP",
        footer_html=footer_html,
    )

    text_content = (
        "Hi there! 👋 Welcome back to Nexus.\n\n"
        f"Your login verification code is: {otp_code} (Expires in 10 minutes ⏱️)\n\n"
        "💡 Didn't request this code? No worries at all! Someone may have entered your email address by mistake. "
        "You can safely ignore and delete this email — your account remains completely secure.\n\n"
        "Warmly,\nThe Nexus Team 💫"
    )

    props = SendEmailProps(
        to=email,
        subject="🔑 Your Nexus Login Code",
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Auth",
    )

    try:
        redacted = redact_email(email)
        logger.info("Sending login-otp email to %s", redacted)
        result = await email_pkg.send_email(props)
        if not result.success:
            logger.error(
                "Failed to send login-otp email to %s: %s",
                redacted,
                result.error,
            )
        return result
    except Exception as err:
        logger.exception(
            "Unexpected exception sending login-otp email to %s",
            redact_email(email),
        )
        use_sp = should_use_sendpulse(email)
        provider_name = "SendPulse" if use_sp else "Brevo"
        return ProviderResult(success=False, provider=provider_name, error=str(err))


async def send_account_deletion_otp_email(
    email: str,
    otp_code: str,
    grace_period_days: int | None = None,
) -> ProviderResult:
    """Sends a specialized OTP email notifying the user that an account
    deletion has been requested, emphasizing that account deletion is a
    sensitive, irreversible action and specifying the grace period before
    permanent anonymization and purge.
    """
    days = (
        grace_period_days
        if grace_period_days is not None
        else settings.account_deletion_grace_period_days
    )

    row_1 = f"""
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <div style="display: inline-block; background-color: rgba(239, 68, 68, 0.15);
                          border: 1px solid rgba(239, 68, 68, 0.4); border-radius: 6px;
                          padding: 6px 12px; margin-bottom: 16px; font-family: ui-monospace,
                          SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                          font-size: 11px; font-weight: bold; color: #EF4444;
                          letter-spacing: 0.1em;">
                ⚠️ CRITICAL SENSITIVE ACTION
              </div>
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #EF4444;
                         text-transform: uppercase;">
                ⚠️ Account Deletion OTP 🚨
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                You have requested to delete your Nexus account. This is a <strong>highly sensitive action</strong>.
                Please use the verification code below to authorize this request.
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 24px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(239,68,68,0.08);
                     border-left: 4px solid #EF4444; border-radius: 4px;">
                <tr>
                  <td style="padding: 20px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 28px; line-height: 1.5; color: #EF4444;
                             font-weight: bold; text-align: center;
                             letter-spacing: 0.3em;">
                    🔒 {otp_code}
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
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(239,68,68,0.05);
                     border: 1px dashed rgba(239,68,68,0.3); border-radius: 8px;
                     margin-bottom: 24px;">
                <tr>
                  <td style="padding: 16px;">
                    <p style="margin: 0 0 10px 0; color: #EF4444; font-weight: 600; font-size: 14px;">
                      🚨 SENSITIVE ACTION NOTICE: PERMANENT &amp; IRREVERSIBLE
                    </p>
                    <p style="margin: 0 0 8px 0; color: #D1D5DB; font-size: 13px;">
                      • Entering this verification code will confirm your deletion request and initiate a <strong>{days}-day</strong> grace period.
                    </p>
                    <p style="margin: 0 0 8px 0; color: #D1D5DB; font-size: 13px;">
                      • After <strong>{days} days</strong>, your account data will be <strong>permanently anonymized and deleted</strong> from our servers.
                    </p>
                    <p style="margin: 0; color: #D1D5DB; font-size: 13px;">
                      • Once permanently deleted after {days} days, this process is <strong>completely irreversible</strong>. All your profile information, matches, message history, and preferences will be permanently lost and cannot be recovered.
                    </p>
                  </td>
                </tr>
              </table>
              <p style="margin: 0 0 16px 0;">
                ⏱️ This code will expire in <strong>10 minutes</strong>.
              </p>
              <p style="margin: 0; color: #9CA3AF; font-size: 13px;">
                💡 <strong>Didn't request account deletion?</strong> If you did not initiate this request, you can safely ignore and delete this email. Someone may have entered your email address by mistake. Your account will <strong>not</strong> be affected unless this verification code is entered in your active session.
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
        subject="⚠️ Confirm Account Deletion Request",
        preheader_category="DANGER_ZONE",
        preheader_action="DELETION_OTP",
        footer_html=footer_html,
    )

    text_content = (
        f"⚠️ SENSITIVE ACTION ALERT: You have requested to delete your Nexus account.\n\n"
        f"Verification Code: {otp_code} (Expires in 10 minutes ⏱️)\n\n"
        f"🚨 WARNING: Account deletion is a sensitive and irreversible action.\n"
        f"After {days} days of grace period, your account data will be permanently anonymized and deleted.\n"
        f"Once permanently deleted after {days} days, your profile, matches, and message history cannot be recovered.\n\n"
        f"💡 Didn't request this? If you did not initiate this request, you can safely ignore and delete this email. Someone may have entered your email address by mistake. Your account will not be affected unless this code is verified in your session."
    )

    props = SendEmailProps(
        to=email,
        subject="⚠️ Confirm Account Deletion Request",
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
    data export has been requested, detailing what data is included in the export,
    how the archive compilation works, and providing aesthetic emoji styling.
    """
    row_1 = """
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <div style="display: inline-block; background-color: rgba(59, 130, 246, 0.15);
                          border: 1px solid rgba(59, 130, 246, 0.4); border-radius: 6px;
                          padding: 6px 12px; margin-bottom: 16px; font-family: ui-monospace,
                          SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                          font-size: 11px; font-weight: bold; color: #3B82F6;
                          letter-spacing: 0.1em;">
                📦 PERSONAL DATA EXPORT REQUEST
              </div>
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #3B82F6;
                         text-transform: uppercase;">
                Data Export Verification 🔒
              </h1>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                You have requested a full archive of your personal Nexus account data.
                Please use the verification code below to authorize compilation of your data archive.
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 24px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(59,130,246,0.08);
                     border-left: 4px solid #3B82F6; border-radius: 4px;">
                <tr>
                  <td style="padding: 20px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 28px; line-height: 1.5; color: #3B82F6;
                             font-weight: bold; text-align: center;
                             letter-spacing: 0.3em;">
                    🔑 {otp_code}
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
              <p style="margin: 0 0 16px 0; color: #E5E7EB; font-size: 15px; font-weight: 500;">
                📁 What is included in your data archive:
              </p>
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="margin-bottom: 24px; font-size: 13px; color: #D1D5DB;">
                <tr>
                  <td width="32" valign="top" style="padding-bottom: 12px; font-size: 18px;">👤</td>
                  <td style="padding-bottom: 12px;">
                    <strong>Profile &amp; Identity:</strong> Name, email, bio, vector embedding coordinates, and semantic anchor preferences.
                  </td>
                </tr>
                <tr>
                  <td width="32" valign="top" style="padding-bottom: 12px; font-size: 18px;">💬</td>
                  <td style="padding-bottom: 12px;">
                    <strong>Messages &amp; Chat History:</strong> Full transcript of sent and received messages across your active and archived conversations.
                  </td>
                </tr>
                <tr>
                  <td width="32" valign="top" style="padding-bottom: 12px; font-size: 18px;">🤝</td>
                  <td style="padding-bottom: 12px;">
                    <strong>Matches &amp; Orbit Activity:</strong> Record of past and present compatible connections, matches, passes, and discovery interactions.
                  </td>
                </tr>
                <tr>
                  <td width="32" valign="top" style="padding-bottom: 12px; font-size: 18px;">⚙️</td>
                  <td style="padding-bottom: 12px;">
                    <strong>Settings &amp; Security Logs:</strong> Account preferences, notification settings, device sessions, and authentication security logs.
                  </td>
                </tr>
              </table>
              <div style="background-color: rgba(59, 130, 246, 0.05); border: 1px dashed rgba(59, 130, 246, 0.3); border-radius: 8px; padding: 16px; margin-bottom: 24px;">
                <p style="margin: 0 0 8px 0; color: #60A5FA; font-weight: bold; font-size: 13px;">
                  💡 How it works:
                </p>
                <p style="margin: 0; color: #9CA3AF; font-size: 13px; line-height: 1.5;">
                  Once you enter this code, our system will generate a secure, encrypted archive of your account data. As soon as your download package is prepared, a secure, time-limited link will be sent to your email.
                </p>
              </div>
              <p style="margin: 0 0 16px 0;">
                ⏱️ This verification code will expire in <strong>10 minutes</strong>.
              </p>
              <p style="margin: 0; color: #9CA3AF; font-size: 13px;">
                💡 <strong>Didn't request a data export?</strong> No worries! If you did not initiate this request, you can safely ignore and delete this email — someone may have typed your email address by mistake. Your data will not be exported without verifying this code.
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
        subject="🔐 Confirm Data Export Request - Nexus",
        preheader_category="SECURITY",
        preheader_action="EXPORT_OTP",
        footer_html=footer_html,
    )

    text_content = (
        f"📦 PERSONAL DATA EXPORT REQUEST\n\n"
        f"Verification Code: {otp_code} (Expires in 10 minutes ⏱️)\n\n"
        f"📁 Included Data:\n"
        f"• 👤 Profile & Identity: Bio, coordinates, anchor preferences\n"
        f"• 💬 Messages & Chat History: Transcripts of all sent and received messages\n"
        f"• 🤝 Matches & Orbit Activity: Compatible connections and interaction history\n"
        f"• ⚙️ Settings & Security Logs: Preferences, device sessions, security logs\n\n"
        f"💡 How it works: Entering this verification code authorizes our system to compile an encrypted archive of your account data. You will receive a notification with a download link once ready.\n\n"
        f"💡 Didn't request a data export? No worries! If you did not initiate this request, you can safely ignore and delete this email — someone may have typed your email address by mistake."
    )

    props = SendEmailProps(
        to=email,
        subject="🔐 Confirm Data Export Request - Nexus",
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
    a support appeal ticket while logged out or suspended, featuring friendly tone and aesthetic emojis.
    """
    row_1 = """
          <tr>
            <td style="padding: 40px 32px 24px 32px;">
              <div style="display: inline-block; background-color: rgba(124, 58, 237, 0.15);
                          border: 1px solid rgba(124, 58, 237, 0.4); border-radius: 6px;
                          padding: 6px 12px; margin-bottom: 16px; font-family: ui-monospace,
                          SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                          font-size: 11px; font-weight: bold; color: #A78BFA;
                          letter-spacing: 0.1em;">
                💜 SUPPORT &amp; HELP VERIFICATION
              </div>
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #A78BFA;
                         text-transform: uppercase;">
                Verify Your Ticket 📩✨
              </h1>
              <p style="margin: 0 0 12px 0; font-size: 16px; line-height: 1.6;
                         color: #FFFFFF; font-weight: 400;">
                Hi there! 👋 We're almost ready to process your support request.
              </p>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                To verify your email and protect your inquiry, please enter the verification code below to complete your ticket submission.
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 24px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(124,58,237,0.08);
                     border-left: 4px solid #7C3AED; border-radius: 4px;">
                <tr>
                  <td style="padding: 20px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 28px; line-height: 1.5; color: #A78BFA;
                             font-weight: bold; text-align: center;
                             letter-spacing: 0.3em;">
                    🔑 {otp_code}
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
              <div style="background-color: rgba(124, 58, 237, 0.05); border: 1px dashed rgba(124, 58, 237, 0.3); border-radius: 8px; padding: 16px; margin-bottom: 24px;">
                <p style="margin: 0 0 6px 0; color: #C4B5FD; font-weight: 500; font-size: 13px;">
                  🤝 Why verification is required:
                </p>
                <p style="margin: 0; color: #9CA3AF; font-size: 13px; line-height: 1.5;">
                  Verifying your email ensures that our support team communicates directly with the rightful account holder and keeps your inquiry safe and private.
                </p>
              </div>
              <p style="margin: 0 0 16px 0;">
                ⏱️ This verification code will expire in <strong>10 minutes</strong>.
              </p>
              <p style="margin: 0; color: #9CA3AF; font-size: 13px;">
                💡 <strong>Didn't submit a support ticket?</strong> You can safely ignore and delete this email — someone may have entered your email address by mistake when submitting an inquiry.
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
        subject="📩 Confirm Support Verification - Nexus",
        preheader_category="SECURITY",
        preheader_action="SUPPORT_OTP",
        footer_html=footer_html,
    )

    text_content = (
        "Hi there! 👋\n\n"
        f"Use verification code {otp_code} to verify your email and submit your support ticket or appeal.\n"
        "This code will expire in 10 minutes. ⏱️\n\n"
        "Why verification? Verifying your email ensures our support team communicates directly with the account holder.\n\n"
        "💡 Didn't initiate this request? You can safely ignore and delete this email — someone may have typed your email address by mistake.\n\n"
        "Warm regards,\nNexus Support Team 💜"
    )

    props = SendEmailProps(
        to=email,
        subject="📩 Confirm Support Verification - Nexus",
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
              <div style="display: inline-block; background-color: rgba(78, 204, 163, 0.15);
                          border: 1px solid rgba(78, 204, 163, 0.4); border-radius: 6px;
                          padding: 6px 12px; margin-bottom: 16px; font-family: ui-monospace,
                          SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                          font-size: 11px; font-weight: bold; color: #4ECCA3;
                          letter-spacing: 0.1em;">
                🎉 WELCOME BACK TO NEXUS ✨
              </div>
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #4ECCA3;
                         text-transform: uppercase;">
                Welcome Back! 👋🌟
              </h1>
              <p style="margin: 0 0 12px 0; font-size: 16px; line-height: 1.6;
                         color: #FFFFFF; font-weight: 400;">
                We are so happy to see you again! 💖 Thank you so much for coming back to Nexus!
              </p>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                Your account deletion request has been officially canceled, and your Nexus account is now fully reactivated and ready for action.
              </p>
            </td>
          </tr>
    """

    row_2 = """
          <tr>
            <td style="padding: 0 32px 32px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(78,204,163,0.08);
                     border-left: 4px solid #4ECCA3; border-radius: 4px;">
                <tr>
                  <td style="padding: 18px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 13px; line-height: 1.7; color: #4ECCA3;">
                    <span style="color: #9CA3AF;">ACCOUNT_STATUS:</span> 🟢 ACTIVE &amp; RESTORED ✨<br />
                    <span style="color: #9CA3AF;">DELETION_REQUEST:</span> ❌ CANCELLED<br />
                    <span style="color: #9CA3AF;">DATA_INTEGRITY:</span> 100% PRESERVED 🛡️
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
              <p style="margin: 0 0 16px 0; color: #E5E7EB; font-size: 15px;">
                We've restored everything so you can pick up right where you left off:
              </p>
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="margin-bottom: 24px; font-size: 14px; color: #D1D5DB;">
                <tr>
                  <td width="32" valign="top" style="padding-bottom: 12px; font-size: 18px;">✨</td>
                  <td style="padding-bottom: 12px;">
                    <strong>Profile &amp; Preferences:</strong> Your vector profile, bio, and semantic anchor settings remain fully intact.
                  </td>
                </tr>
                <tr>
                  <td width="32" valign="top" style="padding-bottom: 12px; font-size: 18px;">💬</td>
                  <td style="padding-bottom: 12px;">
                    <strong>Matches &amp; Conversations:</strong> All your active connections, match histories, and chat threads are seamlessly re-established.
                  </td>
                </tr>
                <tr>
                  <td width="32" valign="top" style="padding-bottom: 12px; font-size: 18px;">🚀</td>
                  <td style="padding-bottom: 12px;">
                    <strong>Spatial Discovery:</strong> You are once again visible in the coordinate universe to discover new meaningful connections!
                  </td>
                </tr>
              </table>
              <div style="background-color: rgba(255, 255, 255, 0.03); border: 1px solid rgba(255, 255, 255, 0.08); border-radius: 8px; padding: 16px; margin-bottom: 24px;">
                <p style="margin: 0; color: #9CA3AF; font-size: 13px; line-height: 1.5;">
                  🔒 <strong>Security Notice:</strong> If you did not perform this reactivation yourself, please update your account password immediately and contact Nexus Support.
                </p>
              </div>
              <p style="margin: 0; text-align: center; color: #4ECCA3; font-weight: bold; font-size: 16px;">
                Welcome back home! 🎊💖<br />
                <span style="font-weight: normal; font-size: 13px; color: #9CA3AF;">The Nexus Team 💫</span>
              </p>
            </td>
          </tr>
    """

    button_row = render_cta_button_row(
        cta_text="Return to Nexus App ✨",
        cta_url=f"https://{settings.app_domain}/app",
    )

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
        rows_html=row_1 + row_2 + row_3 + button_row,
        subject="Welcome Back! 🎉 Your Nexus Account is Reactivated ✨",
        preheader_category="ACCOUNT",
        preheader_action="REACTIVATED",
        footer_html=footer_html,
    )

    text_content = (
        "🎉 Welcome back to Nexus! ✨\n\n"
        "Thank you so much for coming back! We are thrilled to have you return to our community. 👋🌟\n\n"
        "Your Nexus account has been successfully reactivated and your account deletion request has been canceled.\n"
        "• Profile & Preferences: Fully intact\n"
        "• Matches & Conversations: Restored\n"
        "• Spatial Discovery: Active\n\n"
        "If you did not initiate this reactivation, please update your password immediately and contact support.\n\n"
        "Warmly,\nThe Nexus Team 💫"
    )

    props = SendEmailProps(
        to=email,
        subject="Welcome Back! 🎉 Your Nexus Account is Reactivated ✨",
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
