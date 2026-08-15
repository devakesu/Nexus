"""Email provider configuration, data models, and utility helpers.

Contains the core SendEmailProps/ProviderResult models, HTML stripping utility,
PII redaction helpers, and provider availability/routing logic.
"""

import logging
from collections.abc import Callable, Coroutine
from html.parser import HTMLParser
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict

from app.core.config import settings

logger = logging.getLogger(__name__)


class SendEmailProps(BaseModel):
    """Configuration payload schema for transactional email dispatch."""

    to: str
    subject: str
    html: str
    text: str | None = None
    reply_to: str | None = None
    from_name: str | None = None
    to_name: str | None = None
    sender_email: str | None = None


class ProviderResult(BaseModel):
    """Result schema for individual email provider dispatch attempts."""

    success: bool
    provider: Literal["Brevo", "SendPulse"]
    id: str | None = None
    error: str | None = None


class HTMLStripper(HTMLParser):
    """HTML parser utility to extract plain text from HTML markup."""

    def __init__(self) -> None:
        """Initialize the HTML parser state and accumulator buffer."""
        super().__init__()
        self.reset()
        self.strict = False
        self.convert_charrefs = True
        self.text: list[str] = []

    def handle_data(self, data: str) -> None:
        """Append extracted text node data to the internal text buffer.

        Args:
            data: Raw text content from an HTML text node.
        """
        self.text.append(data)

    def get_data(self) -> str:
        """Concatenate buffered text data into a single plain text string.

        Returns:
            str: Accumulated plain text string.
        """
        return "".join(self.text)


def strip_tags(html: str) -> str:
    """Strips HTML tags to generate a plain text fallback string.

    Args:
        html: Raw HTML input string.

    Returns:
        str: Cleaned plain text string.
    """
    s = HTMLStripper()
    s.feed(html)
    return s.get_data()


def redact_email(email: str) -> str:
    """Redacts an email address string for privacy-compliant logging.

    Args:
        email: Raw email address string.

    Returns:
        str: Redacted email string (e.g. u***r@domain.com).
    """
    if not email or "@" not in email:
        return email
    parts = email.split("@", 1)

    name = parts[0]
    domain = parts[1]
    if len(name) <= 2:
        return f"{name[0]}***@{domain}"
    return f"{name[0]}***{name[-1]}@{domain}"


def redact(type_: str, val: str) -> str:
    """Executes redact operation.

        Args:
            type_: Input type  parameter.
            val: Input val parameter.

        Returns:
            str: Response payload or result."""
    if type_ == "email":
        return redact_email(val)
    return val


has_brevo = bool(settings.brevo_api_key)
has_sendpulse = bool(settings.sendpulse_client_id and settings.sendpulse_client_secret)


def get_support_email() -> str:
    """Centralized support email address for notifications and system routing."""
    return f"support@{settings.email_domain}"


def get_sender_email() -> str:
    """Executes get sender email operation.

        Returns:
            str: Response payload or result."""
    return get_support_email()


def get_feedback_notify_email() -> str:
    """Where "Help, Feedback & Bug Report" admin notifications are routed."""
    return get_support_email()


def get_sender_name(from_name: str | None = None) -> str:
    """Executes get sender name operation.

        Args:
            from_name: Input from name parameter.

        Returns:
            str: Response payload or result."""
    if from_name and from_name.strip():
        return from_name.strip()
    return settings.app_name


class ProvidersConfig(BaseModel):
    """Providersconfig class representation."""
    primary: Any  # ProviderFn
    secondary: Any | None = None  # ProviderFn | None
    p_name: Literal["SendPulse", "Brevo"]
    s_name: Literal["Brevo", "SendPulse"]

    model_config = ConfigDict(arbitrary_types_allowed=True)


# Type alias for provider send functions
ProviderFn = Callable[[SendEmailProps], Coroutine[Any, Any, ProviderResult]]


class CircuitBreakerState(BaseModel):
    """Tracks provider failure status and circuit breaker state."""

    consecutive_failures: int = 0
    last_failure_time: float = 0.0
    is_open: bool = False


_CIRCUIT_FAILURE_THRESHOLD = 5
_CIRCUIT_COOLDOWN_SECONDS = 60.0

_circuit_breakers: dict[str, CircuitBreakerState] = {
    "Brevo": CircuitBreakerState(),
    "SendPulse": CircuitBreakerState(),
}


def record_provider_success(provider: str) -> None:
    """Records a successful email dispatch for a provider, resetting failure counts."""
    state = _circuit_breakers.setdefault(provider, CircuitBreakerState())
    state.consecutive_failures = 0
    state.is_open = False


def record_provider_failure(provider: str) -> None:
    """Records a failed email dispatch for a provider, tripping the circuit if threshold exceeded."""
    import time

    state = _circuit_breakers.setdefault(provider, CircuitBreakerState())
    state.consecutive_failures += 1
    state.last_failure_time = time.monotonic()
    if state.consecutive_failures >= _CIRCUIT_FAILURE_THRESHOLD:
        if not state.is_open:
            logger.warning(
                "Circuit breaker tripped for email provider %s (%d consecutive failures). "
                "Temporarily routing email traffic to fallback provider.",
                provider,
                state.consecutive_failures,
            )
        state.is_open = True


def is_circuit_open(provider: str) -> bool:
    """Checks if the provider circuit breaker is open (tripped)."""
    import time

    state = _circuit_breakers.get(provider)
    if not state or not state.is_open:
        return False
    # If cooldown period has elapsed, allow trial request (half-open state)
    return (time.monotonic() - state.last_failure_time) <= _CIRCUIT_COOLDOWN_SECONDS


def reset_circuit_breakers() -> None:
    """Resets all provider circuit breakers (used in tests or manual health resets)."""
    for state in _circuit_breakers.values():
        state.consecutive_failures = 0
        state.last_failure_time = 0.0
        state.is_open = False


def should_use_sendpulse(email: str | None = None) -> bool:
    """Determines whether to route email dispatch to SendPulse or Brevo.

    Respects provider circuit-breaker health:
    - If Brevo circuit is open, routes 100% to SendPulse.
    - If SendPulse circuit is open, routes 100% to Brevo.
    - If both are healthy, applies consistent email hash load-balancing.

    Args:
        email: Email address string.

    Returns:
        bool: True to route to SendPulse, False to route to Brevo.
    """
    if has_brevo and has_sendpulse:
        brevo_open = is_circuit_open("Brevo")
        sendpulse_open = is_circuit_open("SendPulse")

        if brevo_open and not sendpulse_open:
            return True
        if sendpulse_open and not brevo_open:
            return False

        if email:
            import hashlib

            encoded_email = email.lower().encode("utf-8")
            hash_val = int(hashlib.sha256(encoded_email).hexdigest(), 16)
            return hash_val % 2 == 0
        import secrets

        return secrets.randbelow(100) < 50
    return has_sendpulse
