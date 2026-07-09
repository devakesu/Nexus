import base64
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
    success: bool
    provider: Literal["Twilio"]
    id: str | None = None
    error: str | None = None


def redact_phone(phone: str) -> str:
    digits = phone[-4:] if len(phone) >= 4 else phone
    return f"***{digits}"


async def send_via_twilio(to: str, body: str) -> ProviderResult:
    if not has_twilio:
        raise ValueError("Twilio not configured")

    account_sid = settings.twilio_account_sid
    auth_token = settings.twilio_auth_token
    url = f"https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Messages.json"

    basic_auth = base64.b64encode(f"{account_sid}:{auth_token}".encode()).decode()

    async with httpx.AsyncClient() as client:
        res = await client.post(
            url,
            data={
                "To": to,
                "From": settings.twilio_from_number,
                "Body": body,
            },
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
    """Sends a single SMS via Twilio. Never raises - failures come back as a
    ProviderResult with success=False so callers (e.g. the safety alert
    fan-out, which must keep notifying remaining contacts even if one send
    fails) don't need their own try/except around every call.
    """
    if not has_twilio:
        logger.warning("Twilio not configured; skipping SMS to %s", redact_phone(to))
        return ProviderResult(
            success=False,
            provider="Twilio",
            error="SMS provider not configured",
        )
    try:
        return await send_via_twilio(to, body)
    except Exception as e:
        logger.exception("Failed to send SMS via Twilio to %s", redact_phone(to))
        return ProviderResult(success=False, provider="Twilio", error=str(e))


# ---------------------------------------------------------------------------
# Meetup Safety alert message composition
#
# Kept short and always link-out-shaped rather than trying to cram GPS
# coordinates, venue, and evidence into the SMS body - see the Meetup Safety
# plan's "Message strategy" note. {portal_link} is left out entirely until
# the OTP-gated trusted-contact portal (Milestone E) exists; there's nothing
# useful to link to yet.
# ---------------------------------------------------------------------------


def _maps_link(location: dict[str, float] | None) -> str | None:
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
    """The emergency tier - fired by Silent or Loud SOS."""
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
    """The precautionary tier - a genuine (if lower-severity) safety signal,
    not a casual FYI.
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
