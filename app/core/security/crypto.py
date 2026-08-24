"""Field-level cryptography and deterministic blind index utilities.

Provides multi-key Fernet symmetric encryption and decryption for PII fields,
as well as HMAC-SHA256 blind indexing for secure, searchable database lookups.
"""

import hashlib
import hmac
from typing import Any

from cryptography.exceptions import InvalidSignature
from cryptography.fernet import Fernet, InvalidToken, MultiFernet
from cryptography.hazmat.primitives.asymmetric import ed25519

from app.core.config import settings


class DecryptFailedError(Exception):
    """Raised when decryption of encrypted PII fails."""

    pass


_keys = [
    k.strip().encode()
    for k in settings.pii_encryption_key.split(",")
    if k.strip()
]
_cipher_suite = MultiFernet([Fernet(k) for k in _keys])


def _get_cipher_suite() -> MultiFernet:
    """Returns the globally configured MultiFernet cipher suite instance."""
    return _cipher_suite


def encrypt_pii(plaintext: str | None) -> bytes:
    """Encrypts a plaintext string into Fernet ciphertext bytes.

    Args:
        plaintext: Raw input string to be encrypted, or None.

    Returns:
        bytes: Encrypted Fernet token bytes, or empty bytes if input is empty or None.
    """
    if plaintext is None or plaintext == "":
        return b""
    return _get_cipher_suite().encrypt(plaintext.encode("utf-8"))


def decrypt_pii(ciphertext: Any) -> str:
    """Decrypts raw or hex-encoded ciphertext into plaintext.

    Supports raw bytes, memoryviews, and PostgREST hex strings starting with '\\x'.

    Args:
        ciphertext: Ciphertext as bytes, memoryview, or hex string.

    Returns:
        str: Decrypted UTF-8 plaintext string.

    Raises:
        DecryptFailedError: If key is invalid, token is corrupted, or hex conversion fails.
    """
    if ciphertext is None or ciphertext == b"" or ciphertext == "":
        return ""

    if isinstance(ciphertext, memoryview):
        ciphertext = ciphertext.tobytes()

    if isinstance(ciphertext, str):
        if ciphertext.startswith("\\x"):
            try:
                ciphertext = bytes.fromhex(ciphertext[2:])
            except ValueError as err:
                raise DecryptFailedError("Invalid hex-encoded ciphertext") from err
        else:
            ciphertext = ciphertext.encode("utf-8")

    try:
        return _get_cipher_suite().decrypt(ciphertext).decode("utf-8")
    except InvalidToken as e:
        raise DecryptFailedError("Invalid Fernet token or wrong key") from e
    except Exception as e:
        raise DecryptFailedError("Decryption failed") from e


def compute_blind_index(value: str | None) -> str:
    """Computes a deterministic HMAC-SHA256 blind index for exact match database lookups.

    Values are lowercased and stripped before hashing for case-insensitive matching.

    Args:
        value: Input string to generate blind index for.

    Returns:
        str: Hex-encoded HMAC-SHA256 digest string, or empty string if input is empty/None.
    """
    if value is None or value == "":
        return ""

    normalized = value.strip().lower()
    return hmac.new(
        settings.blind_index_key.encode("utf-8"),
        normalized.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()


def encrypt_to_hex(value: str | None) -> str | None:
    """Encrypts plaintext string and formats as a PostgREST bytea hex string literal ('\\x...').

    Args:
        value: Plaintext string to encrypt.

    Returns:
        str | None: PostgREST hex string '\\x<hex>' or None if input is empty/None.
    """
    enc = encrypt_pii(value)
    return f"\\x{enc.hex()}" if enc else None


def get_hmac_signing_key() -> bytes:
    """Returns the dedicated HMAC signing key for token and OTP signatures.

    Enforces cryptographic domain separation (NIST SP 800-57): strictly requires
    `hmac_signing_key` and forbids fallback to `blind_index_key`.
    """
    key = settings.hmac_signing_key.strip() if settings.hmac_signing_key else ""
    if not key:
        raise RuntimeError(
            "HMAC_SIGNING_KEY must be configured for signing and verifying tokens.",
        )
    return key.encode("utf-8")


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



