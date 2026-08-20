from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from fastapi import Request

from app.api.user.devices import (
    _deactivate_device_token,
    _upsert_device_token,
    register_device,
    unregister_device,
)
from app.models import RegisterDeviceRequest


def _make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/devices/register",
    }
    return Request(scope)


@patch("app.api.user.devices.supabase_client.table")
def test_upsert_device_token_deactivates_older_tokens_for_same_device(mock_table: MagicMock) -> None:
    builder = MagicMock()
    builder.update.return_value = builder
    builder.upsert.return_value = builder
    builder.eq.return_value = builder
    builder.neq.return_value = builder
    builder.execute.return_value = MagicMock(data=[])
    mock_table.return_value = builder

    _upsert_device_token(
        user_id="00000000-0000-0000-0000-000000000123",
        fcm_token="new-fcm-token",
        platform="android",
        device_id="hardware-device-abc",
    )

    mock_table.assert_called_with("user_devices")
    builder.update.assert_called_once_with({"is_active": False})
    builder.upsert.assert_called_once()


@patch("app.api.user.devices.supabase_client.table")
def test_deactivate_device_token_uses_device_id_filter(mock_table: MagicMock) -> None:
    builder = MagicMock()
    builder.update.return_value = builder
    builder.eq.return_value = builder
    builder.or_.return_value = builder
    builder.execute.return_value = MagicMock(data=[{"id": "device-row-1"}])
    mock_table.return_value = builder

    deactivated = _deactivate_device_token(
        user_id="00000000-0000-0000-0000-000000000123",
        fcm_token="rotated-fcm-token",
        device_id="hardware-device-abc",
    )

    assert deactivated is True
    builder.or_.assert_called_once_with("device_id.eq.hardware-device-abc,fcm_token.eq.rotated-fcm-token")


@pytest.mark.anyio
@patch("app.api.user.devices._upsert_device_token")
async def test_register_device_endpoint(mock_upsert: MagicMock) -> None:
    payload = RegisterDeviceRequest(
        fcm_token="token-xyz",
        platform="ios",
        device_id="dev-123",
    )
    res = await register_device(
        request=_make_dummy_request(),
        payload=payload,
        _device=None,
        user_id="user-123",
    )
    assert res == {"success": True}
    mock_upsert.assert_called_once_with("user-123", "token-xyz", "ios", "dev-123")


@pytest.mark.anyio
@patch("app.api.user.devices._deactivate_device_token")
async def test_unregister_device_endpoint(mock_deactivate: MagicMock) -> None:
    payload = RegisterDeviceRequest(
        fcm_token="token-xyz",
        platform="ios",
        device_id="dev-123",
    )
    res = await unregister_device(
        request=_make_dummy_request(),
        payload=payload,
        _device=None,
        user_id="user-123",
    )
    assert res == {"success": True}
    mock_deactivate.assert_called_once_with("user-123", "token-xyz", "dev-123")
