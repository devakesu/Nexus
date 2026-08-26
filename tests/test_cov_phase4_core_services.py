"""Phase 4 Core & Services Layer Coverage Expansion.

Targets:
- app/services/reminder_scheduler.py
- app/services/fcm_sender.py
- app/services/spotify_sync.py
- app/core/infra/tasks.py
- app/core/email/
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
SESS_1 = "00000000-0000-0000-0000-000000000011"


# -----------------------------------------------------------------------------
# 1. SERVICES: REMINDER SCHEDULER
# -----------------------------------------------------------------------------
async def test_reminder_scheduler():
    from app.services.reminder_scheduler import (
        _check_due_reminders,
        _check_overdue_safety_sessions,
        _check_upcoming_safety_reminders,
        _compose_session_unreachable_message,
        _dispatch_escalation_sms_and_record,
        _next_escalation_due,
        _run_account_deletion_long_tail_purge,
        _run_account_deletion_purge,
        _run_blocklist_expiry,
        _run_safety_data_legal_hold_purge,
        _run_safety_evidence_retention_purge,
        start_reminder_scheduler,
    )

    # 1. _check_due_reminders
    with patch("app.services.reminder_scheduler.fetch_due_event_reminders", return_value=[]):
        await _check_due_reminders()

    # 2. _check_upcoming_safety_reminders
    with patch("app.services.reminder_scheduler.fetch_due_safety_reminders", return_value=[]):
        await _check_upcoming_safety_reminders()

    # 3. message composition & escalation checks
    session_dict: dict[str, Any] = {
        "id": SESS_1,
        "user_id": USER_1,
        "escalations_sent": 0,
        "escalation_cancelled_at": None,
        "label": "Coffee date",
        "event_context": {},
    }
    assert _next_escalation_due(session_dict, datetime.now(timezone.utc)) is True
    msg = _compose_session_unreachable_message(session_dict, SESS_1, 1, user_name="Alice")
    assert "Alice" in msg

    # 4. _dispatch_escalation_sms_and_record
    with patch("app.services.reminder_scheduler.record_safety_escalation_sent", return_value=True), \
         patch("app.services.reminder_scheduler.fetch_contact_facing_profile_summary", return_value={"name": "Alice"}), \
         patch("app.services.reminder_scheduler.send_sms", AsyncMock(return_value=MagicMock(success=True))):
        await _dispatch_escalation_sms_and_record([{"id": "c1", "phone": "+15555555555"}], session_dict, SESS_1, 1, "idem_key")

    # 5. _check_overdue_safety_sessions
    with patch("app.services.reminder_scheduler.fetch_overdue_safety_sessions", return_value=[]):
        await _check_overdue_safety_sessions()

    # 6. purges
    with patch("app.services.reminder_scheduler._run_in_maintenance_executor", AsyncMock()):
        await _run_account_deletion_purge()
        await _run_blocklist_expiry()
        await _run_account_deletion_long_tail_purge()
        await _run_safety_evidence_retention_purge()
        await _run_safety_data_legal_hold_purge()

    # 7. start_reminder_scheduler
    sched = start_reminder_scheduler()
    assert sched is not None


# -----------------------------------------------------------------------------
# 2. SERVICES: FCM SENDER
# -----------------------------------------------------------------------------
async def test_fcm_sender():
    from app.services.fcm_sender import (
        _fetch_user_fcm_tokens,
        send_chat_event_reminder_notification,
        send_chat_message_notification,
        send_match_notification,
        send_meetup_safety_reminder_notification,
        send_prekey_replenishment_notification,
    )

    def mock_table_factory(table_name: str):
        mock_t = MagicMock()
        if table_name == "profiles":
            mock_t.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(data=[{"is_deactivated": False}])
        else:
            mock_t.select.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"fcm_token": "fcm_tok_1"}])
        return mock_t

    with patch("app.services.fcm_sender.supabase_client.table", side_effect=mock_table_factory):
        tokens = _fetch_user_fcm_tokens(USER_1)
        assert tokens == ["fcm_tok_1"]

    with patch("app.services.fcm_sender._fetch_user_fcm_tokens", return_value=["tok1"]), \
         patch("app.services.fcm_sender.get_cached_active_block_ids", AsyncMock(return_value=set())), \
         patch("app.services.fcm_sender._fcm.send_each"):
        await send_chat_message_notification(
            sender_id=USER_1,
            recipient_id=USER_2,
            conversation_id="conv_1",
            tab="Dating",
            message_id="msg_1",
            ciphertext="cipher123",
            ciphertext_metadata={},
        )

        await send_match_notification(
            user_a_id=USER_1,
            user_b_id=USER_2,
        )

        await send_chat_event_reminder_notification(
            user_a_id=USER_1,
            user_b_id=USER_2,
            conversation_id="conv_1",
            tab="Dating",
        )

        await send_meetup_safety_reminder_notification(
            user_id=USER_1,
            peer_id=USER_2,
            conversation_id="conv_1",
            tab="Dating",
        )

        await send_prekey_replenishment_notification(USER_1)


# -----------------------------------------------------------------------------
# 3. SERVICES: SPOTIFY SYNC
# -----------------------------------------------------------------------------
async def test_spotify_sync():
    from app.services.spotify_sync import (
        blend_artist_affinity,
        compute_artist_frequency,
        compute_genre_affinity,
        top_display_names,
    )

    # 1. blend and top display names
    native_ranked: dict[str, float] = {"queen": 1.0, "david bowie": 0.8}
    playlist_freq: dict[str, float] = {"Queen": 5.0, "The Beatles": 3.0}
    blended, casing = blend_artist_affinity(native_ranked, playlist_freq)
    assert len(blended) > 0
    assert "queen" in casing

    names = top_display_names(blended, casing, n=2)
    assert len(names) <= 2

    # 2. compute genre affinity
    genre_w = {"rock": 2.0, "pop": 1.0}
    g_aff = compute_genre_affinity(genre_w)
    assert "rock" in g_aff

    # 3. compute artist frequency
    tracks = [
        {"artists": ["Queen"]},
        {"artists": ["Queen", "David Bowie"]},
    ]
    freq = compute_artist_frequency(tracks)
    assert freq["Queen"] == 1.0
    assert freq["David Bowie"] == 0.5


# -----------------------------------------------------------------------------
# 4. CORE INFRA: TASKS & EMAIL
# -----------------------------------------------------------------------------
async def test_core_infra_tasks_and_email():
    from app.core.infra.tasks import safe_create_task
    from app.core.email.config import redact_email, strip_tags

    # 1. tasks
    async def sample_task():
        await asyncio.sleep(0.01)
        return "done"

    t = safe_create_task(sample_task())
    assert t is not None
    await t

    # 2. email redaction & stripping
    assert redact_email("alice@example.com") == "a***e@example.com"
    assert redact_email("invalid") == "invalid"
    assert strip_tags("<h1>Hello</h1>") == "Hello"
