"""Field-level cryptography and deterministic blind index utilities.

Provides multi-key Fernet symmetric encryption and decryption for PII fields,
as well as HMAC-SHA256 blind indexing for secure, searchable database lookups.
"""

import hashlib
import hmac
from typing import Any

from cryptography.fernet import Fernet, InvalidToken, MultiFernet

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

