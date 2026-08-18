"""SMS delivery service and safety alert message composition utilities.

Handles Twilio API integration for SMS dispatching as well as standard message formatting
for Meetup Safety emergency alerts, check-ins, trusted contact notifications, and signed token validation.
"""

import base64
import hashlib
import hmac
import logging
from datetime import datetime, timedelta, timezone
from typing import Literal

import httpx
from pydantic import BaseModel

from app.core.config import settings

logger = logging.getLogger(__name__)

has_twilio = bool(
    settings.twilio_account_sid
    and settings.twilio_auth_token
    and settings.twilio_from_number,
)


class ProviderResult(BaseModel):
    """Result schema for SMS provider dispatch attempts."""

    success: bool
    provider: Literal["Twilio"]
    id: str | None = None
    error: str | None = None


def redact_phone(phone: str) -> str:
    """Masks a phone number string for safe log outputs.

    Args:
        phone: Target phone number string.

    Returns:
        str: Sanitized phone string showing only last 4 digits (***1234).
    """
    digits = phone[-4:] if len(phone) >= 4 else phone
    return f"***{digits}"


async def send_via_twilio(to: str, body: str) -> ProviderResult:
    """Dispatches an SMS message directly via the Twilio REST API.

    Args:
        to: Destination phone number in E.164 format.
        body: Text message body content.

    Returns:
        ProviderResult: Execution status and Twilio message SID or error details.

    Raises:
        ValueError: If Twilio credentials are missing.
    """
    if not has_twilio:
        raise ValueError("Twilio not configured")

    account_sid = settings.twilio_account_sid
    auth_token = settings.twilio_auth_token
    url = f"https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Messages.json"

    basic_auth = base64.b64encode(f"{account_sid}:{auth_token}".encode()).decode()

    from_number = settings.twilio_from_number or ""
    post_data = {
        "To": to,
        "Body": body,
    }
    if from_number.startswith("MG"):
        post_data["MessagingServiceSid"] = from_number
    else:
        post_data["From"] = from_number

    async with httpx.AsyncClient() as client:
        res = await client.post(
            url,
            data=post_data,
            headers={
                "Authorization": f"Basic {basic_auth}",
                "Content-Type": "application/x-www-form-urlencoded",
            },
            timeout=15.0,
        )
        if res.status_code not in (200, 201):
            try:
                err_data = res.json()
                err_msg = err_data.get("message", f"Twilio error: {res.status_code}")
            except Exception:  # noqa: BLE001
                err_msg = f"Twilio error: {res.status_code}"
            return ProviderResult(success=False, provider="Twilio", error=err_msg)

        try:
            data = res.json()
            message_sid = str(data.get("sid", ""))
        except Exception:  # noqa: BLE001
            message_sid = ""

        return ProviderResult(success=True, provider="Twilio", id=message_sid)


async def send_sms(to: str, body: str) -> ProviderResult:
    """Dispatches a single SMS via Twilio safely without raising exceptions.

    Args:
        to: Destination phone number.
        body: Text content of the SMS.

    Returns:
        ProviderResult: Object containing dispatch success flag and message/error ID.
    """
    masked_to = redact_phone(to)
    if not has_twilio:
        logger.warning("Twilio not configured; skipping SMS to %s", masked_to)
        return ProviderResult(
            success=False,
            provider="Twilio",
            error="SMS provider not configured",
        )
    try:
        return await send_via_twilio(to, body)
    except Exception as e:
        logger.exception("Failed to send SMS via Twilio to %s", masked_to)
        return ProviderResult(success=False, provider="Twilio", error=str(e))


def _maps_link(location: dict[str, float] | None) -> str | None:
    """Formats Google Maps URL from latitude/longitude dictionary.

    Args:
        location: Lat/lng dictionary or None.

    Returns:
        str | None: Formatted Google Maps URL or None.
    """
    if not location:
        return None
    lat, lng = location.get("lat"), location.get("lng")
    if lat is None or lng is None:
        return None
    return f"https://maps.google.com/?q={lat},{lng}"


def sanitize_sms_text(text: str | None, max_length: int = 100) -> str | None:
    """Sanitizes user-supplied text for SMS messages by stripping control

    characters, newlines, and excessive whitespace, and capping length.

    Args:
        text: Input string to sanitize.
        max_length: Maximum allowed character length.

    Returns:
        str | None: Cleaned string, or None if empty.
    """
    if not text:
        return None
    cleaned = "".join(ch if (ch.isprintable() and ch not in "\r\n\t") else " " for ch in text)
    cleaned = " ".join(cleaned.split()).strip()
    if not cleaned:
        return None
    return cleaned[:max_length]


