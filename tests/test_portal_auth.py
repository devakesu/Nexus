import base64
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from app.core.security.portal_auth import (
    generate_otp_code,
    hash_otp,
    make_portal_access_token,
    verify_otp_hash,
    verify_portal_access_token,
)


def test_generate_otp_code_length() -> None:
    code = generate_otp_code()
    assert len(code) == 6
    assert code.isdigit()


def test_hash_and_verify_otp() -> None:
    session_id = "session-123"
    phone_norm = "+15551234567"
    code = "123456"

    digest = hash_otp(session_id, phone_norm, code)
    assert verify_otp_hash(session_id, phone_norm, code, digest) is True
    assert verify_otp_hash(session_id, phone_norm, "654321", digest) is False
    assert verify_otp_hash("other-session", phone_norm, code, digest) is False


def test_make_portal_access_token_does_not_leak_plaintext_phone() -> None:
    session_id = "sess-abc-789"
    phone_norm = "+15559876543"

    token = make_portal_access_token(session_id, phone_norm)
    assert "." in token
    payload_b64, _signature = token.split(".", 1)

    # Decode base64 payload
    padding = "=" * (-len(payload_b64) % 4)
    decoded_payload = base64.urlsafe_b64decode(payload_b64 + padding).decode()

    # Plaintext phone MUST NOT appear in the payload string
    assert phone_norm not in decoded_payload
    assert "9876543" not in decoded_payload

    # Valid token verification succeeds
    res = verify_portal_access_token(session_id, token)
    assert res is not None


def test_verify_portal_access_token_rejections() -> None:
    session_id = "sess-abc-789"
    phone_norm = "+15559876543"

    token = make_portal_access_token(session_id, phone_norm)

    # Wrong session_id
    assert verify_portal_access_token("different-session", token) is None

    # Tampered signature
    assert verify_portal_access_token(session_id, token + "bad") is None

    # Malformed token
    assert verify_portal_access_token(session_id, "invalid.token") is None
    assert verify_portal_access_token(session_id, "no-dot-token") is None

    # Expired token
    with patch("app.core.security.portal_auth.datetime") as mock_dt:
        mock_dt.now.return_value = datetime.now(timezone.utc) + timedelta(hours=2)
        assert verify_portal_access_token(session_id, token) is None


def test_get_signing_key_behavior() -> None:
    import pytest

    from app.core.security.portal_auth import _get_signing_key

    # Prefer hmac_signing_key
    with patch("app.core.security.portal_auth.settings.hmac_signing_key", "custom_hmac_key"), patch(
        "app.core.security.portal_auth.settings.blind_index_key", "fallback_blind_key",
    ):
        assert _get_signing_key() == b"custom_hmac_key"

    # Fallback to blind_index_key when hmac_signing_key is empty
    with patch("app.core.security.portal_auth.settings.hmac_signing_key", ""), patch(
        "app.core.security.portal_auth.settings.blind_index_key", "fallback_blind_key",
    ):
        assert _get_signing_key() == b"fallback_blind_key"

    # Raise RuntimeError when neither key is configured
    with patch("app.core.security.portal_auth.settings.hmac_signing_key", ""), patch(
        "app.core.security.portal_auth.settings.blind_index_key", "",
    ):
        with pytest.raises(RuntimeError) as exc_info:
            _get_signing_key()
        assert "HMAC_SIGNING_KEY or BLIND_INDEX_KEY must be configured" in str(exc_info.value)

