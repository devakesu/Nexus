"""Phase 22 Coverage Suite: Comprehensive coverage for app/api/user/settings.py, app/api/user/devices.py, and app/db/users/profile.py."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from postgrest.exceptions import APIError

from app.models import (
    EmailNotificationSettingsUpdate,
    PrivacySettingsUpdate,
    RegisterDeviceRequest,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"


# =============================================================================
# 1. API USER SETTINGS TESTS
# =============================================================================

def test_api_user_settings_deep():
    from app.api.user.settings import (
        get_email_notification_settings,
        get_privacy_settings,
        update_email_notification_settings,
        update_privacy_settings,
    )

    mock_req = MagicMock()

    # get_privacy_settings: 404 & 500
    with patch("app.api.user.settings.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=None)
        with pytest.raises(HTTPException, match="Profile not found"):
            get_privacy_settings(mock_req, _device=None, user_id=USER_1)

        mock_sb.table().select().eq().maybe_single().execute.side_effect = RuntimeError("DB fail")
        with pytest.raises(HTTPException, match="Internal server error"):
            get_privacy_settings(mock_req, _device=None, user_id=USER_1)

    # update_privacy_settings: no fields (400), not rows (404), exception (500)
    with pytest.raises(HTTPException, match="No fields to update"):
        update_privacy_settings(mock_req, PrivacySettingsUpdate(), _device=None, user_id=USER_1)

    with patch("app.api.user.settings.supabase_client") as mock_sb:
        mock_sb.table().update().eq().select().execute.return_value = MagicMock(data=[])
        with pytest.raises(HTTPException, match="Profile not found"):
            update_privacy_settings(mock_req, PrivacySettingsUpdate(share_active_status=False), _device=None, user_id=USER_1)

        mock_sb.table().update().eq().select().execute.side_effect = RuntimeError("DB error")
        with pytest.raises(HTTPException, match="Internal server error"):
            update_privacy_settings(mock_req, PrivacySettingsUpdate(share_active_status=False), _device=None, user_id=USER_1)

    # get_email_notification_settings: 404 & 500
    with patch("app.api.user.settings.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=None)
        with pytest.raises(HTTPException, match="Profile not found"):
            get_email_notification_settings(mock_req, _device=None, user_id=USER_1)

        mock_sb.table().select().eq().maybe_single().execute.side_effect = RuntimeError("DB fail")
        with pytest.raises(HTTPException, match="Internal server error"):
            get_email_notification_settings(mock_req, _device=None, user_id=USER_1)

    # update_email_notification_settings: no fields (400), not rows (404), exception (500)
    with pytest.raises(HTTPException, match="No fields to update"):
        update_email_notification_settings(mock_req, EmailNotificationSettingsUpdate(), _device=None, user_id=USER_1)

    with patch("app.api.user.settings.supabase_client") as mock_sb:
        mock_sb.table().update().eq().select().execute.return_value = MagicMock(data=[])
        with pytest.raises(HTTPException, match="Profile not found"):
            update_email_notification_settings(mock_req, EmailNotificationSettingsUpdate(email_notify_matches=False), _device=None, user_id=USER_1)

        mock_sb.table().update().eq().select().execute.side_effect = RuntimeError("DB error")
        with pytest.raises(HTTPException, match="Internal server error"):
            update_email_notification_settings(mock_req, EmailNotificationSettingsUpdate(email_notify_matches=False), _device=None, user_id=USER_1)


# =============================================================================
# 2. API USER DEVICES TESTS
# =============================================================================

async def test_api_user_devices_deep():
    from app.api.user.devices import (
        _deactivate_device_token,
        _upsert_device_token,
        register_device,
        unregister_device,
    )

    mock_req = MagicMock()
    valid_fcm = "a" * 152

    # _upsert_device_token with prior deactivation exception
    with patch("app.api.user.devices.supabase_client") as mock_sb:
        mock_sb.table().update().eq().eq().neq().execute.side_effect = Exception("deactivate error")
        mock_sb.table().upsert().execute.return_value = MagicMock()
        _upsert_device_token(USER_1, valid_fcm, "android", "device-id-12345678")

    # _deactivate_device_token without device_id
    with patch("app.api.user.devices.supabase_client") as mock_sb:
        mock_sb.table().update().eq().eq().execute.return_value = MagicMock(data=[{"id": 1}])
        res = _deactivate_device_token(USER_1, valid_fcm, None)
        assert res is True

    # register_device & unregister_device exception -> 503
    with patch("app.api.user.devices._upsert_device_token", side_effect=Exception("DB fail")):
        with pytest.raises(HTTPException, match="Service temporarily unavailable"):
            await register_device(mock_req, RegisterDeviceRequest(fcm_token=valid_fcm, platform="android"), _device=None, user_id=USER_1)

    with patch("app.api.user.devices._deactivate_device_token", side_effect=Exception("DB fail")):
        with pytest.raises(HTTPException, match="Service temporarily unavailable"):
            await unregister_device(mock_req, RegisterDeviceRequest(fcm_token=valid_fcm, platform="android"), _device=None, user_id=USER_1)


# =============================================================================
# 3. DB USERS PROFILE TESTS
# =============================================================================

def test_db_users_profile_deep():
    from app.db.users.profile import fetch_profile, upsert_profile_variant

    # fetch_profile: APIError & not a dict row
    with patch("app.db.users.profile.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(HTTPException, match="Profile service temporarily unavailable"):
            fetch_profile(USER_1)

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=["not-dict"])
        assert fetch_profile(USER_1) is None

    # upsert_profile_variant: APIError, fallback fetch returns None, name/age change log insert APIErrors
    with patch("app.db.users.profile.fetch_profile", return_value=None), \
         patch("app.db.users.profile.supabase_client") as mock_sb:
        
        # upsert APIError
        mock_sb.table().upsert().execute.side_effect = APIError({"message": "upsert fail"})
        with pytest.raises(HTTPException, match="Failed to save profile"):
            upsert_profile_variant(USER_1, "Alice", "CS", 2024, 21, "MIT", "NB")

        # result.data empty and fallback fetch_profile returns None -> 500
        mock_sb.table().upsert().execute.side_effect = None
        mock_sb.table().upsert().execute.return_value = MagicMock(data=[])
        with patch("app.db.users.profile.fetch_profile", side_effect=[None, None]):
            with pytest.raises(HTTPException, match="Profile save returned no row"):
                upsert_profile_variant(USER_1, "Alice", "CS", 2024, 21, "MIT", "NB")

        # Initial logs insert APIErrors caught gracefully
        mock_sb.table().upsert().execute.return_value = MagicMock(data=[{"id": USER_1, "name": "Alice"}])
        mock_sb.table().insert().execute.side_effect = APIError({"message": "log insert fail"})
        row, created = upsert_profile_variant(USER_1, "Alice", "CS", 2024, 21, "MIT", "NB")
        assert row["id"] == USER_1
        assert created is True
