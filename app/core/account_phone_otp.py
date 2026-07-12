import hashlib
import hmac
import secrets

from app.core.config import settings

_OTP_LENGTH = 6
_OTP_TOKEN_CONTEXT = "account_phone_otp"  # noqa: S105 - domain-separation label, not a secret


def normalize_phone(raw: str) -> str:
    """Canonicalizes a phone number to a leading '+' plus its digits, so a
    number can always be looked up/stored the same way it was validated
    client-side (E.164). Unlike portal_auth.normalize_phone (which
    truncates to the last 10 digits for tolerant matching against a
    freeform trusted-contact input), this is for canonical account
    storage, so nothing is discarded.
    """
    digits = "".join(ch for ch in raw if ch.isdigit())
    return f"+{digits}"


def generate_otp_code() -> str:
    return "".join(secrets.choice("0123456789") for _ in range(_OTP_LENGTH))


def hash_otp(user_id: str, phone_norm: str, code: str) -> str:
    """The raw code is never stored (in Redis or anywhere else) - only this
    HMAC, so a Redis dump/leak doesn't hand out valid codes directly. Keyed
    by user_id rather than a session_id since this flow is for an
    already-authenticated Nexus account, not an anonymous portal visitor
    (see app/core/portal_auth.py for that variant).
    """
    key = settings.blind_index_key.encode()
    message = f"{_OTP_TOKEN_CONTEXT}:{user_id}:{phone_norm}:{code}".encode()
    return hmac.new(key, message, hashlib.sha256).hexdigest()


def verify_otp_hash(
    user_id: str,
    phone_norm: str,
    code: str,
    expected_hash: str,
) -> bool:
    return hmac.compare_digest(hash_otp(user_id, phone_norm, code), expected_hash)
