from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request

from app.api.user.account_deletion import (
    cancel_account_deletion,
    request_account_deletion,
)
from app.core.email import (
    send_account_deletion_otp_email,
    send_account_deletion_scheduled_email,
    send_account_reactivated_email,
    send_data_export_otp_email,
    send_login_otp_email,
    send_support_appeal_otp_email,
)
from app.models import AccountDeletionRequestRequest


@pytest.mark.anyio
@patch("app.core.email.send_email")
async def test_send_login_otp_email_props(
    mock_send_email: MagicMock,
) -> None:
    mock_send_email.return_value = MagicMock(success=True)

    res = await send_login_otp_email(
        email="testuser@example.com",
        otp_code="555123",
    )

    assert res.success is True
    mock_send_email.assert_called_once()
    props = mock_send_email.call_args[0][0]
    assert props.to == "testuser@example.com"
    assert "Your Nexus Login Code" in props.subject
    assert "555123" in props.html
    assert "🔐 SECURE SIGN-IN VERIFICATION" in props.html
    assert "Your Login Code 🔑✨" in props.html
    assert "Didn't request this code?" in props.html
    assert "safely ignore and delete this email" in props.html
    assert "Hi there! 👋" in props.text


@pytest.mark.anyio
@patch("app.core.email.send_email")
async def test_send_data_export_otp_email_props(
    mock_send_email: MagicMock,
) -> None:
    mock_send_email.return_value = MagicMock(success=True)

    res = await send_data_export_otp_email(
        email="testuser@example.com",
        otp_code="12345678",
    )

    assert res.success is True
    mock_send_email.assert_called_once()
    props = mock_send_email.call_args[0][0]
    assert props.to == "testuser@example.com"
    assert "🔐 Confirm Data Export Request" in props.subject
    assert "12345678" in props.html
    assert "📦 PERSONAL DATA EXPORT REQUEST" in props.html
    assert "Included in Export:" in props.html
    assert "Excluded for Privacy:" in props.html
    assert "Chat message contents" in props.html
    assert "end-to-end encrypted" in props.html
    assert "How it works:" in props.html
    assert "PERSONAL DATA EXPORT REQUEST" in props.text


@pytest.mark.anyio
@patch("app.core.email.send_email")
async def test_send_support_appeal_otp_email_props(
    mock_send_email: MagicMock,
) -> None:
    mock_send_email.return_value = MagicMock(success=True)

    res = await send_support_appeal_otp_email(
        email="testuser@example.com",
        otp_code="65432109",
    )

    assert res.success is True
    mock_send_email.assert_called_once()
    props = mock_send_email.call_args[0][0]
    assert props.to == "testuser@example.com"
    assert "📩 Confirm Support Verification" in props.subject
    assert "65432109" in props.html
    assert "💜 SUPPORT &amp; HELP VERIFICATION" in props.html
    assert "Verify Your Ticket 📩✨" in props.html
    assert "Why verification is required:" in props.html
    assert "Hi there! 👋" in props.text


@pytest.mark.anyio
@patch("app.core.email.send_email")
async def test_send_account_deletion_otp_email_props(
    mock_send_email: MagicMock,
) -> None:
    mock_send_email.return_value = MagicMock(success=True)

    res = await send_account_deletion_otp_email(
        email="testuser@example.com",
        otp_code="98765432",
        grace_period_days=14,
    )

    assert res.success is True
    mock_send_email.assert_called_once()
    props = mock_send_email.call_args[0][0]
    assert props.to == "testuser@example.com"
    assert "⚠️ Confirm Account Deletion Request" in props.subject
    assert "98765432" in props.html
    assert "⚠️ CRITICAL SENSITIVE ACTION" in props.html
    assert "🚨 SENSITIVE ACTION NOTICE: PERMANENT &amp; IRREVERSIBLE" in props.html
    assert "14-day" in props.html
    assert "permanently anonymized and deleted" in props.html
    assert "completely irreversible" in props.html
    assert "SENSITIVE ACTION ALERT" in props.text


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
    assert "Welcome Back!" in props.subject
    assert "Welcome Back! 👋🌟" in props.html
    assert "🎉 WELCOME BACK TO NEXUS ✨" in props.html
    assert "DELETION_REQUEST:" in props.html
    assert "CANCELLED" in props.html
    assert "Welcome back home! 🎊💖" in props.html


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
    assert mock_redis.delete.call_count == 2
    mock_redis.delete.assert_any_call("user:status:user-123")
    bg_tasks.add_task.assert_called_once_with(
        mock_scheduled_email,
        email="user@example.com",
        scheduled_purge_at=purge_time,
        grace_period_days=14,
    )


