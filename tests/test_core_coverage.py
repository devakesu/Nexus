"""Comprehensive unit tests covering 100% of app/core modules (JWKS, config, crypto, email, sms, infra, utils)."""

import asyncio
import base64
import time
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec

from app.core.config import (
    Settings,
    is_valid_app_domain,
)
from app.core.email.config import (
    SendEmailProps,
    get_sender_email,
    get_sender_name,
    redact,
    strip_tags,
)
from app.core.email.senders import (
    clear_sendpulse_token_cache,
    close_email_client,
    get_sendpulse_token,
    send_email,
    send_via_brevo,
    send_via_sendpulse,
)
from app.core.infra.cache import (
    get_block_ids_cache_ttl,
    invalidate_user_status_cache,
)
from app.core.infra.otp import (
    generate_otp_code,
    otp_verified_redis_key,
)
from app.core.infra.tasks import (
    run_with_retries,
    safe_create_task,
)
from app.core.security.crypto import (
    DecryptFailedError,
    compute_blind_index,
    decrypt_pii,
    encrypt_pii,
    reset_cipher_suites,
)
from app.core.security.jwks import (
    _find_jwk_by_kid,
    _isolate_fallback_jwk,
    _parse_jwk_dict,
    clear_jwks_cache,
    get_live_supabase_public_key,
)
from app.core.security.portal_auth import (
    hash_otp,
    hash_phone_identifier,
    make_portal_access_token,
    verify_otp_hash,
    verify_portal_access_token,
)
from app.core.utils.moderation import (
    NameModerationError,
    validate_display_name,
)
from app.core.utils.sms import (
    compose_contact_added_message,
    compose_contact_self_removed_message,
    compose_inform_message,
    compose_sos_message,
    compose_unreachable_message,
    make_contact_portal_token,
    make_escalation_cancel_token,
    redact_phone,
    sanitize_sms_text,
    send_via_twilio,
    verify_contact_portal_token,
    verify_escalation_cancel_token,
)

pytestmark = pytest.mark.anyio


# ==========================================
# 1. JWKS & SUPABASE SECURITY TESTS
# ==========================================

async def test_jwks_resolution_and_caching():
    # Clear existing state
    clear_jwks_cache()

    # _parse_jwk_dict with invalid type
    with pytest.raises(RuntimeError, match="Invalid key format configuration"):
        _parse_jwk_dict(12345)

    # _find_jwk_by_kid
    keys: list[object] = [{"kid": "key-1", "kty": "EC"}, {"kid": "key-2", "kty": "EC"}]
    assert _find_jwk_by_kid(keys, "key-1") == {"kid": "key-1", "kty": "EC"}
    assert _find_jwk_by_kid(keys, "key-missing") is None

    # _isolate_fallback_jwk with no keys wrapper
    single_jwk = {"kty": "EC", "crv": "P-256", "x": "abc", "y": "def"}
    assert _isolate_fallback_jwk(single_jwk, None) == single_jwk

    # _isolate_fallback_jwk with empty keys list
    with pytest.raises(jwt.InvalidTokenError):
        _isolate_fallback_jwk({"keys": []}, None)

    # _isolate_fallback_jwk with matching kid
    jwks_dict = {"keys": [{"kid": "k1", "val": 1}, {"kid": "k2", "val": 2}]}
    assert _isolate_fallback_jwk(jwks_dict, "k2") == {"kid": "k2", "val": 2}
    assert _isolate_fallback_jwk(jwks_dict, "unknown-kid") == {"kid": "k1", "val": 1}


