from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request, status

from app.api.dependencies import get_active_user_id
from app.api.feedback import (
    ContactOtpRequest,
    ContactSubmitRequest,
    send_contact_otp,
    submit_contact_ticket,
)
from app.db.profiles import (
    _build_candidate_query,
)
from app.models import DiscoveryFilters


@pytest.mark.anyio
async def test_get_active_user_id_active() -> None:
    user_row = {
        "id": "user123",
        "is_active": True,
        "is_suspended": False,
        "moderation_status": "clear",
    }
    with patch(
        "app.api.dependencies.get_cached_public_user",
        AsyncMock(return_value=user_row),
    ):
        res = await get_active_user_id("user123")
        assert res == "user123"


@pytest.mark.anyio
async def test_get_active_user_id_suspended() -> None:
    user_row = {
        "id": "user123",
        "is_active": True,
        "is_suspended": True,
        "moderation_status": "suspended",
    }
    with patch(
        "app.api.dependencies.get_cached_public_user",
        AsyncMock(return_value=user_row),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await get_active_user_id("user123")
        assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN


@pytest.mark.anyio
async def test_get_active_user_id_inactive() -> None:
    user_row = {
        "id": "user123",
        "is_active": False,
        "is_suspended": False,
        "moderation_status": "clear",
    }
    with patch(
        "app.api.dependencies.get_cached_public_user",
        AsyncMock(return_value=user_row),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await get_active_user_id("user123")
        assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN


@pytest.mark.anyio
async def test_get_active_user_id_deletion_pending() -> None:
    user_row = {
        "id": "user123",
        "is_active": True,
        "is_suspended": False,
        "moderation_status": "clear",
        "deletion_requested_at": "2026-08-11T20:00:00Z",
    }
    with patch(
        "app.api.dependencies.get_cached_public_user",
        AsyncMock(return_value=user_row),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await get_active_user_id("user123")
        assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
        assert exc_info.value.detail == "Account is pending deletion."


@pytest.mark.anyio
async def test_get_active_user_id_banned() -> None:
    user_row = {
        "id": "user123",
        "is_active": True,
        "is_suspended": False,
        "moderation_status": "banned",
    }
    with patch(
        "app.api.dependencies.get_cached_public_user",
        AsyncMock(return_value=user_row),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await get_active_user_id("user123")
        assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
        assert exc_info.value.detail == "Account is permanently banned."


def test_build_candidate_query_moderation_filters() -> None:
    filters = DiscoveryFilters()
    query = _build_candidate_query(
        viewer_id="viewer123",
        active_tab="Dating",
        filters=filters,
        excluded_ids=set(),
        app_variant="nexus",
    )
    assert query is not None


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
@patch("app.api.feedback.redis_client")
@patch("app.api.feedback.send_support_appeal_otp_email")
async def test_send_appeal_otp_flow(
    mock_send_email: MagicMock,
    mock_redis: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    _ = mock_supabase

    # 1. Mock redis set and email send
    mock_redis.set = AsyncMock()
    mock_send_email.return_value.success = True

    # 2. Call endpoint helper
    payload = ContactOtpRequest(email="test@example.com", turnstile_token=None)
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)
    res = await send_contact_otp(
        request=request,
        payload=payload,
    )

    assert res == {"success": True}
    mock_redis.set.assert_called_once()
    mock_send_email.assert_called_once()


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
@patch("app.api.feedback.redis_client")
@patch("app.api.feedback.record_feedback_submission")
@patch("app.api.feedback.send_feedback_confirmation_email")
@patch("app.api.feedback.send_feedback_admin_notification_email")
async def test_submit_appeal_ticket_flow(
    mock_admin_email: MagicMock,
    mock_conf_email: MagicMock,
    mock_record_sub: MagicMock,
    mock_redis: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    # 1. Mock redis get
    def _mock_redis_get(k: Any) -> str | None:
        return "123456" if str(k) == "appeal:otp:test@example.com" else None

    mock_redis.get = AsyncMock(side_effect=_mock_redis_get)
    mock_redis.delete = AsyncMock()

    # 2. Mock user lookup RPC
    mock_rpc_exec = MagicMock()
    mock_rpc_exec.execute.return_value.data = "user-uuid-123"
    mock_supabase.rpc.return_value = mock_rpc_exec

    # 3. Mock DB feedback insert
    mock_record_sub.return_value = {"id": "ticket-uuid-abc", "status": "open"}

    # 4. Call endpoint helper
    payload = ContactSubmitRequest(
        email="test@example.com",
        otp_code="123456",
        subject="Suspension Appeal",
        message="Please restore my account.",
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    res = await submit_contact_ticket(
        request=request,
        background_tasks=bg_tasks,
        payload=payload,
    )

    assert res == {"success": True, "ticket_id": "ticket-uuid-abc", "status": "open"}
    mock_redis.get.assert_any_call("appeal:otp:test@example.com")
    mock_redis.delete.assert_any_call("appeal:otp:test@example.com")
    mock_redis.delete.assert_any_call("appeal:otp_attempts:test@example.com")
    mock_record_sub.assert_called_once()
    bg_tasks.add_task.assert_any_call(
        mock_conf_email,
        email="test@example.com",
        query_type="help",
        subject="Suspension Appeal",
        report_id="ticket-uuid-abc",
    )
    bg_tasks.add_task.assert_any_call(
        mock_admin_email,
        report_id="ticket-uuid-abc",
        query_type="help",
        subject="Suspension Appeal",
        message="Please restore my account.",
        user_id="user-uuid-123",
        submitter_email="test@example.com",
        github_issue_url=None,
        attachment_count=0,
        attachment_names=None,
        submitter_name=None,
        account_id_or_phone=None,
    )


def test_set_user_suspension_invalidates_cache() -> None:
    from app.db.users.auth import set_user_suspension

    mock_builder = MagicMock()
    mock_builder.update.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[{"id": "user-susp-123"}])

    with (
        patch("app.db.users.auth.supabase_client.table", return_value=mock_builder),
        patch("app.db.users.auth.invalidate_user_status_cache") as mock_invalidate,
    ):
        set_user_suspension(
            user_id="user-susp-123",
            is_suspended=True,
            moderation_status="banned",
            moderation_reason_code="harassment",
        )
        mock_builder.update.assert_called_once_with({
            "is_suspended": True,
            "suspended_until": None,
            "moderation_status": "banned",
            "moderation_reason_code": "harassment",
        })
        mock_builder.eq.assert_called_once_with("id", "user-susp-123")
        mock_invalidate.assert_called_once_with("user-susp-123")


def test_get_moderation_subjects_filters_deactivated_users() -> None:
    from app.api.user.profile.moderation import get_moderation_subjects
    from app.models import ModerationSubjectsRequest

    # Mock discovery actions table returning valid blocked IDs
    mock_discovery_builder = MagicMock()
    mock_discovery_builder.select.return_value = mock_discovery_builder
    mock_discovery_builder.eq.return_value = mock_discovery_builder
    mock_discovery_builder.in_.return_value = mock_discovery_builder
    mock_discovery_builder.is_.return_value = mock_discovery_builder
    mock_discovery_builder.execute.return_value = MagicMock(
        data=[{"target_id": "11111111-1111-1111-1111-111111111111"}],
    )

    # Mock profiles table
    mock_profiles_builder = MagicMock()
    mock_profiles_builder.select.return_value = mock_profiles_builder
    mock_profiles_builder.in_.return_value = mock_profiles_builder
    mock_profiles_builder.eq.return_value = mock_profiles_builder
    mock_profiles_builder.execute.return_value = MagicMock(
        data=[
            {
                "id": "11111111-1111-1111-1111-111111111111",
                "name": "Alice",
                "age": 22,
                "campus_year": 3,
                "campus_name": "mec",
                "campus_branch": "CS",
                "hometown": "NY",
                "current_place": "Campus",
                "profile_pic": "pic.jpg",
            },
        ],
    )

    def _table_side_effect(name: str) -> MagicMock:
        if name == "profile_discovery_actions":
            return mock_discovery_builder
        return mock_profiles_builder

    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)
    payload = ModerationSubjectsRequest(
        target_ids=["11111111-1111-1111-1111-111111111111"],
    )

    with (
        patch("app.api.user.profile.moderation.supabase_client.table", side_effect=_table_side_effect),
        patch("app.api.user.profile.moderation.sign_profile_media_bulk"),
    ):
        res = get_moderation_subjects(
            request=request,
            payload=payload,
            user_id="22222222-2222-2222-2222-222222222222",
            _device=None,
        )

        assert len(res) == 1
        assert res[0]["id"] == "11111111-1111-1111-1111-111111111111"
        # Verify is_deactivated=False was queried on profiles
        mock_profiles_builder.eq.assert_called_once_with("is_deactivated", False)


def test_moderation_subjects_request_validation() -> None:
    from pydantic import ValidationError

    from app.models import ModerationSubjectsRequest

    # Valid list of UUIDs
    req = ModerationSubjectsRequest(target_ids=["11111111-1111-1111-1111-111111111111"])
    assert req.target_ids == ["11111111-1111-1111-1111-111111111111"]

    # Reject empty list
    with pytest.raises(ValidationError):
        ModerationSubjectsRequest(target_ids=[])

    # Reject invalid UUID
    with pytest.raises(ValidationError):
        ModerationSubjectsRequest(target_ids=["not-a-valid-uuid"])

    # Reject exceeding upper bound of 50
    with pytest.raises(ValidationError):
        ModerationSubjectsRequest(target_ids=[f"{i:08x}-0000-0000-0000-000000000000" for i in range(51)])


