"""Unit tests for phone blocklist audit logging and PII field compliance."""
# pyright: reportAttributeAccessIssue=false, reportUnknownMemberType=false

from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError

from app.core.security.crypto import decrypt_pii, encrypt_to_hex
from app.db.client import DatabaseAccessError
from app.db.users.account_deletion import (
    _ANONYMIZED_NAME,
    _PROFILE_PII_COLUMNS,
    is_phone_blocklisted,
)


def test_is_phone_blocklisted_empty_index_returns_false() -> None:
    """Empty blind index returns False immediately without DB query."""
    assert is_phone_blocklisted("") is False
    assert is_phone_blocklisted(None) is False  # type: ignore[arg-type]


def test_is_phone_blocklisted_hit_logs_structured_warning_and_returns_true(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A blocklist hit must return True and log a structured warning with masked blind index."""
    blind_index = "a1b2c3d4e5f67890abcdef1234567890abcdef12"
    cooldown = "2026-09-01T12:00:00Z"
    mock_res = MagicMock()
    mock_res.data = [{"id": "block-1", "cooldown_expires_at": cooldown}]

    table_mock = MagicMock()
    table_mock.select.return_value = table_mock
    table_mock.eq.return_value = table_mock
    table_mock.gt.return_value = table_mock
    table_mock.limit.return_value = table_mock
    table_mock.execute.return_value = mock_res

    with patch("app.db.users.account_deletion.supabase_client.table", return_value=table_mock), \
         caplog.at_level("WARNING"):
        result = is_phone_blocklisted(blind_index)

    assert result is True
    warning_records = [r for r in caplog.records if r.levelname == "WARNING"]
    assert len(warning_records) == 1
    record = warning_records[0]
    assert "blocked by deleted account blocklist hit" in record.message
    assert record.masked_phone_hash == f"{blind_index[:6]}...{blind_index[-6:]}"
    assert blind_index not in record.message
    assert record.cooldown_expires_at == cooldown


def test_is_phone_blocklisted_hit_short_blind_index_masked(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A short blind index should be masked as ***."""
    short_index = "short"
    mock_res = MagicMock()
    mock_res.data = [{"id": "block-2", "cooldown_expires_at": "2026-09-01T00:00:00Z"}]

    table_mock = MagicMock()
    table_mock.select.return_value = table_mock
    table_mock.eq.return_value = table_mock
    table_mock.gt.return_value = table_mock
    table_mock.limit.return_value = table_mock
    table_mock.execute.return_value = mock_res

    with patch("app.db.users.account_deletion.supabase_client.table", return_value=table_mock), \
         caplog.at_level("WARNING"):
        result = is_phone_blocklisted(short_index)

    assert result is True
    warning_records = [r for r in caplog.records if r.levelname == "WARNING"]
    assert len(warning_records) == 1
    assert warning_records[0].masked_phone_hash == "***"


def test_is_phone_blocklisted_miss_returns_false_and_no_warning(
    caplog: pytest.LogCaptureFixture,
) -> None:
    """A blocklist miss returns False and emits no warning."""
    blind_index = "a1b2c3d4e5f67890abcdef1234567890abcdef12"
    mock_res = MagicMock()
    mock_res.data = []

    table_mock = MagicMock()
    table_mock.select.return_value = table_mock
    table_mock.eq.return_value = table_mock
    table_mock.gt.return_value = table_mock
    table_mock.limit.return_value = table_mock
    table_mock.execute.return_value = mock_res

    with patch("app.db.users.account_deletion.supabase_client.table", return_value=table_mock), \
         caplog.at_level("WARNING"):
        result = is_phone_blocklisted(blind_index)

    assert result is False
    warning_records = [r for r in caplog.records if r.levelname == "WARNING"]
    assert len(warning_records) == 0


def test_is_phone_blocklisted_raises_database_access_error_on_api_error() -> None:
    """APIError from database raises DatabaseAccessError."""
    table_mock = MagicMock()
    table_mock.select.return_value = table_mock
    table_mock.eq.return_value = table_mock
    table_mock.gt.return_value = table_mock
    table_mock.limit.return_value = table_mock
    table_mock.execute.side_effect = APIError({"message": "DB connection failure", "code": "500"})

    with patch("app.db.users.account_deletion.supabase_client.table", return_value=table_mock), \
         pytest.raises(DatabaseAccessError):
        is_phone_blocklisted("test_blind_index_1234567890")


def test_age_excluded_from_pii_columns_and_name_anonymized_is_encrypted() -> None:
    """Verifies age is intentionally excluded from _PROFILE_PII_COLUMNS and anonymized name is encrypted."""
    assert "age" not in _PROFILE_PII_COLUMNS
    assert "name" not in _PROFILE_PII_COLUMNS

    # Verify anonymized name round-trip encryption
    encrypted_anon_name = encrypt_to_hex(_ANONYMIZED_NAME)
    assert encrypted_anon_name != _ANONYMIZED_NAME
    assert decrypt_pii(encrypted_anon_name) == _ANONYMIZED_NAME
