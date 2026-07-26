from typing import Any
from unittest.mock import MagicMock, patch

from fastapi import Request
import pytest

from app.api.feedback import add_feedback_comment, close_feedback_ticket
from app.core.email import (
    send_feedback_closed_admin_notification_email,
    send_feedback_comment_admin_notification_email,
)
from app.models import FeedbackCloseRequest, FeedbackCommentRequest


@pytest.mark.anyio
@patch("app.core.email.send_email")
async def test_send_feedback_comment_admin_notification_email_subject(
    mock_send_email: MagicMock,
) -> None:
    mock_send_email.return_value = MagicMock(success=True)

    res = await send_feedback_comment_admin_notification_email(
        report_id="12345678-abcd-1234-5678-1234567890ab",
        query_type="bug_report",
        subject="App crashes on open",
        comment_body="Here is more info about the crash.",
        user_id="user-123",
        submitter_email="user@example.com",
    )

    assert res.success is True
    mock_send_email.assert_called_once()
    props = mock_send_email.call_args[0][0]
    assert props.subject == "[New Comment] [#12345678] [Nexus Bug Report] App crashes on open"
    assert props.reply_to == "user@example.com"
    assert "Here is more info about the crash." in props.text


@pytest.mark.anyio
@patch("app.core.email.send_email")
async def test_send_feedback_closed_admin_notification_email_subject(
    mock_send_email: MagicMock,
) -> None:
    mock_send_email.return_value = MagicMock(success=True)

    res = await send_feedback_closed_admin_notification_email(
        report_id="12345678-abcd-1234-5678-1234567890ab",
        query_type="help",
        subject="Need login assistance",
        reason="Resolved the issue myself.",
        user_id="user-123",
        submitter_email="user@example.com",
    )

    assert res.success is True
    mock_send_email.assert_called_once()
    props = mock_send_email.call_args[0][0]
    assert props.subject == "[Closed] [#12345678] [Nexus Help Request] Need login assistance"
    assert props.reply_to == "user@example.com"
    assert "Resolved the issue myself." in props.text


@pytest.mark.anyio
@patch("app.api.feedback.fetch_ticket_report")
@patch("app.api.feedback.add_ticket_comment")
@patch("app.api.feedback.fetch_user_email")
@patch("app.api.feedback.send_feedback_comment_admin_notification_email")
async def test_add_feedback_comment_endpoint_admin_email(
    mock_comment_email: MagicMock,
    mock_fetch_email: MagicMock,
    mock_add_comment: MagicMock,
    mock_fetch_report: MagicMock,
) -> None:
    mock_fetch_report.return_value = {
        "id": "ticket-111",
        "query_type": "feedback",
        "subject": "Great features",
        "status": "open",
    }
    mock_add_comment.return_value = {
        "id": "comment-999",
        "author_id": "user-123",
        "body": "Another suggestion here",
        "created_at": "2026-07-26T18:00:00Z",
    }
    mock_fetch_email.return_value = "user@example.com"

    bg_tasks = MagicMock()
    payload = FeedbackCommentRequest(body="Another suggestion here")
    scope: dict[str, Any] = {"type": "http", "headers": [], "query_string": b"", "path": "/"}
    request = Request(scope)

    res = await add_feedback_comment(
        request=request,
        report_id="ticket-111",
        background_tasks=bg_tasks,
        payload=payload,
        user_id="user-123",
    )

    assert res.id == "comment-999"
    bg_tasks.add_task.assert_called_once_with(
        mock_comment_email,
        report_id="ticket-111",
        query_type="feedback",
        subject="Great features",
        comment_body="Another suggestion here",
        user_id="user-123",
        submitter_email="user@example.com",
    )


@pytest.mark.anyio
@patch("app.api.feedback.close_ticket")
@patch("app.api.feedback.fetch_user_email")
@patch("app.api.feedback._assemble_ticket_detail")
@patch("app.api.feedback.send_feedback_closed_admin_notification_email")
async def test_close_feedback_ticket_endpoint_admin_email(
    mock_close_email: MagicMock,
    mock_assemble: MagicMock,
    mock_fetch_email: MagicMock,
    mock_close_ticket: MagicMock,
) -> None:
    mock_close_ticket.return_value = {
        "id": "ticket-222",
        "query_type": "bug_report",
        "subject": "UI glitch in list",
        "status": "closed",
    }
    mock_fetch_email.return_value = "user@example.com"
    mock_assemble.return_value = MagicMock()

    bg_tasks = MagicMock()
    payload = FeedbackCloseRequest(reason="Issue fixed in update")
    scope: dict[str, Any] = {"type": "http", "headers": [], "query_string": b"", "path": "/"}
    request = Request(scope)

    await close_feedback_ticket(
        request=request,
        report_id="ticket-222",
        background_tasks=bg_tasks,
        payload=payload,
        user_id="user-123",
    )

    bg_tasks.add_task.assert_called_once_with(
        mock_close_email,
        report_id="ticket-222",
        query_type="bug_report",
        subject="UI glitch in list",
        reason="Issue fixed in update",
        user_id="user-123",
        submitter_email="user@example.com",
    )
