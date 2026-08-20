"""Tests verifying PostgREST .or_() filter injection protection."""

from unittest.mock import MagicMock, patch

import pytest
from pydantic import ValidationError

from app.api.user.devices import _deactivate_device_token, _upsert_device_token
from app.db.chat.chat import (
    _fetch_conversations_for_reactivation,
    close_conversation_for_match_action,
    fetch_conversations_for_user,
    fetch_started_match_ids,
)
from app.db.chat.keys import has_active_match, mark_session_established
from app.db.client import (
    normalize_uuid,
    validate_device_id,
    validate_fcm_token,
)
from app.db.discovery.exclusions import (
    fetch_active_block_ids,
    fetch_active_discovery_excluded_ids,
)
from app.db.discovery.matches import (
    fetch_matches_for_user,
    record_match,
    set_match_unmatched,
)
from app.db.users.account_deletion import (
    _delete_no_retention_rows,
    _fetch_archive_source,
)
from app.db.users.export import (
    _build_chat_section,
    _build_matches_and_discovery,
    _build_reports_section,
)
from app.models import RegisterDeviceRequest

VALID_UUID_A = "00000000-0000-0000-0000-000000000001"
VALID_UUID_B = "00000000-0000-0000-0000-000000000002"
INJECTION_PAYLOADS = [
    "foo),user_id.neq.",
    "device_id.eq.foo),user_id.neq.",
    "foo,bar",
    "foo(bar)",
    "'; DROP TABLE users; --",
    "\" OR 1=1 --",
    "foo bar",
    "foo\nbar",
]


class TestValidationHelpers:
    """Test normalize_uuid, validate_fcm_token and validate_device_id helpers."""

    def test_normalize_uuid_valid(self) -> None:
        assert normalize_uuid(VALID_UUID_A) == VALID_UUID_A
        assert normalize_uuid(VALID_UUID_A.upper()) == VALID_UUID_A

    def test_normalize_uuid_injections_and_invalid(self) -> None:
        for payload in INJECTION_PAYLOADS:
            with pytest.raises(ValueError, match="Invalid UUID|badly formed"):
                normalize_uuid(payload)
        with pytest.raises(ValueError, match="Invalid UUID"):
            normalize_uuid("")
        with pytest.raises(ValueError, match="Invalid UUID"):
            normalize_uuid(None)

    def test_validate_fcm_token_valid(self) -> None:
        valid_tokens = [
            "fcm_token_12345",
            "fcm-token-with-hyphens",
            "fcm:token:with:colons:and_underscores",
            "bk3RNwTe3H0:CI2k_HHwgIpoDKCIZvvDMExUdFQ3P1...",
        ]
        for token in valid_tokens:
            assert validate_fcm_token(token) == token.strip()

    def test_validate_fcm_token_invalid_and_injections(self) -> None:
        for payload in INJECTION_PAYLOADS:
            with pytest.raises(ValueError, match="Invalid FCM token"):
                validate_fcm_token(payload)

        with pytest.raises(ValueError, match="Invalid FCM token"):
            validate_fcm_token("")
        with pytest.raises(ValueError, match="Invalid FCM token"):
            validate_fcm_token(None)

    def test_validate_device_id_valid(self) -> None:
        valid_ids = [
            "hardware-device-abc",
            "dev-123",
            VALID_UUID_A,
            "device_id_999",
            "device:id:123",
        ]
        for dev_id in valid_ids:
            assert validate_device_id(dev_id) == dev_id.strip()

    def test_validate_device_id_invalid_and_injections(self) -> None:
        for payload in INJECTION_PAYLOADS:
            with pytest.raises(ValueError, match="Invalid device ID"):
                validate_device_id(payload)

        with pytest.raises(ValueError, match="Invalid device ID"):
            validate_device_id("")
        with pytest.raises(ValueError, match="Invalid device ID"):
            validate_device_id(None)


class TestRegisterDeviceRequestValidation:
    """Test Pydantic model validation on device registration payload."""

    def test_valid_payload(self) -> None:
        model = RegisterDeviceRequest(
            fcm_token="valid_fcm_token_123",
            device_id="hardware-device-abc",
            platform="android",
        )
        assert model.fcm_token == "valid_fcm_token_123"
        assert model.device_id == "hardware-device-abc"

    def test_injection_in_fcm_token_rejected(self) -> None:
        with pytest.raises(ValidationError):
            RegisterDeviceRequest(
                fcm_token="device_id.eq.foo),user_id.neq.",
                device_id="dev-123",
            )

    def test_injection_in_device_id_rejected(self) -> None:
        with pytest.raises(ValidationError):
            RegisterDeviceRequest(
                fcm_token="valid_token",
                device_id="dev),user_id.neq.something(",
            )


