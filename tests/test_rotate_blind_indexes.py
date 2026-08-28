import sys
from unittest.mock import MagicMock, patch

from cryptography.fernet import Fernet

from app.core.security.crypto import (
    DecryptFailedError,
    compute_blind_index,
    compute_blind_index_with_key,
    encrypt_to_hex,
    reset_cipher_suites,
)
from scripts.rotate_blind_indexes import (
    init_sentry_if_configured,
    rotate_profiles_campus_branch_blind_index,
    rotate_safety_contacts_blind_index,
    rotate_users_mobile_blind_index,
)
from scripts.rotate_blind_indexes import (
    main as blind_index_main,
)
from scripts.rotate_hmac_signing_key import main as hmac_tool_main


def test_init_sentry_if_configured() -> None:
    with (
        patch(
            "scripts.rotate_blind_indexes.settings.sentry_backend_dsn",
            "https://key@sentry.io/123",
        ),
        patch(
            "sentry_sdk.init",
        ) as mock_sentry_init,
    ):
        init_sentry_if_configured()
        mock_sentry_init.assert_called_once()

    with patch("scripts.rotate_blind_indexes.settings.sentry_backend_dsn", ""):
        init_sentry_if_configured()


def test_rotate_users_mobile_blind_index_success() -> None:
    key_pii = Fernet.generate_key().decode()
    old_bi_key = "old_blind_index_key_111111111111"
    new_bi_key = "new_blind_index_key_222222222222"

    with (
        patch("app.core.security.crypto.settings.pii_encryption_key", key_pii),
        patch(
            "app.core.security.crypto.settings.pii_contact_key",
            "",
        ),
    ):
        reset_cipher_suites()
        hex_mobile = encrypt_to_hex("+15551234567", category="contact")

    old_digest = compute_blind_index_with_key(
        "+15551234567", domain="mobile", key=old_bi_key,
    )

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
    with (
        patch("app.core.security.crypto.settings.pii_encryption_key", key_pii),
        patch(
            "app.core.security.crypto.settings.pii_contact_key",
            "",
        ),
        patch("app.core.security.crypto.settings.blind_index_key", dual_bi_setting),
        patch(
            "scripts.rotate_blind_indexes.supabase_client",
            mock_client,
        ),
    ):
        reset_cipher_suites()
        res = rotate_users_mobile_blind_index(batch_size=10, dry_run=False)

        assert res.total_scanned == 2
        assert res.total_updated == 1
        assert res.total_unchanged == 1
        assert res.total_skipped == 0
        assert res.errors == 0

        new_digest = compute_blind_index("+15551234567", domain="mobile")
        mock_query.update.assert_called_once_with({"mobile_blind_index": new_digest})


