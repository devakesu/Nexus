"""Unit tests verifying account deletion pending access control and lifecycle."""

from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, status
from starlette.requests import Request

from app.api.dependencies import assert_account_active, get_active_user_id
from app.api.user.account_deletion import cancel_account_deletion
from app.api.user.auth_otp import auth_bootstrap


def test_assert_account_active_rejects_pending_deletion() -> None:
    """Verify assert_account_active raises 403 when deletion_requested_at is set."""
    user_row = {
        "id": "user-123",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": "2026-08-15T12:00:00Z",
    }
    with pytest.raises(HTTPException) as exc_info:
        assert_account_active(user_row)

    assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
    assert exc_info.value.detail == "Account is pending deletion."


@pytest.mark.anyio
async def test_get_active_user_id_blocks_pending_deletion() -> None:
    """Verify get_active_user_id dependency rejects pending deletion users."""
    user_row = {
        "id": "user-123",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": "2026-08-15T12:00:00Z",
    }
    with patch(
        "app.api.dependencies.get_cached_public_user",
        AsyncMock(return_value=user_row),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await get_active_user_id("user-123")

        assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
        assert exc_info.value.detail == "Account is pending deletion."


@pytest.mark.anyio
async def test_auth_bootstrap_allows_pending_deletion_user_login() -> None:
    """Verify auth_bootstrap allows login and returns deletion_pending=True for Reactivation UI."""
    user_id = "user-123"
    purge_time = datetime(2026, 8, 29, 12, 0, 0, tzinfo=timezone.utc)
    user_row = {
        "id": user_id,
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": "2026-08-15T12:00:00Z",
        "scheduled_purge_at": purge_time.isoformat(),
        "accepted_terms_version": "2026-08-01",
        "moderation_status": "clear",
    }

    auth_payload = {
        "id": user_id,
        "email": "user@example.com",
    }
    scope: dict[str, Any] = {"type": "http", "headers": [], "query_string": b"", "path": "/"}
    request = Request(scope)

    with patch("app.api.user.auth_otp.fetch_public_user", return_value=user_row), \
         patch("app.api.user.auth_otp.fetch_profile", return_value={"name": "Test User"}):
        res = await auth_bootstrap(
            request=request,
            _device=None,
            auth_user=auth_payload,
        )

        assert res.user_id == user_id
        assert res.deletion_pending is True
        assert res.scheduled_purge_at == purge_time


@pytest.mark.anyio
async def test_cancel_account_deletion_reactivates_account() -> None:
    """Verify cancel_account_deletion succeeds for a pending deletion user."""
    user_id = "user-123"
    deletion_status = {
        "deletion_requested_at": "2026-08-15T12:00:00Z",
        "scheduled_purge_at": datetime(2026, 8, 29, 12, 0, 0, tzinfo=timezone.utc),
    }

    scope: dict[str, Any] = {"type": "http", "headers": [], "query_string": b"", "path": "/"}
    request = Request(scope)
    bg_tasks = MagicMock()

    with patch("app.api.user.account_deletion.fetch_deletion_status", return_value=deletion_status), \
         patch("app.api.user.account_deletion.get_user_email_by_id", return_value="user@example.com"), \
         patch("app.api.user.account_deletion.cancel_deletion") as mock_cancel, \
         patch("app.api.user.account_deletion.redis_client") as mock_redis:
        mock_redis.delete = AsyncMock()

        res = await cancel_account_deletion(
            request=request,
            background_tasks=bg_tasks,
            _device=None,
            user_id=user_id,
        )

        assert res.reactivated is True
        mock_cancel.assert_called_once_with(user_id)


@pytest.mark.anyio
async def test_phone_otp_endpoints_blocked_by_active_user_guard() -> None:
    """Verify phone OTP endpoints are protected by get_active_user_id and block pending deletion users."""
    user_row = {
        "id": "user-123",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": "2026-08-15T12:00:00Z",
    }

    # When get_active_user_id is called with pending deletion user, it raises 403
    with patch(
        "app.api.dependencies.get_cached_public_user",
        AsyncMock(return_value=user_row),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await get_active_user_id("user-123")
        assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
        assert exc_info.value.detail == "Account is pending deletion."


def test_anonymize_profile_and_user_sets_is_deactivated_true() -> None:
    """Verify that Tier-1 anonymization explicitly marks the profile is_deactivated=True."""
    from app.db.users.account_deletion import _anonymize_profile_and_user

    mock_builder = MagicMock()
    mock_builder.update.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])

    now = datetime(2026, 8, 15, 12, 0, 0, tzinfo=timezone.utc)
    user_id = "00000000-0000-0000-0000-000000000123"

    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_builder), \
         patch("app.db.users.account_deletion.invalidate_user_status_cache"):
        _anonymize_profile_and_user(user_id, now)

    # First table call is profiles, second is users
    calls = mock_builder.update.call_args_list
    assert len(calls) == 2

    profile_payload = calls[0][0][0]
    assert profile_payload["is_deactivated"] is True
    assert profile_payload["deactivated_at"] == now.isoformat()
    from app.core.security.crypto import decrypt_pii
    assert decrypt_pii(profile_payload["name"]) == "Deleted User"

    user_payload = calls[1][0][0]
    assert user_payload["is_active"] is False
    assert user_payload["purged_at"] == now.isoformat()


