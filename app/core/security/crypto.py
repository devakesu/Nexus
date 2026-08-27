"""Field-level cryptography and deterministic blind index utilities.

Provides multi-key Fernet symmetric encryption and decryption for PII fields,
as well as HMAC-SHA256 blind indexing for secure, searchable database lookups.

Memory Lifetime & Zeroing Considerations (F-10):
CPython's standard `str` and `bytes` objects are immutable in heap memory and cannot be
explicitly zeroed out upon request completion. Decrypted PII values held as strings or dicts
remain resident until garbage collected. For high-security transient secrets (e.g. raw media keys),
callers should use mutable `bytearray` buffers and invoke `zero_sensitive_buffer()` immediately
after use.
"""

import base64
import hashlib
import hmac
from typing import Any, cast

from cryptography.exceptions import InvalidSignature
from cryptography.fernet import Fernet, InvalidToken, MultiFernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ed25519
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

from app.core.config import settings


class DecryptFailedError(Exception):
    """Raised when decryption of encrypted PII fails."""

    pass


_category_cipher_suites: dict[str, MultiFernet] = {}


def _derive_category_key(raw_key: bytes, category: str) -> bytes:
    """Derives a category-specific 32-byte Fernet key using HKDF-SHA256 (NIST SP 800-108 / RFC 5869)."""
    derived = HKDF(
        algorithm=hashes.SHA256(),
        length=32,
        salt=b"nexus-pii-v1",
        info=f"nexus:pii:{category}".encode(),
    ).derive(raw_key)
    return base64.urlsafe_b64encode(derived)


def _get_cipher_suite(category: str = "profile") -> MultiFernet:
    """Returns the MultiFernet cipher suite instance for the specified category.

    If a dedicated category key is configured in settings (e.g. pii_contact_key),
    it is used directly. Otherwise, category-isolated keys are derived from
    pii_encryption_key via HKDF-SHA256.
    """
    if category in _category_cipher_suites:
        return _category_cipher_suites[category]

    # Check for dedicated category-specific settings
    category_setting_map = {
        "profile": getattr(settings, "pii_profile_key", ""),
        "contact": getattr(settings, "pii_contact_key", ""),
        "media_escrow": getattr(settings, "pii_media_escrow_key", ""),
        "oauth": getattr(settings, "pii_oauth_token_key", ""),
        "chat": getattr(settings, "pii_chat_key", ""),
    }
    dedicated_key = category_setting_map.get(category, "").strip()

    if dedicated_key:
        keys = [k.strip().encode() for k in dedicated_key.split(",") if k.strip()]
    else:
        raw_keys = [
            k.strip().encode()
            for k in settings.pii_encryption_key.split(",")
            if k.strip()
        ]
        keys = [_derive_category_key(k, category) for k in raw_keys]

    suite = MultiFernet([Fernet(k) for k in keys])
    _category_cipher_suites[category] = suite
    return suite


def encrypt_pii(plaintext: str | None, category: str = "profile") -> bytes:
    """Encrypts a plaintext string into Fernet ciphertext bytes for the given category.

    Args:
        plaintext: Raw input string to be encrypted, or None.
        category: Cryptographic domain category (e.g., 'profile', 'contact', 'media_escrow', 'oauth', 'chat').

    Returns:
        bytes: Encrypted Fernet token bytes, or empty bytes if input is empty or None.
    """
    if plaintext is None or plaintext == "":
        return b""
    return _get_cipher_suite(category).encrypt(plaintext.encode("utf-8"))


def _normalize_ciphertext_bytes(ciphertext: Any) -> bytes:
    if isinstance(ciphertext, memoryview):
        return ciphertext.tobytes()
    if isinstance(ciphertext, str):
        if ciphertext.startswith("\\x"):
            try:
                return bytes.fromhex(ciphertext[2:])
            except ValueError as err:
                raise DecryptFailedError("Invalid hex-encoded ciphertext") from err
        return ciphertext.encode("utf-8")
    return cast(bytes, ciphertext)


