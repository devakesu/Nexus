import base64
import logging
import random
from collections.abc import Callable, Coroutine
from html.parser import HTMLParser
from typing import Any, Literal, cast

import httpx
import sentry_sdk
from pydantic import BaseModel, ConfigDict

from app.core.config import settings

logger = logging.getLogger(__name__)


class SendEmailProps(BaseModel):
    to: str
    subject: str
    html: str
    text: str | None = None
    reply_to: str | None = None
    from_name: str | None = None
    to_name: str | None = None
    sender_email: str | None = None


class ProviderResult(BaseModel):
    success: bool
    provider: Literal["Brevo", "SendPulse"]
    id: str | None = None
    error: str | None = None


class HTMLStripper(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.reset()
        self.strict = False
        self.convert_charrefs = True
        self.text: list[str] = []

    def handle_data(self, data: str) -> None:
        self.text.append(data)

    def get_data(self) -> str:
        return "".join(self.text)


def strip_tags(html: str) -> str:
    s = HTMLStripper()
    s.feed(html)
    return s.get_data()


def redact_email(email: str) -> str:
    if not email or "@" not in email:
        return email
    parts = email.split("@", 1)
    name = parts[0]
    domain = parts[1]
    if len(name) <= 2:
        return f"{name[0]}***@{domain}"
    return f"{name[0]}***{name[-1]}@{domain}"


def redact(type_: str, val: str) -> str:
    if type_ == "email":
        return redact_email(val)
    return val


has_brevo = bool(settings.brevo_api_key)
has_sendpulse = bool(settings.sendpulse_client_id and settings.sendpulse_client_secret)


def get_support_email() -> str:
    """Centralized support email address for notifications and system routing."""
    return f"support@{settings.email_domain}"


def get_sender_email() -> str:
    return get_support_email()


def get_feedback_notify_email() -> str:
    """Where "Help, Feedback & Bug Report" admin notifications are routed."""
    return get_support_email()


def get_sender_name(from_name: str | None = None) -> str:
    if from_name and from_name.strip():
        return from_name.strip()
    return settings.app_name


async def get_sendpulse_token() -> str:
    if not has_sendpulse:
        raise ValueError("SendPulse credentials not configured")

    auth_url = "https://api.sendpulse.com/oauth/access_token"
    payload = {
        "grant_type": "client_credentials",
        "client_id": settings.sendpulse_client_id,
        "client_secret": settings.sendpulse_client_secret,
    }

    async with httpx.AsyncClient() as client:
        try:
            res = await client.post(auth_url, json=payload, timeout=10.0)
            if res.status_code != 200:
                raise httpx.HTTPStatusError(
                    f"SendPulse auth HTTP {res.status_code}",
                    request=res.request,
                    response=res,
                )
            data = res.json()
            return data["access_token"]
        except Exception as error:
            wrapped = RuntimeError(f"SendPulse Auth Failed: {error!s}")
            raise wrapped from error


async def send_via_sendpulse(props: SendEmailProps) -> ProviderResult:
    if not has_sendpulse:
        raise ValueError("SendPulse not configured")

    token = await get_sendpulse_token()
    email_url = "https://api.sendpulse.com/smtp/emails"

    stripped_text = props.text or strip_tags(props.html)
    sender_email = props.sender_email or get_sender_email()
    sender_name = get_sender_name(props.from_name)

    html_base64 = base64.b64encode(props.html.encode("utf-8")).decode("utf-8")

    payload = {
        "email": {
            "html": html_base64,
            "text": stripped_text,
            "subject": props.subject,
            "from": {
                "email": sender_email,
                "name": sender_name,
            },
            "to": [
                {
                    "email": props.to,
                    "name": props.to_name or "User",
                },
            ],
        },
    }

    if props.reply_to:
        payload["email"]["reply_to"] = {"email": props.reply_to}

    async with httpx.AsyncClient() as client:
        res = await client.post(
            email_url,
            json=payload,
            headers={"Authorization": f"Bearer {token}"},
            timeout=15.0,
        )
        if res.status_code != 200:
            try:
                err_data = res.json()
                err_msg = err_data.get(
                    "message",
                    f"SendPulse error: {res.status_code}",
                )
            except Exception:  # noqa: BLE001
                err_msg = f"SendPulse error: {res.status_code}"
            raise RuntimeError(err_msg)

        try:
            data = res.json()
            message_id = str(data.get("id", ""))
        except Exception:  # noqa: BLE001
            message_id = ""

        return ProviderResult(success=True, provider="SendPulse", id=message_id)


async def send_via_brevo(props: SendEmailProps) -> ProviderResult:
    if not has_brevo:
        raise ValueError("Brevo not configured")

    url = "https://api.brevo.com/v3/smtp/email"
    sender_email = props.sender_email or get_sender_email()
    sender_name = get_sender_name(props.from_name)
    stripped_text = props.text or strip_tags(props.html)

    payload: dict[str, Any] = {
        "sender": {
            "email": sender_email,
            "name": sender_name,
        },
        "to": [{"email": props.to}],
        "subject": props.subject,
        "htmlContent": props.html,
        "textContent": stripped_text,
    }

    if props.to_name:
        payload["to"][0]["name"] = props.to_name

    if props.reply_to:
        payload["replyTo"] = {"email": props.reply_to}

    async with httpx.AsyncClient() as client:
        res = await client.post(
            url,
            json=payload,
            headers={
                "api-key": settings.brevo_api_key or "",
                "content-type": "application/json",
                "accept": "application/json",
            },
            timeout=15.0,
        )
        if res.status_code not in (200, 201, 202):
            try:
                err_data = res.json()
                err_msg = err_data.get(
                    "message",
                    f"Brevo error: {res.status_code}",
                )
            except Exception:  # noqa: BLE001
                err_msg = f"Brevo error: {res.status_code}"
            raise RuntimeError(err_msg)

        try:
            data = res.json()
            message_id = str(data.get("messageId", ""))
        except Exception:  # noqa: BLE001
            message_id = ""

        return ProviderResult(success=True, provider="Brevo", id=message_id)


def should_use_sendpulse(email: str | None = None) -> bool:
    if has_brevo and has_sendpulse:
        if email:
            import hashlib

            encoded_email = email.lower().encode("utf-8")
            hash_val = int(hashlib.sha256(encoded_email).hexdigest(), 16)
            return hash_val % 2 == 0
        return random.random() < 0.5  # noqa: S311
    return has_sendpulse


ProviderFn = Callable[[SendEmailProps], Coroutine[Any, Any, ProviderResult]]


class ProvidersConfig(BaseModel):
    primary: Any  # ProviderFn
    secondary: Any | None = None  # ProviderFn | None
    p_name: Literal["SendPulse", "Brevo"]
    s_name: Literal["Brevo", "SendPulse"]

    model_config = ConfigDict(arbitrary_types_allowed=True)


def get_providers(use_sp: bool) -> ProvidersConfig:
    if use_sp:
        return ProvidersConfig(
            primary=send_via_sendpulse,
            secondary=send_via_brevo if has_brevo else None,
            p_name="SendPulse",
            s_name="Brevo",
        )
    return ProvidersConfig(
        primary=send_via_brevo,
        secondary=send_via_sendpulse if has_sendpulse else None,
        p_name="Brevo",
        s_name="SendPulse",
    )


async def execute_failover(
    secondary: ProviderFn,
    props: SendEmailProps,
    s_name: Literal["Brevo", "SendPulse"],
    err: Exception,
) -> ProviderResult:
    err_msg = str(err)
    try:
        return await secondary(props)
    except Exception as err2:  # noqa: BLE001
        err2_msg = str(err2)
        msg = f"All providers failed. P: {err_msg} | S: {err2_msg}"
        logger.error(msg)
        sentry_sdk.capture_exception(
            err2,
            tags={"type": "email_critical"},
            extras={
                "to": redact("email", props.to),
                "primary_error": err_msg,
                "secondary_error": err2_msg,
            },
        )
        return ProviderResult(success=False, provider=s_name, error=msg)


async def send_email(props: SendEmailProps) -> ProviderResult:
    if not has_brevo and not has_sendpulse:
        err = RuntimeError("No provider configured")
        sentry_sdk.capture_exception(err, tags={"location": "send_email"})
        raise err

    use_sp = should_use_sendpulse(props.to)
    config = get_providers(use_sp)

    try:
        return await config.primary(props)
    except Exception as err:  # noqa: BLE001
        err_msg = str(err)
        logger.warning(
            f"{config.p_name} failed: {err_msg}",
            exc_info=True,
        )
        sentry_sdk.capture_message(
            f"Failover: {config.p_name} failed",
            level="warning",
            tags={"provider": config.p_name, "location": "send_email"},
        )

        if config.secondary:
            return await execute_failover(
                config.secondary,
                props,
                config.s_name,
                err,
            )
        return ProviderResult(success=False, provider=config.p_name, error=err_msg)


def render_email_template(
    rows_html: str,
    subject: str,
    preheader_category: str = "SYSTEM",
    preheader_action: str = "VERIFIED",
    footer_html: str | None = None,
) -> str:
    """
    Renders a unified HTML wrapper using standard Nexus branding.

    This enables reusing styling, fonts, layouts, and footer information
    across all transactional emails.

    footer_html: custom footer row content. Defaults (None) to the standard
    "a Nexus account was created" notice, which is only accurate for
    account/auth emails - pass an explicit string for anything else, or an
    empty string to omit the footer row entirely.
    """
    app_domain = settings.app_domain
    email_domain = settings.email_domain
    if footer_html is None:
        footer_html = f"""
              You are receiving this mandatory service-related communication
              because a Nexus account was created using this
              email address. If you did not initiate this action, please contact
              support at <a href="mailto:support@{email_domain}" style="color: pink;">
              support@{email_domain}</a>
              <br>
              <a href="https://{app_domain}/legal" target="_blank"
                 style="color: white">Privacy, Terms & Legal</a>
        """
    footer_row = (
        f"""
          <tr>
            <td style="padding: 24px 32px; background-color: #0A0B0E;
                       border-top: 1px solid #1A1C20;
                       font-family: ui-monospace, SFMono-Regular,
                       Menlo, Monaco, Consolas, monospace;
                       font-size: 10px; color: white; line-height: 1.5;
                       text-align: center;">
              {footer_html}
            </td>
          </tr>
        """
        if footer_html.strip()
        else ""
    )
    return f"""<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" lang="en">
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>{subject}</title>
  <style type="text/css">
    body {{
      margin: 0;
      padding: 0;
      min-width: 100%;
      -webkit-text-size-adjust: 100%;
      -ms-text-size-adjust: 100%;
      background-color: #0B0C10;
      color: #FFFFFF;
      font-family: -apple-system, BlinkMacSystemFont,
        "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }}
    img {{
      line-height: 100%;
      outline: none;
      text-decoration: none;
      -ms-interpolation-mode: bicubic;
      border: 0;
    }}
    table {{
      border-collapse: collapse !important;
      mso-table-lspace: 0pt;
      mso-table-rspace: 0pt;
    }}
    td {{
      font-family: -apple-system, BlinkMacSystemFont,
        "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }}

    /* Reveal real dark mode properties for compliant clients */
    @media (prefers-color-scheme: dark) {{
      .body-wrapper {{ background-color: #0B0C10 !important; }}
      .main-card {{ background-color: #0D0E12 !important; }}
    }}
  </style>
</head>
<body style="margin: 0; padding: 0; background-color: #0B0C10; color: #FFFFFF;">

  <table width="100%" border="0" cellspacing="0" cellpadding="0"
         class="body-wrapper" style="background-color: #0B0C10; table-layout: fixed;">
    <tr>
      <td align="center" style="padding: 40px 16px 60px 16px;">

        <table width="100%" border="0" cellspacing="0" cellpadding="0"
               class="main-card" style="max-width: 580px; background-color: #0D0E12;
               border: 1px solid #22252A; text-align: left;">

          <tr>
            <td style="padding: 16px 24px; border-bottom: 1px solid #22252A;
                       font-family: ui-monospace, SFMono-Regular,
                       Menlo, Monaco, Consolas, 'Liberation Mono',
                       'Courier New', monospace; font-size: 11px;
                       color: #6B7280; letter-spacing: 0.05em;">
              [ {preheader_category}: // {preheader_action} ]
            </td>
          </tr>

          {rows_html}

          {footer_row}
        </table>

      </td>
    </tr>
  </table>

</body>
</html>
"""


def render_cta_button_row(cta_text: str, cta_url: str) -> str:
    """
    Renders a standard CTA button row.
    """
    return f"""
          <tr>
            <td align="center" style="padding: 0 32px 48px 32px;">
              <table border="0" cellspacing="0" cellpadding="0" width="100%">
                <tr>
                  <td align="center">
                    <a href="{cta_url}" target="_blank"
                       style="display: block; width: 100%; max-width: 280px;
                       background-color: #00ADB5; border: 1px solid #00ADB5;
                       color: #FFFFFF; font-family: -apple-system,
                       BlinkMacSystemFont, sans-serif; font-size: 13px;
                       font-weight: 600; letter-spacing: 0.08em;
                       text-transform: uppercase; text-decoration: none;
                       padding: 15px 0; text-align: center;
                       transition: background-color 0.2s, border-color 0.2s;">
                      {cta_text}
                    </a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
    """


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


# ---------------------------------------------------------------------------
# Help, Feedback & Bug Report emails
# ---------------------------------------------------------------------------

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
    return report_id.split("-")[0].upper()


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


async def send_feedback_admin_notification_email(
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
        return f'<span style="color: #6B7280;">{field}:</span> {value}'

    # Explicit color + anchor tag rather than bare text: several mail
    # clients auto-linkify plain email addresses and override styling with
    # their own (often low-contrast on a dark background) link color.
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
