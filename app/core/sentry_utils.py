"""Sentry `before_send` scrub hook - see app/main.py's sentry_sdk.init()
call. Redacts email-shaped substrings (except support@) and secret/token-
shaped substrings from exception values, the top-level message, and extras,
mirroring mobile/lib/utils/error_handler.dart's `sanitize()` so both
platforms apply the same redaction policy before anything reaches Sentry.

Deliberately does NOT touch `tags` - app/db/chat_keys.py's `user_id` tag
(and any future similar tag) is a deliberate debugging correlation
identifier, not accidental PII leakage. The same reasoning is why Sentry
itself belongs in the privacy policy as a data sub-processor rather than
something to avoid using.
"""

import re
from typing import Any, cast

from sentry_sdk.types import Event, Hint

_EMAIL_RE = re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")
_SECRET_RE = re.compile(
    r"(bearer|auth|token|authorization|key|password|secret|jwt|"
    r"access_token|refresh_token)[=\s:]+"
    r"([A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.?[A-Za-z0-9\-_.+/=]*|"
    r"[A-Za-z0-9\-_.+/=]{8,})",
    re.IGNORECASE,
)


def _redact_email(match: re.Match[str]) -> str:
    email = match.group(0)
    return email if email.lower().startswith("support@") else "[EMAIL_REDACTED]"


def _redact_secret(match: re.Match[str]) -> str:
    return f"{match.group(1)}: [REDACTED_SENSITIVE]"


def _scrub_string(value: str) -> str:
    value = _EMAIL_RE.sub(_redact_email, value)
    return _SECRET_RE.sub(_redact_secret, value)


def _scrub_object(value: Any) -> Any:
    if isinstance(value, str):
        return _scrub_string(value)
    if isinstance(value, dict):
        typed_dict = cast("dict[Any, Any]", value)
        return {key: _scrub_object(item) for key, item in typed_dict.items()}
    if isinstance(value, list):
        typed_list = cast("list[Any]", value)
        return [_scrub_object(item) for item in typed_list]
    return value


def scrub_event(event: Event, hint: Hint) -> Event | None:
    _ = hint

    exception = event.get("exception")
    if isinstance(exception, dict):
        exc_values = exception.get("values")
        if isinstance(exc_values, list):
            for exc in exc_values:
                if isinstance(exc.get("value"), str):
                    exc["value"] = _scrub_string(exc["value"])

    message = event.get("message")
    if isinstance(message, str):
        event["message"] = _scrub_string(message)

    extra = event.get("extra")
    if isinstance(extra, dict):
        scrubbed_extra: dict[str, Any] = {}
        for key, value in extra.items():
            scrubbed_extra[key] = _scrub_object(value)
        event["extra"] = scrubbed_extra

    return event
