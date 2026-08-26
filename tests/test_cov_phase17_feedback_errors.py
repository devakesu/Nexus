"""Phase 17 Feedback & Tickets Database Error Coverage Suite.

Targeting error and exception branches in app/db/feedback/feedback.py.
"""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
from app.db.client import DatabaseAccessError
from postgrest.exceptions import APIError

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
REPORT_1 = "00000000-0000-0000-0000-000000000050"


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
    single_mock.execute.side_effect = APIError({"message": "DB Single Error", "code": "500"})
    err_table.maybe_single.return_value = single_mock
    err_table.single.return_value = single_mock

    mock_client = MagicMock()
    mock_client.table.return_value = err_table

    with patch("app.db.feedback.feedback.supabase_client", mock_client):
        with pytest.raises(DatabaseAccessError):
            record_feedback_submission(USER_1, "general", "Sub", "Msg", None, None, "1.0", "ios", None)

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