def decrypt_pii(
    ciphertext: Any,
    category: str = "profile",
    ttl: int | None = None,
) -> str:
    """Decrypts raw or hex-encoded ciphertext into plaintext using the category cipher suite.

    Supports raw bytes, memoryviews, and PostgREST hex strings starting with '\\x'.

    TTL Considerations (F-14):
    Fernet tokens embed a 64-bit unsigned integer UTC creation timestamp.
    - Persistent PII (Default, ttl=None): Phone numbers, user profiles, safety contacts,
      and feedback tickets must not expire cryptographically; ttl is omitted (None).
    - Ephemeral Payloads (ttl in seconds): Short-lived session contexts, verification tokens,
      or transient auth nonces can specify a ttl to enforce cryptographic expiration at the
      Fernet layer. Tokens older than `ttl` seconds will raise `DecryptFailedError`.

    Args:
        ciphertext: Ciphertext as bytes, memoryview, or hex string.
        category: Cryptographic domain category (e.g., 'profile', 'contact', 'media_escrow', 'oauth', 'chat').
        ttl: Optional maximum token age in seconds (F-14).

    Returns:
        str: Decrypted UTF-8 plaintext string.

    Raises:
        DecryptFailedError: If key is invalid, token is expired (when ttl is passed), corrupted, or hex conversion fails.
    """
    if ciphertext is None or ciphertext == b"" or ciphertext == "":
        return ""

    raw_bytes = _normalize_ciphertext_bytes(ciphertext)

    try:
        suite = _get_cipher_suite(category)
        if ttl is not None:
            return suite.decrypt(raw_bytes, ttl=ttl).decode("utf-8")
        return suite.decrypt(raw_bytes).decode("utf-8")
    except InvalidToken as e:
        raise DecryptFailedError(f"Invalid Fernet token, expired TTL, or wrong key for category '{category}'") from e
    except Exception as e:
        raise DecryptFailedError("Decryption failed") from e


def reset_cipher_suites() -> None:
    """Clears the cached MultiFernet cipher suites.

    Useful when encryption keys in settings are changed dynamically (e.g. during testing
    or runtime configuration reloads).
    """
    _category_cipher_suites.clear()


def _get_blind_index_keys() -> list[bytes]:
    """Returns all configured blind index keys (first = active write key)."""
    raw = settings.blind_index_key.strip() if settings.blind_index_key else ""
    keys = [k.strip().encode("utf-8") for k in raw.split(",") if k.strip()]
    if not keys:
        raise RuntimeError("BLIND_INDEX_KEY must be configured for blind indexing.")
    return keys