def compose_sos_message(
    *,
    name: str,
    silent: bool,
    location: dict[str, float] | None = None,
    event_label: str | None = None,
) -> str:
    """Composes emergency SOS SMS message text.

    Args:
        name: User display name.
        silent: True if silent SOS alert, False if loud SOS.
        location: Optional lat/lng coordinates dictionary.
        event_label: Optional meetup event label description.

    Returns:
        str: Composed multi-line SOS message text.
    """
    clean_name = sanitize_sms_text(name, max_length=50) or "A Nexus user"
    clean_event = sanitize_sms_text(event_label, max_length=100)

    lines = [f"\U0001f6a8 Emergency alert from {clean_name} via Nexus."]
    if silent:
        lines.append(
            f"{clean_name} triggered a silent SOS during a meetup and may need "
            "help right now. They may not be able to talk or text back.",
        )
    else:
        lines.append(
            f"{clean_name} triggered an SOS during a meetup and may need help "
            "right now.",
        )
    maps_link = _maps_link(location)
    if maps_link:
        lines.append(f"\U0001f4cd Last known location: {maps_link}")
    if clean_event:
        lines.append(f"\U0001f4c5 Meetup: {clean_event}")
    lines.append(
        f"If you can't reach {clean_name}, consider contacting local authorities.",
    )
    return "\n".join(lines)


def compose_inform_message(
    *,
    name: str,
    location: dict[str, float] | None = None,
    event_label: str | None = None,
) -> str:
    """Composes a non-emergency safety check-in alert message.

    Args:
        name: User display name.
        location: Optional location coordinates dictionary.
        event_label: Optional meetup description.

    Returns:
        str: Formatted precautionary SMS message string.
    """
    clean_name = sanitize_sms_text(name, max_length=50) or "A Nexus user"
    clean_event = sanitize_sms_text(event_label, max_length=100)

    lines = [
        f"⚠️ Safety check-in from {clean_name} via Nexus.",
        f"{clean_name} is flagging a low-priority safety concern during a "
        "meetup - no emergency reported, but they wanted you looped in "
        "now rather than after the fact.",
    ]
    maps_link = _maps_link(location)
    if maps_link:
        lines.append(f"\U0001f4cd Location: {maps_link}")
    if clean_event:
        lines.append(f"\U0001f4c5 Meetup: {clean_event}")
    lines.append(f"Please check in with {clean_name} when you can.")
    return "\n".join(lines)


def compose_contact_added_message(*, user_name: str, manage_link: str) -> str:
    """Composes initial onboarding SMS for newly added trusted contacts.

    Args:
        user_name: User display name who added the contact.
        manage_link: Self-service opt-out/management web link.

    Returns:
        str: Informational SMS text string.
    """
    clean_name = sanitize_sms_text(user_name, max_length=50) or "A Nexus user"
    return "\n".join([
        f"{clean_name} added you as a trusted contact on Nexus Meetup Safety.",
        "If something feels off during a meetup, you may get a check-in "
        "or SOS text from us on their behalf.",
        f"Didn't expect this, or want out? {manage_link}",
    ])


def compose_contact_self_removed_message(*, contact_name: str) -> str:
    """Composes notification text when a trusted contact opts out.

    Args:
        contact_name: Display name of the contact who removed themselves.

    Returns:
        str: Formatted notification SMS text.
    """
    clean_name = sanitize_sms_text(contact_name, max_length=50) or "A trusted contact"
    return "\n".join([
        f"⚠️ {clean_name} removed themselves as your Nexus "
        "Meetup Safety trusted contact.",
        "They will no longer receive check-in or SOS alerts on your "
        "behalf. Add a replacement contact in Safety Center if you'd like.",
    ])


def compose_unreachable_message(
    *,
    name: str,
    escalation_number: int,
    battery_percent: int | None,
    connection_type: str | None,
    event_label: str | None,
    cancel_link: str,
) -> str:
    """Composes unreachable device escalation alert message text.

    Args:
        name: User display name.
        escalation_number: Escalation attempt index (1..3).
        battery_percent: Last reported battery percentage.
        connection_type: Last known network connection string.
        event_label: Meetup description.
        cancel_link: Cancellation URL link.

    Returns:
        str: Composed message string.
    """
    clean_name = sanitize_sms_text(name, max_length=50) or "A Nexus user"
    clean_event = sanitize_sms_text(event_label, max_length=100)
    clean_conn = sanitize_sms_text(connection_type, max_length=30)

    lines = [
        f"\U0001f4f5 {clean_name}'s phone hasn't checked in via Nexus Meetup "
        f"Safety (attempt {escalation_number} of 3).",
    ]
    context_bits: list[str] = []
    if battery_percent is not None:
        context_bits.append(f"last known battery: {battery_percent}%")
    if clean_conn:
        context_bits.append(f"was on {clean_conn}")
    if context_bits:
        lines.append(f"Last update: {', '.join(context_bits)}.")
    if clean_event:
        lines.append(f"\U0001f4c5 Meetup: {clean_event}")
    lines.append(f"Please try to check on {clean_name} if you can.")
    lines.append(
        f"If {clean_name} is safe (or you'd rather not get further alerts for "
        f"this): {cancel_link}",
    )
    return "\n".join(lines)