def test_rotate_users_mobile_blind_index_errors_and_branches() -> None:
    # 1. DB select exception
    mock_client = MagicMock()
    mock_client.table.return_value.select.return_value.range.return_value.execute.side_effect = Exception(
        "DB Fail",
    )
    with (
        patch("scripts.rotate_blind_indexes.supabase_client", mock_client),
        patch(
            "scripts.rotate_blind_indexes.settings.sentry_backend_dsn",
            "https://key@sentry.io/1",
        ),
        patch("sentry_sdk.capture_exception") as mock_sentry,
    ):
        res = rotate_users_mobile_blind_index(batch_size=10)
        assert res.errors == 1
        mock_sentry.assert_called_once()

    # 2. DecryptFailedError, generic Exception during decrypt, and normalize_phone fallback
    key_pii = Fernet.generate_key().decode()
    with (
        patch("app.core.security.crypto.settings.pii_encryption_key", key_pii),
        patch(
            "app.core.security.crypto.settings.pii_contact_key",
            "",
        ),
    ):
        reset_cipher_suites()
        hex_mobile = encrypt_to_hex("+15551234567", category="contact")

    mock_rows = [
        {"id": "u-dec-err", "mobile": hex_mobile, "mobile_blind_index": "old"},
        {"id": "u-gen-err", "mobile": hex_mobile, "mobile_blind_index": "old"},
        {"id": "u-empty-dec", "mobile": hex_mobile, "mobile_blind_index": "old"},
        {"id": "u-norm-err", "mobile": hex_mobile, "mobile_blind_index": "old"},
        {
            "id": "u-already-updated",
            "mobile": hex_mobile,
            "mobile_blind_index": compute_blind_index("+15551234567", domain="mobile"),
        },
        {"id": "u-dry-run", "mobile": hex_mobile, "mobile_blind_index": "old"},
        {"id": "u-update-err", "mobile": hex_mobile, "mobile_blind_index": "old"},
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

    # Test DecryptFailedError & Generic Exception
    with (
        patch(
            "scripts.rotate_blind_indexes.decrypt_pii",
            side_effect=[
                DecryptFailedError("bad key"),
                Exception("unexpected"),
                "",  # empty decrypted
                "not-a-phone-format",
                "+15551234567",
                "+15551234567",
                "+15551234567",
            ],
        ),
        patch("scripts.rotate_blind_indexes.supabase_client", mock_client),
        patch(
            "scripts.rotate_blind_indexes.settings.sentry_backend_dsn",
            "https://key@sentry.io/1",
        ),
        patch("sentry_sdk.capture_message"),
        patch("sentry_sdk.capture_exception"),
    ):
        # simulate update error on the 7th item
        mock_query.execute.side_effect = [None, Exception("update fail")]
        res = rotate_users_mobile_blind_index(batch_size=10, dry_run=False)
        assert res.total_scanned == 7
        assert res.total_skipped == 2
        assert res.total_unchanged == 2

    # Test dry_run=True mode
    mock_client2 = MagicMock()
    mock_client2.table.return_value.select.return_value.range.side_effect = [
        MagicMock(
            execute=MagicMock(
                return_value=MagicMock(
                    data=[
                        {"id": "u-1", "mobile": hex_mobile, "mobile_blind_index": "old"},
                    ],
                ),
            ),
        ),
        MagicMock(execute=MagicMock(return_value=MagicMock(data=[]))),
    ]
    with (
        patch("app.core.security.crypto.settings.pii_encryption_key", key_pii),
        patch(
            "app.core.security.crypto.settings.pii_contact_key",
            "",
        ),
        patch("scripts.rotate_blind_indexes.supabase_client", mock_client2),
    ):
        reset_cipher_suites()
        res_dry = rotate_users_mobile_blind_index(batch_size=10, dry_run=True)
        assert res_dry.total_updated == 1
        mock_client2.table.return_value.update.assert_not_called()


def test_rotate_profiles_campus_branch_blind_index_errors_and_branches() -> None:
    # 1. DB select exception
    mock_client = MagicMock()
    mock_client.table.return_value.select.return_value.range.return_value.execute.side_effect = Exception(
        "DB Fail",
    )
    with (
        patch("scripts.rotate_blind_indexes.supabase_client", mock_client),
        patch(
            "scripts.rotate_blind_indexes.settings.sentry_backend_dsn",
            "https://key@sentry.io/1",
        ),
        patch("sentry_sdk.capture_exception") as mock_sentry,
    ):
        res = rotate_profiles_campus_branch_blind_index(batch_size=10)
        assert res.errors == 1
        mock_sentry.assert_called_once()

    # 2. Decrypt errors, empty decrypted, unchanged, dry-run, and update exception
    key_pii = Fernet.generate_key().decode()
    with (
        patch("app.core.security.crypto.settings.pii_encryption_key", key_pii),
        patch(
            "app.core.security.crypto.settings.pii_profile_key",
            "",
        ),
    ):
        reset_cipher_suites()
        hex_branch = encrypt_to_hex("Computer Science", category="profile")

    mock_rows = [
        {"id": "p-none", "campus_branch": None, "campus_branch_blind_index": None},
        {
            "id": "p-dec-err",
            "campus_branch": hex_branch,
            "campus_branch_blind_index": "old",
        },
        {
            "id": "p-gen-err",
            "campus_branch": hex_branch,
            "campus_branch_blind_index": "old",
        },
        {
            "id": "p-empty",
            "campus_branch": hex_branch,
            "campus_branch_blind_index": "old",
        },
        {
            "id": "p-same",
            "campus_branch": hex_branch,
            "campus_branch_blind_index": compute_blind_index(
                "Computer Science", domain="campus_branch",
            ),
        },
        {
            "id": "p-dry",
            "campus_branch": hex_branch,
            "campus_branch_blind_index": "old",
        },
        {
            "id": "p-upd-err",
            "campus_branch": hex_branch,
            "campus_branch_blind_index": "old",
        },
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
            "scripts.rotate_blind_indexes.decrypt_pii",
            side_effect=[
                DecryptFailedError("fail"),
                Exception("fail"),
                "",
                "Computer Science",
                "Computer Science",
                "Computer Science",
            ],
        ),
        patch("scripts.rotate_blind_indexes.supabase_client", mock_client),
        patch(
            "scripts.rotate_blind_indexes.settings.sentry_backend_dsn",
            "https://key@sentry.io/1",
        ),
        patch("sentry_sdk.capture_message"),
        patch("sentry_sdk.capture_exception"),
    ):
        mock_query.execute.side_effect = [None, Exception("update fail")]
        res = rotate_profiles_campus_branch_blind_index(batch_size=10, dry_run=False)
        assert res.total_scanned == 7
        assert res.total_skipped == 2
        assert res.total_unchanged == 3

    # Dry run
    mock_client2 = MagicMock()
    mock_client2.table.return_value.select.return_value.range.side_effect = [
        MagicMock(
            execute=MagicMock(
                return_value=MagicMock(
                    data=[
                        {
                            "id": "p-1",
                            "campus_branch": hex_branch,
                            "campus_branch_blind_index": "old",
                        },
                    ],
                ),
            ),
        ),
        MagicMock(execute=MagicMock(return_value=MagicMock(data=[]))),
    ]
    with (
        patch("app.core.security.crypto.settings.pii_encryption_key", key_pii),
        patch(
            "app.core.security.crypto.settings.pii_profile_key",
            "",
        ),
        patch("scripts.rotate_blind_indexes.supabase_client", mock_client2),
    ):
        reset_cipher_suites()
        res_dry = rotate_profiles_campus_branch_blind_index(batch_size=10, dry_run=True)
        assert res_dry.total_updated == 1


