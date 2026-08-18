"""Phone number normalization and secure OTP token hashing for account verification.

Provides E.164 phone normalization, cryptographically secure OTP generation,
and HMAC-SHA256 hash calculation/verification for account phone verification flows.
"""

import hashlib
import hmac
import re

from fastapi import HTTPException, status

from app.core.infra.otp import generate_otp_code
from app.core.security.crypto import get_hmac_signing_key

__all__ = [
    "generate_otp_code",
    "hash_otp",
    "mask_phone",
    "normalize_phone",
    "verify_otp_hash",
]

_OTP_LENGTH = 6
_OTP_DOMAIN_LABEL = "account_phone_otp"  # domain-separation label
_E164_REGEX = re.compile(r"^\+[1-9][0-9]{7,14}$")


def normalize_phone(raw: str) -> str:
    """Canonicalizes a phone number string to E.164 format (+<digits>) and validates format.

    Args:
        raw: Raw phone number input string.

    Returns:
        str: Canonicalized E.164 phone string starting with '+'.

    Raises:
        HTTPException: If the normalized phone number does not conform to E.164 format (8-15 digits starting with +[1-9]).
    """
    if not raw or not str(raw).strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid phone number format. Phone number cannot be empty.",
        )
    cleaned = str(raw).strip()
    digits = "".join(ch for ch in cleaned if ch.isdigit())
    normalized = f"+{digits}"
    if not _E164_REGEX.match(normalized):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid phone number format. Must follow E.164 format with 8-15 digits (e.g. +1234567890).",
        )
    return normalized


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
    key = get_hmac_signing_key()
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


def mask_phone(phone: str | None) -> str | None:
    """Masks a phone number for privacy-safe API responses (e.g. +91******3210, +1*****2671).

    Args:
        phone: Raw or normalized phone number string.

    Returns:
        str | None: Masked phone string with middle digits obscured by asterisks, or None.
    """
    if not phone:
        return None
    phone_clean = str(phone).strip()
    if not phone_clean:
        return None
    if len(phone_clean) <= 6:
        return f"***{phone_clean[-2:]}" if len(phone_clean) >= 2 else "***"

    if phone_clean.startswith("+1") and len(phone_clean) <= 12:
        prefix_len = 2
    elif phone_clean.startswith("+"):
        prefix_len = 3
    else:
        prefix_len = 2

    prefix = phone_clean[:prefix_len]
    suffix = phone_clean[-4:]
    masked_middle = "*" * max(len(phone_clean) - prefix_len - 4, 3)
    return f"{prefix}{masked_middle}{suffix}"