_ESCALATION_LABEL_DOMAIN = "safety_escalation_cancel"
_ESCALATION_CANCEL_TOKEN_TTL_SECONDS = 86400  # 24 hours


def _sign_escalation_cancel_payload(payload: str) -> str:
    key = (settings.hmac_signing_key or settings.blind_index_key).encode()
    message = f"{_ESCALATION_LABEL_DOMAIN}:{payload}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def make_escalation_cancel_token(
    session_id: str,
    escalation_number: int,
    ttl_seconds: int = _ESCALATION_CANCEL_TOKEN_TTL_SECONDS,
) -> str:
    """Generates a signed, time-bound cancellation token for an escalation session and attempt.

    Args:
        session_id: Safety session identifier string.
        escalation_number: The escalation attempt number (1..3).
        ttl_seconds: Validity period in seconds (defaults to 24 hours).

    Returns:
        str: Formatted signed token string (base64_payload.signature).
    """
    expires_at = int(
        (datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds)).timestamp(),
    )
    payload = f"{session_id}:{escalation_number}:{expires_at}"
    payload_b64 = base64.urlsafe_b64encode(payload.encode()).decode().rstrip("=")
    signature = _sign_escalation_cancel_payload(payload)
    return f"{payload_b64}.{signature}"


def verify_escalation_cancel_token(session_id: str, token: str) -> int | None:
    """Verifies a submitted cancellation token against expected HMAC and expiration.

    Args:
        session_id: Safety session identifier.
        token: Submitted token string.

    Returns:
        int | None: The escalation_number if valid and not expired, None otherwise.
    """
    if not token or "." not in token:
        return None

    try:
        payload_b64, signature = token.split(".", 1)
        padding = "=" * (-len(payload_b64) % 4)
        payload = base64.urlsafe_b64decode(payload_b64 + padding).decode()
        parts = payload.split(":", 2)
        if len(parts) != 3:
            return None
        token_session_id, escalation_number_str, expires_at_raw = parts
        escalation_number = int(escalation_number_str)
        expires_at = int(expires_at_raw)
    except (ValueError, UnicodeDecodeError):
        return None

    if token_session_id != session_id:
        return None

    if not hmac.compare_digest(_sign_escalation_cancel_payload(payload), signature):
        return None

    if datetime.now(timezone.utc).timestamp() >= expires_at:
        return None

    return escalation_number


_CONTACT_PORTAL_LABEL_DOMAIN = "safety_contact_portal"


def _sign_contact_portal_payload(payload: str) -> str:
    key = (settings.hmac_signing_key or settings.blind_index_key).encode()
    message = f"{_CONTACT_PORTAL_LABEL_DOMAIN}:{payload}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


_CONTACT_PORTAL_DEFAULT_TTL_SECONDS = 30 * 86400  # 30 days


def make_contact_portal_token(
    contact_id: str,
    ttl_seconds: int = _CONTACT_PORTAL_DEFAULT_TTL_SECONDS,
) -> str:
    """Generates a signed HMAC token with expiration for the contact portal link.

    Args:
        contact_id: Safety contact identifier.
        ttl_seconds: Validity period in seconds (defaults to 30 days).

    Returns:
        str: Formatted signed token string (base64_payload.signature).
    """
    expires_at = int(
        (datetime.now(timezone.utc) + timedelta(seconds=ttl_seconds)).timestamp(),
    )
    payload = f"{contact_id}:{expires_at}"
    payload_b64 = base64.urlsafe_b64encode(payload.encode()).decode().rstrip("=")
    signature = _sign_contact_portal_payload(payload)
    return f"{payload_b64}.{signature}"


def verify_contact_portal_token(token: str) -> str | None:
    """Verifies a contact portal token against expected HMAC and expiration.

    Args:
        token: Submitted token string.

    Returns:
        str | None: The actual contact_id if valid and not expired, None otherwise.
    """
    if not token or "." not in token:
        return None

    try:
        payload_b64, signature = token.split(".", 1)
        padding = "=" * (-len(payload_b64) % 4)
        payload = base64.urlsafe_b64decode(payload_b64 + padding).decode()
        parts = payload.split(":", 1)
        if len(parts) != 2:
            return None
        contact_id, expires_at_raw = parts
        expires_at = int(expires_at_raw)
    except (ValueError, UnicodeDecodeError):
        return None

    if not hmac.compare_digest(_sign_contact_portal_payload(payload), signature):
        return None

    if datetime.now(timezone.utc).timestamp() >= expires_at:
        return None

    return contact_id