@pytest.mark.anyio
async def test_concurrent_deletion_request_does_not_evict_otp_key_for_in_flight_request() -> None:
    """Verify that idempotent deletion status returns do not prematurely delete the OTP key."""
    from fastapi import BackgroundTasks
    from app.api.user.account_deletion import request_account_deletion
    from app.models import AccountDeletionRequestRequest

    mock_request = MagicMock(spec=Request)
    bg_tasks = MagicMock(spec=BackgroundTasks)
    payload = AccountDeletionRequestRequest(confirmation_text="DELETE", email="user@example.com")

    existing_status = {
        "deletion_requested_at": "2026-08-15T12:00:00Z",
        "scheduled_purge_at": "2026-08-22T12:00:00Z",
    }

    mock_delete = AsyncMock()

    with patch("app.api.user.account_deletion.resolve_verified_user", AsyncMock(return_value=("user-123", "user@example.com"))), \
         patch("app.api.user.account_deletion.fetch_deletion_status", return_value=existing_status), \
         patch("app.api.user.account_deletion.redis_client.delete", mock_delete):

        res = await request_account_deletion(
            request=mock_request,
            background_tasks=bg_tasks,
            payload=payload,
            _device=None,
            auth_user_id="user-123",
            access_token="test-token",
        )

        assert res.scheduled_purge_at is not None
        mock_delete.assert_not_called()


def test_delete_user_media_objects_batches_storage_removals() -> None:
    from app.db.users.account_deletion import _delete_user_media_objects

    mock_storage_from = MagicMock()
    mock_bucket = MagicMock()
    mock_bucket.list.return_value = [{"name": "pic1.jpg"}, {"name": "pic2.jpg"}]
    mock_bucket.remove.return_value = MagicMock()
    mock_storage_from.return_value = mock_bucket

    mock_table = MagicMock()
    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.or_.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(
        data=[{"id": "00000000-0000-0000-0000-000000000010"}, {"id": "00000000-0000-0000-0000-000000000020"}],
    )
    mock_table.return_value = mock_builder

    with patch("app.db.users.account_deletion.supabase_client.storage.from_", mock_storage_from), \
         patch("app.db.users.account_deletion.supabase_client.table", mock_table), \
         patch("app.db.users.account_deletion.batch_delete_conversations_chat_media") as mock_batch_media:

        _delete_user_media_objects("00000000-0000-0000-0000-000000000001")

        # user_media and feedback_attachments both remove in single calls
        assert mock_bucket.remove.call_count == 2
        mock_batch_media.assert_called_once_with([
            "00000000-0000-0000-0000-000000000010",
            "00000000-0000-0000-0000-000000000020",
        ])


def test_batch_delete_conversations_chat_media() -> None:
    from app.db.chat.chat import batch_delete_conversations_chat_media

    mock_storage_from = MagicMock()
    mock_bucket = MagicMock()
    mock_bucket.list.side_effect = [
        [{"name": "file1.enc"}, {"name": "file2.enc"}],
        [{"name": "file3.enc"}],
    ]
    mock_bucket.remove.return_value = MagicMock()
    mock_storage_from.return_value = mock_bucket

    with patch("app.db.chat.chat.supabase_client.storage.from_", mock_storage_from):
        batch_delete_conversations_chat_media(["conv-1", "conv-2"])

        mock_bucket.remove.assert_called_once_with([
            "conv-1/file1.enc",
            "conv-1/file2.enc",
            "conv-2/file3.enc",
        ])


