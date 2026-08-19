import base64
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

from app.core.security.portal_auth import (
    generate_otp_code,
    hash_otp,
    hash_phone_identifier,
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

    # Valid token verification succeeds and returns phone_id hash
    res = verify_portal_access_token(session_id, token)
    assert res == hash_phone_identifier(phone_norm)


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

    from app.core.security.crypto import get_hmac_signing_key
    from app.core.security.portal_auth import _get_signing_key

    # Strictly use hmac_signing_key
    with patch("app.core.security.crypto.settings.hmac_signing_key", "custom_hmac_key"), patch(
        "app.core.security.crypto.settings.blind_index_key", "fallback_blind_key",
    ):
        assert _get_signing_key() == b"custom_hmac_key"
        assert get_hmac_signing_key() == b"custom_hmac_key"

    # Strictly forbid fallback to blind_index_key when hmac_signing_key is empty
    with patch("app.core.security.crypto.settings.hmac_signing_key", ""), patch(
        "app.core.security.crypto.settings.blind_index_key", "fallback_blind_key",
    ):
        with pytest.raises(RuntimeError) as exc_info:
            _get_signing_key()
        assert "HMAC_SIGNING_KEY must be configured" in str(exc_info.value)

        with pytest.raises(RuntimeError) as exc_crypto:
            get_hmac_signing_key()
        assert "HMAC_SIGNING_KEY must be configured" in str(exc_crypto.value)

    # Raise RuntimeError when neither key is configured
    with patch("app.core.security.crypto.settings.hmac_signing_key", ""), patch(
        "app.core.security.crypto.settings.blind_index_key", "",
    ):
        with pytest.raises(RuntimeError) as exc_info:
            _get_signing_key()
        assert "HMAC_SIGNING_KEY must be configured" in str(exc_info.value)


def test_domain_separation_across_all_signing_modules() -> None:
    import pytest

    from app.core.auth.phone_otp import hash_otp as phone_hash_otp
    from app.core.utils.sms import (
        _sign_contact_portal_payload,
        _sign_escalation_cancel_payload,
    )

    # When HMAC_SIGNING_KEY is empty and only BLIND_INDEX_KEY is set:
    with patch("app.core.security.crypto.settings.hmac_signing_key", ""), patch(
        "app.core.security.crypto.settings.blind_index_key", "active_blind_index_key",
    ):
        with pytest.raises(RuntimeError) as exc_phone:
            phone_hash_otp("user1", "+15551234567", "123456")
        assert "HMAC_SIGNING_KEY must be configured" in str(exc_phone.value)

        with pytest.raises(RuntimeError) as exc_sms_cancel:
            _sign_escalation_cancel_payload("sess1:1:123456789")
        assert "HMAC_SIGNING_KEY must be configured" in str(exc_sms_cancel.value)

        with pytest.raises(RuntimeError) as exc_sms_portal:
            _sign_contact_portal_payload("contact1:123456789")
        assert "HMAC_SIGNING_KEY must be configured" in str(exc_sms_portal.value)


def test_contact_portal_token_expiration_and_tampering() -> None:
    from app.core.utils.sms import (
        make_contact_portal_token,
        verify_contact_portal_token,
    )

    contact_id = "test-contact-999"

    # 1. Valid token verification
    token = make_contact_portal_token(contact_id, ttl_seconds=3600)
    assert verify_contact_portal_token(token) == contact_id

    # 2. Expired token is rejected
    expired_token = make_contact_portal_token(contact_id, ttl_seconds=-10)
    assert verify_contact_portal_token(expired_token) is None

    # 3. Tampered payload or signature is rejected
    tampered_sig = token[:-4] + "abcd"
    assert verify_contact_portal_token(tampered_sig) is None

    # 4. Malformed tokens are rejected
    assert verify_contact_portal_token("not-a-token") is None
    assert verify_contact_portal_token("") is None
    assert verify_contact_portal_token("abc.def.ghi") is None




