"""Unit tests verifying transparency/sensitivity annotations in user data export."""

import json
from typing import Any, cast
from unittest.mock import MagicMock, patch

from app.core.security.crypto import encrypt_to_hex
from app.db.users.export import _build_chat_section, _build_safety_alerts


def test_build_safety_alerts_includes_location_sensitivity_note() -> None:
    """Verifies safety alerts with decrypted current_location receive location_sensitivity_note."""
    user_id = "11111111-1111-1111-1111-111111111111"
    raw_loc = {"latitude": 12.9716, "longitude": 77.5946, "accuracy": 15.0}
    encrypted_loc = encrypt_to_hex(json.dumps(raw_loc))

    mock_res = MagicMock()
    mock_res.data = [
        {
            "id": "alert-1",
            "alert_type": "checkin_missed",
            "current_location": encrypted_loc,
            "created_at": "2026-08-20T10:00:00Z",
        },
        {
            "id": "alert-2",
            "alert_type": "sos_triggered",
            "current_location": None,
            "created_at": "2026-08-21T14:00:00Z",
        },
    ]

    table_mock = MagicMock()
    table_mock.select.return_value = table_mock
    table_mock.eq.return_value = table_mock
    table_mock.execute.return_value = mock_res

    with patch("app.db.users.export.supabase_client.table", return_value=table_mock):
        alerts = _build_safety_alerts(user_id)

    assert len(alerts) == 2
    # Alert with location has parsed location dict and sensitivity note
    assert alerts[0]["current_location"] == raw_loc
    assert "location_sensitivity_note" in alerts[0]
    assert "Historical emergency/alert location data" in alerts[0]["location_sensitivity_note"]

    # Alert without location does not have sensitivity note
    assert alerts[1]["current_location"] is None
    assert "location_sensitivity_note" not in alerts[1]


def test_build_chat_section_includes_location_sensitivity_note_on_events() -> None:
    """Verifies chat events with location coordinates receive location_sensitivity_note."""
    user_id = "11111111-1111-1111-1111-111111111111"
    convo_id = "22222222-2222-2222-2222-222222222222"

    convo_res = MagicMock()
    convo_res.data = [{"id": convo_id, "user_a_id": user_id, "user_b_id": "33333333-3333-3333-3333-333333333333"}]

    msg_res = MagicMock()
    msg_res.data = []

    encrypted_lat = encrypt_to_hex("12.9716", category="chat")
    encrypted_lng = encrypt_to_hex("77.5946", category="chat")
    encrypted_label = encrypt_to_hex("Blue Tokai Coffee", category="chat")

    event_res = MagicMock()
    event_res.data = [
        {
            "id": "event-1",
            "conversation_id": convo_id,
            "created_by": user_id,
            "event_time": "2026-08-22T15:00:00Z",
            "location_lat": encrypted_lat,
            "location_lng": encrypted_lng,
            "location_label": encrypted_label,
            "status": "confirmed",
            "created_at": "2026-08-20T12:00:00Z",
        },
        {
            "id": "event-2",
            "conversation_id": convo_id,
            "created_by": user_id,
            "event_time": "2026-08-23T16:00:00Z",
            "location_lat": None,
            "location_lng": None,
            "location_label": None,
            "status": "cancelled",
            "created_at": "2026-08-21T12:00:00Z",
        },
    ]

    def mock_table(table_name: str) -> MagicMock:
        t = MagicMock()
        if table_name == "chat_conversations":
            t.select.return_value.or_.return_value.execute.return_value = convo_res
        elif table_name == "chat_messages":
            t.select.return_value.in_.return_value.execute.return_value = msg_res
        elif table_name == "chat_events":
            t.select.return_value.in_.return_value.execute.return_value = event_res
        elif table_name == "chat_presence":
            t.select.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
        return t

    with patch("app.db.users.export.supabase_client.table", side_effect=mock_table):
        chat_data = _build_chat_section(user_id)

    events = cast(list[dict[str, Any]], chat_data.get("events") or [])
    assert len(events) == 2

    # Event with coordinates has decrypted values and sensitivity note
    assert events[0]["location_lat"] == 12.9716
    assert events[0]["location_lng"] == 77.5946
    assert events[0]["location_label"] == "Blue Tokai Coffee"
    assert "location_sensitivity_note" in events[0]
    assert "Precise scheduled meeting location" in events[0]["location_sensitivity_note"]

    # Event without coordinates does not have sensitivity note
    assert events[1]["location_lat"] is None
    assert "location_sensitivity_note" not in events[1]
