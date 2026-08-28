import sys
from unittest.mock import MagicMock, patch

from cryptography.fernet import Fernet

from app.core.security.crypto import (
    DecryptFailedError,
    encrypt_to_hex,
    reset_cipher_suites,
)
from scripts.rotate_pii_encryption import (
    PII_TABLE_CONFIGS,
    TableConfig,
    init_sentry_if_configured,
    rotate_table_records,
)
from scripts.rotate_pii_encryption import (
    main as pii_main,
)


def test_init_sentry_if_configured() -> None:
    with (
        patch(
            "scripts.rotate_pii_encryption.settings.sentry_backend_dsn",
            "https://key@sentry.io/123",
        ),
        patch(
            "sentry_sdk.init",
        ) as mock_sentry_init,
    ):
        init_sentry_if_configured()
        mock_sentry_init.assert_called_once()

    with patch("scripts.rotate_pii_encryption.settings.sentry_backend_dsn", ""):
        init_sentry_if_configured()


def test_rotate_table_records_successful_batch() -> None:
    key_old = Fernet.generate_key().decode()
    key_new = Fernet.generate_key().decode()

    # Encrypt with old key
    with (
        patch("app.core.security.crypto.settings.pii_encryption_key", key_old),
        patch(
            "app.core.security.crypto.settings.pii_profile_key",
            "",
        ),
    ):
        reset_cipher_suites()
        hex_name = encrypt_to_hex("Alice", category="profile")
        hex_bio = encrypt_to_hex("Hello World", category="profile")

    mock_rows = [
        {"id": "user-1", "name": hex_name, "bio": hex_bio},
        {"id": "user-2", "name": None, "bio": hex_bio},
        {"id": "user-3", "name": "", "bio": b""},  # empty fields -> unchanged
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

    with (
        patch(
            "app.core.security.crypto.settings.pii_encryption_key",
            f"{key_new},{key_old}",
        ),
        patch(
            "app.core.security.crypto.settings.pii_profile_key",
            "",
        ),
        patch("scripts.rotate_pii_encryption.supabase_client", mock_client),
    ):
        reset_cipher_suites()
        res = rotate_table_records(config=config, batch_size=10, dry_run=False)

        assert res.total_scanned == 3
        assert res.total_updated == 2
        assert res.total_unchanged == 1
        assert res.total_skipped == 0
        assert res.errors == 0
        assert mock_query.update.call_count == 2


def test_rotate_table_records_errors_and_branches() -> None:
    config = TableConfig(
        table="profiles",
        pk="id",
        category="profile",
        fields=["name"],
    )

    # 1. DB select error
    mock_client_err = MagicMock()
    mock_client_err.table.return_value.select.return_value.range.return_value.execute.side_effect = Exception(
        "DB Error",
    )
    with (
        patch("scripts.rotate_pii_encryption.supabase_client", mock_client_err),
        patch(
            "scripts.rotate_pii_encryption.settings.sentry_backend_dsn",
            "https://key@sentry.io/1",
        ),
        patch("sentry_sdk.capture_exception") as mock_sentry,
    ):
        res = rotate_table_records(config=config, batch_size=10)
        assert res.errors == 1
        mock_sentry.assert_called_once()

    # 2. DecryptFailedError, generic Exception during decrypt, and DB update error
    mock_rows = [
        {"id": "r-dec-fail", "name": "\\x1234"},
        {"id": "r-gen-fail", "name": "\\x5678"},
        {"id": "r-upd-fail", "name": "\\x9999"},
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

    with (
        patch(
            "scripts.rotate_pii_encryption.decrypt_pii",
            side_effect=[
                DecryptFailedError("decryption failed"),
                Exception("generic unexpected fail"),
                "Valid Plaintext",
            ],
        ),
        patch("scripts.rotate_pii_encryption.supabase_client", mock_client),
        patch(
            "scripts.rotate_pii_encryption.settings.sentry_backend_dsn",
            "https://key@sentry.io/1",
        ),
        patch("sentry_sdk.capture_message"),
        patch("sentry_sdk.capture_exception"),
    ):
        mock_query.execute.side_effect = Exception("DB update error")
        res = rotate_table_records(config=config, batch_size=10, dry_run=False)

        assert res.total_scanned == 3
        assert res.total_skipped == 2
        assert res.errors == 1


def test_rotate_table_records_dry_run_mode() -> None:
    key_old = Fernet.generate_key().decode()
    key_new = Fernet.generate_key().decode()

    with (
        patch("app.core.security.crypto.settings.pii_encryption_key", key_old),
        patch(
            "app.core.security.crypto.settings.pii_profile_key",
            "",
        ),
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

    with (
        patch(
            "app.core.security.crypto.settings.pii_encryption_key",
            f"{key_new},{key_old}",
        ),
        patch(
            "app.core.security.crypto.settings.pii_profile_key",
            "",
        ),
        patch("scripts.rotate_pii_encryption.supabase_client", mock_client),
    ):
        reset_cipher_suites()
        res = rotate_table_records(config=config, batch_size=10, dry_run=True)

        assert res.total_scanned == 2
        assert res.total_updated == 2
        assert res.total_skipped == 0
        mock_query.update.assert_not_called()


def test_pii_main_cli_execution() -> None:
    # 1. Invalid table name -> returns 1
    with patch.object(
        sys, "argv", ["rotate_pii_encryption.py", "--table", "non_existent_table"],
    ):
        assert pii_main() == 1

    # 2. Specific table with dry-run -> returns 0
    with (
        patch.object(
            sys,
            "argv",
            [
                "rotate_pii_encryption.py",
                "--table",
                "profiles",
                "--dry-run",
                "--batch-size",
                "25",
                "--offset",
                "10",
            ],
        ),
        patch("scripts.rotate_pii_encryption.rotate_table_records") as mock_rotate,
    ):
        mock_rotate.return_value = MagicMock(
            total_scanned=5, total_updated=5, total_skipped=0, errors=0,
        )
        code = pii_main()
        assert code == 0
        mock_rotate.assert_called_once_with(
            config=PII_TABLE_CONFIGS[0],
            batch_size=25,
            dry_run=True,
            start_offset=10,
        )

    # 3. All tables with failures -> returns 1
    with (
        patch.object(sys, "argv", ["rotate_pii_encryption.py"]),
        patch(
            "scripts.rotate_pii_encryption.rotate_table_records",
            return_value=MagicMock(
                total_scanned=5, total_updated=4, total_skipped=1, errors=0,
            ),
        ),
    ):
        assert pii_main() == 1


def test_rotate_pii_encryption_main_entrypoint() -> None:
    mock_client = MagicMock()
    mock_client.table.return_value.select.return_value.range.return_value.execute.return_value = MagicMock(
        data=[],
    )
    with (
        patch.object(
            sys,
            "argv",
            ["rotate_pii_encryption.py", "--dry-run", "--table", "profiles"],
        ),
        patch(
            "app.db.client.supabase_client",
            mock_client,
        ),
        patch("sys.exit") as mock_exit,
    ):
        import runpy

        runpy.run_path("scripts/rotate_pii_encryption.py", run_name="__main__")
        mock_exit.assert_called_once_with(0)