def test_rotate_safety_contacts_blind_index_errors_and_branches() -> None:
    # 1. DB select exception
    mock_client = MagicMock()
    mock_client.table.return_value.select.return_value.range.return_value.execute.side_effect = Exception(
        "DB Fail",
    )
    with (
        patch("scripts.rotate_blind_indexes.supabase_client", mock_client),
        patch(
            "scripts.rotate_blind_indexes.settings.sentry_backend_dsn",
            "https://key@sentry.io/1",
        ),
        patch("sentry_sdk.capture_exception") as mock_sentry,
    ):
        res = rotate_safety_contacts_blind_index(batch_size=10)
        assert res.errors == 1
        mock_sentry.assert_called_once()

    # 2. Decrypt errors, empty decrypted, normalize phone fallback, dry-run, and update exception
    key_pii = Fernet.generate_key().decode()
    with (
        patch("app.core.security.crypto.settings.pii_encryption_key", key_pii),
        patch(
            "app.core.security.crypto.settings.pii_contact_key",
            "",
        ),
    ):
        reset_cipher_suites()
        hex_phone = encrypt_to_hex("+15559876543", category="contact")

    mock_rows = [
        {"id": "c-none", "user_id": None, "phone": None},
        {"id": "c-dec-err", "user_id": "u-1", "phone": hex_phone},
        {"id": "c-gen-err", "user_id": "u-1", "phone": hex_phone},
        {"id": "c-empty", "user_id": "u-1", "phone": hex_phone},
        {"id": "c-norm-err", "user_id": "u-1", "phone": hex_phone},
        {"id": "c-dry", "user_id": "u-1", "phone": hex_phone},
        {"id": "c-upd-err", "user_id": "u-1", "phone": hex_phone},
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
            "scripts.rotate_blind_indexes.decrypt_pii",
            side_effect=[
                DecryptFailedError("fail"),
                Exception("fail"),
                "",
                "not-a-phone",
                "+15559876543",
                "+15559876543",
            ],
        ),
        patch("scripts.rotate_blind_indexes.supabase_client", mock_client),
        patch(
            "scripts.rotate_blind_indexes.settings.sentry_backend_dsn",
            "https://key@sentry.io/1",
        ),
        patch("sentry_sdk.capture_message"),
        patch("sentry_sdk.capture_exception"),
        patch(
            "scripts.rotate_blind_indexes._get_blind_index_keys",
            return_value=["new_k", "old_k"],
        ),
    ):
        mock_query.execute.side_effect = [None, Exception("update fail")]
        res = rotate_safety_contacts_blind_index(batch_size=10, dry_run=False)
        assert res.total_scanned == 7
        assert res.total_skipped == 2
        assert res.total_unchanged == 2

    # Dry run
    mock_client2 = MagicMock()
    mock_client2.table.return_value.select.return_value.range.side_effect = [
        MagicMock(
            execute=MagicMock(
                return_value=MagicMock(
                    data=[{"id": "c-1", "user_id": "u-1", "phone": hex_phone}],
                ),
            ),
        ),
        MagicMock(execute=MagicMock(return_value=MagicMock(data=[]))),
    ]
    with (
        patch("app.core.security.crypto.settings.pii_encryption_key", key_pii),
        patch(
            "app.core.security.crypto.settings.pii_contact_key",
            "",
        ),
        patch("scripts.rotate_blind_indexes.supabase_client", mock_client2),
    ):
        reset_cipher_suites()
        res_dry = rotate_safety_contacts_blind_index(batch_size=10, dry_run=True)
        assert res_dry.total_updated == 1


