"""SMS delivery service and safety alert message composition utilities.

Handles Twilio API integration for SMS dispatching as well as standard message formatting
for Meetup Safety emergency alerts, check-ins, trusted contact notifications, and signed token validation.
"""

import base64
import hashlib
import hmac
import logging
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
    lines = [f"\U0001f6a8 Emergency alert from {name} via Nexus."]
    if silent:
        lines.append(
            f"{name} triggered a silent SOS during a meetup and may need "
            "help right now. They may not be able to talk or text back.",
        )
    else:
        lines.append(
            f"{name} triggered an SOS during a meetup and may need help "
            "right now.",
        )
    maps_link = _maps_link(location)
    if maps_link:
        lines.append(f"\U0001f4cd Last known location: {maps_link}")
    if event_label:
        lines.append(f"\U0001f4c5 Meetup: {event_label}")
    lines.append(
        f"If you can't reach {name}, consider contacting local authorities.",
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
    lines = [
        f"⚠️ Safety check-in from {name} via Nexus.",
        f"{name} is flagging a low-priority safety concern during a "
        "meetup - no emergency reported, but they wanted you looped in "
        "now rather than after the fact.",
    ]
    maps_link = _maps_link(location)
    if maps_link:
        lines.append(f"\U0001f4cd Location: {maps_link}")
    if event_label:
        lines.append(f"\U0001f4c5 Meetup: {event_label}")
    lines.append(f"Please check in with {name} when you can.")
    return "\n".join(lines)


def compose_contact_added_message(*, user_name: str, manage_link: str) -> str:
    """Composes initial onboarding SMS for newly added trusted contacts.

    Args:
        user_name: User display name who added the contact.
        manage_link: Self-service opt-out/management web link.

    Returns:
        str: Informational SMS text string.
    """
    return "\n".join([
        f"{user_name} added you as a trusted contact on Nexus Meetup Safety.",
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
    return "\n".join([
        f"⚠️ {contact_name} removed themselves as your Nexus "
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
    lines = [
        f"\U0001f4f5 {name}'s phone hasn't checked in via Nexus Meetup "
        f"Safety (attempt {escalation_number} of 3).",
    ]
    context_bits: list[str] = []
    if battery_percent is not None:
        context_bits.append(f"last known battery: {battery_percent}%")
    if connection_type:
        context_bits.append(f"was on {connection_type}")
    if context_bits:
        lines.append(f"Last update: {', '.join(context_bits)}.")
    if event_label:
        lines.append(f"\U0001f4c5 Meetup: {event_label}")
    lines.append(f"Please try to check on {name} if you can.")
    lines.append(
        f"If {name} is safe (or you'd rather not get further alerts for "
        f"this): {cancel_link}",
    )
    return "\n".join(lines)


_ESCALATION_TOKEN_CONTEXT = "safety_escalation_cancel"


def make_escalation_cancel_token(session_id: str) -> str:
    """Generates an HMAC-SHA256 cancellation token for an escalation session.

    Args:
        session_id: Safety session identifier string.

    Returns:
        str: Hex-encoded HMAC-SHA256 digest string.
    """
    key = settings.blind_index_key.encode()
    message = f"{_ESCALATION_TOKEN_CONTEXT}:{session_id}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def verify_escalation_cancel_token(session_id: str, token: str) -> bool:
    """Verifies a submitted cancellation token against expected HMAC using constant-time comparison.

    Args:
        session_id: Safety session identifier.
        token: Submitted token string.

    Returns:
        bool: True if valid, False otherwise.
    """
    expected = make_escalation_cancel_token(session_id)
    return hmac.compare_digest(expected, token)

