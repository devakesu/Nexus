"""Unit tests for profile decryption failure sentinel assertions."""

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.api.user.profile.details import (
    get_profile_derived_signals,
    update_profile_details,
)
from app.models.profile import ProfileDetailsUpdate


def test_update_profile_details_raises_500_on_decryption_failure() -> None:
    """update_profile_details must raise HTTP 500 when existing profile has decryption failure sentinels."""
    user_id = "00000000-0000-0000-0000-000000000001"
    payload = ProfileDetailsUpdate(name="Bobby")

    mock_profile_raw = {
        "id": user_id,
        "name": "corrupted_cipher_hex",
        "bio": "corrupted_cipher_hex",
    }

    mock_decrypted = {
        "id": user_id,
        "name": "__DECRYPTION_FAILED__",
        "bio": "Hello world",
    }

    mock_profile_res = MagicMock()
    mock_profile_res.data = mock_profile_raw

    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_profile_res

    with patch("app.api.user.profile.details.supabase_client.table", return_value=mock_table), \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value=mock_decrypted):
        with pytest.raises(HTTPException) as exc_info:
            update_profile_details(
                request=MagicMock(),
                background_tasks=MagicMock(),
                payload=payload,
                user_id=user_id,
            )
        assert exc_info.value.status_code == 500
        assert "Profile decryption failed" in exc_info.value.detail


def test_derived_signals_transparency_raises_500_on_decryption_failure() -> None:
    """get_profile_derived_signals must raise HTTP 500 when profile decryption fails."""
    user_id = "00000000-0000-0000-0000-000000000002"

    mock_profile_raw = {"id": user_id}
    mock_decrypted = {
        "id": user_id,
        "artist_affinity": {"__DECRYPTION_FAILED__": True},
    }

    mock_profile_res = MagicMock()
    mock_profile_res.data = mock_profile_raw

    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_profile_res

    with patch("app.api.user.profile.details.supabase_client.table", return_value=mock_table), \
         patch("app.api.user.profile.details.decrypt_profile_record", return_value=mock_decrypted):
        with pytest.raises(HTTPException) as exc_info:
            get_profile_derived_signals(
                request=MagicMock(),
                user_id=user_id,
            )
        assert exc_info.value.status_code == 500
        assert "Profile decryption failed" in exc_info.value.detail
