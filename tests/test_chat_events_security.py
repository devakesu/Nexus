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
