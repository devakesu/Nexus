from unittest.mock import MagicMock, patch
from cryptography.fernet import Fernet

from app.core.security.crypto import encrypt_to_hex, reset_cipher_suites
from scripts.rotate_pii_encryption import TableConfig, rotate_table_records


def test_rotate_table_records_successful_batch() -> None:
    key_old = Fernet.generate_key().decode()
    key_new = Fernet.generate_key().decode()

    # Step 1: Encrypt with old key
    with patch("app.core.security.crypto.settings.pii_encryption_key", key_old), patch(
        "app.core.security.crypto.settings.pii_profile_key", "",
    ):
        reset_cipher_suites()
        hex_name = encrypt_to_hex("Alice", category="profile")
        hex_bio = encrypt_to_hex("Hello World", category="profile")

    # Mock DB table
    mock_rows = [
        {"id": "user-1", "name": hex_name, "bio": hex_bio},
        {"id": "user-2", "name": None, "bio": hex_bio},
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
    mock_query.execute.return_value = MagicMock(data=[])

    config = TableConfig(
        table="profiles",
        pk="id",
        category="profile",
        fields=["name", "bio"],
    )

    # Step 2: Rotate with dual keys configured
    with patch("app.core.security.crypto.settings.pii_encryption_key", f"{key_new},{key_old}"), patch(
        "app.core.security.crypto.settings.pii_profile_key", "",
    ), patch("scripts.rotate_pii_encryption.supabase_client", mock_client):
        reset_cipher_suites()
        res = rotate_table_records(config=config, batch_size=10, dry_run=False)

        assert res.total_scanned == 2
        assert res.total_updated == 2
        assert res.total_skipped == 0
        assert res.errors == 0
        assert mock_query.update.call_count == 2


def test_rotate_table_records_row_atomicity_skips_corrupted_row() -> None:
    key_old = Fernet.generate_key().decode()
    key_new = Fernet.generate_key().decode()

    # Create one valid ciphertext and one corrupted field
    with patch("app.core.security.crypto.settings.pii_encryption_key", key_old), patch(
        "app.core.security.crypto.settings.pii_profile_key", "",
    ):
        reset_cipher_suites()
        hex_valid = encrypt_to_hex("Valid Plaintext", category="profile")

    mock_rows = [
        # Row 1: completely valid
        {"id": "row-valid", "name": hex_valid, "bio": hex_valid},
        # Row 2: corrupted 'bio' field -> entire row must be skipped (no partial write of 'name')
        {"id": "row-corrupt", "name": hex_valid, "bio": "\\x674141426164626164"},
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

    config = TableConfig(
        table="profiles",
        pk="id",
        category="profile",
        fields=["name", "bio"],
    )

    with patch("app.core.security.crypto.settings.pii_encryption_key", f"{key_new},{key_old}"), patch(
        "app.core.security.crypto.settings.pii_profile_key", "",
    ), patch("scripts.rotate_pii_encryption.supabase_client", mock_client):
        reset_cipher_suites()
        res = rotate_table_records(config=config, batch_size=10, dry_run=False)

        assert res.total_scanned == 2
        assert res.total_updated == 1  # only row-valid updated
        assert res.total_skipped == 1  # row-corrupt skipped
        assert res.errors == 0
        assert mock_query.update.call_count == 1
        # Confirm that the update call was for row-valid only
        mock_query.eq.assert_called_once_with("id", "row-valid")


def test_rotate_table_records_dry_run_mode() -> None:
    key_old = Fernet.generate_key().decode()
    key_new = Fernet.generate_key().decode()

    with patch("app.core.security.crypto.settings.pii_encryption_key", key_old), patch(
        "app.core.security.crypto.settings.pii_profile_key", "",
    ):
        reset_cipher_suites()
        hex_valid = encrypt_to_hex("Plaintext", category="profile")

    mock_rows = [
        {"id": "user-1", "name": hex_valid},
        {"id": "user-2", "name": hex_valid},
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

    config = TableConfig(
        table="profiles",
        pk="id",
        category="profile",
        fields=["name"],
    )

    with patch("app.core.security.crypto.settings.pii_encryption_key", f"{key_new},{key_old}"), patch(
        "app.core.security.crypto.settings.pii_profile_key", "",
    ), patch("scripts.rotate_pii_encryption.supabase_client", mock_client):
        reset_cipher_suites()
        res = rotate_table_records(config=config, batch_size=10, dry_run=True)

        assert res.total_scanned == 2
        assert res.total_updated == 2
        assert res.total_skipped == 0
        # In dry run, update is NOT called
        mock_query.update.assert_not_called()
