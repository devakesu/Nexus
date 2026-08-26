"""Test coverage suite for DB Safety layers.

Covers:
- app/db/safety/alerts.py
- app/db/safety/contacts.py
- app/db/safety/evidence.py
- app/db/safety/sessions.py
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError

from app.core.security.crypto import encrypt_to_hex
from app.db.safety.alerts import (
    fetch_alerts_for_session,
    fetch_contact_facing_profile_summary,
    fetch_recent_safety_alert,
    fetch_safety_alert,
    purge_expired_safety_evidence,
    purge_safety_data_for_purged_accounts,
    record_safety_alert,
    update_alert_contacts_notified,
)
from app.db.safety.contacts import (
    fetch_safety_contact_by_id,
    fetch_safety_contacts,
    fetch_safety_contacts_with_id,
    remove_safety_contact_self_service,
    sync_safety_contacts,
)
from app.db.safety.evidence import (
    create_evidence_download_url,
    fetch_evidence_for_alert_ids,
    register_safety_evidence,
)
from app.db.safety.sessions import (
    EscalationInProgressError,
    cancel_safety_escalation,
    end_safety_session,
    fetch_overdue_safety_sessions,
    fetch_safety_session,
    fetch_safety_session_for_user,
    heartbeat_safety_session,
    record_safety_escalation_sent,
    start_safety_session,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
ALERT_1 = "00000000-0000-0000-0000-000000000011"
SESSION_1 = "00000000-0000-0000-0000-000000000022"
CONTACT_1 = "00000000-0000-0000-0000-000000000033"


# ==============================================================================
# 1. SAFETY ALERTS & RETENTION PURGES
# ==============================================================================

def test_safety_alerts_and_purges():
    now = datetime.now(timezone.utc)
    mock_table = MagicMock()

    # 1. fetch_contact_facing_profile_summary
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"name": encrypt_to_hex("Alice"), "profile_pic": f"{USER_1}/pic.jpg", "hometown": "NYC", "current_place": "SF"}
    )
    with patch("app.db.safety.alerts.supabase_client.table", return_value=mock_table), \
         patch("app.db.profiles.media.supabase_client.storage.from_"):
        summary = fetch_contact_facing_profile_summary(USER_1)
        assert summary is not None
        assert summary["name"] == "Alice"

    # 2. record_safety_alert & fetch_safety_alert & fetch_recent_safety_alert & update_alert_contacts_notified
    mock_table.insert.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": ALERT_1, "created_at": now.isoformat()}]
    )
    with patch("app.db.safety.alerts.supabase_client.table", return_value=mock_table):
        rec = record_safety_alert(USER_1, "sos", {"lat": 37.77, "lng": -122.41}, session_id=SESSION_1)
        assert rec["id"] == ALERT_1

    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": ALERT_1, "created_at": now.isoformat()}
    )
    with patch("app.db.safety.alerts.supabase_client.table", return_value=mock_table):
        al = fetch_safety_alert(ALERT_1)
        assert al is not None
        assert al["id"] == ALERT_1

    mock_table.select.return_value.eq.return_value.eq.return_value.gte.return_value.order.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": ALERT_1, "contacts_notified": 2, "created_at": now.isoformat()}]
    )
    with patch("app.db.safety.alerts.supabase_client.table", return_value=mock_table):
        rec_al = fetch_recent_safety_alert(USER_1, "sos")
        assert rec_al is not None
        assert rec_al["id"] == ALERT_1

    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": ALERT_1}])
    with patch("app.db.safety.alerts.supabase_client.table", return_value=mock_table):
        update_alert_contacts_notified(ALERT_1, 3)

    # 3. fetch_alerts_for_session
    mock_table.select.return_value.eq.return_value.order.return_value.execute.return_value = MagicMock(
        data=[
            {
                "id": ALERT_1,
                "alert_type": "sos",
                "current_location": encrypt_to_hex(json.dumps({"lat": 37.77, "lng": -122.41}), category="media_escrow"),
                "created_at": now.isoformat(),
            }
        ]
    )
    with patch("app.db.safety.alerts.supabase_client.table", return_value=mock_table):
        session_alerts = fetch_alerts_for_session(SESSION_1)
        assert len(session_alerts) == 1
        assert session_alerts[0]["current_location"] == {"lat": 37.77, "lng": -122.41}

    # 4. purge_expired_safety_evidence & purge_safety_data_for_purged_accounts
    mock_from = MagicMock()
    mock_from.return_value.remove.return_value = []
    mock_table.select.return_value.lt.return_value.execute.return_value = MagicMock(
        data=[{"id": "ev1", "storage_path": "evidence/ev1.m4a"}]
    )
    mock_table.delete.return_value.in_.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.safety.alerts.supabase_client.table", return_value=mock_table), \
         patch("app.db.safety.alerts.supabase_client.storage.from_", mock_from):
        purge_expired_safety_evidence()

    mock_table.select.return_value.not_.return_value.is_.return_value.lte.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_2}]
    )
    with patch("app.db.safety.alerts.supabase_client.table", return_value=mock_table), \
         patch("app.db.safety.alerts.supabase_client.storage.from_", mock_from):
        purge_safety_data_for_purged_accounts()


# ==============================================================================
# 2. SAFETY CONTACTS TESTS
# ==============================================================================

def test_safety_contacts_crud():
    mock_table = MagicMock()

    # 1. sync_safety_contacts
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(
        data={"blocked_indices": [], "newly_notified_indices": []}
    )
    with patch("app.db.safety.contacts.supabase_client.rpc", return_value=mock_rpc):
        blocked, notified = sync_safety_contacts(
            USER_1,
            [{"name": "Mom", "phone": "+15551234567"}],
        )
        assert blocked == []
        assert notified == []

    # >3 contacts -> ValueError
    with pytest.raises(ValueError):
        sync_safety_contacts(USER_1, [{"phone": "1"}, {"phone": "2"}, {"phone": "3"}, {"phone": "4"}])

    # 2. fetch_safety_contacts & fetch_safety_contacts_with_id & fetch_safety_contact_by_id
    mock_table.select.return_value.eq.return_value.execute.side_effect = lambda: MagicMock(
        data=[{"id": CONTACT_1, "name": encrypt_to_hex("Dad", category="contact"), "phone": encrypt_to_hex("+15559876543", category="contact")}]
    )
    with patch("app.db.safety.contacts.supabase_client.table", return_value=mock_table):
        c_list = fetch_safety_contacts(USER_1)
        assert len(c_list) == 1
        assert c_list[0]["name"] == "Dad"

        c_with_id = fetch_safety_contacts_with_id(USER_1)
        assert len(c_with_id) == 1
        assert c_with_id[0]["id"] == CONTACT_1

    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": CONTACT_1, "user_id": USER_1, "name": encrypt_to_hex("Dad", category="contact"), "phone": encrypt_to_hex("+15559876543", category="contact")}
    )
    with patch("app.db.safety.contacts.supabase_client.table", return_value=mock_table):
        c_item = fetch_safety_contact_by_id(CONTACT_1)
        assert c_item is not None
        assert c_item["name"] == "Dad"

    # 3. remove_safety_contact_self_service
    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[{"id": "not1"}])
    mock_table.delete.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": CONTACT_1}])
    with patch("app.db.safety.contacts.fetch_safety_contact_by_id", return_value={"id": CONTACT_1, "user_id": USER_1, "name": "Dad", "phone": "+15551234567"}), \
         patch("app.db.safety.contacts.supabase_client.table", return_value=mock_table):
        rem = remove_safety_contact_self_service(CONTACT_1)
        assert rem is not None
        assert rem["name"] == "Dad"


# ==============================================================================
# 3. SAFETY EVIDENCE TESTS
# ==============================================================================

def test_safety_evidence_ops():
    mock_table = MagicMock()

    # 1. register_safety_evidence
    mock_table.insert.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": "ev1"}]
    )
    with patch("app.db.safety.evidence.supabase_client.table", return_value=mock_table):
        ev = register_safety_evidence(
            user_id=USER_1,
            alert_id=ALERT_1,
            storage_path="evidence/audio.m4a",
            media_key_base64="test_key_base64",
            content_type="audio/mp4",
            duration_seconds=15.0,
        )
        assert ev["id"] == "ev1"

    # 2. fetch_evidence_for_alert_ids
    mock_table.select.return_value.in_.return_value.order.return_value.execute.return_value = MagicMock(
        data=[
            {
                "id": "ev1",
                "alert_id": ALERT_1,
                "storage_path": "evidence/audio.m4a",
                "media_key_base64": encrypt_to_hex("test_key_base64", category="media_escrow"),
                "content_type": "audio/mp4",
            }
        ]
    )
    with patch("app.db.safety.evidence.supabase_client.table", return_value=mock_table):
        evs = fetch_evidence_for_alert_ids([ALERT_1])
        assert len(evs) == 1
        assert evs[0]["media_key_base64"] == "test_key_base64"

    # 3. create_evidence_download_url
    mock_from = MagicMock()
    mock_from.return_value.create_signed_url.return_value = {"signedURL": "https://signed.url/ev.m4a"}
    with patch("app.db.safety.evidence.supabase_client.storage.from_", mock_from):
        url = create_evidence_download_url("evidence/audio.m4a", expires_in=3600)
        assert url == "https://signed.url/ev.m4a"


# ==============================================================================
# 4. SAFETY SESSIONS & ESCALATION LIFECYCLE
# ==============================================================================

def test_safety_sessions_lifecycle():
    now = datetime.now(timezone.utc)
    mock_table = MagicMock()

    # 1. start_safety_session
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(
        data={
            "id": SESSION_1,
            "user_id": USER_1,
            "label": encrypt_to_hex("Coffee Meetup", category="media_escrow"),
            "interval_seconds": 900,
            "next_checkin_at": (now + timedelta(minutes=15)).isoformat(),
            "event_context": encrypt_to_hex(json.dumps({"match_name": "Bob"}), category="media_escrow"),
            "status": "active",
        }
    )
    with patch("app.db.safety.sessions.supabase_client.rpc", return_value=mock_rpc):
        sess = start_safety_session(
            user_id=USER_1,
            label="Coffee Meetup",
            interval_seconds=900,
            next_checkin_at=(now + timedelta(minutes=15)).isoformat(),
            event_context={"match_name": "Bob"},
            battery_percent=85,
            connection_type="wifi",
        )
        assert sess["id"] == SESSION_1
        assert sess["label"] == "Coffee Meetup"
        assert sess["event_context"]["match_name"] == "Bob"

    # Escalation already in progress -> EscalationInProgressError
    mock_rpc.execute.side_effect = APIError({"message": "escalation already in progress"})
    with patch("app.db.safety.sessions.supabase_client.rpc", return_value=mock_rpc):
        with pytest.raises(EscalationInProgressError):
            start_safety_session(USER_1, None, 900, now.isoformat(), None, None, None)

    # 2. heartbeat_safety_session
    mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[{"id": SESSION_1, "next_checkin_at": now.isoformat(), "escalations_sent": 0, "last_escalated_at": None}]
    )
    mock_table.update.return_value.eq.return_value.eq.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": SESSION_1, "status": "active", "label": encrypt_to_hex("Coffee", category="media_escrow")}]
    )
    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_table):
        hb = heartbeat_safety_session(
            user_id=USER_1,
            session_id=SESSION_1,
            next_checkin_at=(now + timedelta(minutes=15)).isoformat(),
            battery_percent=80,
            connection_type="cellular",
        )
        assert hb is not None

    # 3. end_safety_session & fetch_overdue_safety_sessions
    mock_table.update.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": SESSION_1}])
    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_table):
        end_safety_session(USER_1, SESSION_1)

    mock_table.select.return_value.eq.return_value.is_.return_value.eq.return_value.eq.return_value.is_.return_value.is_.return_value.lt.return_value.lt.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[
            {
                "id": SESSION_1,
                "status": "active",
                "label": encrypt_to_hex("Coffee", category="media_escrow"),
                "users": {"is_active": True},
            }
        ]
    )
    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_table):
        overdue = fetch_overdue_safety_sessions(grace_seconds=120)
        assert len(overdue) == 1
        assert overdue[0]["id"] == SESSION_1

    # 4. record_safety_escalation_sent & fetch_safety_session & fetch_safety_session_for_user & cancel_safety_escalation
    mock_table.update.return_value.eq.return_value.lt.return_value.execute.return_value = MagicMock(data=[{"id": SESSION_1}])
    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_table):
        assert record_safety_escalation_sent(SESSION_1, 1) is True

    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": SESSION_1, "label": encrypt_to_hex("Coffee", category="media_escrow")}
    )
    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_table):
        fs = fetch_safety_session(SESSION_1)
        assert fs is not None
        assert fs["label"] == "Coffee"

    mock_table.select.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": SESSION_1, "user_id": USER_1, "label": encrypt_to_hex("Coffee", category="media_escrow")}
    )
    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_table):
        fsu = fetch_safety_session_for_user(USER_1, SESSION_1)
        assert fsu is not None

    mock_table.update.return_value.eq.return_value.eq.return_value.is_.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": SESSION_1, "label": encrypt_to_hex("Coffee", category="media_escrow")}]
    )
    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_table):
        canc = cancel_safety_escalation(USER_1, SESSION_1, reason="false_alarm", note="I am safe")
        assert canc is not None
