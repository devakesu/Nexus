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


def test_scrub_event_redacts_sensitive_dictionary_keys() -> None:
    raw_event: dict[str, Any] = {
        "extra": {
            "response": {
                "refresh_token": "super_secret_refresh_token_value_60_days",
                "access_token": "ephemeral_access_token_value",
                "session_id": "sess-12345",
                "safe_field": "visible_data",
            },
            "auth_payload": {
                "password": "mysecretpassword123",
                "jwt": "eyJhbGciOi...",
                "authorization": "Bearer token123",
            },
        },
    }

    event = cast(Event, raw_event)
    scrubbed = scrub_event(event, {})
    assert scrubbed is not None

    result = cast(dict[str, Any], scrubbed)
    extra = result["extra"]
    assert extra["response"]["refresh_token"] == "[REDACTED_SENSITIVE]"
    assert extra["response"]["access_token"] == "[REDACTED_SENSITIVE]"
    assert extra["response"]["session_id"] == "[REDACTED_SENSITIVE]"
    assert extra["response"]["safe_field"] == "visible_data"
    assert extra["auth_payload"]["password"] == "[REDACTED_SENSITIVE]"
    assert extra["auth_payload"]["jwt"] == "[REDACTED_SENSITIVE]"
    assert extra["auth_payload"]["authorization"] == "[REDACTED_SENSITIVE]"


def test_scrub_event_scrubs_stack_frame_local_vars() -> None:
    raw_event: dict[str, Any] = {
        "exception": {
            "values": [
                {
                    "value": "KeyError: 'decrypted_user_record'",
                    "stacktrace": {
                        "frames": [
                            {
                                "function": "get_authenticated_user_profile",
                                "filename": "app/db/profiles/crud.py",
                                "lineno": 142,
                                "vars": {
                                    "user_id": "00000000-0000-0000-0000-000000000123",
                                    "user_phone": "+14155552671",
                                    "user_email": "victim@example.com",
                                    "user_bio": "I love coding and hiking",
                                    "auth_token": "bearer eyJhbGciOi...",
                                    "nested_profile": {
                                        "emergency_contact": "+919876543210",
                                        "secret_code": "secret_passphrase_xyz",
                                    },
                                },
                            },
                        ],
                    },
                },
            ],
        },
        "threads": {
            "values": [
                {
                    "stacktrace": {
                        "frames": [
                            {
                                "vars": {
                                    "phone": "+447911123456",
                                    "access_token": "token-xyz-12345",
                                },
                            },
                        ],
                    },
                },
            ],
        },
    }

    event = cast(Event, raw_event)
    scrubbed = scrub_event(event, {})
    assert scrubbed is not None

    result = cast(dict[str, Any], scrubbed)
    exc_frame_vars = result["exception"]["values"][0]["stacktrace"]["frames"][0]["vars"]
    assert exc_frame_vars["user_phone"] == "[PHONE_REDACTED]"
    assert exc_frame_vars["user_email"] == "[EMAIL_REDACTED]"
    assert exc_frame_vars["auth_token"] == "[REDACTED_SENSITIVE]"
    assert exc_frame_vars["nested_profile"]["emergency_contact"] == "[PHONE_REDACTED]"
    assert exc_frame_vars["nested_profile"]["secret_code"] == "[REDACTED_SENSITIVE]"

    thread_frame_vars = result["threads"]["values"][0]["stacktrace"]["frames"][0]["vars"]
    assert thread_frame_vars["phone"] == "[PHONE_REDACTED]"
    assert thread_frame_vars["access_token"] == "[REDACTED_SENSITIVE]"