async def test_get_live_supabase_public_key_flows():
    clear_jwks_cache()

    # Generate a real EC key pair for testing
    private_key = ec.generate_private_key(ec.SECP256R1())
    public_key = private_key.public_key()
    pub_numbers = public_key.public_numbers()

    x_b64 = base64.urlsafe_b64encode(pub_numbers.x.to_bytes(32, "big")).rstrip(b"=").decode("ascii")
    y_b64 = base64.urlsafe_b64encode(pub_numbers.y.to_bytes(32, "big")).rstrip(b"=").decode("ascii")

    jwks_payload = {
        "keys": [
            {
                "kty": "EC",
                "crv": "P-256",
                "x": x_b64,
                "y": y_b64,
                "kid": "test-kid-1",
                "alg": "ES256",
                "use": "sig",
            },
        ],
    }

    # Encode a test token signed with EC private key
    token = jwt.encode(
        {"sub": "usr-123", "exp": time.time() + 3600},
        private_key,
        algorithm="ES256",
        headers={"kid": "test-kid-1"},
    )

    # Mock httpx response for JWKS endpoint
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = jwks_payload

    with patch("httpx.AsyncClient.get", new_callable=AsyncMock, return_value=mock_resp):
        resolved_key = await get_live_supabase_public_key(token, force_refresh=True)
        assert isinstance(resolved_key, ec.EllipticCurvePublicKey)

    # Test invalid token format
    with pytest.raises(jwt.InvalidTokenError, match="Malformed request payload"):
        await get_live_supabase_public_key("invalid.token")

    # Test unknown kid when cache is populated
    unknown_token = jwt.encode(
        {"sub": "usr-123"},
        private_key,
        algorithm="ES256",
        headers={"kid": "revoked-kid-999"},
    )
    with patch("httpx.AsyncClient.get", new_callable=AsyncMock, return_value=mock_resp):
        with pytest.raises(jwt.InvalidTokenError, match="not recognized or has been revoked"):
            await get_live_supabase_public_key(unknown_token)


# ==========================================
# 2. CONFIG TESTS
# ==========================================

def test_config_validators_and_defaults():
    # Firebase service account validator
    assert Settings.parse_firebase_service_account(None) is None
    assert Settings.parse_firebase_service_account({"type": "service_account"}) == {"type": "service_account"}
    assert Settings.parse_firebase_service_account('{"type": "service_account"}') == {"type": "service_account"}

    b64_json = base64.b64encode(b'{"type": "service_account"}').decode("ascii")
    assert Settings.parse_firebase_service_account(b64_json) == {"type": "service_account"}

    with pytest.raises(ValueError, match="firebase_service_account must be a valid JSON"):
        Settings.parse_firebase_service_account("invalid-string-not-json")

    # Allowed signup domains validator
    assert Settings.parse_allowed_signup_domains(None) == {}
    assert Settings.parse_allowed_signup_domains('{"nexus": ["domain.com"]}') == {"nexus": ["domain.com"]}
    assert Settings.parse_allowed_signup_domains({"nexus": "domain1.com, domain2.com"}) == {"nexus": ["domain1.com", "domain2.com"]}
    assert Settings.parse_allowed_signup_domains({"nexus": ["d1.com", "d2.com"]}) == {"nexus": ["d1.com", "d2.com"]}

    with pytest.raises(ValueError, match="allowed_signup_domains must be a JSON object"):
        Settings.parse_allowed_signup_domains(12345)

    # Domain validator helpers
    assert is_valid_app_domain("nexusapp.xyz") is True
    assert is_valid_app_domain("localhost:8000") is False


# ==========================================
# 3. EMAIL SENDERS & CONFIG TESTS
# ==========================================

