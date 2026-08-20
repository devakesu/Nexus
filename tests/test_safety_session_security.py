from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request

from app.api.safety.endpoints import cancel_escalation, checkin_session, start_session
from app.models import SafetySessionCheckinRequest, SafetySessionStartRequest


@pytest.mark.anyio
async def test_start_session_past_checkin_rejected() -> None:
    now = datetime.now(timezone.utc)
    payload = SafetySessionStartRequest(
        interval_seconds=1800,
        next_checkin_at=now - timedelta(minutes=5),
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await start_session(
            request=request,
            payload=payload,
            user_id="user-123",
        )

    assert exc_info.value.status_code == 400
    assert "next_checkin_at must be in the future." in exc_info.value.detail


@pytest.mark.anyio
async def test_checkin_session_past_checkin_rejected() -> None:
    now = datetime.now(timezone.utc)
    payload = SafetySessionCheckinRequest(
        session_id="11111111-1111-1111-1111-111111111111",
        next_checkin_at=now - timedelta(seconds=30),
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await checkin_session(
            request=request,
            payload=payload,
            user_id="user-123",
        )

    assert exc_info.value.status_code == 400
    assert "next_checkin_at must be in the future." in exc_info.value.detail


@pytest.mark.anyio
@patch("app.api.safety.endpoints.heartbeat_safety_session")
async def test_checkin_session_future_checkin_succeeds(
    mock_heartbeat: MagicMock,
) -> None:
    now = datetime.now(timezone.utc)
    future_time = now + timedelta(minutes=30)
    mock_heartbeat.return_value = {"id": "11111111-1111-1111-1111-111111111111"}

    payload = SafetySessionCheckinRequest(
        session_id="11111111-1111-1111-1111-111111111111",
        next_checkin_at=future_time,
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await checkin_session(
        request=request,
        payload=payload,
        user_id="user-123",
    )

    assert res == {"ok": True}
    mock_heartbeat.assert_called_once_with(
        "user-123",
        "11111111-1111-1111-1111-111111111111",
        future_time.isoformat(),
        None,
        None,
    )


@pytest.mark.anyio
@patch("app.api.safety.endpoints.verify_escalation_cancel_token")
@patch("app.api.safety.endpoints.fetch_safety_session")
@patch("app.api.safety.endpoints.cancel_safety_escalation")
async def test_cancel_escalation_valid_note(
    mock_cancel: MagicMock,
    mock_fetch: MagicMock,
    mock_verify: MagicMock,
) -> None:
    mock_verify.return_value = 1
    mock_fetch.return_value = {
        "id": "11111111-1111-1111-1111-111111111111",
        "user_id": "user-123",
        "escalations_sent": 1,
        "escalation_cancelled_at": None,
    }

    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await cancel_escalation(
        request=request,
        session_id="11111111-1111-1111-1111-111111111111",
        token="valid-token",
        reason="safe",
        note="User checked in via phone call.",
    )

    assert res.status_code == 200
    mock_cancel.assert_called_once_with(
        "user-123",
        "11111111-1111-1111-1111-111111111111",
        "safe",
        "User checked in via phone call.",
    )


@pytest.mark.anyio
@patch("app.api.safety.endpoints.verify_escalation_cancel_token")
@patch("app.api.safety.endpoints.fetch_safety_session")
@patch("app.api.safety.endpoints.cancel_safety_escalation")
@patch("app.api.safety.endpoints.redis_client.set", new_callable=AsyncMock)
async def test_cancel_escalation_replay_rejected(
    mock_redis_set: AsyncMock,
    mock_cancel: MagicMock,
    mock_fetch: MagicMock,
    mock_verify: MagicMock,
) -> None:
    mock_verify.return_value = 1
    # Redis set with NX returns None/False when key already exists (token already consumed)
    mock_redis_set.return_value = None

    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await cancel_escalation(
        request=request,
        session_id="11111111-1111-1111-1111-111111111111",
        token="replayed-token",
        reason="safe",
        note=None,
    )

    assert res.status_code == 400
    assert b"already been used" in res.body
    mock_cancel.assert_not_called()
    mock_fetch.assert_not_called()


@pytest.mark.anyio
@patch("app.api.safety.endpoints.verify_escalation_cancel_token")
@patch("app.api.safety.endpoints.fetch_safety_session")
@patch("app.api.safety.endpoints.cancel_safety_escalation")
async def test_cancel_escalation_missing_user_id(
    mock_cancel: MagicMock,
    mock_fetch: MagicMock,
    mock_verify: MagicMock,
) -> None:
    mock_verify.return_value = 1
    mock_fetch.return_value = {
        "id": "11111111-1111-1111-1111-111111111111",
        "user_id": None,
        "escalations_sent": 1,
        "escalation_cancelled_at": None,
    }

    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await cancel_escalation(
        request=request,
        session_id="11111111-1111-1111-1111-111111111111",
        token="valid-token",
        reason="safe",
        note=None,
    )

    assert res.status_code == 404
    mock_cancel.assert_not_called()


def test_cancel_safety_escalation_db_ownership() -> None:
    from app.db.safety.sessions import cancel_safety_escalation

    mock_builder = MagicMock()
    mock_builder.update.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.is_.return_value = mock_builder
    mock_builder.select.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[{"id": "session-123", "user_id": "user-123"}])

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_builder):
        res = cancel_safety_escalation(
            user_id="user-123",
            session_id="session-123",
            reason="safe",
            note="All good",
        )

    assert res == {"id": "session-123", "user_id": "user-123"}
    mock_builder.update.assert_called_once()
    eq_calls = mock_builder.eq.call_args_list
    assert eq_calls == [
        (("id", "session-123"),),
        (("user_id", "user-123"),),
    ]
    mock_builder.is_.assert_called_once_with("escalation_cancelled_at", "null")


def test_fetch_safety_session_for_user_scopes_by_id_and_user_id() -> None:
    from app.db.safety.sessions import fetch_safety_session_for_user

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.maybe_single.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data={"id": "session-456", "user_id": "user-123"})

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_builder):
        res = fetch_safety_session_for_user(user_id="user-123", session_id="session-456")

    assert res == {"id": "session-456", "user_id": "user-123"}
    mock_builder.select.assert_called_once()
    eq_calls = mock_builder.eq.call_args_list
    assert eq_calls == [
        (("id", "session-456"),),
        (("user_id", "user-123"),),
    ]
    mock_builder.maybe_single.assert_called_once()


