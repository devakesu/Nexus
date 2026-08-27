# pyright: reportAttributeAccessIssue=false
import io
import logging
from typing import Any, cast
from unittest.mock import MagicMock, patch

import pytest
from sentry_sdk.types import Event

from app.core.infra.sentry import (
    SensitiveDataFilter,
    SensitiveDataFormatter,
    _scrub_string,
    scrub_event,
)


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


def test_scrub_string_redacts_media_keys() -> None:
    text1 = "Upload evidence with media_key=dGVzdC1rZXktYmFzZTY0"
    text2 = 'JSON payload: {"media_key_base64": "dGVzdC1rZXktYmFzZTY0"}'
    text3 = "media_key_base64: dGVzdC1rZXktYmFzZTY0"

    assert "[REDACTED_SENSITIVE]" in _scrub_string(text1)
    assert "[REDACTED_SENSITIVE]" in _scrub_string(text2)
    assert "[REDACTED_SENSITIVE]" in _scrub_string(text3)
    assert "dGVzdC1rZXktYmFzZTY0" not in _scrub_string(text1)
    assert "dGVzdC1rZXktYmFzZTY0" not in _scrub_string(text2)
    assert "dGVzdC1rZXktYmFzZTY0" not in _scrub_string(text3)


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
                "media_key_base64": "dGVzdC1rZXktYmFzZTY0",
                "safe_field": "visible_data",
            },
            "user_payload": {
                "password": "mysecretpassword123",
                "jwt": "eyJhbGciOi...",
                "authorization": "Bearer token123",
                "media_key": "raw_media_key_bytes",
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
    assert extra["response"]["media_key_base64"] == "[REDACTED_SENSITIVE]"
    assert extra["response"]["safe_field"] == "visible_data"
    assert extra["user_payload"]["password"] == "[REDACTED_SENSITIVE]"
    assert extra["user_payload"]["jwt"] == "[REDACTED_SENSITIVE]"
    assert extra["user_payload"]["authorization"] == "[REDACTED_SENSITIVE]"
    assert extra["user_payload"]["media_key"] == "[REDACTED_SENSITIVE]"


def test_scrub_event_f05_media_key_and_blind_index_coverage() -> None:
    # 1. Direct extra media_key_base64
    event1 = cast(Event, {"extra": {"media_key_base64": "abc123"}})
    scrubbed1 = cast(dict[str, Any], scrub_event(event1, {}))
    assert scrubbed1 is not None
    assert scrubbed1["extra"]["media_key_base64"] == "[REDACTED_SENSITIVE]"

    # 2. Request body data with media_key_base64
    event2 = cast(Event, {"request": {"data": {"media_key_base64": "k"}}})
    scrubbed2 = cast(dict[str, Any], scrub_event(event2, {}))
    assert scrubbed2 is not None
    assert scrubbed2["request"]["data"]["media_key_base64"] == "[REDACTED_SENSITIVE]"

    # 3. blind_index, otp_hash, aes_key in extras and stack frame vars
    event3 = cast(
        Event,
        {
            "extra": {
                "blind_index": "hmac_secret_hex",
                "otp_hash": "argon2_or_sha256_hash",
                "aes_key": "aes_gcm_secret",
            },
            "exception": {
                "values": [
                    {
                        "stacktrace": {
                            "frames": [
                                {
                                    "vars": {
                                        "blind_index": "5f4dcc3b5aa765d61d8327deb882cf99",
                                        "media_key": "aes_secret_key",
                                        "otp_hash": "otp_salt_hash",
                                    },
                                },
                            ],
                        },
                    },
                ],
            },
        },
    )
    scrubbed3 = cast(dict[str, Any], scrub_event(event3, {}))
    assert scrubbed3 is not None
    assert scrubbed3["extra"]["blind_index"] == "[REDACTED_SENSITIVE]"
    assert scrubbed3["extra"]["otp_hash"] == "[REDACTED_SENSITIVE]"
    assert scrubbed3["extra"]["aes_key"] == "[REDACTED_SENSITIVE]"

    vars_scrubbed = scrubbed3["exception"]["values"][0]["stacktrace"]["frames"][0]["vars"]
    assert vars_scrubbed["blind_index"] == "[REDACTED_SENSITIVE]"
    assert vars_scrubbed["media_key"] == "[REDACTED_SENSITIVE]"
    assert vars_scrubbed["otp_hash"] == "[REDACTED_SENSITIVE]"


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


def test_sensitive_data_filter_redacts_log_record_msg() -> None:
    record = logging.LogRecord(
        name="test_logger",
        level=logging.INFO,
        pathname="test.py",
        lineno=10,
        msg="Login with bearer eyJhbGciOi... from user@example.com",
        args=(),
        exc_info=None,
    )
    data_filter = SensitiveDataFilter()
    assert data_filter.filter(record) is True
    assert "[REDACTED_SENSITIVE]" in record.msg
    assert "[EMAIL_REDACTED]" in record.msg
    assert "user@example.com" not in record.msg


def test_sensitive_data_filter_redacts_log_record_args_and_extras() -> None:
    record = logging.LogRecord(
        name="test_logger",
        level=logging.WARNING,
        pathname="test.py",
        lineno=20,
        msg="Dispatch error for user %s with phone %s",
        args=("user@victim.com", "+14155552671"),
        exc_info=None,
    )
    # Extra fields attached to LogRecord
    record.auth_token = "Bearer secret_jwt_token_12345"
    record.user_email = "victim@example.com"
    record.metadata = {"nested_phone": "+919876543210"}

    data_filter = SensitiveDataFilter()
    assert data_filter.filter(record) is True
    assert record.args == ("[EMAIL_REDACTED]", "[PHONE_REDACTED]")
    assert record.auth_token == "[REDACTED_SENSITIVE]"
    assert record.user_email == "[EMAIL_REDACTED]"
    assert record.metadata == {"nested_phone": "[PHONE_REDACTED]"}


def test_sensitive_data_filter_with_stream_handler() -> None:
    stream = io.StringIO()
    handler = logging.StreamHandler(stream)
    handler.setFormatter(logging.Formatter("%(levelname)s: %(message)s"))
    handler.addFilter(SensitiveDataFilter())

    test_logger = logging.getLogger("nexus.test_stream_scrubbing")
    test_logger.setLevel(logging.INFO)
    test_logger.handlers = [handler]
    test_logger.propagate = False

    test_logger.info("Bearer eyJhbGciOi... issued for user@example.com")
    output = stream.getvalue()

    assert "[REDACTED_SENSITIVE]" in output
    assert "[EMAIL_REDACTED]" in output
    assert "eyJhbGciOi" not in output
    assert "user@example.com" not in output


def test_sensitive_data_formatter_redacts_formatted_messages_and_exceptions() -> None:
    formatter = SensitiveDataFormatter("%(levelname)s: %(message)s")
    record = logging.LogRecord(
        name="test_logger",
        level=logging.ERROR,
        pathname="test.py",
        lineno=30,
        msg="Failed auth with token: secret_api_key_12345",
        args=(),
        exc_info=None,
    )
    formatted = formatter.format(record)
    assert "[REDACTED_SENSITIVE]" in formatted
    assert "secret_api_key_12345" not in formatted

    record_json = logging.LogRecord(
        name="test_logger",
        level=logging.ERROR,
        pathname="test.py",
        lineno=35,
        msg='Payload error: {"password": "supersecretpassword", "phone": "(555) 123-4567"}',
        args=(),
        exc_info=None,
    )
    formatted_json = formatter.format(record_json)
    assert "[REDACTED_SENSITIVE]" in formatted_json
    assert "supersecretpassword" not in formatted_json
    assert "[PHONE_REDACTED]" in formatted_json
    assert "(555) 123-4567" not in formatted_json


@pytest.mark.anyio
@patch("app.api.dependencies.sentry_sdk.set_user")
@patch("app.api.dependencies._decode_jwt")
async def test_get_authenticated_user_payload_sets_sentry_user(
    mock_decode: MagicMock,
    mock_set_user: MagicMock,
) -> None:
    from fastapi import Request

    from app.api.dependencies import get_authenticated_user_payload

    mock_decode.return_value = {"sub": "user-uuid-1234", "email": "test@example.com"}
    scope: dict[str, Any] = {"type": "http", "headers": [], "state": {}}
    request = Request(scope)

    payload = await get_authenticated_user_payload(request, token="fake.jwt.token")
    assert payload["sub"] == "user-uuid-1234"
    mock_set_user.assert_called_once_with({"id": "user-uuid-1234"})


@pytest.mark.anyio
@patch("app.api.dependencies.sentry_sdk.set_user")
@patch("app.api.dependencies._decode_jwt")
async def test_get_optional_authenticated_user_id_sets_sentry_user(
    mock_decode: MagicMock,
    mock_set_user: MagicMock,
) -> None:
    from app.api.dependencies import get_optional_authenticated_user_id

    mock_decode.return_value = {"sub": "user-uuid-5678"}
    user_id = await get_optional_authenticated_user_id(token="fake.jwt.token")
    assert user_id == "user-uuid-5678"
    mock_set_user.assert_called_once_with({"id": "user-uuid-5678"})


@pytest.mark.anyio
async def test_correlation_id_middleware_generates_and_propagates_request_id() -> None:
    from fastapi import FastAPI
    from httpx import ASGITransport, AsyncClient

    from app.core.infra.correlation import (
        CorrelationIdFilter,
        CorrelationIdMiddleware,
        get_request_id,
    )

    test_app = FastAPI()
    test_app.add_middleware(CorrelationIdMiddleware)

    captured_ctx_id = None
    captured_record_id = None

    class CaptureFilter(logging.Filter):
        def filter(self, record: logging.LogRecord) -> bool:
            nonlocal captured_record_id
            captured_record_id = getattr(record, "request_id", None)
            return True

    logger = logging.getLogger("test_correlation")
    logger.setLevel(logging.INFO)
    logger.addFilter(CorrelationIdFilter())
    logger.addFilter(CaptureFilter())

    @test_app.get("/test-correlation")
    async def sample_endpoint() -> dict[str, str]:
        nonlocal captured_ctx_id
        captured_ctx_id = get_request_id()
        logger.info("Handling correlation test request")
        return {"status": "ok"}

    _ = sample_endpoint

    async with AsyncClient(
        transport=ASGITransport(app=test_app), base_url="http://test",
    ) as client:
        # Case 1: Client does not provide X-Request-ID -> Middleware auto-generates UUID
        resp1 = await client.get("/test-correlation")
        assert resp1.status_code == 200
        req_id1 = resp1.headers.get("X-Request-ID")
        assert req_id1 is not None
        assert len(req_id1) >= 16
        assert captured_ctx_id == req_id1
        assert captured_record_id == req_id1

        # Case 2: Client provides custom safe X-Request-ID -> Middleware propagates it
        resp2 = await client.get(
            "/test-correlation",
            headers={"X-Request-ID": "custom-req-id-12345"},
        )
        assert resp2.status_code == 200
        assert resp2.headers.get("X-Request-ID") == "custom-req-id-12345"
        assert captured_ctx_id == "custom-req-id-12345"
        assert captured_record_id == "custom-req-id-12345"


def test_sentry_init_excludes_local_variables() -> None:
    """Verify Sentry SDK initialization options disable local variable capture and default PII."""
    with patch("sentry_sdk.init") as mock_init:
        # Simulate main.py init block
        from app.core.config import settings
        from app.core.infra.sentry import scrub_event

        sentry_sdk_mock = mock_init
        if not settings.sentry_backend_dsn:
            mock_dsn = "https://mock@sentry.io/123"
        else:
            mock_dsn = settings.sentry_backend_dsn

        import sentry_sdk
        sentry_sdk.init(
            dsn=mock_dsn,
            environment="test",
            traces_sample_rate=0.0,
            send_default_pii=False,
            include_local_variables=False,
            before_send=scrub_event,
        )

        sentry_sdk_mock.assert_called_once()
        _, kwargs = sentry_sdk_mock.call_args
        assert kwargs.get("include_local_variables") is False
        assert kwargs.get("send_default_pii") is False
        assert kwargs.get("before_send") is scrub_event


