"""Unit tests for Sentry before_send event scrubbing (phone numbers, emails, secrets)."""

from typing import Any, cast

from sentry_sdk.types import Event

from app.core.infra.sentry import _scrub_string, scrub_event


def test_scrub_string_redacts_phones() -> None:
    # E.164 and international phone numbers
    text = "User phone is +14155552671 and contact is +919876543210."
    scrubbed = _scrub_string(text)
    assert scrubbed == "User phone is [PHONE_REDACTED] and contact is [PHONE_REDACTED]."


def test_scrub_string_redacts_emails_and_secrets() -> None:
    text = "Contact user@example.com or support@nexus.com with token: eyJhbGciOi..."
    scrubbed = _scrub_string(text)
    assert "[EMAIL_REDACTED]" in scrubbed
    assert "support@nexus.com" in scrubbed
    assert "[REDACTED_SENSITIVE]" in scrubbed


def test_scrub_event_deep_scrubbing() -> None:
    raw_event: dict[str, Any] = {
        "message": "Failed SMS dispatch to +14155552671",
        "exception": {
            "values": [
                {
                    "value": "Error sending to +447911123456: user@victim.com bearer=secret_jwt_token_12345",
                },
            ],
        },
        "extra": {
            "recipient_phone": "+12025550199",
            "nested": {
                "contact_phone": "+919876543210",
            },
        },
        "breadcrumbs": [
            {
                "message": "Attempted SMS to +15551234567",
            },
        ],
    }

    event = cast(Event, raw_event)
    scrubbed = scrub_event(event, {})
    assert scrubbed is not None

    result = cast(dict[str, Any], scrubbed)
    assert result["message"] == "Failed SMS dispatch to [PHONE_REDACTED]"
    assert result["exception"]["values"][0]["value"] == "Error sending to [PHONE_REDACTED]: [EMAIL_REDACTED] bearer: [REDACTED_SENSITIVE]"
    assert result["extra"]["recipient_phone"] == "[PHONE_REDACTED]"
    assert result["extra"]["nested"]["contact_phone"] == "[PHONE_REDACTED]"
    assert result["breadcrumbs"][0]["message"] == "Attempted SMS to [PHONE_REDACTED]"