def test_fetch_safety_session_portal_scopes_by_id() -> None:
    from app.db.safety.sessions import fetch_safety_session

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.maybe_single.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data={"id": "session-456", "user_id": "user-123"})

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_builder):
        res = fetch_safety_session(session_id="session-456")

    assert res == {"id": "session-456", "user_id": "user-123"}
    mock_builder.select.assert_called_once()
    mock_builder.eq.assert_called_once_with("id", "session-456")
    mock_builder.maybe_single.assert_called_once()




def test_register_safety_evidence_encrypts_media_key() -> None:
    from app.core.security.crypto import decrypt_pii
    from app.db.safety.evidence import register_safety_evidence

    mock_builder = MagicMock()
    mock_builder.insert.return_value = mock_builder
    mock_builder.select.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[{"id": "ev-123"}])

    with patch("app.db.safety.evidence.supabase_client.table", return_value=mock_builder):
        res = register_safety_evidence(
            user_id="user-123",
            alert_id="alert-456",
            storage_path="user-123/alert-456/segment_0.m4a",
            media_key_base64="dGVzdC1rZXktYmFzZTY0",
            content_type="audio/mp4",
            duration_seconds=15.0,
        )

    assert res == {"id": "ev-123"}
    mock_builder.insert.assert_called_once()
    insert_payload = mock_builder.insert.call_args[0][0]
    # Verify the stored key is encrypted hex, and decrypts back to original key
    stored_key = insert_payload["media_key_base64"]
    assert stored_key.startswith("\\x")
    assert decrypt_pii(stored_key) == "dGVzdC1rZXktYmFzZTY0"


def test_fetch_evidence_decrypts_media_key() -> None:
    from app.core.security.crypto import encrypt_to_hex
    from app.db.safety.evidence import fetch_evidence_for_alert_ids

    raw_key = "YWVzLWdjbS1zZWNyZXQta2V5"
    encrypted_key = encrypt_to_hex(raw_key)

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.in_.return_value = mock_builder
    mock_builder.order.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(
        data=[
            {
                "id": "ev-123",
                "alert_id": "alert-456",
                "storage_path": "path/seg.m4a",
                "media_key_base64": encrypted_key,
                "content_type": "audio/mp4",
                "duration_seconds": 10.0,
                "created_at": "2026-08-15T00:00:00Z",
            },
        ],
    )

    with patch("app.db.safety.evidence.supabase_client.table", return_value=mock_builder):
        rows = fetch_evidence_for_alert_ids(["alert-456"])

    assert len(rows) == 1
    assert rows[0]["media_key_base64"] == raw_key


@pytest.mark.anyio
@patch("app.api.safety.endpoints.end_safety_session")
async def test_end_session_succeeds(mock_end: MagicMock) -> None:
    from app.api.safety.endpoints import end_session
    from app.models import SafetySessionEndRequest

    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/safety/session/end",
    }
    request = Request(scope)
    payload = SafetySessionEndRequest(session_id="11111111-1111-1111-1111-111111111111")

    res = await end_session(
        request=request,
        payload=payload,
        user_id="user-123",
    )
    assert res == {"ok": True}
    mock_end.assert_called_once_with("user-123", "11111111-1111-1111-1111-111111111111")


