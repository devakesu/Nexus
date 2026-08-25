"""Unit tests for F-02 (PII Category Separation) and F-03 (Blind Index Domain Separation)."""

import pytest
from app.core.security.crypto import (
    DecryptFailedError,
    compute_blind_index,
    decrypt_pii,
    encrypt_pii,
    encrypt_to_hex,
    _derive_category_key,
)


def test_pii_category_isolation() -> None:
    """Test that ciphertext encrypted under one category cannot be decrypted by another category."""
    plaintext = "sensitive-user-information"

    categories = ["profile", "contact", "media_escrow", "oauth", "chat"]

    for cat in categories:
        encrypted = encrypt_pii(plaintext, category=cat)
        assert encrypted != b""
        # Can decrypt within the same category
        decrypted = decrypt_pii(encrypted, category=cat)
        assert decrypted == plaintext

        # Cannot decrypt using any different category
        for other_cat in categories:
            if other_cat != cat:
                with pytest.raises(DecryptFailedError):
                    decrypt_pii(encrypted, category=other_cat)


def test_encrypt_to_hex_with_category() -> None:
    """Test encrypt_to_hex and decrypt_pii roundtrip with categories."""
    phone = "+15551234567"
    hex_contact = encrypt_to_hex(phone, category="contact")
    assert hex_contact is not None
    assert hex_contact.startswith("\\x")

    # Correct category decrypts
    assert decrypt_pii(hex_contact, category="contact") == phone

    # Wrong category fails
    with pytest.raises(DecryptFailedError):
        decrypt_pii(hex_contact, category="profile")


def test_blind_index_domain_separation() -> None:
    """Test that HMAC blind indexes for identical values differ across domains (F-03)."""
    val = "+15551234567"

    mobile_bi = compute_blind_index(val, domain="mobile")
    safety_bi = compute_blind_index(val, domain="safety_contact_phone")
    general_bi = compute_blind_index(val, domain="general")

    assert mobile_bi != ""
    assert safety_bi != ""
    assert general_bi != ""

    # All three must be cryptographically distinct to prevent cross-table correlation
    assert mobile_bi != safety_bi
    assert mobile_bi != general_bi
    assert safety_bi != general_bi


def test_blind_index_fields_differ_for_same_value() -> None:
    """Low cardinality values (e.g. 'yes', 'no') must not produce identical digests across fields."""
    value = "yes"
    drinking_bi = compute_blind_index(value, domain="drinking")
    smoking_bi = compute_blind_index(value, domain="smoking")
    children_bi = compute_blind_index(value, domain="children_plans")
    religious_bi = compute_blind_index(value, domain="religious_beliefs")

    digests = {drinking_bi, smoking_bi, children_bi, religious_bi}
    assert len(digests) == 4, "Each field domain must produce a unique blind index"


def test_blind_index_normalization() -> None:
    """Verify stripping and lowercasing within a domain."""
    bi1 = compute_blind_index("  Computer Science  ", domain="campus_branch")
    bi2 = compute_blind_index("computer science", domain="campus_branch")
    assert bi1 == bi2
    assert bi1 != ""


def test_hkdf_derivation_determinism() -> None:
    """Verify HKDF derivation is deterministic and produces distinct keys per category."""
    raw_key = b"01234567890123456789012345678901"
    key_profile = _derive_category_key(raw_key, "profile")
    key_contact = _derive_category_key(raw_key, "contact")
    key_profile_again = _derive_category_key(raw_key, "profile")

    assert key_profile == key_profile_again
    assert key_profile != key_contact


def test_zero_sensitive_buffer() -> None:
    from app.core.security.crypto import zero_sensitive_buffer

    buf = bytearray(b"super_secret_aes_media_key_bytes")
    assert len(buf) > 0
    assert any(b != 0 for b in buf)

    zero_sensitive_buffer(buf)
    assert all(b == 0 for b in buf)
    assert len(buf) == 32


def test_decrypt_pii_ttl_support() -> None:
    import time
    from cryptography.fernet import Fernet
    from app.core.config import settings
    from app.core.security.crypto import (
        DecryptFailedError,
        _derive_category_key,
        decrypt_pii,
        encrypt_pii,
    )

    # Encrypt a transient token
    enc = encrypt_pii("temporary-verification-token", category="contact")

    # Decrypt with valid large TTL
    dec = decrypt_pii(enc, category="contact", ttl=60)
    assert dec == "temporary-verification-token"

    # Decrypt without TTL (persistent PII default)
    dec_no_ttl = decrypt_pii(enc, category="contact", ttl=None)
    assert dec_no_ttl == "temporary-verification-token"

    # Create a token timestamped in the past
    active_key = settings.pii_encryption_key.split(",")[0].strip().encode()
    fernet_key = _derive_category_key(active_key, "contact")
    past_time = int(time.time()) - 100
    expired_token = Fernet(fernet_key).encrypt_at_time(b"expired-token-data", past_time)

    # Decrypting an old token with a 30-second TTL must raise DecryptFailedError
    with pytest.raises(DecryptFailedError) as exc_info:
        decrypt_pii(expired_token, category="contact", ttl=30)
    assert "expired TTL" in str(exc_info.value) or "Invalid Fernet token" in str(exc_info.value)
