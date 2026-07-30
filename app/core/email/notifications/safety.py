import logging

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
              <div style="display: inline-block; background-color: rgba(245, 158, 11, 0.15);
                          border: 1px solid rgba(245, 158, 11, 0.4); border-radius: 6px;
                          padding: 6px 12px; margin-bottom: 16px; font-family: ui-monospace,
                          SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                          font-size: 11px; font-weight: bold; color: #F59E0B;
                          letter-spacing: 0.1em;">
                🛡️ MEETUP SAFETY UPDATE ✨
              </div>
              <h1 style="margin: 0 0 16px 0; font-family: -apple-system,
                         BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial,
                         sans-serif; font-size: 26px; font-weight: 300;
                         letter-spacing: 0.15em; color: #F59E0B;
                         text-transform: uppercase;">
                Trusted Contact Update 👥
              </h1>
              <p style="margin: 0 0 12px 0; font-size: 16px; line-height: 1.6;
                         color: #FFFFFF; font-weight: 400;">
                Hi {user_name}! 👋
              </p>
              <p style="margin: 0; font-size: 15px; line-height: 1.6;
                         color: #9CA3AF; font-weight: 400;">
                <strong style="color: #FFFFFF;">{contact_name}</strong> has removed themselves as one of your designated Meetup Safety trusted contacts.
              </p>
            </td>
          </tr>
    """

    row_2 = f"""
          <tr>
            <td style="padding: 0 32px 32px 32px;">
              <table width="100%" border="0" cellspacing="0" cellpadding="0"
                     style="background-color: rgba(245,158,11,0.06);
                     border-left: 4px solid #F59E0B; border-radius: 4px;">
                <tr>
                  <td style="padding: 18px; font-family: ui-monospace,
                             SFMono-Regular, Menlo, Monaco, Consolas, monospace;
                             font-size: 13px; line-height: 1.7; color: #F59E0B;">
                    <span style="color: #9CA3AF;">CONTACT:</span> {contact_name}<br />
                    <span style="color: #9CA3AF;">ACTION:</span> REMOVED_SELF 🚪<br />
                    <span style="color: #9CA3AF;">SAFETY_ALERTS:</span> DEACTIVATED FOR THIS CONTACT
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
                  💡 What this means for your safety settings:
                </p>
                <p style="margin: 0; color: #9CA3AF; font-size: 13px; line-height: 1.5;">
                  • They will no longer receive check-in notifications or emergency SOS alerts on your behalf.<br />
                  • If you'd like to re-add them or assign a new trusted contact, open the <strong>Safety Center</strong> tab inside the Nexus app.
                </p>
              </div>
              <p style="margin: 0; text-align: center; color: #F59E0B; font-weight: 500; font-size: 14px;">
                Your safety and peace of mind remain our highest priority. 🛡️✨<br />
                <span style="font-weight: normal; font-size: 13px; color: #9CA3AF;">The Nexus Safety Team</span>
              </p>
            </td>
          </tr>
    """

    html_content = render_email_template(
        rows_html=row_1 + row_2 + row_3,
        subject="🛡️ Meetup Safety: Trusted Contact Update - Nexus",
        preheader_category="SAFETY",
        preheader_action="CONTACT_REMOVED",
        footer_html=f"""
              You are receiving this notice because {contact_name} was added as a Meetup Safety trusted contact on Nexus.
              <br>
              <a href="https://{settings.app_domain}/legal" target="_blank"
                 style="color: #9CA3AF; text-decoration: underline;">Privacy, Terms &amp; Legal</a>
        """,
    )
    text_content = (
        f"Hi {user_name}! 👋\n\n"
        f"{contact_name} has removed themselves as one of your Meetup Safety trusted contacts. "
        "They will no longer receive check-in reminders or emergency SOS alerts on your behalf.\n\n"
        "You can add a replacement trusted contact anytime in the Safety Center inside the Nexus app.\n\n"
        "Warm regards,\nThe Nexus Safety Team 🛡️"
    )

    props = SendEmailProps(
        to=email,
        subject="🛡️ Meetup Safety: Trusted Contact Update - Nexus",
        html=html_content,
        text=text_content,
        sender_email=f"support@{settings.email_domain}",
        from_name="Nexus Safety",
    )

    try:
        redacted = redact_email(email)
        logger.info("Sending trusted-contact-removed email to %s", redacted)
        result = await email_pkg.send_email(props)
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