@pytest.mark.anyio
@patch("app.api.user.account_deletion.redis_client")
@patch("app.api.user.account_deletion.resolve_verified_user")
@patch("app.api.user.account_deletion.fetch_deletion_status")
async def test_request_account_deletion_invalid_confirmation_preserves_otp(
    mock_fetch_status: MagicMock,
    mock_resolve_user: AsyncMock,
    mock_redis: AsyncMock,
) -> None:
    mock_resolve_user.return_value = ("user-123", "user@example.com")
    mock_fetch_status.return_value = None
    mock_redis.get.return_value = b"1"

    bg_tasks = MagicMock()
    payload = AccountDeletionRequestRequest(
        email="user@example.com",
        confirmation_text="NOT_DELETE",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await request_account_deletion(
            request=request,
            background_tasks=bg_tasks,
            payload=payload,
            auth_user_id="user-123",
            access_token="token-abc",
        )

    assert exc_info.value.status_code == 400
    assert "Type DELETE to confirm" in exc_info.value.detail
    mock_redis.delete.assert_not_called()


@pytest.mark.anyio
@patch("app.api.user.account_deletion.redis_client")
@patch("app.api.user.account_deletion.resolve_verified_user")
@patch("app.api.user.account_deletion.fetch_deletion_status")
async def test_request_account_deletion_early_return_preserves_otp_for_concurrency(
    mock_fetch_status: MagicMock,
    mock_resolve_user: AsyncMock,
    mock_redis: AsyncMock,
) -> None:
    purge_time = datetime(2026, 8, 9, 12, 0, 0, tzinfo=timezone.utc)
    mock_resolve_user.return_value = ("user-123", "user@example.com")
    mock_fetch_status.return_value = {
        "deletion_requested_at": "2026-07-26T12:00:00Z",
        "scheduled_purge_at": purge_time,
    }
    mock_redis.delete = AsyncMock()

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
    mock_redis.delete.assert_not_called()



@pytest.mark.anyio
@patch("app.api.user.account_deletion.redis_client")
@patch("app.api.user.account_deletion.fetch_deletion_status")
@patch("app.api.user.account_deletion.get_user_email_by_id")
@patch("app.api.user.account_deletion.cancel_deletion")
@patch("app.api.user.account_deletion.send_account_reactivated_email")
async def test_cancel_account_deletion_queues_email(
    mock_reactivated_email: MagicMock,
    mock_cancel_deletion: MagicMock,
    mock_get_email: MagicMock,
    mock_fetch_status: MagicMock,
    mock_redis: AsyncMock,
) -> None:

    mock_fetch_status.return_value = {
        "deletion_requested_at": "2026-07-26T19:00:00Z",
        "scheduled_purge_at": "2026-08-09T19:00:00Z",
    }
    mock_get_email.return_value = "user@example.com"
    mock_redis.delete = AsyncMock()

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
    assert mock_redis.delete.call_count == 2
    bg_tasks.add_task.assert_called_once_with(
        mock_reactivated_email,
        email="user@example.com",
    )


@patch("app.db.users.account_deletion._close_all_conversations")
@patch("app.db.users.account_deletion.invalidate_user_status_cache")
@patch("app.db.users.account_deletion.supabase_client.table")
def test_request_deletion_deletes_discovery_session_items(
    mock_table: MagicMock,
    _mock_invalidate: MagicMock,
    _mock_close_convos: MagicMock,
) -> None:
    from app.db.users.account_deletion import request_deletion

    table_builders: dict[str, MagicMock] = {}

    def get_table_builder(table_name: str) -> MagicMock:
        if table_name not in table_builders:
            builder = MagicMock()
            builder.update.return_value = builder
            builder.delete.return_value = builder
            builder.eq.return_value = builder
            builder.execute.return_value = MagicMock(data=[])
            table_builders[table_name] = builder
        return table_builders[table_name]

    mock_table.side_effect = get_table_builder

    valid_uid = "00000000-0000-0000-0000-000000000123"
    purge_time = request_deletion(valid_uid, "user_requested")

    assert purge_time is not None
    assert "discovery_session_items" in table_builders
    discovery_builder = table_builders["discovery_session_items"]
    discovery_builder.delete.assert_called_once()
    discovery_builder.eq.assert_called_once_with("candidate_id", valid_uid)
    discovery_builder.execute.assert_called_once()


@pytest.mark.anyio
@patch("app.api.user.account_deletion.redis_client")
@patch("app.api.user.account_deletion.resolve_verified_user")
async def test_verify_account_deletion_otp_attempts_lockout(
    mock_resolve_user: AsyncMock,
    mock_redis: AsyncMock,
) -> None:
    from app.api.user.account_deletion import verify_account_deletion_otp
    from app.models import AccountDeletionOtpVerifyRequest

    mock_resolve_user.return_value = ("user-123", "user@example.com")

    async def fake_redis_get(key: str) -> str | None:
        if "otp_attempts" in key:
            return "5"
        return "12345678"

    mock_redis.get = AsyncMock(side_effect=fake_redis_get)
    mock_redis.incr = AsyncMock(return_value=6)

    payload = AccountDeletionOtpVerifyRequest(
        email="user@example.com",
        code="12345678",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
        "client": ("10.0.0.1", 12345),
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await verify_account_deletion_otp(
            request=request,
            payload=payload,
            _device=None,
            auth_user_id="user-123",
        )

    assert exc_info.value.status_code == 429
    assert "Too many incorrect attempts" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.user.export.redis_client")
@patch("app.api.user.export.resolve_verified_user")
async def test_verify_data_export_otp_attempts_lockout(
    mock_resolve_user: AsyncMock,
    mock_redis: AsyncMock,
) -> None:
    from app.api.user.export import verify_data_export_otp
    from app.models import DataExportOtpVerifyRequest

    mock_resolve_user.return_value = ("user-123", "user@example.com")

    async def fake_redis_get(key: str) -> str | None:
        if "otp_attempts" in key:
            return "5"
        return "12345678"

    mock_redis.get = AsyncMock(side_effect=fake_redis_get)
    mock_redis.incr = AsyncMock(return_value=6)

    payload = DataExportOtpVerifyRequest(
        email="user@example.com",
        code="12345678",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
        "client": ("10.0.0.2", 12345),
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await verify_data_export_otp(
            request=request,
            payload=payload,
            _device=None,
            auth_user_id="user-123",
        )

    assert exc_info.value.status_code == 429
    assert "Too many incorrect attempts" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.user.export.build_user_data_export")
@patch("app.api.user.export.redis_client")
@patch("app.api.user.export.resolve_verified_user")
async def test_export_account_data_response_headers(
    mock_resolve_user: AsyncMock,
    mock_redis: AsyncMock,
    mock_build_export: MagicMock,
) -> None:
    from app.api.user.export import export_account_data
    from app.models import DataExportRequestRequest

    mock_resolve_user.return_value = ("user-123", "user@example.com")
    mock_redis.get.return_value = b"1"
    mock_redis.delete = AsyncMock()
    mock_build_export.return_value = {"user_id": "user-123", "profile": {"name": "Test"}}

    payload = DataExportRequestRequest(email="user@example.com")
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
        "client": ("10.0.0.3", 12345),
    }
    request = Request(scope)

    response = await export_account_data(
        request=request,
        payload=payload,
        _device=None,
        auth_user_id="user-123",
    )

    assert response.status_code == 200
    assert response.headers.get("Content-Disposition") == 'attachment; filename="nexus-data-export.json"'
    mock_redis.delete.assert_called_once_with("data_export:otp_verified:user-123")


def test_build_matches_and_discovery_uuid_validation():
    from app.db.users.export import _build_matches_and_discovery

    # Invalid non-UUID user_id must raise ValueError before any query is formed
    with pytest.raises(ValueError):
        _build_matches_and_discovery("malicious_id_with_commas,eq.admin")

    valid_uuid = "00000000-0000-0000-0000-000000000001"
    with patch("app.db.users.export.supabase_client.table") as mock_table:
        mock_builder = MagicMock()
        mock_builder.select.return_value = mock_builder
        mock_builder.or_.return_value = mock_builder
        mock_builder.execute.return_value = MagicMock(data=[])
        mock_table.return_value = mock_builder

        result = _build_matches_and_discovery(valid_uuid)
        assert "matches" in result
        mock_builder.or_.assert_called_once_with(f"liker_id.eq.{valid_uuid},liked_back_id.eq.{valid_uuid}")


@patch("app.db.users.export.get_user_email_by_id")
@patch("app.db.users.export.supabase_client.table")
def test_build_account_section_filters_tombstone_email(
    mock_table: MagicMock,
    mock_get_email: MagicMock,
):
    from app.db.users.export import _build_account_section

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.maybe_single.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data={"id": "00000000-0000-0000-0000-000000000001"})
    mock_table.return_value = mock_builder

    valid_uuid = "00000000-0000-0000-0000-000000000001"

    # Case 1: Active legitimate email
    mock_get_email.return_value = "alex@example.com"
    account = _build_account_section(valid_uuid)
    assert account.get("email") == "alex@example.com"

    # Case 2: Post-purge tombstone email
    mock_get_email.return_value = f"deleted-{valid_uuid}@deleted.nexus.app"
    account_purged = _build_account_section(valid_uuid)
    assert account_purged.get("email") is None


@pytest.mark.anyio
@patch("app.api.user.account_deletion.dummy_email_send_delay")
@patch("app.api.user.account_deletion.resolve_verified_user")
async def test_request_account_deletion_otp_unregistered_email(
    mock_resolve_user: AsyncMock,
    mock_dummy_delay: AsyncMock,
) -> None:
    from app.api.user.account_deletion import request_account_deletion_otp
    from app.models import AccountDeletionOtpRequestRequest

    mock_resolve_user.return_value = (None, "unregistered@example.com")
    payload = AccountDeletionOtpRequestRequest(email="unregistered@example.com")
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
        "client": ("10.0.0.1", 12345),
    }
    request = Request(scope)

    resp = await request_account_deletion_otp(
        request=request,
        payload=payload,
        _device=None,
        auth_user_id=None,
    )
    assert resp.sent is True
    mock_dummy_delay.assert_called_once()


