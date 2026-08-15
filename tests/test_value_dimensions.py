from unittest.mock import MagicMock, patch

import pytest

from app.services.value_dimensions import recompile_value_dimensions


@patch("app.services.value_dimensions.supabase_client")
@patch("app.services.value_dimensions.decrypt_profile_record")
@patch("app.services.value_dimensions.derive_value_dimensions")
@patch("app.services.value_dimensions.encrypt_to_hex")
def test_recompile_value_dimensions_success(
    mock_encrypt: MagicMock,
    mock_derive: MagicMock,
    mock_decrypt: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    mock_select = MagicMock()
    mock_supabase.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute = mock_select
    mock_select.return_value.data = {"id": "user123", "lifestyle": "gym"}

    mock_decrypt.return_value = {"id": "user123", "lifestyle": "gym"}
    mock_derive.return_value = {"civil_liberties": 7, "environmentalism": 8, "technology_optimism": 9}
    mock_encrypt.return_value = "deadbeef123"

    mock_update = MagicMock()
    mock_supabase.table.return_value.update.return_value.eq.return_value.execute = mock_update

    recompile_value_dimensions("user123")

    mock_update.assert_called_once()
    mock_encrypt.assert_called_once()


@patch("app.services.value_dimensions.supabase_client")
def test_recompile_value_dimensions_missing_profile_skips(mock_supabase: MagicMock) -> None:
    mock_select = MagicMock()
    mock_supabase.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute = mock_select
    mock_select.return_value.data = None

    # Should exit cleanly without raising
    recompile_value_dimensions("user_nonexistent")


@patch("app.services.value_dimensions.supabase_client")
@patch("app.services.value_dimensions.decrypt_profile_record")
@patch("app.services.value_dimensions.derive_value_dimensions")
def test_recompile_value_dimensions_propagates_db_error(
    mock_derive: MagicMock,
    mock_decrypt: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    mock_select = MagicMock()
    mock_supabase.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute = mock_select
    mock_select.return_value.data = {"id": "user123"}
    mock_decrypt.return_value = {"id": "user123"}
    mock_derive.return_value = {"civil_liberties": 5}

    mock_update = MagicMock()
    mock_update.side_effect = Exception("DB update connection failure")
    mock_supabase.table.return_value.update.return_value.eq.return_value.execute = mock_update

    with pytest.raises(Exception) as exc_info:
        recompile_value_dimensions("user123")

    assert "DB update connection failure" in str(exc_info.value)
