from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request

from app.api.chat.events import create_chat_event
from app.core.config import settings
from app.models import CreateEventRequest


@pytest.mark.anyio
@patch("app.api.chat.events.fetch_conversation_participants")
@patch("app.api.chat.events.create_event_with_message")
@patch("app.api.chat.events.send_chat_message_notification")
@patch("app.api.chat.events.get_cached_public_user")
async def test_create_chat_event_safety_disabled_skips_consent(
    mock_get_cached_user: AsyncMock,
    _mock_notify: MagicMock,
    mock_create_event: MagicMock,
    mock_fetch_convo: MagicMock,
) -> None:
    mock_fetch_convo.return_value = {
        "user_a_id": "user-a",
        "user_b_id": "user-b",
        "closed_at": None,
        "tab": "Dating",
    }
    mock_create_event.return_value = {
        "message": {
            "id": "msg-1",
            "created_at": "2026-08-15T12:00:00Z",
        },
        "event": {
            "id": "evt-1",
            "event_time": "2026-08-16T18:00:00Z",
            "status": "proposed",
        },
    }

    payload = CreateEventRequest(
        event_time=datetime.now(timezone.utc),
        ciphertext="c2VjcmV0",
        safety_enabled=False,
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await create_chat_event(
        request=request,
        conversation_id="convo-1",
        payload=payload,
        user_id="user-a",
    )

    assert res.event_id == "evt-1"
    mock_get_cached_user.assert_not_called()


@pytest.mark.anyio
@patch("app.api.chat.events.fetch_conversation_participants")
@patch("app.api.chat.events.create_event_with_message")
@patch("app.api.chat.events.send_chat_message_notification")
@patch("app.api.chat.events.get_cached_public_user")
async def test_create_chat_event_safety_enabled_uses_cache_and_verifies_consent(
    mock_get_cached_user: AsyncMock,
    _mock_notify: MagicMock,
    mock_create_event: MagicMock,
    mock_fetch_convo: MagicMock,
) -> None:
    mock_fetch_convo.return_value = {
        "user_a_id": "user-a",
        "user_b_id": "user-b",
        "closed_at": None,
        "tab": "Dating",
    }
    mock_get_cached_user.return_value = {
        "id": "user-a",
        "safety_data_consent_version": settings.current_terms_version,
        "is_active": True,
    }
    mock_create_event.return_value = {
        "message": {
            "id": "msg-1",
            "created_at": "2026-08-15T12:00:00Z",
        },
        "event": {
            "id": "evt-1",
            "event_time": "2026-08-16T18:00:00Z",
            "status": "proposed",
        },
    }

    payload = CreateEventRequest(
        event_time=datetime.now(timezone.utc),
        ciphertext="c2VjcmV0",
        safety_enabled=True,
        safety_interval_seconds=1800,
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await create_chat_event(
        request=request,
        conversation_id="convo-1",
        payload=payload,
        user_id="user-a",
    )

    assert res.event_id == "evt-1"
    mock_get_cached_user.assert_called_once_with("user-a")


@pytest.mark.anyio
@patch("app.api.chat.events.fetch_conversation_participants")
@patch("app.api.chat.events.get_cached_public_user")
async def test_create_chat_event_safety_enabled_missing_consent_raises_412(
    mock_get_cached_user: AsyncMock,
    mock_fetch_convo: MagicMock,
) -> None:
    mock_fetch_convo.return_value = {
        "user_a_id": "user-a",
        "user_b_id": "user-b",
        "closed_at": None,
        "tab": "Dating",
    }
    mock_get_cached_user.return_value = {
        "id": "user-a",
        "safety_data_consent_version": None,
        "is_active": True,
    }

    payload = CreateEventRequest(
        event_time=datetime.now(timezone.utc),
        ciphertext="c2VjcmV0",
        safety_enabled=True,
        safety_interval_seconds=1800,
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await create_chat_event(
            request=request,
            conversation_id="convo-1",
            payload=payload,
            user_id="user-a",
        )

    assert exc_info.value.status_code == 412
    assert exc_info.value.detail == "safety_consent_required"


def test_validate_event_status_transition_rules() -> None:
    from app.api.chat.events import _validate_event_status_transition

    # 1. Proposer cannot confirm their own proposed event
    with pytest.raises(HTTPException) as exc_info:
        _validate_event_status_transition(
            current_status="proposed",
            new_status="confirmed",
            user_id="creator-1",
            created_by="creator-1",
        )
    assert exc_info.value.status_code == 400
    assert "Proposer cannot confirm" in exc_info.value.detail

    # 2. Responder can confirm a proposed event
    _validate_event_status_transition(
        current_status="proposed",
        new_status="confirmed",
        user_id="responder-2",
        created_by="creator-1",
    )

    # 3. Disallow reverting to proposed
    with pytest.raises(HTTPException) as exc_info:
        _validate_event_status_transition(
            current_status="confirmed",
            new_status="proposed",
            user_id="responder-2",
            created_by="creator-1",
        )
    assert exc_info.value.status_code == 400
    assert "Cannot revert event to proposed status" in exc_info.value.detail

    # 4. Either participant can cancel proposed or confirmed event
    _validate_event_status_transition(
        current_status="proposed",
        new_status="cancelled",
        user_id="creator-1",
        created_by="creator-1",
    )
    _validate_event_status_transition(
        current_status="confirmed",
        new_status="cancelled",
        user_id="responder-2",
        created_by="creator-1",
    )

    # 5. Cannot update already cancelled event
    with pytest.raises(HTTPException) as exc_info:
        _validate_event_status_transition(
            current_status="cancelled",
            new_status="confirmed",
            user_id="responder-2",
            created_by="creator-1",
        )
    assert exc_info.value.status_code == 400
    assert "Cannot update status of a cancelled event" in exc_info.value.detail


def test_create_event_with_message_encrypts_location_and_time_at_rest() -> None:
    from app.core.security.crypto import decrypt_pii
    from app.db.chat.chat import create_event_with_message

    inserted_payload: dict[str, Any] = {}

    def fake_insert(payload: dict[str, Any]) -> Any:
        nonlocal inserted_payload
        inserted_payload = payload
        mock_execute = MagicMock()
        mock_execute.execute.return_value = MagicMock(
            data=[
                {
                    "id": "evt-123",
                    "conversation_id": payload["conversation_id"],
                    "message_id": payload["message_id"],
                    "created_by": payload["created_by"],
                    "event_time": payload["event_time"],
                    "location_lat": payload["location_lat"],
                    "location_lng": payload["location_lng"],
                    "location_label": payload["location_label"],
                    "status": "proposed",
                    "safety_enabled": payload["safety_enabled"],
                    "safety_interval_seconds": payload["safety_interval_seconds"],
                },
            ],
        )
        return mock_execute

    with (
        patch("app.db.chat.chat.insert_message", return_value={"id": "msg-123", "created_at": "2026-08-24T12:00:00Z"}),
        patch("app.db.chat.chat.supabase_client") as mock_supabase,
    ):
        mock_table = MagicMock()
        mock_table.insert = fake_insert
        mock_supabase.table.return_value = mock_table

        event_time = datetime(2026, 8, 25, 18, 30, 0, tzinfo=timezone.utc)
        lat = 37.7749
        lng = -122.4194
        label = "Central Park Cafe"

        result = create_event_with_message(
            conversation_id="convo-abc",
            sender_id="user-123",
            ciphertext="enc-msg",
            ciphertext_metadata={"v": 1},
            event_time=event_time,
            location_lat=lat,
            location_lng=lng,
            location_label=label,
        )

        # Verify DB insert payload contains encrypted hex values, NOT plaintext
        assert inserted_payload["location_lat"] != str(lat)
        assert inserted_payload["location_lat"] != lat
        assert inserted_payload["location_lng"] != str(lng)
        assert inserted_payload["location_lng"] != lng
        assert inserted_payload["location_label"] != label
        assert inserted_payload["event_time"] != event_time.isoformat()

        # Verify they can be decrypted with decrypt_pii
        assert float(decrypt_pii(inserted_payload["location_lat"])) == lat
        assert float(decrypt_pii(inserted_payload["location_lng"])) == lng
        assert decrypt_pii(inserted_payload["location_label"]) == label
        assert decrypt_pii(inserted_payload["event_time"]) == event_time.isoformat()

        # Verify returned result is properly decrypted
        assert result["event"]["location_lat"] == lat
        assert result["event"]["location_lng"] == lng
        assert result["event"]["location_label"] == label
        assert result["event"]["event_time"] == event_time


def test_decrypt_event_row_handles_encrypted_and_empty_fields() -> None:
    from app.core.security.crypto import encrypt_to_hex
    from app.db.chat.chat import decrypt_event_row

    encrypted_row = {
        "id": "evt-456",
        "event_time": encrypt_to_hex("2026-08-25T19:00:00+00:00"),
        "location_lat": encrypt_to_hex("40.7128"),
        "location_lng": encrypt_to_hex("-74.0060"),
        "location_label": encrypt_to_hex("Empire State Building"),
    }

    decrypted = decrypt_event_row(dict(encrypted_row))
    assert decrypted is not None
    assert decrypted["location_lat"] == 40.7128
    assert decrypted["location_lng"] == -74.0060
    assert decrypted["location_label"] == "Empire State Building"
    assert decrypted["event_time"] == datetime(2026, 8, 25, 19, 0, 0, tzinfo=timezone.utc)

    # Empty/None fields
    empty_row = {
        "id": "evt-789",
        "event_time": None,
        "location_lat": None,
        "location_lng": None,
        "location_label": None,
    }
    decrypted_empty = decrypt_event_row(dict(empty_row))
    assert decrypted_empty is not None
    assert decrypted_empty["location_lat"] is None
    assert decrypted_empty["location_lng"] is None
    assert decrypted_empty["location_label"] is None

