"""Unit tests for phone number normalization (E.164) and secure OTP hashing."""

import pytest
from fastapi import HTTPException

from app.core.auth.phone_otp import (
    generate_otp_code,
    hash_otp,
    normalize_phone,
    verify_otp_hash,
)


def test_normalize_phone_valid_e164():
    """Valid standard E.164 phone numbers normalize correctly."""
    assert normalize_phone("+14155552671") == "+14155552671"
    assert normalize_phone("+447911123456") == "+447911123456"
    assert normalize_phone("+919876543210") == "+919876543210"


def test_normalize_phone_valid_formatted_inputs():
    """Formatted phone numbers with spaces, dashes, and parentheses normalize to E.164."""
    assert normalize_phone("+1 (415) 555-2671") == "+14155552671"
    assert normalize_phone("+44-7911-123456") == "+447911123456"
    assert normalize_phone("+44 (0) 7911 123456") == "+447911123456"
    assert normalize_phone("+33 (0) 6 12 34 56 78") == "+33612345678"
    assert normalize_phone("+91 98765 43210") == "+919876543210"
    assert normalize_phone("14155552671") == "+14155552671"


def test_normalize_phone_international_00_prefix():
    """International dialing prefix '00' is normalized identically to '+' prefix without collisions."""
    assert normalize_phone("0014155552671") == "+14155552671"
    assert normalize_phone("00447911123456") == "+447911123456"
    assert normalize_phone("00919876543210") == "+919876543210"
    assert normalize_phone("001 (800) 555-1234") == "+18005551234"


@pytest.mark.parametrize(
    "invalid_input",
    [
        "!!!!!!",
        "???",
        "---",
        "+",
        "",
        "   ",
        "+0123456789",  # Country code cannot start with 0
        "0123456789",
        "000123456789",  # Triple zero prefix invalid
        "+12345",  # Too short (<8 digits)
        "+1234567",
        "+1234567890123456",  # Too long (>15 digits)
        "+99912345678",  # Non-existent country code 999
        "abc-def-ghij",
        "14155552671bad",
        "14155552671; DROP TABLE",
        "1+4155552671",
        "+1415+5552671",
    ],
)
def test_normalize_phone_invalid_inputs_raise_http_400(invalid_input: str):
    """Invalid or malformed phone inputs raise HTTP 400 Bad Request."""
    with pytest.raises(HTTPException) as exc_info:
        normalize_phone(invalid_input)
    assert exc_info.value.status_code == 400
    assert "Invalid phone number format" in exc_info.value.detail


def test_generate_and_verify_otp_hash():
    """Generates numeric OTP and verifies HMAC hash comparison."""
    code = generate_otp_code()
    assert len(code) == 6
    assert code.isdigit()

    user_id = "user-test-uuid"
    phone_norm = "+14155552671"

    digest = hash_otp(user_id, phone_norm, code)
    assert isinstance(digest, str)
    assert len(digest) == 64  # SHA-256 hex length

    assert verify_otp_hash(user_id, phone_norm, code, digest) is True
    assert verify_otp_hash(user_id, phone_norm, "000000", digest) is False
    assert verify_otp_hash("other-user", phone_norm, code, digest) is False
    assert verify_otp_hash(user_id, "+14155559999", code, digest) is False


@pytest.mark.anyio
async def test_check_and_increment_otp_attempts_sets_ttl_on_first_attempt():
    """First attempt atomically increments and applies TTL expiration."""
    from unittest.mock import AsyncMock, patch
    from app.core.infra.otp import check_and_increment_otp_attempts

    mock_incr = AsyncMock(return_value=1)
    mock_expire = AsyncMock(return_value=True)

    with patch("app.core.infra.otp.redis_client.incr", mock_incr), \
         patch("app.core.infra.otp.redis_client.expire", mock_expire):
        count = await check_and_increment_otp_attempts("attempts:key:1", max_attempts=5, ttl_seconds=600)
        assert count == 1
        mock_incr.assert_called_once_with("attempts:key:1")
        mock_expire.assert_called_once_with("attempts:key:1", 600)


@pytest.mark.anyio
async def test_check_and_increment_otp_attempts_below_threshold():
    """Attempts up to max_attempts succeed and do not reset TTL."""
    from unittest.mock import AsyncMock, patch
    from app.core.infra.otp import check_and_increment_otp_attempts

    mock_incr = AsyncMock(return_value=5)
    mock_expire = AsyncMock(return_value=True)

    with patch("app.core.infra.otp.redis_client.incr", mock_incr), \
         patch("app.core.infra.otp.redis_client.expire", mock_expire):
        count = await check_and_increment_otp_attempts("attempts:key:1", max_attempts=5, ttl_seconds=600)
        assert count == 5
        mock_incr.assert_called_once_with("attempts:key:1")
        mock_expire.assert_not_called()


@pytest.mark.anyio
async def test_check_and_increment_otp_attempts_exceeding_threshold_raises_429():
    """Attempts exceeding max_attempts atomically raise HTTP 429."""
    from unittest.mock import AsyncMock, patch
    from app.core.infra.otp import check_and_increment_otp_attempts

    mock_incr = AsyncMock(return_value=6)

    with patch("app.core.infra.otp.redis_client.incr", mock_incr):
        with pytest.raises(HTTPException) as exc_info:
            await check_and_increment_otp_attempts("attempts:key:1", max_attempts=5, ttl_seconds=600)
        assert exc_info.value.status_code == 429
        assert "Too many incorrect attempts" in exc_info.value.detail


@pytest.mark.anyio
async def test_dummy_email_send_delay():
    """Validates dummy email send delay execution."""
    import time
    from app.core.infra.otp import dummy_email_send_delay

    start = time.perf_counter()
    await dummy_email_send_delay(min_delay=0.01)
    duration = time.perf_counter() - start
    assert duration >= 0.01


def test_mask_phone():
    """Verify phone masking logic for privacy protection."""
    from app.core.auth.phone_otp import mask_phone

    assert mask_phone(None) is None
    assert mask_phone("") is None
    assert mask_phone("   ") is None
    assert mask_phone("+919876543210") == "+91******3210"
    assert mask_phone("+14155552671") == "+1******2671"
    assert mask_phone("+447911123456") == "+44******3456"
    assert mask_phone("9876543210") == "98****3210"
    assert mask_phone("1234") == "***34"


def test_generate_otp_code_lengths_and_validation():
    """Verify generate_otp_code generates correct length numeric strings and enforces validation."""
    from app.core.infra.otp import generate_otp_code

    code6 = generate_otp_code()
    assert len(code6) == 6
    assert code6.isdigit()

    code8 = generate_otp_code(8)
    assert len(code8) == 8
    assert code8.isdigit()

    code4 = generate_otp_code(4)
    assert len(code4) == 4
    assert code4.isdigit()

    with pytest.raises(ValueError, match="positive"):
        generate_otp_code(0)

    with pytest.raises(ValueError, match="positive"):
        generate_otp_code(-5)


