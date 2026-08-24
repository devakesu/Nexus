"""Sentry `before_send` scrub hook - see app/main.py's sentry_sdk.init() call.

Redacts email-shaped substrings (except support@) and secret/token-shaped substrings from
exception values, the top-level message, and extras, mirroring mobile error handler's
sanitize implementation so both platforms apply identical redaction policies before Sentry ingestion.
"""

import re
from typing import Any, cast

from sentry_sdk.types import Event, Hint

_EMAIL_RE = re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")
_PHONE_RE = re.compile(r"(?:\+[1-9]\d{6,14}\b|\b[1-9]\d{7,14}\b)")
_SECRET_RE = re.compile(
    r"(bearer|auth|token|authorization|key|password|secret|jwt|"
    r"access_token|refresh_token)[=\s:]+"
    r"([A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.?[A-Za-z0-9\-_.+/=]*|"
    r"[A-Za-z0-9\-_.+/=]{8,})",
    re.IGNORECASE,
)
_SENSITIVE_KEY_RE = re.compile(
    r"(bearer|auth|token|authorization|password|secret|jwt|"
    r"access_token|refresh_token|credential|cookie|session|media_key|private_key)",
    re.IGNORECASE,
)


def _is_sensitive_key(key: str) -> bool:
    """Checks whether a dictionary key name indicates sensitive authentication data."""
    return bool(_SENSITIVE_KEY_RE.search(key.strip()))


def _redact_email(match: re.Match[str]) -> str:
    """Redacts email addresses unless starting with support@.

    Args:
        match: Regex match object containing email string.

    Returns:
        str: Redacted string placeholder or original support email.
    """
    email = match.group(0)
    return email if email.lower().startswith("support@") else "[EMAIL_REDACTED]"


def _redact_phone(match: re.Match[str]) -> str:
    """Redacts phone number strings.

    Args:
        match: Regex match object containing phone number string.

    Returns:
        str: Redacted phone placeholder.
    """
    _ = match
    return "[PHONE_REDACTED]"


def _redact_secret(match: re.Match[str]) -> str:
    """Redacts sensitive tokens and secret values.

    Args:
        match: Regex match object for token key and secret value.

    Returns:
        str: Token key name appended with redaction tag.
    """
    return f"{match.group(1)}: [REDACTED_SENSITIVE]"


def _scrub_string(value: str) -> str:
    """Scrubs sensitive email addresses, phone numbers, and token secrets from a string value.

    Args:
        value: Input string to scrub.

    Returns:
        str: Sanitized string.
    """
    value = _EMAIL_RE.sub(_redact_email, value)
    value = _PHONE_RE.sub(_redact_phone, value)
    return _SECRET_RE.sub(_redact_secret, value)


def _scrub_object(value: Any) -> Any:
    """Recursively scrubs nested data structures (dicts, lists, strings).

    Args:
        value: Object of arbitrary type to scrub.

    Returns:
        Any: Sanitized object copy.
    """
    if isinstance(value, str):
        return _scrub_string(value)
    if isinstance(value, dict):
        typed_dict = cast("dict[Any, Any]", value)
        scrubbed_dict: dict[Any, Any] = {}
        for key, item in typed_dict.items():
            if isinstance(key, str) and _is_sensitive_key(key):
                scrubbed_dict[key] = "[REDACTED_SENSITIVE]"
            else:
                scrubbed_dict[key] = _scrub_object(item)
        return scrubbed_dict
    if isinstance(value, list):
        typed_list = cast("list[Any]", value)
        return [_scrub_object(item) for item in typed_list]
    return value


def _scrub_stacktrace(stacktrace: Any) -> None:
    """Recursively scrubs local variable dictionaries inside stack frames."""
    if not isinstance(stacktrace, dict):
        return
    typed_stacktrace = cast(dict[str, Any], stacktrace)
    frames = typed_stacktrace.get("frames")
    if isinstance(frames, list):
        typed_frames = cast(list[Any], frames)
        for frame in typed_frames:
            if isinstance(frame, dict):
                typed_frame = cast(dict[str, Any], frame)
                if isinstance(typed_frame.get("vars"), dict):
                    typed_frame["vars"] = _scrub_object(typed_frame["vars"])


def scrub_event(event: Event, hint: Hint) -> Event | None:  # noqa: C901
    """Sentry `before_send` hook callback function.

    Args:
        event: Sentry Event dictionary.
        hint: Sentry Hint context object.

    Returns:
        Event | None: Sanitized Sentry event dictionary or None to drop.
    """
    _ = hint

    exception = event.get("exception")
    if isinstance(exception, dict):
        exc_values = exception.get("values")
        if isinstance(exc_values, list):
            for exc in exc_values:
                if isinstance(exc.get("value"), str):
                    exc["value"] = _scrub_string(exc["value"])
                if isinstance(exc.get("stacktrace"), dict):
                    _scrub_stacktrace(exc["stacktrace"])

    threads = event.get("threads")
    if isinstance(threads, dict):
        thread_values = threads.get("values")
        if isinstance(thread_values, list):
            for thread in thread_values:
                if isinstance(thread.get("stacktrace"), dict):
                    _scrub_stacktrace(thread["stacktrace"])

    stacktrace = event.get("stacktrace")
    if isinstance(stacktrace, dict):
        _scrub_stacktrace(stacktrace)

    message = event.get("message")
    if isinstance(message, str):
        event["message"] = _scrub_string(message)

    extra = event.get("extra")
    if isinstance(extra, dict):
        scrubbed_extra: dict[str, Any] = {}
        for key, value in extra.items():
            scrubbed_extra[key] = _scrub_object(value)
        event["extra"] = scrubbed_extra

    breadcrumbs = event.get("breadcrumbs")
    if isinstance(breadcrumbs, (dict, list)):
        event["breadcrumbs"] = _scrub_object(breadcrumbs)

    request_data = event.get("request")
    if isinstance(request_data, dict):
        event["request"] = _scrub_object(request_data)

    contexts = event.get("contexts")
    if isinstance(contexts, dict):
        event["contexts"] = _scrub_object(contexts)

    return event