def test_safety_endpoints_enforce_replay_protected_app_check() -> None:
    from fastapi.routing import APIRoute

    from app.api.dependencies import (
        verify_app_check_with_replay_protection,
        verify_app_check_with_strict_replay_protection,
    )
    from app.api.safety.endpoints import router

    strict_endpoints = {
        "/api/v1/safety/alert",
        "/api/v1/safety/evidence",
    }
    standard_endpoints = {
        "/api/v1/safety/session/checkin",
        "/api/v1/safety/session/end",
        "/api/v1/safety/session/start",
    }

    found: set[str] = set()
    for route in router.routes:
        if isinstance(route, APIRoute):
            dep_callables = [d.call for d in route.dependant.dependencies]
            if route.path in strict_endpoints:
                assert verify_app_check_with_strict_replay_protection in dep_callables, (
                    f"Route {route.path} is missing verify_app_check_with_strict_replay_protection"
                )
                found.add(route.path)
            elif route.path in standard_endpoints:
                assert verify_app_check_with_replay_protection in dep_callables, (
                    f"Route {route.path} is missing verify_app_check_with_replay_protection"
                )
                found.add(route.path)

    assert found == (strict_endpoints | standard_endpoints)


def test_sanitize_sms_text_strips_newlines_and_control_chars() -> None:
    from app.core.utils.sms import sanitize_sms_text

    # None and empty
    assert sanitize_sms_text(None) is None
    assert sanitize_sms_text("") is None
    assert sanitize_sms_text("   \n\r\t  ") is None

    # Strips newlines, control chars, and multi-spaces
    malicious = "Alice\n\nDISREGARD: All safe\x00\x1f\r\tPlease wire $500"
    cleaned = sanitize_sms_text(malicious, max_length=100)
    assert cleaned == "Alice DISREGARD: All safe Please wire $500"
    assert "\n" not in cleaned
    assert "\r" not in cleaned
    assert "\x00" not in cleaned

    # Enforces max_length
    assert sanitize_sms_text("A" * 200, max_length=50) == "A" * 50


def test_compose_sos_message_sanitizes_injected_labels() -> None:
    from app.core.utils.sms import compose_sos_message

    injected_name = "Mallory\n🚨 FAKE ALERT 🚨\nIgnore previous texts"
    injected_event = "Coffee\nCRITICAL: Call +19999999999"

    msg = compose_sos_message(
        name=injected_name,
        silent=False,
        location={"lat": 37.7749, "lng": -122.4194},
        event_label=injected_event,
    )

    # Name is sanitized onto the single alert line without newline splitting
    lines = msg.split("\n")
    assert lines[0] == "🚨 Emergency alert from Mallory 🚨 FAKE ALERT 🚨 Ignore previous texts via Nexus."
    # Meetup line contains cleaned event
    assert "Meetup: Coffee CRITICAL: Call +19999999999" in msg


def test_record_safety_escalation_sent_optimistic_locking_success() -> None:
    from app.db.safety.sessions import record_safety_escalation_sent

    session_id = "00000000-0000-0000-0000-000000000123"
    mock_builder = MagicMock()
    mock_builder.update.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[{"id": session_id, "escalations_sent": 2}])

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_builder):
        updated = record_safety_escalation_sent(session_id, new_count=2, expected_count=1)

    assert updated is True
    # Verify both .eq("id", session_id) and .eq("escalations_sent", 1) were invoked
    eq_calls = mock_builder.eq.call_args_list
    assert any(c[0] == ("id", session_id) for c in eq_calls)
    assert any(c[0] == ("escalations_sent", 1) for c in eq_calls)


def test_record_safety_escalation_sent_optimistic_locking_mismatch() -> None:
    from app.db.safety.sessions import record_safety_escalation_sent

    session_id = "00000000-0000-0000-0000-000000000123"
    mock_builder = MagicMock()
    mock_builder.update.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    # 0 rows returned because escalations_sent did not match expected_count
    mock_builder.execute.return_value = MagicMock(data=[])

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_builder):
        updated = record_safety_escalation_sent(session_id, new_count=2, expected_count=1)

    assert updated is False


def test_safety_alert_request_sanitizes_labels() -> None:
    from app.models import SafetyAlertRequest

    req = SafetyAlertRequest(
        alert_type="sos_silent",
        session_label="Alice\n\nDISREGARD\x00\r\tTest",
        event_label="Coffee Date\n\x1fSpecial Location",
    )

    assert req.session_label == "Alice DISREGARD Test"
    assert req.event_label == "Coffee Date Special Location"
    assert "\n" not in (req.session_label or "")
    assert "\r" not in (req.session_label or "")
    assert "\x00" not in (req.session_label or "")



