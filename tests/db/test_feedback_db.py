"""Test Suite for Test Feedback Db.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from datetime import datetime, timezone
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.security.crypto import encrypt_to_hex
from app.db.client import DatabaseAccessError

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
SESS_1 = "00000000-0000-0000-0000-000000000040"
SESSION_1 = "00000000-0000-0000-0000-000000000020"
ALERT_1 = "00000000-0000-0000-0000-000000000010"
CONV_1 = "00000000-0000-0000-0000-000000000020"
CONVO_1 = "00000000-0000-0000-0000-000000000020"
MATCH_1 = "00000000-0000-0000-0000-000000000010"
MSG_1 = "00000000-0000-0000-0000-000000000020"
PHONE_VALID = "+14155552671"
REPORT_1 = "00000000-0000-0000-0000-000000000050"
EVENT_1 = "00000000-0000-0000-0000-000000000033"
CONTACT_1 = "00000000-0000-0000-0000-000000000030"


def _make_chaining_mock(
    data: Any = None, error: Exception | None = None,
) -> MagicMock:
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
    mock.range.return_value = mock
    mock.contains.return_value = mock
    mock.contained_by.return_value = mock
    mock.overlaps.return_value = mock

    def _exec() -> MagicMock:
        if error:
            raise error
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    def _single() -> MagicMock:
        if error:
            raise error
        if isinstance(data, list) and data:
            return MagicMock(data=copy.deepcopy(data[0]))
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    mock.single.return_value = single_mock
    return mock


def make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/test",
        "headers": [],
        "client": ("127.0.0.1", 12345),
        "app": MagicMock(),
    }
    return Request(scope)


def _make_mock_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/test",
        "headers": [(b"host", b"localhost"), (b"user-agent", b"pytest")],
        "client": ("127.0.0.1", 12345),
        "app": {},
    }
    return Request(scope)


def make_api_error(code: str = "P0001", message: str = "DB error") -> APIError:
    return APIError(
        {"code": code, "message": message, "details": "details", "hint": "hint"},
    )


pytestmark = pytest.mark.anyio


def test_db_feedback_and_spotify():
    from app.db.feedback.feedback import (
        add_ticket_comment,
        close_ticket,
        fetch_ticket_report,
        fetch_user_tickets,
        record_feedback_submission,
    )
    from app.db.spotify import (
        disconnect,
        get_connection,
        get_decrypted_refresh_token,
        mark_sync_result,
        persist_artist_signals,
        upsert_connection,
    )

    mock_table = MagicMock()

    # 1. feedback.py
    mock_table.insert.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": "ticket_1", "subject": encrypt_to_hex("Bug", category="contact")}],
    )
    with patch(
        "app.db.feedback.feedback.supabase_client.table", return_value=mock_table,
    ):
        t = record_feedback_submission(USER_1, "bug", "Bug subject", "Bug message")
        assert t is not None

    mock_table.select.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={
            "id": "ticket_1",
            "subject": encrypt_to_hex("Bug", category="contact"),
            "message": encrypt_to_hex("Details", category="contact"),
        },
    )
    with patch(
        "app.db.feedback.feedback.supabase_client.table", return_value=mock_table,
    ):
        rep = fetch_ticket_report(USER_1, "ticket_1")
        assert rep is not None

    mock_table.select.return_value.eq.return_value.order.return_value.execute.return_value = MagicMock(
        data=[{"id": "ticket_1", "subject": encrypt_to_hex("Bug", category="contact")}],
    )
    with patch(
        "app.db.feedback.feedback.supabase_client.table", return_value=mock_table,
    ):
        tickets = fetch_user_tickets(USER_1)
        assert len(tickets) == 1

    mock_table.update.return_value.eq.return_value.eq.return_value.neq.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": "ticket_1", "status": "closed"}],
    )
    with patch(
        "app.db.feedback.feedback.supabase_client.table", return_value=mock_table,
    ):
        cl = close_ticket(USER_1, "ticket_1", "Resolved issue")
        assert cl is not None

    mock_table.insert.return_value.execute.return_value = MagicMock(data=[{"id": "c1"}])
    with patch(
        "app.db.feedback.feedback.supabase_client.table", return_value=mock_table,
    ):
        add_ticket_comment("ticket_1", USER_1, "Comment text")

    # 2. spotify.py
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[
            {
                "user_id": USER_1,
                "spotify_user_id": "spot123",
                "refresh_token": encrypt_to_hex("refresh_tok_secret", category="oauth"),
                "disconnected_at": None,
            },
        ],
    )
    with patch("app.db.spotify.supabase_client.table", return_value=mock_table):
        conn = get_connection(USER_1)
        assert conn is not None
        tok = get_decrypted_refresh_token(USER_1)
        assert tok == "refresh_tok_secret"

    mock_table.upsert.return_value.execute.return_value = MagicMock(
        data=[{"user_id": USER_1}],
    )
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[{"user_id": USER_1}],
    )
    with patch("app.db.spotify.supabase_client.table", return_value=mock_table):
        upsert_connection(USER_1, "spot123", "refresh_tok_secret", "user-top-read")
        mark_sync_result(USER_1, "success")
        persist_artist_signals(USER_1, {"Queen": 0.95}, ["Queen"])
        disconnect(USER_1)


def test_db_feedback_spotify_safety():
    from app.db.feedback.feedback import (
        add_ticket_comment,
        close_ticket,
        fetch_ticket_comments,
        fetch_ticket_report,
        fetch_ticket_status_history,
        fetch_user_email,
        fetch_user_tickets,
        record_feedback_submission,
    )
    from app.db.safety.sessions import (
        cancel_safety_escalation,
        fetch_overdue_safety_sessions,
        fetch_safety_session,
    )
    from app.db.spotify import (
        disconnect,
        get_connection,
        mark_sync_result,
        upsert_connection,
    )

    mock_row: dict[str, Any] = {
        "id": REPORT_1,
        "user_id": USER_1,
        "status": "open",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "access_token": "\\x6161",
        "refresh_token": "\\x6262",
        "next_checkin_at": datetime.now(timezone.utc).isoformat(),
        "escalations_sent": 0,
    }
    mock_t = _make_chaining_mock([mock_row])

    with (
        patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_t),
        patch("app.db.spotify.supabase_client.table", return_value=mock_t),
        patch("app.db.safety.sessions.supabase_client.table", return_value=mock_t),
    ):
        record_feedback_submission(
            USER_1, "help", "Subject", "Message", contact_email="a@b.com",
        )
        fetch_user_tickets(USER_1)
        fetch_ticket_report(USER_1, REPORT_1)
        fetch_ticket_status_history(REPORT_1)
        fetch_ticket_comments(REPORT_1)
        add_ticket_comment(REPORT_1, USER_1, "Comment")
        close_ticket(USER_1, REPORT_1, "resolved")
        fetch_user_email(USER_1)

        upsert_connection(USER_1, "spotify_id", "refresh_tok", "user-top-read")
        get_connection(USER_1)
        mark_sync_result(USER_1, "success")
        disconnect(USER_1)

        fetch_safety_session("s1")
        fetch_overdue_safety_sessions(60)
        cancel_safety_escalation(USER_1, "s1", "safe", "all good")


def test_db_feedback_error_branches():
    from app.db.feedback.feedback import (
        add_ticket_comment,
        close_ticket,
        fetch_ticket_comments,
        fetch_ticket_report,
        fetch_ticket_status_history,
        fetch_user_tickets,
        record_feedback_submission,
    )

    err_table = MagicMock()
    err_table.select.return_value = err_table
    err_table.insert.return_value = err_table
    err_table.update.return_value = err_table
    err_table.eq.return_value = err_table
    err_table.neq.return_value = err_table
    err_table.order.return_value = err_table
    err_table.execute.side_effect = APIError({"message": "DB Error", "code": "500"})

    single_mock = MagicMock()
    single_mock.execute.side_effect = APIError(
        {"message": "DB Single Error", "code": "500"},
    )
    err_table.maybe_single.return_value = single_mock
    err_table.single.return_value = single_mock

    mock_client = MagicMock()
    mock_client.table.return_value = err_table

    with patch("app.db.feedback.feedback.supabase_client", mock_client):
        with pytest.raises(DatabaseAccessError):
            record_feedback_submission(
                USER_1, "general", "Sub", "Msg", None, None, "1.0", "ios", None,
            )

        with pytest.raises(DatabaseAccessError):
            fetch_user_tickets(USER_1)

        with pytest.raises(DatabaseAccessError):
            fetch_ticket_report(USER_1, REPORT_1)

        with pytest.raises(DatabaseAccessError):
            fetch_ticket_status_history(REPORT_1)

        with pytest.raises(DatabaseAccessError):
            fetch_ticket_comments(REPORT_1)

        with pytest.raises(DatabaseAccessError):
            add_ticket_comment(REPORT_1, USER_1, "Comment")

        with pytest.raises(DatabaseAccessError):
            close_ticket(USER_1, REPORT_1, "closing reason")