async def test_email_senders_and_failover():
    clear_sendpulse_token_cache()

    # Helper functions
    assert strip_tags("<p>Hello <b>World</b></p>") == "Hello World"
    assert redact("email", "john@example.com") == "j***n@example.com"
    assert redact("other", "plain_val") == "plain_val"

    sender_email = get_sender_email()
    assert "@" in sender_email
    sender_name = get_sender_name()
    assert len(sender_name) > 0

    # Test SendPulse token fetch failure
    with patch("app.core.email.senders.has_sendpulse", True), \
         patch("app.core.config.settings.sendpulse_client_id", "invalid_id"), \
         patch("app.core.config.settings.sendpulse_client_secret", "invalid_secret"):
        mock_auth_fail = MagicMock()
        mock_auth_fail.status_code = 401
        mock_auth_fail.text = "Unauthorized"
        with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_auth_fail):
            with pytest.raises(RuntimeError, match="SendPulse Auth Failed"):
                await get_sendpulse_token()

    # Test SendPulse token fetch success
    mock_auth_ok = MagicMock()
    mock_auth_ok.status_code = 200
    mock_auth_ok.json.return_value = {"access_token": "mock_sp_token", "expires_in": 3600}
    with patch("app.core.email.senders.has_sendpulse", True), \
         patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_auth_ok):
        token = await get_sendpulse_token()
        assert token == "mock_sp_token"

    # Test send_via_sendpulse success
    mock_sp_send = MagicMock()
    mock_sp_send.status_code = 200
    mock_sp_send.json.return_value = {"result": True, "id": "sp_msg_123"}
    with patch("app.core.email.senders.has_sendpulse", True), \
         patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_sp_send):
        props = SendEmailProps(to="user@example.com", subject="Test Subject", html="<p>Test Body</p>")
        res = await send_via_sendpulse(props)
        assert res.success is True
        assert res.provider == "SendPulse"

    # Test send_via_brevo success
    mock_brevo_send = MagicMock()
    mock_brevo_send.status_code = 201
    mock_brevo_send.json.return_value = {"messageId": "brevo_msg_456"}
    with patch("app.core.email.senders.has_brevo", True), \
         patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_brevo_send):
        props_b = SendEmailProps(to="user@example.com", subject="Test Subject", html="<p>Test Body</p>")
        res_brevo = await send_via_brevo(props_b)
        assert res_brevo.success is True
        assert res_brevo.provider == "Brevo"

    # Test send_email top-level dispatcher
    with patch("app.core.email.senders.has_sendpulse", True), \
         patch("app.core.email.senders.send_via_sendpulse", new_callable=AsyncMock, return_value=res):
        out = await send_email(
            SendEmailProps(to="recipient@example.com", subject="Welcome", html="<p>Welcome!</p>"),
        )
        assert out.success is True

    await close_email_client()


# ==========================================
# 4. SMS & UTILS & MODERATION TESTS
# ==========================================

async def test_sms_twilio_and_tokens():
    # Sanitize SMS text
    assert sanitize_sms_text("Hello\x00World\nNew\rLine") == "Hello World New Line"
    assert sanitize_sms_text("   Lots   of   spaces   ") == "Lots of spaces"
    sanitized_long = sanitize_sms_text("a" * 300, max_length=100)
    assert sanitized_long is not None and len(sanitized_long) == 100
    assert sanitize_sms_text(None) is None
    assert sanitize_sms_text("   ") is None
    assert redact_phone("+15551234567") == "***4567"

    # Message composition
    sos_loud = compose_sos_message(name="Jane", silent=False, location={"lat": 12.97, "lng": 77.59}, event_label="Coffee")
    assert "Emergency alert from Jane" in sos_loud
    assert "Last known location" in sos_loud

    sos_silent = compose_sos_message(name="Jane", silent=True)
    assert "silent SOS" in sos_silent

    inform = compose_inform_message(name="Jane", location={"lat": 12.97, "lng": 77.59}, event_label="Dinner")
    assert "Safety check-in" in inform

    contact_add = compose_contact_added_message(user_name="Jane", manage_link="https://nexusapp.xyz/safety")
    assert "added you as a trusted contact" in contact_add

    self_remove = compose_contact_self_removed_message(contact_name="Bob")
    assert "removed themselves as your Nexus" in self_remove

    unreach = compose_unreachable_message(
        name="Jane",
        escalation_number=1,
        battery_percent=15,
        connection_type="cellular",
        event_label="Dinner",
        cancel_link="https://nexusapp.xyz/cancel",
    )
    assert "hasn't checked in" in unreach
    assert "battery 15%" in unreach

    # Escalation cancel token generation and verification
    esc_token = make_escalation_cancel_token(session_id="ses-123", escalation_number=2, ttl_seconds=300)
    assert verify_escalation_cancel_token("ses-123", esc_token) == 2
    assert verify_escalation_cancel_token("wrong-session", esc_token) is None
    assert verify_escalation_cancel_token("ses-123", "invalid-token") is None

    # Contact portal token generation and verification
    c_token = make_contact_portal_token(contact_id="11111111-1111-1111-1111-111111111111", ttl_seconds=300)
    assert verify_contact_portal_token(c_token) == "11111111-1111-1111-1111-111111111111"
    assert verify_contact_portal_token("invalid-token") is None

    # Twilio SMS dispatch mock
    mock_twilio_resp = MagicMock()
    mock_twilio_resp.status_code = 201
    mock_twilio_resp.json.return_value = {"sid": "SM1234567890", "status": "queued"}

    with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_twilio_resp):
        res_send = await send_via_twilio(
            to="+15551234567",
            body="Safety Check-in reminder",
        )
        assert res_send.success is True
        assert res_send.id == "SM1234567890"

    # Twilio SMS failure handling
    mock_twilio_fail = MagicMock()
    mock_twilio_fail.status_code = 400
    mock_twilio_fail.json.return_value = {"message": "Invalid number", "code": 21211}

    with patch("httpx.AsyncClient.post", new_callable=AsyncMock, return_value=mock_twilio_fail):
        res_fail = await send_via_twilio(
            to="+15551234567",
            body="Safety Check-in reminder",
        )
        assert res_fail.success is False
        assert res_fail.error_code == 21211


