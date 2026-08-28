"""Unit tests for reminder scheduler resilience, distributed locks, and error recovery."""

from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.db.client import DatabaseAccessError
from app.services.reminder_scheduler import (
    _check_due_reminders,
    _check_overdue_safety_sessions,
    _check_upcoming_safety_reminders,
    _run_account_deletion_long_tail_purge,
    _run_account_deletion_purge,
    _run_blocklist_expiry,
    _run_safety_data_legal_hold_purge,
    _run_safety_evidence_retention_purge,
)


def _mock_redis_lock_acquired() -> MagicMock:
    mock_lock = MagicMock()
    mock_lock.acquire = AsyncMock(return_value=True)
    mock_lock.release = AsyncMock(return_value=None)
    return mock_lock


@pytest.mark.anyio
async def test_maintenance_purges_database_access_error_handling():
    """All 5 maintenance jobs should catch DatabaseAccessError, report to Sentry, and not crash."""
    with patch("app.services.reminder_scheduler.redis_client.lock", return_value=_mock_redis_lock_acquired()):
        with patch(
            "app.services.reminder_scheduler.purge_due_accounts",
            side_effect=DatabaseAccessError("DB error"),
        ):
            with patch("app.services.reminder_scheduler.sentry_sdk.capture_exception") as mock_sentry:
                await _run_account_deletion_purge()
                mock_sentry.assert_called_once()

        with patch(
            "app.services.reminder_scheduler.expire_blocklist_entries",
            side_effect=DatabaseAccessError("DB error"),
        ):
            with patch("app.services.reminder_scheduler.sentry_sdk.capture_exception") as mock_sentry:
                await _run_blocklist_expiry()
                mock_sentry.assert_called_once()

        with patch(
            "app.services.reminder_scheduler.hard_purge_long_tail_accounts",
            side_effect=DatabaseAccessError("DB error"),
        ):
            with patch("app.services.reminder_scheduler.sentry_sdk.capture_exception") as mock_sentry:
                await _run_account_deletion_long_tail_purge()
                mock_sentry.assert_called_once()

        with patch(
            "app.services.reminder_scheduler.purge_expired_safety_evidence",
            side_effect=DatabaseAccessError("DB error"),
        ):
            with patch("app.services.reminder_scheduler.sentry_sdk.capture_exception") as mock_sentry:
                await _run_safety_evidence_retention_purge()
                mock_sentry.assert_called_once()

        with patch(
            "app.services.reminder_scheduler.purge_safety_data_for_purged_accounts",
            side_effect=DatabaseAccessError("DB error"),
        ):
            with patch("app.services.reminder_scheduler.sentry_sdk.capture_exception") as mock_sentry:
                await _run_safety_data_legal_hold_purge()
                mock_sentry.assert_called_once()


@pytest.mark.anyio
async def test_check_upcoming_reminders_edge_cases():
    """Test upcoming reminders handling missing conversation and DatabaseAccessError."""
    # 1. DB error in fetch_due_event_reminders
    with patch("app.services.reminder_scheduler.redis_client.lock", return_value=_mock_redis_lock_acquired()):
        with patch(
            "app.services.reminder_scheduler.fetch_due_event_reminders",
            side_effect=DatabaseAccessError("Fetch error"),
        ):
            with patch("app.services.reminder_scheduler.sentry_sdk.capture_exception") as mock_sentry:
                await _check_due_reminders()
                mock_sentry.assert_called_once()

        # 2. Iterate through events
        due_events = [
            {"id": "evt-1", "conversation_id": "conv-1", "location_label": "Cafe"},
            {"id": "evt-2", "conversation_id": "conv-2", "location_label": "Park"},
        ]
        with patch("app.services.reminder_scheduler.fetch_due_event_reminders", return_value=due_events):
            with patch("app.services.reminder_scheduler.mark_reminder_sent", return_value=True):
                def fetch_conv_side_effect(conv_id: str) -> dict[str, Any] | None:
                    if conv_id == "conv-1":
                        return None
                    raise DatabaseAccessError("Conv error")

                with patch(
                    "app.services.reminder_scheduler.fetch_conversation_participants",
                    side_effect=fetch_conv_side_effect,
                ):
                    with patch("app.services.reminder_scheduler.sentry_sdk.capture_exception") as mock_sentry:
                        await _check_due_reminders()
                        mock_sentry.assert_called_once()