def compute_blind_index(value: str | None, domain: str = "general") -> str:
    """Computes a deterministic HMAC-SHA256 blind index for exact match database lookups.

    Values are lowercased and stripped before hashing for case-insensitive matching.
    Includes a domain-separation label (e.g., 'mobile', 'safety_contact_phone', 'campus_branch')
    to prevent cross-table correlation and rainbow table attacks across different fields.
    Always uses the primary (first) key in BLIND_INDEX_KEY.

    Args:
        value: Input string to generate blind index for.
        domain: Field-specific domain separation label.

    Returns:
        str: Hex-encoded HMAC-SHA256 digest string, or empty string if input is empty/None.
    """
    if value is None or value == "":
        return ""

    keys = _get_blind_index_keys()
    normalized = value.strip().lower()
    msg = f"{domain}:{normalized}"
    return hmac.new(
        keys[0],
        msg.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def compute_blind_index_with_key(
    value: str | None,
    domain: str = "general",
    key: bytes | str | None = None,
) -> str:
    """Computes a deterministic blind index using a specified HMAC key.

    Useful during key rotation and migration to compute digests under specific keys.

    Args:
        value: Input string to generate blind index for.
        domain: Field-specific domain separation label.
        key: Specific HMAC key (bytes or str). If None, uses primary blind index key.

    Returns:
        str: Hex-encoded HMAC-SHA256 digest string, or empty string if input is empty/None.
    """
    if value is None or value == "":
        return ""

    if key is None:
        key_bytes = _get_blind_index_keys()[0]
    elif isinstance(key, str):
        key_bytes = key.strip().encode("utf-8")
    else:
        key_bytes = key

    normalized = value.strip().lower()
    msg = f"{domain}:{normalized}"
    return hmac.new(
        key_bytes,
        msg.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def encrypt_to_hex(value: str | None, category: str = "profile") -> str | None:
    """Encrypts plaintext string and formats as a PostgREST bytea hex string literal ('\\x...').

    Args:
        value: Plaintext string to encrypt.
        category: Cryptographic domain category.

    Returns:
        str | None: PostgREST hex string '\\x<hex>' or None if input is empty/None.
    """
    enc = encrypt_pii(value, category=category)
    return f"\\x{enc.hex()}" if enc else None


def _get_hmac_keys() -> list[bytes]:
    """Returns all configured HMAC signing keys parsed from comma-separated settings.hmac_signing_key."""
    raw = settings.hmac_signing_key.strip() if settings.hmac_signing_key else ""
    keys = [k.strip().encode("utf-8") for k in raw.split(",") if k.strip()]
    if not keys:
        raise RuntimeError(
            "HMAC_SIGNING_KEY must be configured for signing and verifying tokens.",
        )
    return keys


def get_hmac_signing_key() -> bytes:
    """Returns the primary dedicated HMAC signing key for token and OTP signatures.

    Enforces cryptographic domain separation (NIST SP 800-57): strictly requires
    `hmac_signing_key` and forbids fallback to `blind_index_key`. Always returns
    the first key in the comma-separated key list.
    """
    return _get_hmac_keys()[0]


def get_hmac_verify_keys() -> list[bytes]:
    """Returns all configured HMAC signing keys for token and OTP signature verification.

    Allows a graceful rotation window where tokens signed with previous keys
    remain valid during transition.
    """
    return _get_hmac_keys()


def verify_signed_prekey_signature(
    identity_public_key: bytes,
    signed_prekey_public: bytes,
    signature: bytes,
) -> bool:
    """Verifies that a signed prekey's public key was signed by the owner's identity key.

    Supports XEdDSA (Curve25519-to-Ed25519) as used by Signal Protocol and libsignal,
    as well as standard Ed25519 signatures.

    Args:
        identity_public_key: 32-byte or 33-byte (0x05-prefixed) identity public key.
        signed_prekey_public: 32-byte or 33-byte (0x05-prefixed) signed prekey public key.
        signature: 64-byte cryptographic signature.

    Returns:
        bool: True if signature is cryptographically valid, False otherwise.
    """
    if len(signature) != 64:
        return False

    mont_pub = (
        identity_public_key[1:]
        if (len(identity_public_key) == 33 and identity_public_key[0] == 0x05)
        else identity_public_key
    )
    if len(mont_pub) != 32:
        return False

    # 1. Attempt XEdDSA / Curve25519-to-Edwards conversion (standard in libsignal)
    try:
        p = 2**255 - 19
        mont_bytes = bytearray(mont_pub)
        mont_bytes[31] &= 0x7F
        u = int.from_bytes(mont_bytes, "little")
        if u < p:
            y = ((u - 1) * pow(u + 1, p - 2, p)) % p
            y_bytes = bytearray(y.to_bytes(32, "little"))
            sig_bytes = bytearray(signature)
            y_bytes[31] |= sig_bytes[63] & 0x80
            sig_bytes[63] &= 0x7F

            ed_pub = ed25519.Ed25519PublicKey.from_public_bytes(bytes(y_bytes))
            ed_pub.verify(bytes(sig_bytes), signed_prekey_public)
            return True
    except (InvalidSignature, ValueError):
        pass

    # 2. Fallback: direct Ed25519 verification over signed_prekey_public
    try:
        ed_pub = ed25519.Ed25519PublicKey.from_public_bytes(mont_pub)
        ed_pub.verify(signature, signed_prekey_public)
        return True
    except (InvalidSignature, ValueError):
        pass

    # 3. Fallback: direct Ed25519 verification over stripped 32-byte signed_prekey_public
    if len(signed_prekey_public) == 33 and signed_prekey_public[0] == 0x05:
        try:
            ed_pub = ed25519.Ed25519PublicKey.from_public_bytes(mont_pub)
            ed_pub.verify(signature, signed_prekey_public[1:])
            return True
        except (InvalidSignature, ValueError):
            pass

    return False


def zero_sensitive_buffer(buffer: bytearray) -> None:
    """Overwrites a mutable bytearray with zeros to minimize in-memory secret lifetime (F-10).

    Security Note (F-10): Python's standard `str` and `bytes` types are immutable and
    cannot be reliably wiped from heap memory prior to garbage collection.
    For short-lived sensitive material (such as AES-256 media keys or raw private key
    material), callers should prefer mutable `bytearray` buffers and invoke this function
    immediately after cryptographic operations.
    """
    for i in range(len(buffer)):
        buffer[i] = 0



