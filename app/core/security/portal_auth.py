"""Safety portal authentication and temporary access token utilities.

Handles phone number normalization for trusted contacts, OTP token generation,
HMAC hashing, and signed stateless access token creation and verification.
"""

import base64
import hashlib
import hmac
from datetime import datetime, timedelta, timezone

from app.core.auth.phone_otp import normalize_phone as normalize_phone
from app.core.infra.otp import generate_otp_code as generate_otp_code
from app.core.security.crypto import get_hmac_signing_key, get_hmac_verify_keys

_OTP_LENGTH = 6
_OTP_DOMAIN_LABEL = "safety_portal_otp"  # domain-separation label
_ACCESS_DOMAIN_LABEL = "safety_portal_access"  # domain-separation label
_ACCESS_TOKEN_TTL_SECONDS = 30 * 60


def _get_signing_key() -> bytes:
    """Returns the dedicated primary HMAC signing key for safety portal operations.

    Enforces cryptographic domain separation (NIST SP 800-57): strictly uses
    `hmac_signing_key` and never falls back to `blind_index_key`.
    """
    try:
        return get_hmac_signing_key()
    except RuntimeError as err:
        raise RuntimeError(
            "HMAC_SIGNING_KEY must be configured for portal authentication.",
        ) from err


def _get_verify_keys() -> list[bytes]:
    """Returns all configured HMAC signing keys for safety portal token verification."""
    try:
        return get_hmac_verify_keys()
    except RuntimeError as err:
        raise RuntimeError(
            "HMAC_SIGNING_KEY must be configured for portal authentication.",
        ) from err


def hash_otp(session_id: str, phone_norm: str, code: str) -> str:
    """Calculates an HMAC-SHA256 digest for a safety portal OTP code.

    Args:
        session_id: Unique safety session identifier.
        phone_norm: Normalized contact phone number.
        code: OTP code string.

    Returns:
        str: Hex-encoded HMAC-SHA256 digest string.
    """
    key = _get_signing_key()
    message = f"{_OTP_DOMAIN_LABEL}:{session_id}:{phone_norm}:{code}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def verify_otp_hash(
    session_id: str,
    phone_norm: str,
    code: str,
    expected_hash: str,
) -> bool:
    """Verifies a safety portal OTP code against an expected HMAC digest across all verification keys.

    Args:
        session_id: Safety session identifier.
        phone_norm: Normalized phone number string.
        code: Submitted OTP code.
        expected_hash: Expected HMAC-SHA256 hex digest string.

    Returns:
        bool: True if code matches digest, False otherwise.
    """
    message = f"{_OTP_DOMAIN_LABEL}:{session_id}:{phone_norm}:{code}".encode()
    for key in _get_verify_keys():
        candidate_hash = hmac.new(key, message, hashlib.sha256).hexdigest()
        if hmac.compare_digest(candidate_hash, expected_hash):
            return True
    return False


def _sign_access_payload(payload: str) -> str:
    """Signs an access token payload using HMAC-SHA256 with the primary signing key.

    Args:
        payload: Access token payload string.
         peculiarities: Uses dedicated HMAC signing key with domain separation.

    Returns:
        str: Hex-encoded HMAC signature.
    """
    key = _get_signing_key()
    message = f"{_ACCESS_DOMAIN_LABEL}:{payload}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def hash_phone_identifier(phone_norm: str) -> str:
    """Computes a one-way HMAC digest of the normalized phone number
    to prevent embedding plaintext phone numbers in token payloads.
    """
    key = _get_signing_key()
    return hmac.new(key, f"portal_phone_id:{phone_norm}".encode(), hashlib.sha256).hexdigest()[:16]


_hash_phone_identifier = hash_phone_identifier



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
    phone_id = _hash_phone_identifier(phone_norm)
    payload = f"{session_id}:{phone_id}:{expires_at}"
    payload_b64 = base64.urlsafe_b64encode(payload.encode()).decode().rstrip("=")
    signature = _sign_access_payload(payload)
    return f"{payload_b64}.{signature}"


def verify_portal_access_token(session_id: str, token: str) -> str | None:
    """Verifies and decodes a safety portal access token across all verification keys.

    Args:
        session_id: Active safety session identifier.
        token: Bearer access token string.

    Returns:
        str | None: Verified phone identifier hash, or None if token invalid/expired.
    """
    try:
        payload_b64, signature = token.split(".", 1)
        padding = "=" * (-len(payload_b64) % 4)
        payload = base64.urlsafe_b64decode(payload_b64 + padding).decode()
        token_session_id, phone_id, expires_at_raw = payload.split(":", 2)
        expires_at = int(expires_at_raw)
    except (ValueError, UnicodeDecodeError):
        return None

    if token_session_id != session_id:
        return None

    message = f"{_ACCESS_DOMAIN_LABEL}:{payload}".encode()
    valid_sig = False
    for key in _get_verify_keys():
        candidate_sig = hmac.new(key, message, hashlib.sha256).hexdigest()
        if hmac.compare_digest(candidate_sig, signature):
            valid_sig = True
            break

    if not valid_sig:
        return None

    if datetime.now(timezone.utc).timestamp() >= expires_at:
        return None
    return phone_id