@pytest.mark.anyio
async def test_check_upcoming_safety_reminders_resilience():
    """Test upcoming meetup safety reminders handling DB error in fetch, already marked, missing conv, and exception."""
    with patch("app.services.reminder_scheduler.redis_client.lock", return_value=_mock_redis_lock_acquired()):
        # 1. DB error in fetch_due_safety_reminders
        with patch(
            "app.services.reminder_scheduler.fetch_due_safety_reminders",
            side_effect=DatabaseAccessError("Fetch error"),
        ):
            with patch("app.services.reminder_scheduler.sentry_sdk.capture_exception") as mock_sentry:
                await _check_upcoming_safety_reminders()
                mock_sentry.assert_called_once()

        # 2. Iterate through events: un-markable, missing conversation, DB error during dispatch
        due_events = [
            {"id": "s-evt-1", "conversation_id": "c-1", "created_by": "u-1"},
            {"id": "s-evt-2", "conversation_id": "c-2", "created_by": "u-1"},
            {"id": "s-evt-3", "conversation_id": "c-3", "created_by": "u-1"},
        ]
        with patch("app.services.reminder_scheduler.fetch_due_safety_reminders", return_value=due_events):
            def mark_side_effect(evt_id: str) -> bool:
                return evt_id != "s-evt-1"

            def fetch_conv_side_effect(conv_id: str) -> dict[str, Any] | None:
                if conv_id == "c-2":
                    return None
                if conv_id == "c-3":
                    raise DatabaseAccessError("Conv error")
                return {"user_a_id": "u-1", "user_b_id": "u-2", "tab": "Dating"}

            with patch("app.services.reminder_scheduler.mark_safety_reminder_sent", side_effect=mark_side_effect):
                with patch(
                    "app.services.reminder_scheduler.fetch_conversation_participants",
                    side_effect=fetch_conv_side_effect,
                ):
                    with patch("app.services.reminder_scheduler.sentry_sdk.capture_exception") as mock_sentry:
                        await _check_upcoming_safety_reminders()
                        mock_sentry.assert_called_once()


@pytest.mark.anyio
async def test_check_overdue_safety_sessions_resilience():
    """Test overdue safety sessions handling DB access error, empty due sessions, and escalation failure."""
    with patch("app.services.reminder_scheduler.redis_client.lock", return_value=_mock_redis_lock_acquired()):
        # 1. DB error in fetch_overdue_safety_sessions
        with patch(
            "app.services.reminder_scheduler.fetch_overdue_safety_sessions",
            side_effect=DatabaseAccessError("Overdue fetch failed"),
        ):
            with patch("app.services.reminder_scheduler.sentry_sdk.capture_exception") as mock_sentry:
                await _check_overdue_safety_sessions()
                mock_sentry.assert_called_once()

        # 2. No sessions due
        with patch("app.services.reminder_scheduler.fetch_overdue_safety_sessions", return_value=[{"id": "sess-1"}]):
            with patch("app.services.reminder_scheduler._next_escalation_due", return_value=False):
                await _check_overdue_safety_sessions()

        # 3. Session due, escalation raises exception caught by _safe_escalate
        with patch("app.services.reminder_scheduler.fetch_overdue_safety_sessions", return_value=[{"id": "sess-1"}]):
            with patch("app.services.reminder_scheduler._next_escalation_due", return_value=True):
                with patch(
                    "app.services.reminder_scheduler._escalate_safety_session",
                    side_effect=RuntimeError("Escalation dispatch exploded"),
                ):
                    with patch("app.services.reminder_scheduler.sentry_sdk.capture_exception") as mock_sentry:
                        await _check_overdue_safety_sessions()
                        mock_sentry.assert_called_once()
