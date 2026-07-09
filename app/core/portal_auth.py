import base64
import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone

from app.core.config import settings

_OTP_LENGTH = 6
_OTP_TOKEN_CONTEXT = "safety_portal_otp"  # noqa: S105 - domain-separation label, not a secret
_ACCESS_TOKEN_CONTEXT = "safety_portal_access"  # noqa: S105 - domain-separation label, not a secret
_ACCESS_TOKEN_TTL_SECONDS = 30 * 60


def normalize_phone(raw: str) -> str:
    """Canonicalizes a phone number down to its last 10 digits so numbers
    typed with or without a country code / trunk prefix ("+91...",
    "091...", "9876543210") all compare equal - the same tolerant matching
    the mobile contact-entry form already does client-side, applied here so
    a trusted contact's freeform portal input can be checked against however
    the number was stored.
    """
    digits = "".join(ch for ch in raw if ch.isdigit())
    return digits[-10:] if len(digits) >= 10 else digits


def generate_otp_code() -> str:
    return "".join(secrets.choice("0123456789") for _ in range(_OTP_LENGTH))


def hash_otp(session_id: str, phone_norm: str, code: str) -> str:
    """The raw code is never stored (in Redis or anywhere else) - only this
    HMAC, so a Redis dump/leak doesn't hand out valid codes directly.
    """
    key = settings.blind_index_key.encode()
    message = f"{_OTP_TOKEN_CONTEXT}:{session_id}:{phone_norm}:{code}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def verify_otp_hash(
    session_id: str,
    phone_norm: str,
    code: str,
    expected_hash: str,
) -> bool:
    return hmac.compare_digest(hash_otp(session_id, phone_norm, code), expected_hash)


def _sign_access_payload(payload: str) -> str:
    key = settings.blind_index_key.encode()
    message = f"{_ACCESS_TOKEN_CONTEXT}:{payload}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def make_portal_access_token(session_id: str, phone_norm: str) -> str:
    """A self-contained, short-lived bearer credential for the trusted-
    contact portal - there's no Nexus account to hold a real session for, so
    this stands in for one. Payload and signature both travel in the token
    itself (no server-side session store needed):
    base64url(session_id:phone_norm:expiry) + "." + HMAC-SHA256(payload).
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
    """Returns the verified phone_norm the token was issued for, or None if
    the token is malformed, doesn't match this session, has expired, or
    fails signature verification.
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
