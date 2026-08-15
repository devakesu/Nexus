import time
from collections.abc import Generator
from unittest.mock import AsyncMock, patch

import httpx
import pytest

from app.core.email.config import (
    _CIRCUIT_FAILURE_THRESHOLD,
    SendEmailProps,
    is_circuit_open,
    record_provider_failure,
    record_provider_success,
    reset_circuit_breakers,
    should_use_sendpulse,
)
from app.core.email.senders import (
    _get_email_client,
    clear_sendpulse_token_cache,
    close_email_client,
    get_sendpulse_token,
    send_via_brevo,
    send_via_sendpulse,
)


@pytest.fixture(autouse=True)
def _clean_state() -> Generator[None, None, None]:  # pyright: ignore[reportUnusedFunction]
    reset_circuit_breakers()
    clear_sendpulse_token_cache()
    yield
    reset_circuit_breakers()
    clear_sendpulse_token_cache()


def test_circuit_breaker_tripping_and_routing() -> None:
    with patch("app.core.email.config.has_brevo", True), patch(
        "app.core.email.config.has_sendpulse", True,
    ):
        # Initially both healthy
        assert is_circuit_open("Brevo") is False
        assert is_circuit_open("SendPulse") is False

        # Fail Brevo below threshold
        for _ in range(_CIRCUIT_FAILURE_THRESHOLD - 1):
            record_provider_failure("Brevo")
        assert is_circuit_open("Brevo") is False

        # Fail Brevo to trip threshold
        record_provider_failure("Brevo")
        assert is_circuit_open("Brevo") is True

        # Now all traffic must route to SendPulse (100%), regardless of email hash
        assert should_use_sendpulse("brevo_user@example.com") is True
        assert should_use_sendpulse("another_user@example.com") is True

        # Record Brevo success resets the circuit
        record_provider_success("Brevo")
        assert is_circuit_open("Brevo") is False

        # Fail SendPulse to trip threshold
        for _ in range(_CIRCUIT_FAILURE_THRESHOLD):
            record_provider_failure("SendPulse")
        assert is_circuit_open("SendPulse") is True

        # Now all traffic must route to Brevo (0% to SendPulse)
        assert should_use_sendpulse("sendpulse_user@example.com") is False
        assert should_use_sendpulse("another_user@example.com") is False


def test_circuit_breaker_cooldown() -> None:
    with patch("app.core.email.config.has_brevo", True), patch(
        "app.core.email.config.has_sendpulse", True,
    ):
        for _ in range(_CIRCUIT_FAILURE_THRESHOLD):
            record_provider_failure("Brevo")
        assert is_circuit_open("Brevo") is True

        # Fast forward time beyond cooldown
        with patch("time.monotonic", return_value=time.monotonic() + 100.0):
            # Half-open probe: circuit returns False to allow trial request
            assert is_circuit_open("Brevo") is False


def test_shared_http_client_reuse() -> None:
    client1 = _get_email_client()
    client2 = _get_email_client()
    assert client1 is client2
    assert isinstance(client1, httpx.AsyncClient)
    assert not client1.is_closed


@pytest.mark.anyio
async def test_sendpulse_token_caching() -> None:
    with patch("app.core.email.senders.has_sendpulse", True), patch(
        "app.core.email.senders.settings.sendpulse_client_id", "test_id",
    ), patch(
        "app.core.email.senders.settings.sendpulse_client_secret", "test_secret",
    ):
        mock_post = AsyncMock(
            return_value=httpx.Response(
                200,
                json={"access_token": "cached_sp_token_123", "expires_in": 3600},
                request=httpx.Request("POST", "https://api.sendpulse.com/oauth/access_token"),
            ),
        )
        with patch.object(_get_email_client(), "post", mock_post):
            token1 = await get_sendpulse_token()
            token2 = await get_sendpulse_token()

            assert token1 == "cached_sp_token_123"
            assert token2 == "cached_sp_token_123"
            # Must be called only once due to in-memory caching
            assert mock_post.call_count == 1


@pytest.mark.anyio
async def test_send_via_sendpulse_success_and_failure_recording() -> None:
    props = SendEmailProps(
        to="user@example.com",
        subject="Test",
        html="<p>Test</p>",
    )
    with patch("app.core.email.senders.has_sendpulse", True), patch(
        "app.core.email.senders.get_sendpulse_token", AsyncMock(return_value="sp_token"),
    ):
        # Test success
        mock_success = AsyncMock(
            return_value=httpx.Response(
                200,
                json={"id": "msg-123"},
                request=httpx.Request("POST", "https://api.sendpulse.com/smtp/emails"),
            ),
        )
        with patch.object(_get_email_client(), "post", mock_success):
            res = await send_via_sendpulse(props)
            assert res.success is True
            assert is_circuit_open("SendPulse") is False

        # Test failure trips breaker after threshold
        mock_failure = AsyncMock(
            return_value=httpx.Response(
                500,
                json={"message": "Service Down"},
                request=httpx.Request("POST", "https://api.sendpulse.com/smtp/emails"),
            ),
        )
        with patch.object(_get_email_client(), "post", mock_failure):
            for _ in range(_CIRCUIT_FAILURE_THRESHOLD):
                with pytest.raises(RuntimeError):
                    await send_via_sendpulse(props)
            assert is_circuit_open("SendPulse") is True


@pytest.mark.anyio
async def test_send_via_brevo_success_and_failure_recording() -> None:
    props = SendEmailProps(
        to="user@example.com",
        subject="Test",
        html="<p>Test</p>",
    )
    with patch("app.core.email.senders.has_brevo", True), patch(
        "app.core.email.senders.settings.brevo_api_key", "test_key",
    ):
        # Test success
        mock_success = AsyncMock(
            return_value=httpx.Response(
                201,
                json={"messageId": "brevo-123"},
                request=httpx.Request("POST", "https://api.brevo.com/v3/smtp/email"),
            ),
        )
        with patch.object(_get_email_client(), "post", mock_success):
            res = await send_via_brevo(props)
            assert res.success is True
            assert is_circuit_open("Brevo") is False

        # Test failure trips breaker after threshold
        mock_failure = AsyncMock(
            return_value=httpx.Response(
                503,
                json={"message": "Brevo unavailable"},
                request=httpx.Request("POST", "https://api.brevo.com/v3/smtp/email"),
            ),
        )
        with patch.object(_get_email_client(), "post", mock_failure):
            for _ in range(_CIRCUIT_FAILURE_THRESHOLD):
                with pytest.raises(RuntimeError):
                    await send_via_brevo(props)
            assert is_circuit_open("Brevo") is True


@pytest.mark.anyio
async def test_close_email_client() -> None:
    client = _get_email_client()
    assert not client.is_closed
    await close_email_client()
    # Next call creates a new client
    new_client = _get_email_client()
    assert new_client is not client
    assert not new_client.is_closed