class TestDevicesApiSecurity:
    """Test _deactivate_device_token and _upsert_device_token."""

    @patch("app.api.user.devices.supabase_client.table")
    def test_deactivate_device_token_safe_or_filter(self, mock_table: MagicMock) -> None:
        builder = MagicMock()
        builder.update.return_value = builder
        builder.eq.return_value = builder
        builder.or_.return_value = builder
        builder.execute.return_value = MagicMock(data=[{"id": "row-1"}])
        mock_table.return_value = builder

        result = _deactivate_device_token(
            user_id=VALID_UUID_A,
            fcm_token="fcm-token-123",
            device_id="device-id-abc",
        )
        assert result is True
        builder.or_.assert_called_once_with(
            "device_id.eq.device-id-abc,fcm_token.eq.fcm-token-123",
        )

    def test_deactivate_device_token_rejects_malformed_user_id(self) -> None:
        with pytest.raises(ValueError, match="Invalid UUID|badly formed"):
            _deactivate_device_token(
                user_id="invalid-uuid",
                fcm_token="fcm-token-123",
                device_id="device-id-abc",
            )

    def test_deactivate_device_token_rejects_malformed_fcm_token(self) -> None:
        with pytest.raises(ValueError, match="Invalid FCM token"):
            _deactivate_device_token(
                user_id=VALID_UUID_A,
                fcm_token="token,user_id.eq.target",
                device_id="device-id-abc",
            )

    def test_deactivate_device_token_rejects_malformed_device_id(self) -> None:
        with pytest.raises(ValueError, match="Invalid device ID"):
            _deactivate_device_token(
                user_id=VALID_UUID_A,
                fcm_token="fcm-token-123",
                device_id="dev),user_id.neq.target",
            )

    @patch("app.api.user.devices.supabase_client.table")
    def test_upsert_device_token_validates_inputs(self, mock_table: MagicMock) -> None:
        builder = MagicMock()
        builder.update.return_value = builder
        builder.upsert.return_value = builder
        builder.eq.return_value = builder
        builder.neq.return_value = builder
        builder.execute.return_value = MagicMock(data=[])
        mock_table.return_value = builder

        _upsert_device_token(
            user_id=VALID_UUID_A,
            fcm_token="token-123",
            platform="android",
            device_id="dev-456",
        )
        builder.upsert.assert_called_once()


class TestOrFilterLocationsRejectInvalidUUIDs:
    """Test all database query locations using .or_() enforce UUID validation."""

    def test_chat_keys_has_active_match(self) -> None:
        with pytest.raises(ValueError):
            has_active_match("invalid-uuid", VALID_UUID_B)
        with pytest.raises(ValueError):
            has_active_match(VALID_UUID_A, "invalid-uuid")

    def test_chat_keys_mark_session_established(self) -> None:
        with pytest.raises(ValueError):
            mark_session_established("invalid-uuid", "some-conversation-id")

    def test_chat_conversations_user(self) -> None:
        with pytest.raises(ValueError):
            fetch_conversations_for_user("invalid-uuid")

    def test_chat_started_match_ids(self) -> None:
        with pytest.raises(ValueError):
            fetch_started_match_ids("invalid-uuid")

    def test_chat_close_conversation(self) -> None:
        with pytest.raises(ValueError):
            close_conversation_for_match_action("invalid-uuid", VALID_UUID_B)

    def test_chat_reactivation_conversations(self) -> None:
        with pytest.raises(ValueError):
            _fetch_conversations_for_reactivation("invalid-uuid")

    def test_export_matches(self) -> None:
        with pytest.raises(ValueError):
            _build_matches_and_discovery("invalid-uuid")

    def test_export_chat(self) -> None:
        with pytest.raises(ValueError):
            _build_chat_section("invalid-uuid")

    def test_export_reports(self) -> None:
        with pytest.raises(ValueError):
            _build_reports_section("invalid-uuid")

    def test_discovery_matches_record(self) -> None:
        with pytest.raises(ValueError):
            record_match("invalid-uuid", VALID_UUID_B)

    def test_discovery_matches_fetch(self) -> None:
        with pytest.raises(ValueError):
            fetch_matches_for_user("invalid-uuid")

    def test_discovery_matches_unmatched(self) -> None:
        with pytest.raises(ValueError):
            set_match_unmatched("invalid-uuid", VALID_UUID_B)

    def test_discovery_exclusions_fetch(self) -> None:
        with pytest.raises(ValueError):
            fetch_active_discovery_excluded_ids("invalid-uuid", "Dating")

    def test_discovery_block_ids_fetch(self) -> None:
        with pytest.raises(ValueError):
            fetch_active_block_ids("invalid-uuid")

    def test_account_deletion_delete_no_retention_rows(self) -> None:
        with pytest.raises(ValueError):
            _delete_no_retention_rows("invalid-uuid")

    def test_account_deletion_fetch_archive_source(self) -> None:
        source = (
            "user_reports",
            "reporter_id.eq.{uid},target_id.eq.{uid}",
            "reason",
            "review_status",
        )
        with pytest.raises(ValueError):
            _fetch_archive_source(source, "invalid-uuid")
