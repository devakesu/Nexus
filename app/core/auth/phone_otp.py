"""Phone number normalization and secure OTP token hashing for account verification.

Provides E.164 phone normalization, cryptographically secure OTP generation,
and HMAC-SHA256 hash calculation/verification for account phone verification flows.
"""

import hashlib
import hmac
import secrets

from app.core.config import settings

_OTP_LENGTH = 6
_OTP_DOMAIN_LABEL = "account_phone_otp"  # domain-separation label


def normalize_phone(raw: str) -> str:
    """Canonicalizes a phone number string to E.164 format (+<digits>).

    Args:
        raw: Raw phone number input string.

    Returns:
        str: Canonicalized E.164 phone string starting with '+'.
    """
    digits = "".join(ch for ch in raw if ch.isdigit())
    return f"+{digits}"


def generate_otp_code() -> str:
    """Generates a random _OTP_LENGTH-digit numeric OTP code.

    Returns:
        str: _OTP_LENGTH-digit numeric OTP string.
    """
    return "".join(secrets.choice("0123456789") for _ in range(_OTP_LENGTH))


def hash_otp(user_id: str, phone_norm: str, code: str) -> str:
    """Calculates an HMAC-SHA256 digest of an OTP code bound to user ID and normalized phone.

    Prevents raw OTP codes from being exposed in memory or cache stores.

    Args:
        user_id: User identifier string.
        phone_norm: E.164 normalized phone string.
        code: OTP code string.

    Returns:
        str: Hex-encoded HMAC-SHA256 digest string.
    """
    key = (settings.hmac_signing_key or settings.blind_index_key).encode()
    message = f"{_OTP_DOMAIN_LABEL}:{user_id}:{phone_norm}:{code}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def verify_otp_hash(
    user_id: str,
    phone_norm: str,
    code: str,
    expected_hash: str,
) -> bool:
    """Verifies an OTP code against an expected HMAC-SHA256 digest using constant-time comparison.

    Args:
        user_id: User identifier string.
        phone_norm: E.164 normalized phone string.
        code: Submitted OTP code string.
        expected_hash: Expected HMAC-SHA256 hex digest string.

    Returns:
        bool: True if code matches digest, False otherwise.
    """
    return hmac.compare_digest(hash_otp(user_id, phone_norm, code), expected_hash)

