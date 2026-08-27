from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from fastapi import Request

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
    assert (
        props.subject
        == "[New Comment] [#12345678] [Nexus Bug Report] App crashes on open"
    )
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
    assert (
        props.subject
        == "[Closed] [#12345678] [Nexus Help Request] Need login assistance"
    )
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
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
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
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
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


@pytest.mark.anyio
@patch("app.api.feedback.tickets.fetch_ticket_comments")
@patch("app.api.feedback.tickets.fetch_ticket_status_history")
async def test_assemble_ticket_detail_concurrent(
    mock_history: MagicMock,
    mock_comments: MagicMock,
) -> None:
    from app.api.feedback.tickets import assemble_ticket_detail

    mock_history.return_value = [
        {"status": "in_review", "note": "old: open", "changed_by": "staff-1", "created_at": "2026-08-01T00:00:00Z"},
    ]
    mock_comments.return_value = [
        {"id": "c-1", "author_id": "user-123", "body": "My comment", "created_at": "2026-08-01T00:00:00Z"},
        {"id": "c-2", "author_id": "staff-99", "body": "Admin reply", "created_at": "2026-08-01T00:01:00Z"},
    ]

    report: dict[str, Any] = {
        "id": "ticket-100",
        "user_id": "user-123",
        "query_type": "help",
        "subject": "Help Needed",
        "message": "Please assist.",
        "status": "in_review",
        "created_at": "2026-08-01T00:00:00Z",
        "updated_at": "2026-08-01T00:00:00Z",
        "github_issue_url": None,
        "attachment_paths": [],
        "app_version": None,
        "platform": None,
        "device_info": {},
    }

    res = await assemble_ticket_detail(user_id="user-123", report=report)

    assert res.id == "ticket-100"
    assert len(res.status_history) == 1
    assert res.status_history[0].changed_by == "staff"
    assert len(res.comments) == 2
    assert res.comments[0].is_own is True
    assert res.comments[0].author_id == "user-123"
    assert res.comments[1].is_own is False
    assert res.comments[1].author_id == "staff"


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
@patch("app.api.feedback.record_feedback_submission")
@patch("app.api.feedback.fetch_user_email")
async def test_submit_feedback_with_valid_attachments_verified_in_storage(
    mock_fetch_email: MagicMock,
    mock_record: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    from app.api.feedback.tickets import submit_feedback
    from app.models import FeedbackSubmitRequest

    mock_storage = MagicMock()
    mock_storage.list.return_value = [{"name": "screenshot1.png"}]
    mock_supabase.storage.from_.return_value = mock_storage

    mock_record.return_value = {
        "id": "ticket-555",
        "status": "open",
        "created_at": "2026-08-19T19:00:00Z",
    }
    mock_fetch_email.return_value = "user@example.com"

    payload = FeedbackSubmitRequest(
        query_type="bug_report",
        subject="Button not responding",
        message="The submit button is unresponsive on iOS.",
        attachment_paths=["user-123/screenshot1.png"],
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/feedback/submit",
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    res = await submit_feedback(
        request=request,
        background_tasks=bg_tasks,
        payload=payload,
        user_id="user-123",
    )

    assert res.id == "ticket-555"
    mock_storage.list.assert_called_once_with("user-123")
    mock_record.assert_called_once()


@pytest.mark.anyio
@patch("app.api.feedback.supabase_client")
@patch("app.api.feedback.record_feedback_submission")
async def test_submit_feedback_rejects_nonexistent_attachment(
    mock_record: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    from fastapi import HTTPException

    from app.api.feedback.tickets import submit_feedback
    from app.models import FeedbackSubmitRequest

    mock_storage = MagicMock()
    mock_storage.list.return_value = [{"name": "other_file.png"}]
    mock_supabase.storage.from_.return_value = mock_storage

    payload = FeedbackSubmitRequest(
        query_type="bug_report",
        subject="Button not responding",
        message="The submit button is unresponsive on iOS.",
        attachment_paths=["user-123/phantom.png"],
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/feedback/submit",
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    with pytest.raises(HTTPException) as exc_info:
        await submit_feedback(
            request=request,
            background_tasks=bg_tasks,
            payload=payload,
            user_id="user-123",
        )

    assert exc_info.value.status_code == 400
    assert "Attachment file not found: phantom.png" in exc_info.value.detail
    mock_record.assert_not_called()


@pytest.mark.anyio
async def test_submit_feedback_rejects_other_user_prefix() -> None:
    from fastapi import HTTPException

    from app.api.feedback.tickets import submit_feedback
    from app.models import FeedbackSubmitRequest

    payload = FeedbackSubmitRequest(
        query_type="bug_report",
        subject="Button not responding",
        message="The submit button is unresponsive on iOS.",
        attachment_paths=["other-user/screenshot1.png"],
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/feedback/submit",
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    with pytest.raises(HTTPException) as exc_info:
        await submit_feedback(
            request=request,
            background_tasks=bg_tasks,
            payload=payload,
            user_id="user-123",
        )

    assert exc_info.value.status_code == 422
    assert "attachment_paths may only reference your own uploads." in exc_info.value.detail


@pytest.mark.anyio
async def test_submit_feedback_rejects_traversal_in_attachment() -> None:
    from fastapi import HTTPException

    from app.api.feedback.tickets import submit_feedback
    from app.models import FeedbackSubmitRequest

    payload = FeedbackSubmitRequest(
        query_type="bug_report",
        subject="Button not responding",
        message="The submit button is unresponsive on iOS.",
        attachment_paths=["user-123/../victim/secret.png"],
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/feedback/submit",
    }
    request = Request(scope)
    bg_tasks = MagicMock()

    with pytest.raises(HTTPException) as exc_info:
        await submit_feedback(
            request=request,
            background_tasks=bg_tasks,
            payload=payload,
            user_id="user-123",
        )

    assert exc_info.value.status_code == 422
    assert "attachment_paths may only reference your own uploads." in exc_info.value.detail


def test_close_ticket_db_sets_reviewed_by_none() -> None:
    from app.db.feedback.feedback import close_ticket

    mock_builder = MagicMock()
    mock_builder.update.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.neq.return_value = mock_builder
    mock_builder.select.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[{"id": "ticket-123", "status": "closed"}])

    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_builder):
        res = close_ticket(user_id="user-123", report_id="ticket-123", reason="Resolved by user")
        assert res == {"id": "ticket-123", "status": "closed"}

        # Verify update payload has reviewed_by: None
        update_args = mock_builder.update.call_args[0][0]
        assert update_args["status"] == "closed"
        assert update_args["reviewed_by"] is None
        assert update_args["reviewer_notes"] == "Resolved by user"
        assert "reviewed_at" in update_args


def test_record_feedback_submission_encrypts_subject_and_message() -> None:
    from app.core.security.crypto import decrypt_pii
    from app.db.feedback.feedback import record_feedback_submission

    mock_builder = MagicMock()
    mock_builder.insert.return_value = mock_builder
    mock_builder.select.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[{"id": "fb-1", "status": "open", "created_at": "2026-08-25T00:00:00Z"}])

    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_builder):
        res = record_feedback_submission(
            user_id="user-1",
            query_type="bug_report",
            subject="Cannot upload photos",
            message="Every time I select a photo it fails with error code 500.",
        )
        assert res["id"] == "fb-1"

        inserted_payload = mock_builder.insert.call_args[0][0]
        assert inserted_payload["subject"] != "Cannot upload photos"
        assert inserted_payload["message"] != "Every time I select a photo it fails with error code 500."
        assert decrypt_pii(inserted_payload["subject"], category="contact") == "Cannot upload photos"
        assert decrypt_pii(inserted_payload["message"], category="contact") == "Every time I select a photo it fails with error code 500."


def test_fetch_user_tickets_and_report_decrypts_subject_and_message() -> None:
    from app.core.security.crypto import encrypt_to_hex
    from app.db.feedback.feedback import fetch_ticket_report, fetch_user_tickets

    enc_sub = encrypt_to_hex("My App Feedback", category="contact")
    enc_msg = encrypt_to_hex("The interface is smooth and intuitive.", category="contact")

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.order.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(
        data=[{"id": "fb-2", "query_type": "feedback", "subject": enc_sub, "status": "open", "created_at": "2026-08-25T00:00:00Z"}],
    )

    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_builder):
        tickets = fetch_user_tickets(user_id="user-2")
        assert len(tickets) == 1
        assert tickets[0]["subject"] == "My App Feedback"

    mock_detail_builder = MagicMock()
    mock_detail_builder.select.return_value = mock_detail_builder
    mock_detail_builder.eq.return_value = mock_detail_builder
    mock_detail_builder.maybe_single.return_value = mock_detail_builder
    mock_detail_builder.execute.return_value = MagicMock(
        data={"id": "fb-2", "query_type": "feedback", "subject": enc_sub, "message": enc_msg, "status": "open"},
    )

    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_detail_builder):
        detail = fetch_ticket_report(user_id="user-2", report_id="fb-2")
        assert detail is not None
        assert detail["subject"] == "My App Feedback"
        assert detail["message"] == "The interface is smooth and intuitive."


def test_export_feedback_section_decrypts_subject_and_message() -> None:
    from app.core.security.crypto import encrypt_to_hex
    from app.db.users.export import _build_feedback_section

    enc_sub = encrypt_to_hex("Exported Ticket Subject", category="contact")
    enc_msg = encrypt_to_hex("Exported Ticket Message Content", category="contact")

    mock_rows = [
        {
            "id": "fb-3",
            "query_type": "help",
            "subject": enc_sub,
            "message": enc_msg,
            "status": "resolved",
            "created_at": "2026-08-25T00:00:00Z",
            "updated_at": "2026-08-25T01:00:00Z",
        },
    ]

    with patch("app.db.users.export._safe_select", return_value=mock_rows), patch(
        "app.db.users.export.supabase_client.table",
    ) as mock_table:
        mock_builder = MagicMock()
        mock_builder.select.return_value = mock_builder
        mock_builder.eq.return_value = mock_builder
        mock_builder.execute.return_value = MagicMock(data=[])
        mock_table.return_value = mock_builder

        exported = _build_feedback_section(user_id="user-3")
        assert len(exported) == 1
        assert exported[0]["subject"] == "Exported Ticket Subject"
        assert exported[0]["message"] == "Exported Ticket Message Content"