@pytest.mark.anyio
@patch("app.api.user.export.dummy_email_send_delay")
@patch("app.api.user.export.resolve_verified_user")
async def test_request_data_export_otp_unregistered_email(
    mock_resolve_user: AsyncMock,
    mock_dummy_delay: AsyncMock,
) -> None:
    from app.api.user.export import request_data_export_otp
    from app.models import DataExportOtpRequestRequest

    mock_resolve_user.return_value = (None, "unregistered@example.com")
    payload = DataExportOtpRequestRequest(email="unregistered@example.com")
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
        "client": ("10.0.0.1", 12345),
    }
    request = Request(scope)

    resp = await request_data_export_otp(
        request=request,
        payload=payload,
        _device=None,
        auth_user_id=None,
    )
    assert resp.sent is True
    mock_dummy_delay.assert_called_once()


@pytest.mark.anyio
@patch("app.api.user.account_deletion.resolve_verified_user")
@patch("app.api.user.account_deletion.redis_client")
async def test_request_account_deletion_otp_per_target_resend_cooldown_raises_429(
    mock_redis: AsyncMock,
    mock_resolve_user: AsyncMock,
) -> None:
    from app.api.user.account_deletion import request_account_deletion_otp
    from app.models import AccountDeletionOtpRequestRequest

    mock_resolve_user.return_value = ("target-user-1", "target@example.com")
    mock_redis.exists.return_value = True  # Cooldown exists
    payload = AccountDeletionOtpRequestRequest(email="target@example.com")
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
        "client": ("10.0.0.1", 12345),
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await request_account_deletion_otp(
            request=request,
            payload=payload,
            _device=None,
            auth_user_id=None,
        )
    assert exc_info.value.status_code == 429
    assert "Please wait a bit before requesting another deletion code" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.user.account_deletion.resolve_verified_user")
