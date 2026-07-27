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
