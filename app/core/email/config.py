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


def should_use_sendpulse(email: str | None = None) -> bool:
    """Executes should use sendpulse operation.

        Args:
            email: Email address string.

        Returns:
            bool: Response payload or result."""
    if has_brevo and has_sendpulse:
        if email:
            import hashlib

            encoded_email = email.lower().encode("utf-8")
            hash_val = int(hashlib.sha256(encoded_email).hexdigest(), 16)
            return hash_val % 2 == 0
        import secrets

        return secrets.randbelow(100) < 50
    return has_sendpulse