@patch("app.api.user.account_deletion.redis_client")
async def test_request_account_deletion_otp_per_target_attempts_exceeded_raises_429(
    mock_redis: AsyncMock,
    mock_resolve_user: AsyncMock,
) -> None:
    from app.api.user.account_deletion import request_account_deletion_otp
    from app.models import AccountDeletionOtpRequestRequest

    mock_resolve_user.return_value = ("target-user-1", "target@example.com")
    mock_redis.exists.return_value = False
    mock_redis.get.return_value = "3"  # Max target attempts reached
    payload = AccountDeletionOtpRequestRequest(email="target@example.com")
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
        "client": ("10.0.0.1", 12345),
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await request_account_deletion_otp(
            request=request,
            payload=payload,
            _device=None,
            auth_user_id=None,
        )
    assert exc_info.value.status_code == 429
    assert "Too many deletion requests for this account" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.user.export.resolve_verified_user")
@patch("app.api.user.export.redis_client")
async def test_request_data_export_otp_per_target_resend_cooldown_raises_429(
    mock_redis: AsyncMock,
    mock_resolve_user: AsyncMock,
) -> None:
    from app.api.user.export import request_data_export_otp
    from app.models import DataExportOtpRequestRequest

    mock_resolve_user.return_value = ("target-user-2", "target2@example.com")
    mock_redis.exists.return_value = True  # Cooldown active
    payload = DataExportOtpRequestRequest(email="target2@example.com")
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
        "client": ("10.0.0.2", 12345),
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await request_data_export_otp(
            request=request,
            payload=payload,
            _device=None,
            auth_user_id=None,
        )
    assert exc_info.value.status_code == 429
    assert "Please wait a bit before requesting another data export code" in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.user.export.resolve_verified_user")
