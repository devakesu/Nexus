from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import Request

from app.api.user.account_deletion import (
    cancel_account_deletion,
    request_account_deletion,
)
from app.core.email import (
    send_account_deletion_scheduled_email,
    send_account_reactivated_email,
)
from app.models import AccountDeletionRequestRequest


@pytest.mark.anyio
@patch("app.core.email.send_email")
async def test_send_account_deletion_scheduled_email_props(
    mock_send_email: MagicMock,
) -> None:
    mock_send_email.return_value = MagicMock(success=True)
    purge_time = datetime(2026, 8, 9, 12, 0, 0, tzinfo=timezone.utc)

    res = await send_account_deletion_scheduled_email(
        email="testuser@example.com",
        scheduled_purge_at=purge_time,
        grace_period_days=14,
    )

    assert res.success is True
    mock_send_email.assert_called_once()
    props = mock_send_email.call_args[0][0]
    assert props.to == "testuser@example.com"
    assert props.subject == "Account Deletion Scheduled - Grace Period Started"
    assert "2026-08-09 12:00 UTC" in props.html
    assert "14-day grace period" in props.html
    assert "Security Alert:" in props.html
    assert (
        "testuser@example.com" not in props.html
    )  # Check template renders without error


@pytest.mark.anyio
@patch("app.core.email.send_email")
async def test_send_account_reactivated_email_props(
    mock_send_email: MagicMock,
) -> None:
    mock_send_email.return_value = MagicMock(success=True)

    res = await send_account_reactivated_email(
        email="testuser@example.com",
    )

    assert res.success is True
    mock_send_email.assert_called_once()
    props = mock_send_email.call_args[0][0]
    assert props.to == "testuser@example.com"
    assert props.subject == "Account Reactivated - Nexus"
    assert "Account Reactivated" in props.html
    assert "DELETION_REQUEST:" in props.html
    assert "CANCELLED" in props.html


@pytest.mark.anyio
@patch("app.api.user.account_deletion.redis_client")
@patch("app.api.user.account_deletion.resolve_verified_user")
@patch("app.api.user.account_deletion.fetch_deletion_status")
@patch("app.api.user.account_deletion.compute_deletion_flag_reason")
@patch("app.api.user.account_deletion.request_deletion")
@patch("app.api.user.account_deletion.send_account_deletion_scheduled_email")
async def test_request_account_deletion_queues_email(
    mock_scheduled_email: MagicMock,
    mock_request_deletion: MagicMock,
    mock_compute_flag: MagicMock,
    mock_fetch_status: MagicMock,
    mock_resolve_user: AsyncMock,
    mock_redis: AsyncMock,
) -> None:
    mock_resolve_user.return_value = ("user-123", "user@example.com")
    mock_fetch_status.return_value = None
    mock_redis.get.return_value = b"1"
    mock_compute_flag.return_value = None
    purge_time = datetime(2026, 8, 9, 12, 0, 0, tzinfo=timezone.utc)
    mock_request_deletion.return_value = purge_time

    bg_tasks = MagicMock()
    payload = AccountDeletionRequestRequest(
        email="user@example.com",
        confirmation_text="DELETE",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await request_account_deletion(
        request=request,
        background_tasks=bg_tasks,
        payload=payload,
        auth_user_id="user-123",
        access_token="token-abc",
    )

    assert res.scheduled_purge_at == purge_time
    bg_tasks.add_task.assert_called_once_with(
        mock_scheduled_email,
        email="user@example.com",
        scheduled_purge_at=purge_time,
        grace_period_days=14,
    )


@pytest.mark.anyio
@patch("app.api.user.account_deletion.fetch_deletion_status")
@patch("app.api.user.account_deletion.get_user_email_by_id")
@patch("app.api.user.account_deletion.cancel_deletion")
@patch("app.api.user.account_deletion.send_account_reactivated_email")
async def test_cancel_account_deletion_queues_email(
    mock_reactivated_email: MagicMock,
    mock_cancel_deletion: MagicMock,
    mock_get_email: MagicMock,
    mock_fetch_status: MagicMock,
) -> None:

    mock_fetch_status.return_value = {
        "deletion_requested_at": "2026-07-26T19:00:00Z",
        "scheduled_purge_at": "2026-08-09T19:00:00Z",
    }
    mock_get_email.return_value = "user@example.com"

    bg_tasks = MagicMock()
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await cancel_account_deletion(
        request=request,
        background_tasks=bg_tasks,
        user_id="user-123",
    )

    assert res.reactivated is True
    mock_cancel_deletion.assert_called_once_with("user-123")
    bg_tasks.add_task.assert_called_once_with(
        mock_reactivated_email,
        email="user@example.com",
    )
