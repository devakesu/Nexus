import logging
from typing import Any

import app.core.email as email_pkg
from app.core.config import settings
from app.core.email.config import (
    ProviderResult,
    SendEmailProps,
    redact_email,
    should_use_sendpulse,
)
from app.core.email.notifications.helpers import extract_user_name
from app.core.email.templates import render_cta_button_row, render_email_template

logger = logging.getLogger(__name__)


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
        result = await email_pkg.send_email(props)
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