@patch("app.api.user.export.redis_client")
async def test_request_data_export_otp_per_target_attempts_exceeded_raises_429(
    mock_redis: AsyncMock,
    mock_resolve_user: AsyncMock,
) -> None:
    from app.api.user.export import request_data_export_otp
    from app.models import DataExportOtpRequestRequest

    mock_resolve_user.return_value = ("target-user-2", "target2@example.com")
    mock_redis.exists.return_value = False
    mock_redis.get.return_value = "3"  # Max target attempts reached
    payload = DataExportOtpRequestRequest(email="target2@example.com")
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
        "client": ("10.0.0.2", 12345),
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await request_data_export_otp(
            request=request,
            payload=payload,
            _device=None,
            auth_user_id=None,
        )
    assert exc_info.value.status_code == 429
    assert "Too many data export requests for this account" in exc_info.value.detail


def test_request_deletion_ends_active_safety_sessions():
    """request_deletion immediately transitions active safety sessions to ended."""
    from app.db.users.account_deletion import request_deletion

    user_id = "00000000-0000-0000-0000-000000000123"
    mock_builder = MagicMock()
    mock_builder.update.return_value = mock_builder
    mock_builder.delete.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])

    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_builder), \
         patch("app.db.users.account_deletion.invalidate_user_status_cache"), \
         patch("app.db.users.account_deletion._close_all_conversations"):
        request_deletion(user_id=user_id, flagged_reason_code=None)

    # Verify update({"status": "ended"}) was called
    update_calls = [c for c in mock_builder.update.call_args_list]
    assert any(c[0][0] == {"status": "ended"} for c in update_calls)







