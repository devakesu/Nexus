"""Phase 12 API Edge & Deep Endpoints Coverage Suite to push total coverage beyond 90%.

Targeting remaining high-statement endpoints and models:
1. app/api/feedback/contact.py (missing branches)
2. app/api/feedback/tickets.py (error paths)
3. app/api/user/settings.py (privacy & email notification settings)
4. app/api/spotify/auth.py (native-exchange, connect url, callback)
5. app/api/user/devices.py & app/api/user/sync.py
6. app/core/auth/passwordless_email.py
"""

from __future__ import annotations

from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
REPORT_1 = "00000000-0000-0000-0000-000000000050"


def _make_chaining_mock(data: Any = None) -> MagicMock:
    mock: MagicMock = MagicMock()
    mock.select.return_value = mock
    mock.insert.return_value = mock
    mock.update.return_value = mock
    mock.delete.return_value = mock
    mock.upsert.return_value = mock
    mock.eq.return_value = mock
    mock.neq.return_value = mock
    mock.gt.return_value = mock
    mock.gte.return_value = mock
    mock.lt.return_value = mock
    mock.lte.return_value = mock
    mock.is_.return_value = mock
    mock.in_.return_value = mock
    mock.or_.return_value = mock
    mock.not_.is_.return_value = mock
    mock.order.return_value = mock
    mock.limit.return_value = mock

    def _exec() -> MagicMock:
        return MagicMock(data=data)

    def _single() -> MagicMock:
        if isinstance(data, list) and data:
            return MagicMock(data=data[0])
        return MagicMock(data=data)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    mock.single.return_value = single_mock
    return mock


# -----------------------------------------------------------------------------
# 1. API USER SETTINGS (PRIVACY & NOTIFICATIONS)
# -----------------------------------------------------------------------------
def test_api_user_settings_deep():
    from app.api.user.settings import (
        get_email_notification_settings,
        get_privacy_settings,
        update_email_notification_settings,
        update_privacy_settings,
    )
    from app.models import (
        EmailNotificationSettingsUpdate,
        PrivacySettingsUpdate,
    )

    mock_req = MagicMock()
    mock_settings_row: dict[str, Any] = {
        "hidden_profile_fields": ["hometown"],
        "share_active_status": True,
        "share_read_receipts": True,
        "email_notify_matches": True,
        "email_notify_messages": True,
        "email_notify_digest": False,
        "email_notify_product_updates": True,
        "email_notify_promotions": False,
    }
    mock_t = _make_chaining_mock([mock_settings_row])

    with patch("app.api.user.settings.supabase_client.table", return_value=mock_t):
        # Privacy GET & PATCH
        priv_get = get_privacy_settings(mock_req, _device=None, user_id=USER_1)
        assert priv_get.share_active_status is True

        priv_patch = update_privacy_settings(
            mock_req,
            PrivacySettingsUpdate(hidden_fields=["hometown"], share_active_status=False),
            _device=None,
            user_id=USER_1,
        )
        assert priv_patch is not None

        # Email Notifications GET & PATCH
        notif_get = get_email_notification_settings(mock_req, _device=None, user_id=USER_1)
        assert notif_get.email_notify_matches is True

        notif_patch = update_email_notification_settings(
            mock_req,
            EmailNotificationSettingsUpdate(email_notify_digest=True),
            _device=None,
            user_id=USER_1,
        )
        assert notif_patch is not None


# -----------------------------------------------------------------------------
# 2. API SPOTIFY AUTH (NATIVE EXCHANGE & REDIRECT)
# -----------------------------------------------------------------------------
async def test_api_spotify_auth_deep():
    from app.api.spotify.auth import (
        _NativeExchangeRequest,
        _consume_state,
        _seed_and_queue_sync,
        _store_state,
        spotify_connect,
        spotify_native_exchange,
    )

    mock_req = MagicMock()
    mock_bg = MagicMock()

    with patch("app.api.spotify.auth.redis_client") as mock_r, \
         patch("app.api.spotify.auth.settings.spotify_client_id", "client_123"), \
         patch("app.api.spotify.auth.settings.spotify_redirect_uri", "https://app.nexus.com/callback"), \
         patch("app.api.spotify.auth.settings.spotify_allowed_redirect_uris", ["https://app.nexus.com/callback"]), \
         patch("app.api.spotify.auth.exchange_code", AsyncMock(return_value=MagicMock(access_token="acc_tok", refresh_token="ref_tok", scope="user-top-read"))), \
         patch("app.api.spotify.auth._seed_and_queue_sync", AsyncMock(return_value=["Taylor Swift"])), \
         patch("app.api.spotify.auth.fetch_spotify_user_id", AsyncMock(return_value="sp_user_1")), \
         patch("app.api.spotify.auth.upsert_connection"), \
         patch("app.api.spotify.auth.invalidate_viewer_discovery_sessions"), \
         patch("app.api.spotify.auth.fetch_top_artists_ranked", AsyncMock(return_value=MagicMock(ranked={"Taylor Swift": 1.0}, genre_weights={"pop": 1.0}))), \
         patch("app.api.spotify.auth.persist_artist_signals"):
        mock_r.setex = AsyncMock()
        mock_r.getdel = AsyncMock(return_value=USER_1)

        await _store_state("state123", USER_1)
        res_state = await _consume_state("state123")
        assert res_state == USER_1

        req_body = _NativeExchangeRequest(code="auth_code_123", redirect_uri="https://app.nexus.com/callback")
        res_exchange = await spotify_native_exchange(mock_req, req_body, mock_bg, _device=None, user_id=USER_1)
        assert res_exchange["syncing"] is True

        conn_url = await spotify_connect(mock_req, _device=None, user_id=USER_1)
        assert "auth_url" in conn_url

        seeded = await _seed_and_queue_sync(mock_bg, USER_1, "acc_tok", "ref_tok", "user-top-read")
        assert len(seeded) > 0


# -----------------------------------------------------------------------------
# 3. API USER DEVICES & PASSWORDLESS EMAIL
# -----------------------------------------------------------------------------
async def test_api_user_devices_and_passwordless_email():
    from app.api.user.devices import (
        register_device,
        unregister_device,
    )
    from app.core.auth.passwordless_email import (
        _scoped_auth_client,
        send_login_email_otp,
        verify_login_email_otp,
    )
    from app.models import RegisterDeviceRequest

    mock_req = MagicMock()
    mock_t = _make_chaining_mock([{"id": "d1", "user_id": USER_1, "platform": "ios", "is_active": True}])

    with patch("app.api.user.devices.supabase_client.table", return_value=mock_t):
        reg_req = RegisterDeviceRequest(
            fcm_token="fcm_token_1234567890",
            platform="ios",
            device_id="d1",
        )
        reg_res = await register_device(mock_req, reg_req, _device=None, user_id=USER_1)
        assert reg_res["success"] is True

        unreg_res = await unregister_device(mock_req, reg_req, _device=None, user_id=USER_1)
        assert unreg_res["success"] is True

    with patch("app.core.auth.passwordless_email.create_client") as mock_cc:
        mock_auth = MagicMock()
        mock_cc.return_value.auth = mock_auth
        mock_auth.sign_in_with_otp.return_value = None
        mock_auth.verify_otp.return_value = MagicMock(session=MagicMock(access_token="tok"))

        _scoped_auth_client()
        send_login_email_otp("a@b.com")
        res_ver = verify_login_email_otp("a@b.com", "123456")
        assert res_ver.session is not None
