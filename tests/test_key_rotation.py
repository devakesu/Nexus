from unittest.mock import patch

import pytest
from cryptography.fernet import Fernet

from app.core.auth.phone_otp import hash_otp as phone_hash_otp
from app.core.auth.phone_otp import verify_otp_hash as phone_verify_otp_hash
from app.core.security.crypto import (
    DecryptFailedError,
    compute_blind_index,
    compute_blind_index_with_key,
    decrypt_pii,
    encrypt_pii,
    encrypt_to_hex,
    get_hmac_signing_key,
    get_hmac_verify_keys,
    reset_cipher_suites,
)
from app.core.security.portal_auth import (
    hash_otp as portal_hash_otp,
)
from app.core.security.portal_auth import (
    make_portal_access_token,
    verify_portal_access_token,
)
from app.core.security.portal_auth import (
    verify_otp_hash as portal_verify_otp_hash,
)
from app.core.utils.sms import (
    make_contact_portal_token,
    make_escalation_cancel_token,
    verify_contact_portal_token,
    verify_escalation_cancel_token,
)


def test_blind_index_multi_key_behavior() -> None:
    key_primary = "primary_blind_key_111111111111111"
    key_secondary = "secondary_blind_key_222222222222"
    multi_key_setting = f"{key_primary},{key_secondary}"

    with patch("app.core.security.crypto.settings.blind_index_key", multi_key_setting):
        digest_primary = compute_blind_index("Computer Science", domain="campus_branch")
        digest_secondary = compute_blind_index_with_key(
            "Computer Science", domain="campus_branch", key=key_secondary.encode(),
        )

        assert digest_primary != digest_secondary
        assert digest_primary == compute_blind_index_with_key(
            "Computer Science", domain="campus_branch", key=key_primary.encode(),
        )


def test_hmac_signing_key_multi_key_verification() -> None:
    key_old = "old_hmac_signing_key_1111111111111"
    key_new = "new_hmac_signing_key_2222222222222"

    # Step 1: Sign with old key
    with patch("app.core.security.crypto.settings.hmac_signing_key", key_old):
        old_otp_hash = phone_hash_otp("user-1", "+15551234567", "123456")
        old_portal_otp_hash = portal_hash_otp("sess-1", "+15551234567", "654321")
        old_portal_token = make_portal_access_token("sess-1", "+15551234567")
        old_cancel_token = make_escalation_cancel_token("sess-1", 2)
        old_contact_token = make_contact_portal_token("contact-1")

    # Step 2: Configure dual key window: key_new (primary), key_old (secondary)
    dual_key_setting = f"{key_new},{key_old}"
    with patch("app.core.security.crypto.settings.hmac_signing_key", dual_key_setting):
        assert get_hmac_signing_key() == key_new.encode()
        assert get_hmac_verify_keys() == [key_new.encode(), key_old.encode()]

        # Old tokens MUST still verify under the dual-key verify window
        assert phone_verify_otp_hash("user-1", "+15551234567", "123456", old_otp_hash) is True
        assert portal_verify_otp_hash("sess-1", "+15551234567", "654321", old_portal_otp_hash) is True
        assert verify_portal_access_token("sess-1", old_portal_token) is not None
        assert verify_escalation_cancel_token("sess-1", old_cancel_token) == 2
        assert verify_contact_portal_token(old_contact_token) == "contact-1"

        # Newly generated tokens are signed with key_new
        new_otp_hash = phone_hash_otp("user-1", "+15551234567", "123456")
        assert phone_verify_otp_hash("user-1", "+15551234567", "123456", new_otp_hash) is True

    # Step 3: Remove old key completely
    with patch("app.core.security.crypto.settings.hmac_signing_key", key_new):
        # Tokens from new key still verify
        assert phone_verify_otp_hash("user-1", "+15551234567", "123456", new_otp_hash) is True
        # Tokens from old key now fail
        assert phone_verify_otp_hash("user-1", "+15551234567", "123456", old_otp_hash) is False
        assert portal_verify_otp_hash("sess-1", "+15551234567", "654321", old_portal_otp_hash) is False
        assert verify_portal_access_token("sess-1", old_portal_token) is None
        assert verify_escalation_cancel_token("sess-1", old_cancel_token) is None
        assert verify_contact_portal_token(old_contact_token) is None


def test_pii_encryption_key_rotation_lifecycle() -> None:
    key_a = Fernet.generate_key().decode()
    key_b = Fernet.generate_key().decode()

    # Stage 1: Key A only
    with patch("app.core.security.crypto.settings.pii_encryption_key", key_a), patch(
        "app.core.security.crypto.settings.pii_profile_key", "",
    ):
        reset_cipher_suites()
        plaintext = "Confidential Profile Bio"
        ciphertext_a = encrypt_pii(plaintext, category="profile")
        hex_a = encrypt_to_hex(plaintext, category="profile")

        assert decrypt_pii(ciphertext_a, category="profile") == plaintext
        assert decrypt_pii(hex_a, category="profile") == plaintext

    # Stage 2: Key B added as leading key (Key B, Key A)
    with patch("app.core.security.crypto.settings.pii_encryption_key", f"{key_b},{key_a}"), patch(
        "app.core.security.crypto.settings.pii_profile_key", "",
    ):
        reset_cipher_suites()
        # Old ciphertext_a is still decryptable
        assert decrypt_pii(ciphertext_a, category="profile") == plaintext
        assert decrypt_pii(hex_a, category="profile") == plaintext

        # Re-encrypt under leading Key B
        decrypted_plain = decrypt_pii(hex_a, category="profile")
        hex_b = encrypt_to_hex(decrypted_plain, category="profile")
        assert hex_b is not None

    # Stage 3: Key A removed, Key B is now sole key
    with patch("app.core.security.crypto.settings.pii_encryption_key", key_b), patch(
        "app.core.security.crypto.settings.pii_profile_key", "",
    ):
        reset_cipher_suites()
        # Old ciphertext_a fails to decrypt
        with pytest.raises(DecryptFailedError):
            decrypt_pii(hex_a, category="profile")

        # Re-encrypted ciphertext under Key B decrypts perfectly
        assert decrypt_pii(hex_b, category="profile") == plaintext