def test_blind_index_main_cli_execution() -> None:
    # Successful run with --domain and --dry-run
    with (
        patch.object(
            sys,
            "argv",
            [
                "rotate_blind_indexes.py",
                "--domain",
                "mobile",
                "--dry-run",
                "--batch-size",
                "25",
                "--offset",
                "10",
            ],
        ),
        patch(
            "scripts.rotate_blind_indexes.rotate_users_mobile_blind_index",
        ) as mock_mobile,
    ):
        mock_mobile.return_value = MagicMock(
            total_scanned=10, total_updated=10, total_skipped=0, errors=0,
        )
        code = blind_index_main()
        assert code == 0
        mock_mobile.assert_called_once_with(
            batch_size=25, dry_run=True, start_offset=10,
        )

    # Failed run with errors
    with (
        patch.object(sys, "argv", ["rotate_blind_indexes.py"]),
        patch(
            "scripts.rotate_blind_indexes.rotate_users_mobile_blind_index",
        ) as mock_m,
        patch(
            "scripts.rotate_blind_indexes.rotate_profiles_campus_branch_blind_index",
        ) as mock_p,
        patch(
            "scripts.rotate_blind_indexes.rotate_safety_contacts_blind_index",
        ) as mock_s,
    ):
        mock_m.return_value = MagicMock(
            total_scanned=10, total_updated=8, total_skipped=1, errors=1,
        )
        mock_p.return_value = MagicMock(
            total_scanned=5, total_updated=5, total_skipped=0, errors=0,
        )
        mock_s.return_value = MagicMock(
            total_scanned=5, total_updated=5, total_skipped=0, errors=0,
        )

        code_fail = blind_index_main()
        assert code_fail == 1


def test_rotate_blind_indexes_main_entrypoint() -> None:
    mock_client = MagicMock()
    mock_client.table.return_value.select.return_value.range.return_value.execute.return_value = MagicMock(
        data=[],
    )
    with (
        patch.object(sys, "argv", ["rotate_blind_indexes.py", "--dry-run"]),
        patch(
            "app.db.client.supabase_client",
            mock_client,
        ),
        patch("sys.exit") as mock_exit,
    ):
        import runpy

        runpy.run_path("scripts/rotate_blind_indexes.py", run_name="__main__")
        mock_exit.assert_called_once_with(0)


def test_rotate_hmac_signing_key_tool_errors_and_main() -> None:
    # 1. Empty HMAC key -> returns 1
    with patch("app.core.config.settings.hmac_signing_key", ""):
        assert hmac_tool_main() == 1

    # 2. Crypto verification failed -> returns 1
    with (
        patch(
            "app.core.config.settings.hmac_signing_key",
            "sample_primary_key_32_bytes_long_12345",
        ),
        patch(
            "scripts.rotate_hmac_signing_key.phone_verify_otp_hash",
            return_value=False,
        ),
    ):
        assert hmac_tool_main() == 1

    # 3. Success and entrypoint
    with (
        patch(
            "app.core.config.settings.hmac_signing_key",
            "sample_primary_key_32_bytes_long_12345",
        ),
        patch(
            "sys.exit",
        ) as mock_exit,
    ):
        import runpy

        runpy.run_path("scripts/rotate_hmac_signing_key.py", run_name="__main__")
        mock_exit.assert_called_once_with(0)
