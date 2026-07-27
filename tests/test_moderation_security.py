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
    mock_redis.get = AsyncMock(return_value="123456")
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
    mock_redis.get.assert_called_once_with("appeal:otp:test@example.com")
    mock_redis.delete.assert_called_once_with("appeal:otp:test@example.com")
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
