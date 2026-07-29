"""Safety portal authentication and temporary access token utilities.

Handles phone number normalization for trusted contacts, OTP token generation,
HMAC hashing, and signed stateless access token creation and verification.
"""

import base64
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

from app.core.auth.phone_otp import normalize_phone as normalize_phone
from app.core.config import settings

_OTP_LENGTH = 6
_OTP_DOMAIN_LABEL = "safety_portal_otp"  # domain-separation label
_ACCESS_DOMAIN_LABEL = "safety_portal_access"  # domain-separation label
_ACCESS_TOKEN_TTL_SECONDS = 30 * 60


def generate_otp_code() -> str:
    """Generates a random _OTP_LENGTH-digit numeric OTP string.

    Returns:
        str: _OTP_LENGTH-digit numeric OTP code.
    """
    return "".join(secrets.choice("0123456789") for _ in range(_OTP_LENGTH))


def hash_otp(session_id: str, phone_norm: str, code: str) -> str:
    """Calculates an HMAC-SHA256 digest for a safety portal OTP code.

    Args:
        session_id: Unique safety session identifier.
        phone_norm: Normalized contact phone number.
        code: OTP code string.

    Returns:
        str: Hex-encoded HMAC-SHA256 digest string.
    """
    key = (settings.hmac_signing_key or settings.blind_index_key).encode()
    message = f"{_OTP_DOMAIN_LABEL}:{session_id}:{phone_norm}:{code}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def verify_otp_hash(
    session_id: str,
    phone_norm: str,
    code: str,
    expected_hash: str,
) -> bool:
    """Verifies a safety portal OTP code against an expected HMAC digest.

    Args:
        session_id: Safety session identifier.
        phone_norm: Normalized phone number string.
        code: Submitted OTP code.
        expected_hash: Expected HMAC-SHA256 hex digest string.

    Returns:
        bool: True if code matches digest, False otherwise.
    """
    return hmac.compare_digest(hash_otp(session_id, phone_norm, code), expected_hash)


def _sign_access_payload(payload: str) -> str:
    """Signs an access token payload using HMAC-SHA256.

    Args:
        payload: Access token payload string.

    Returns:
        str: Hex-encoded HMAC signature.
    """
    key = (settings.hmac_signing_key or settings.blind_index_key).encode()
    message = f"{_ACCESS_DOMAIN_LABEL}:{payload}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def make_portal_access_token(session_id: str, phone_norm: str) -> str:
    """Generates a signed, stateless access token for trusted portal access.

    Args:
        session_id: Active safety session identifier.
        phone_norm: Normalized phone string for authorized contact.

    Returns:
        str: Formatted token string (base64_payload.signature).
    """
    expires_at = int(
        (
            datetime.now(timezone.utc) + timedelta(seconds=_ACCESS_TOKEN_TTL_SECONDS)
        ).timestamp(),
    )
    payload = f"{session_id}:{phone_norm}:{expires_at}"
    payload_b64 = base64.urlsafe_b64encode(payload.encode()).decode().rstrip("=")
    signature = _sign_access_payload(payload)
    return f"{payload_b64}.{signature}"


def verify_portal_access_token(session_id: str, token: str) -> str | None:
    """Verifies and decodes a safety portal access token.

    Args:
        session_id: Active safety session identifier.
        token: Bearer access token string.

    Returns:
        str | None: Verified phone number, or None if token invalid/expired.
    """
    try:
        payload_b64, signature = token.split(".", 1)
        padding = "=" * (-len(payload_b64) % 4)
        payload = base64.urlsafe_b64decode(payload_b64 + padding).decode()
        token_session_id, phone_norm, expires_at_raw = payload.split(":", 2)
        expires_at = int(expires_at_raw)
    except (ValueError, UnicodeDecodeError):
        return None

    if token_session_id != session_id:
        return None
    if not hmac.compare_digest(_sign_access_payload(payload), signature):
        return None
    if datetime.now(timezone.utc).timestamp() >= expires_at:
        return None
    return phone_norm

