from unittest.mock import MagicMock, patch
from cryptography.fernet import Fernet

from app.core.security.crypto import (
    compute_blind_index,
    compute_blind_index_with_key,
    encrypt_to_hex,
    reset_cipher_suites,
)
from scripts.rotate_blind_indexes import (
    rotate_profiles_campus_branch_blind_index,
    rotate_safety_contacts_blind_index,
    rotate_users_mobile_blind_index,
)
from scripts.rotate_hmac_signing_key import main as hmac_tool_main


def test_rotate_users_mobile_blind_index() -> None:
    key_pii = Fernet.generate_key().decode()
    old_bi_key = "old_blind_index_key_111111111111"
    new_bi_key = "new_blind_index_key_222222222222"

    with patch("app.core.security.crypto.settings.pii_encryption_key", key_pii), patch(
        "app.core.security.crypto.settings.pii_contact_key", "",
    ):
        reset_cipher_suites()
        hex_mobile = encrypt_to_hex("+15551234567", category="contact")

    old_digest = compute_blind_index_with_key("+15551234567", domain="mobile", key=old_bi_key)

    mock_rows = [
        {"id": "user-1", "mobile": hex_mobile, "mobile_blind_index": old_digest},
        {"id": "user-2", "mobile": None, "mobile_blind_index": None},
    ]

    mock_client = MagicMock()
    mock_query = MagicMock()
    mock_client.table.return_value = mock_query
    mock_query.select.return_value = mock_query
    mock_query.range.side_effect = [
        MagicMock(execute=MagicMock(return_value=MagicMock(data=mock_rows))),
        MagicMock(execute=MagicMock(return_value=MagicMock(data=[]))),
    ]
    mock_query.update.return_value = mock_query
    mock_query.eq.return_value = mock_query

    dual_bi_setting = f"{new_bi_key},{old_bi_key}"
    with patch("app.core.security.crypto.settings.pii_encryption_key", key_pii), patch(
        "app.core.security.crypto.settings.pii_contact_key", "",
    ), patch("app.core.security.crypto.settings.blind_index_key", dual_bi_setting), patch(
        "scripts.rotate_blind_indexes.supabase_client", mock_client,
    ):
        reset_cipher_suites()
        res = rotate_users_mobile_blind_index(batch_size=10, dry_run=False)

        assert res.total_scanned == 2
        assert res.total_updated == 1  # only user-1 updated
        assert res.total_unchanged == 1  # user-2 has no mobile
        assert res.total_skipped == 0
        assert res.errors == 0

        # Verify new digest was written
        new_digest = compute_blind_index("+15551234567", domain="mobile")
        mock_query.update.assert_called_once_with({"mobile_blind_index": new_digest})


def test_rotate_profiles_campus_branch_blind_index() -> None:
    key_pii = Fernet.generate_key().decode()
    old_bi_key = "old_blind_index_key_111111111111"
    new_bi_key = "new_blind_index_key_222222222222"

    with patch("app.core.security.crypto.settings.pii_encryption_key", key_pii), patch(
        "app.core.security.crypto.settings.pii_profile_key", "",
    ):
        reset_cipher_suites()
        hex_branch = encrypt_to_hex("Electrical Engineering", category="profile")

    old_digest = compute_blind_index_with_key("Electrical Engineering", domain="campus_branch", key=old_bi_key)

    mock_rows = [
        {"id": "prof-1", "campus_branch": hex_branch, "campus_branch_blind_index": old_digest},
    ]

    mock_client = MagicMock()
    mock_query = MagicMock()
    mock_client.table.return_value = mock_query
    mock_query.select.return_value = mock_query
    mock_query.range.side_effect = [
        MagicMock(execute=MagicMock(return_value=MagicMock(data=mock_rows))),
        MagicMock(execute=MagicMock(return_value=MagicMock(data=[]))),
    ]
    mock_query.update.return_value = mock_query
    mock_query.eq.return_value = mock_query

    dual_bi_setting = f"{new_bi_key},{old_bi_key}"
    with patch("app.core.security.crypto.settings.pii_encryption_key", key_pii), patch(
        "app.core.security.crypto.settings.pii_profile_key", "",
    ), patch("app.core.security.crypto.settings.blind_index_key", dual_bi_setting), patch(
        "scripts.rotate_blind_indexes.supabase_client", mock_client,
    ):
        reset_cipher_suites()
        res = rotate_profiles_campus_branch_blind_index(batch_size=10, dry_run=False)

        assert res.total_scanned == 1
        assert res.total_updated == 1
        assert res.errors == 0

        new_digest = compute_blind_index("Electrical Engineering", domain="campus_branch")
        mock_query.update.assert_called_once_with({"campus_branch_blind_index": new_digest})


def test_rotate_safety_contacts_blind_index() -> None:
    key_pii = Fernet.generate_key().decode()
    old_bi_key = "old_blind_index_key_111111111111"
    new_bi_key = "new_blind_index_key_222222222222"

    with patch("app.core.security.crypto.settings.pii_encryption_key", key_pii), patch(
        "app.core.security.crypto.settings.pii_contact_key", "",
    ):
        reset_cipher_suites()
        hex_phone = encrypt_to_hex("+15559876543", category="contact")

    mock_contacts = [
        {"id": "c-1", "user_id": "u-1", "phone": hex_phone},
    ]

    mock_client = MagicMock()
    mock_query = MagicMock()
    mock_client.table.return_value = mock_query
    mock_query.select.return_value = mock_query
    mock_query.range.side_effect = [
        MagicMock(execute=MagicMock(return_value=MagicMock(data=mock_contacts))),
        MagicMock(execute=MagicMock(return_value=MagicMock(data=[]))),
    ]
    mock_query.update.return_value = mock_query
    mock_query.eq.return_value = mock_query
    mock_query.execute.return_value = MagicMock(data=[])

    dual_bi_setting = f"{new_bi_key},{old_bi_key}"
    with patch("app.core.security.crypto.settings.pii_encryption_key", key_pii), patch(
        "app.core.security.crypto.settings.pii_contact_key", "",
    ), patch("app.core.security.crypto.settings.blind_index_key", dual_bi_setting), patch(
        "scripts.rotate_blind_indexes.supabase_client", mock_client,
    ):
        reset_cipher_suites()
        res = rotate_safety_contacts_blind_index(batch_size=10, dry_run=False)

        assert res.total_scanned == 1
        assert res.total_updated == 1
        assert res.errors == 0


def test_rotate_hmac_signing_key_tool_execution() -> None:
    with patch("app.core.config.settings.hmac_signing_key", "sample_primary_key_32_bytes_long_12345"):
        code = hmac_tool_main()
        assert code == 0
