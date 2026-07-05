# app/core/crypto.py
import hashlib
import hmac
from typing import Any

from cryptography.fernet import Fernet, InvalidToken, MultiFernet

from app.core.config import settings


class DecryptFailedError(Exception):
    """Raised when decryption of PII fails."""

    pass


_keys = [
    k.strip().encode()
    for k in settings.pii_encryption_key.split(",")
    if k.strip()
]
_cipher_suite = MultiFernet([Fernet(k) for k in _keys])


def _get_cipher_suite() -> MultiFernet:
    return _cipher_suite


def encrypt_pii(plaintext: str | None) -> bytes:
    """
    Encrypt a plaintext string into Fernet ciphertext bytes for BYTEA storage.
    """
    if plaintext is None or plaintext == "":
        return b""
    return _get_cipher_suite().encrypt(plaintext.encode("utf-8"))


def decrypt_pii(ciphertext: Any) -> str:
    """
    Decrypt BYTEA/PostgREST-returned ciphertext into plaintext.
    Supports raw bytes and PostgREST hex strings beginning with '\\x'.
    Raises DecryptFailedError if decryption fails.
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
    """
    Compute a deterministic HMAC-SHA256 blind index for equality lookups.
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
    """
    Encrypt a plaintext string and return a hex-prefixed BYTEA literal for storage.
    """
    enc = encrypt_pii(value)
    return f"\\x{enc.hex()}" if enc else None