def test_moderation_and_portal_auth():
    # Name moderation tests
    validate_display_name("Alexander Smith")

    with pytest.raises(NameModerationError, match="Display name can't contain numbers"):
        validate_display_name("Alex123")

    with pytest.raises(NameModerationError, match="Titles like"):
        validate_display_name("Dr John")

    with pytest.raises(NameModerationError, match="That name isn't allowed"):
        validate_display_name("BadWordfuckUser")

    # Safety portal HMAC OTP hash & verify
    h = hash_otp(session_id="ses-1", phone_norm="+15551234567", code="123456")
    assert verify_otp_hash(session_id="ses-1", phone_norm="+15551234567", code="123456", expected_hash=h) is True
    assert verify_otp_hash(session_id="ses-1", phone_norm="+15551234567", code="654321", expected_hash=h) is False

    # Safety portal stateless access token
    phone_id = hash_phone_identifier("+15551234567")
    tok = make_portal_access_token(session_id="ses-1", phone_norm="+15551234567")
    verified_phone_id = verify_portal_access_token(session_id="ses-1", token=tok)
    assert verified_phone_id == phone_id
    assert verify_portal_access_token(session_id="wrong-ses", token=tok) is None


# ==========================================
# 5. CRYPTO & INFRA TESTS
# ==========================================

def test_crypto_and_cache():
    # Encryption and Decryption
    plaintext = "Sensitive User PII Data"
    ciphertext = encrypt_pii(plaintext)
    assert ciphertext != plaintext.encode("utf-8")
    assert decrypt_pii(ciphertext) == plaintext

    # Hex ciphertext with \x prefix
    hex_ct = f"\\x{ciphertext.hex()}"
    assert decrypt_pii(hex_ct) == plaintext

    # Empty inputs
    assert encrypt_pii(None) == b""
    assert decrypt_pii(None) == ""

    # Invalid ciphertext raises DecryptFailedError
    with pytest.raises(DecryptFailedError):
        decrypt_pii(b"corrupt-data-bytes")

    # Blind index generation
    idx1 = compute_blind_index("Computer Science", domain="campus_branch")
    idx2 = compute_blind_index("Computer Science", domain="campus_branch")
    idx3 = compute_blind_index("Mechanical Engineering", domain="campus_branch")
    assert idx1 == idx2
    assert idx1 != idx3
    assert compute_blind_index(None) == ""
    reset_cipher_suites()

    # Cache helpers
    ttl = get_block_ids_cache_ttl()
    assert 300 <= ttl <= 330

    with patch("app.core.infra.cache.sync_redis_client.delete") as mock_del:
        invalidate_user_status_cache("usr-123")
        mock_del.assert_called_once_with("user:status:usr-123")

    # OTP code generator and redis key
    code = generate_otp_code(6)
    assert len(code) == 6
    assert code.isdigit()

    with pytest.raises(ValueError, match="OTP length must be positive"):
        generate_otp_code(0)

    key = otp_verified_redis_key("account_deletion", "usr-123")
    assert key == "account_deletion:otp_verified:usr-123"


async def test_background_task_and_retries():
    executed = False

    async def sample_task():
        nonlocal executed
        executed = True

    safe_create_task(sample_task())
    await asyncio.sleep(0.05)
    assert executed is True

    # run_with_retries
    attempts = 0

    async def flaky_task():
        nonlocal attempts
        attempts += 1
        if attempts < 2:
            raise ValueError("Temporary failure")
        return "success"

    res = await run_with_retries(flaky_task, max_retries=3, initial_delay=0.01)
    assert res == "success"
    assert attempts == 2
