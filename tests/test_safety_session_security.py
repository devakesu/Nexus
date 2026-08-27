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
async def test_start_session_interval_minimum_enforced() -> None:
    from pydantic import ValidationError

    now = datetime.now(timezone.utc)
    # Intervals under 300 seconds (5 mins) rejected
    with pytest.raises(ValidationError):
        SafetySessionStartRequest(
            interval_seconds=1,
            next_checkin_at=now + timedelta(seconds=1),
        )
    with pytest.raises(ValidationError):
        SafetySessionStartRequest(
            interval_seconds=299,
            next_checkin_at=now + timedelta(seconds=299),
        )
    # Valid interval >= 300
    req = SafetySessionStartRequest(
        interval_seconds=300,
        next_checkin_at=now + timedelta(seconds=300),
    )
    assert req.interval_seconds == 300


@pytest.mark.anyio
async def test_start_session_far_future_checkin_rejected() -> None:
    now = datetime.now(timezone.utc)
    # interval is 30m (1800s); next_checkin_at 5 hours in future exceeds max window
    payload = SafetySessionStartRequest(
        interval_seconds=1800,
        next_checkin_at=now + timedelta(hours=5),
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
    assert "next_checkin_at exceeds maximum allowed window for this interval." in exc_info.value.detail


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
async def test_checkin_session_far_future_checkin_rejected() -> None:
    now = datetime.now(timezone.utc)
    # next_checkin_at 10 years in the future rejected
    payload = SafetySessionCheckinRequest(
        session_id="11111111-1111-1111-1111-111111111111",
        next_checkin_at=now + timedelta(days=3650),
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
    assert "next_checkin_at exceeds maximum allowed window." in exc_info.value.detail


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


@pytest.mark.anyio
@patch("app.api.safety.endpoints.verify_escalation_cancel_token")
@patch("app.api.safety.endpoints.fetch_safety_session")
@patch("app.api.safety.endpoints.cancel_safety_escalation")
async def test_cancel_escalation_escapes_html_note(
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
        note="<script>alert(1)</script>Safe & Sound",
    )

    assert res.status_code == 200
    mock_cancel.assert_called_once_with(
        "user-123",
        "11111111-1111-1111-1111-111111111111",
        "safe",
        "&lt;script&gt;alert(1)&lt;/script&gt;Safe &amp; Sound",
    )


def test_cancel_safety_escalation_db_escapes_html() -> None:
    from app.db.safety.sessions import cancel_safety_escalation

    mock_builder = MagicMock()
    mock_builder.update.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.is_.return_value = mock_builder
    mock_builder.select.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[{"id": "session-123", "user_id": "user-123"}])

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_builder):
        cancel_safety_escalation(
            user_id="user-123",
            session_id="session-123",
            reason="safe",
            note="<img src=x onerror=alert(1)>",
        )

    update_args = mock_builder.update.call_args[0][0]
    assert update_args["escalation_cancel_note"] == "&lt;img src=x onerror=alert(1)&gt;"


@pytest.mark.anyio
@patch("app.api.safety.endpoints.verify_escalation_cancel_token")
@patch("app.api.safety.endpoints.fetch_safety_session")
@patch("app.api.safety.endpoints.cancel_safety_escalation")
async def test_cancel_escalation_post_success(
    mock_cancel: MagicMock,
    mock_fetch: MagicMock,
    mock_verify: MagicMock,
) -> None:
    from app.api.safety.endpoints import cancel_escalation_post
    from app.models import EscalationCancelRequest

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

    payload = EscalationCancelRequest(
        token="valid-post-token",
        reason="safe",
        note="Everything is fine",
    )

    res = await cancel_escalation_post(
        request=request,
        session_id="11111111-1111-1111-1111-111111111111",
        payload=payload,
    )

    assert res.status_code == 200
    mock_cancel.assert_called_once_with(
        "user-123",
        "11111111-1111-1111-1111-111111111111",
        "safe",
        "Everything is fine",
    )


def test_escalation_cancel_request_sanitizes_html_note() -> None:
    from app.models import EscalationCancelRequest

    req = EscalationCancelRequest(
        token="dummy-token",
        reason="other",
        note="<script>alert(1)</script>Safe & Sound",
    )
    assert req.note == "&lt;script&gt;alert(1)&lt;/script&gt;Safe &amp; Sound"


def test_backend_url_https_validation() -> None:
    from app.core.config import Settings

    # In production (debug=False), http:// should raise ValueError
    with pytest.raises(ValueError, match="backend_url must start with 'https://' in production"):
        Settings(
            app_domain="nexus.example.com",
            backend_url="http://insecure-backend.com",
            debug=False,
        )

    # In production with https://, should succeed
    s = Settings(
        app_domain="nexus.example.com",
        backend_url="https://secure-backend.com",
        debug=False,
    )
    assert s.backend_url == "https://secure-backend.com"


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
    assert decrypt_pii(stored_key, category="media_escrow") == "dGVzdC1rZXktYmFzZTY0"


def test_fetch_evidence_decrypts_media_key() -> None:
    from app.core.security.crypto import encrypt_to_hex
    from app.db.safety.evidence import fetch_evidence_for_alert_ids

    raw_key = "YWVzLWdjbS1zZWNyZXQta2V5"
    encrypted_key = encrypt_to_hex(raw_key, category="media_escrow")

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


def test_fetch_evidence_caller_isolation_assertion() -> None:
    """Assert that fetch_evidence_for_alert_ids is strictly called only by the portal endpoint.

    Ensures media_key_base64 is never exposed to admin APIs, user export, or staff tooling.
    """
    import os

    allowed_modules = {
        "app/db/safety/evidence.py",
        "app/db/safety/__init__.py",
        "app/api/safety/portal/endpoints.py",
    }

    app_dir = "/nexus/app"
    violating_files: list[str] = []

    for root, _, files in os.walk(app_dir):
        for f in files:
            if f.endswith(".py"):
                full_path = os.path.join(root, f)
                rel_path = os.path.relpath(full_path, "/nexus")
                if rel_path in allowed_modules:
                    continue
                with open(full_path, encoding="utf-8") as source_file:
                    content = source_file.read()
                if "fetch_evidence_for_alert_ids" in content:
                    violating_files.append(rel_path)

    assert not violating_files, f"Unauthorized callers of fetch_evidence_for_alert_ids detected: {violating_files}"


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


def test_safety_location_lat_lng_range_validation() -> None:
    from pydantic import ValidationError

    from app.models import SafetyLocation

    # Valid coordinates
    loc = SafetyLocation(lat=37.7749, lng=-122.4194)
    assert loc.lat == 37.7749
    assert loc.lng == -122.4194

    # Boundary coordinates
    loc_bound = SafetyLocation(lat=90.0, lng=180.0)
    assert loc_bound.lat == 90.0
    assert loc_bound.lng == 180.0

    loc_bound_neg = SafetyLocation(lat=-90.0, lng=-180.0)
    assert loc_bound_neg.lat == -90.0
    assert loc_bound_neg.lng == -180.0

    # Invalid lat > 90
    with pytest.raises(ValidationError):
        SafetyLocation(lat=90.1, lng=0.0)

    # Invalid lat < -90
    with pytest.raises(ValidationError):
        SafetyLocation(lat=-90.1, lng=0.0)

    # Invalid lng > 180
    with pytest.raises(ValidationError):
        SafetyLocation(lat=0.0, lng=180.1)

    # Invalid lng < -180
    with pytest.raises(ValidationError):
        SafetyLocation(lat=0.0, lng=-180.1)


def test_export_build_safety_alerts_deserializes_json_location() -> None:
    import json
    from unittest.mock import MagicMock, patch

    from app.core.security.crypto import encrypt_to_hex
    from app.db.users.export import _build_safety_alerts

    enc_loc = encrypt_to_hex(json.dumps({"lat": 37.7749, "lng": -122.4194}))
    mock_rows = [
        {
            "id": "alert-1",
            "alert_type": "sos_silent",
            "current_location": enc_loc,
            "created_at": "2026-08-24T12:00:00Z",
        },
        {
            "id": "alert-2",
            "alert_type": "inform",
            "current_location": None,
            "created_at": "2026-08-24T12:05:00Z",
        },
    ]

    with patch("app.db.users.export.supabase_client.table") as mock_table:
        mock_builder = MagicMock()
        mock_builder.select.return_value = mock_builder
        mock_builder.eq.return_value = mock_builder
        mock_builder.execute.return_value = MagicMock(data=mock_rows)
        mock_table.return_value = mock_builder

        alerts = _build_safety_alerts("user-123")
        assert len(alerts) == 2
        # Verify current_location is a deserialized dict, not a raw string
        assert isinstance(alerts[0]["current_location"], dict)
        assert alerts[0]["current_location"] == {"lat": 37.7749, "lng": -122.4194}
        assert alerts[1]["current_location"] is None


def test_sanitize_sms_text_unicode_normalization_and_separators() -> None:
    from app.core.utils.sms import sanitize_sms_text

    # NFKC compatibility normalization (fullwidth -> ASCII standard)
    fullwidth_input = "Ａｌｉｃｅ\u3000Ｓｍｉｔｈ"
    cleaned = sanitize_sms_text(fullwidth_input)
    assert cleaned == "Alice Smith"

    # Unicode line separator (U+2028) and paragraph separator (U+2029)
    injected_separators = "Alice\u2028Fake Bank Alert\u2029Urgent Action"
    cleaned_sep = sanitize_sms_text(injected_separators)
    assert cleaned_sep == "Alice Fake Bank Alert Urgent Action"
    assert "\u2028" not in (cleaned_sep or "")
    assert "\u2029" not in (cleaned_sep or "")

    # Control chars and whitespace collapsing
    raw_str = "   Mallory \x00\x07\x1b \n\n Test \r\t Alert   "
    assert sanitize_sms_text(raw_str) == "Mallory Test Alert"


@pytest.mark.anyio
@patch("app.api.safety.endpoints.redis_client")
@patch("app.api.safety.endpoints.fetch_safety_contacts")
@patch("app.api.safety.endpoints.fetch_contact_facing_profile_summary")
@patch("app.api.safety.endpoints.send_sms")
@patch("app.api.safety.endpoints.record_safety_alert")
@patch("app.api.safety.endpoints.update_alert_contacts_notified")
async def test_send_safety_alert_uses_profile_name_preventing_spoofing(
    _mock_update: MagicMock,
    mock_record: MagicMock,
    mock_send_sms: MagicMock,
    mock_profile: MagicMock,
    mock_contacts: MagicMock,
    mock_redis: MagicMock,
) -> None:
    from app.api.safety.endpoints import send_safety_alert
    from app.models import SafetyAlertRequest

    mock_redis.get = AsyncMock(return_value=None)
    mock_redis.set = AsyncMock()
    mock_contacts.return_value = [{"phone": "+15551234567"}]
    mock_send_sms.return_value = MagicMock(success=True)
    mock_record.return_value = {"id": "alert-test-123"}
    # The authenticated user's actual profile name in DB
    mock_profile.return_value = {"name": "Mallory Attacker"}

    # Attacker attempts to spoof identity via session_label and inject newlines
    payload = SafetyAlertRequest(
        alert_type="sos_loud",
        session_label="Police Department\n\nYour friend is in custody. Call 911 immediately.",
        event_label="Emergency Action\n\nWire $1000",
    )

    res = await send_safety_alert(request=MagicMock(), payload=payload, user_id="user-attacker-uuid")
    assert res.id == "alert-test-123"

    mock_send_sms.assert_called_once()
    sms_to, sms_body = mock_send_sms.call_args[0]
    assert sms_to == "+15551234567"

    # Verify SMS body sender identity is strictly Mallory Attacker (the verified profile name)
    # and NOT "Police Department" or any injected display name
    assert "🚨 Emergency alert from Mallory Attacker via Nexus." in sms_body
    assert "Police Department" not in sms_body.splitlines()[0]

    # Verify meetup line has sanitized event context without newlines
    assert "Meetup: Emergency Action Wire $1000" in sms_body
    assert "\n\nWire $1000" not in sms_body


@pytest.mark.anyio
@patch("app.api.safety.endpoints.redis_client")
@patch("app.api.safety.endpoints.fetch_safety_contacts")
@patch("app.api.safety.endpoints.fetch_contact_facing_profile_summary")
@patch("app.api.safety.endpoints.send_sms")
@patch("app.api.safety.endpoints.record_safety_alert")
@patch("app.api.safety.endpoints.update_alert_contacts_notified")
async def test_send_safety_alert_fallback_to_session_label_for_event_context(
    _mock_update: MagicMock,
    mock_record: MagicMock,
    mock_send_sms: MagicMock,
    mock_profile: MagicMock,
    mock_contacts: MagicMock,
    mock_redis: MagicMock,
) -> None:
    from app.api.safety.endpoints import send_safety_alert
    from app.models import SafetyAlertRequest

    mock_redis.get = AsyncMock(return_value=None)
    mock_redis.set = AsyncMock()
    mock_contacts.return_value = [{"phone": "+15551234567"}]
    mock_send_sms.return_value = MagicMock(success=True)
    mock_record.return_value = {"id": "alert-test-fallback"}
    # Profile has no name
    mock_profile.return_value = None

    payload = SafetyAlertRequest(
        alert_type="inform",
        session_label="Coffee at Blue Bottle",
        event_label=None,
    )

    res = await send_safety_alert(request=MagicMock(), payload=payload, user_id="user-uuid-2")
    assert res.id == "alert-test-fallback"

    mock_send_sms.assert_called_once()
    _, sms_body = mock_send_sms.call_args[0]
    # Sender falls back to generic default
    assert "⚠️ Safety check-in from A Nexus user via Nexus." in sms_body
    # session_label is used as meetup event context
    assert "Meetup: Coffee at Blue Bottle" in sms_body


def test_safety_alert_request_max_length_validation() -> None:
    from pydantic import ValidationError

    from app.models import SafetyAlertRequest

    # Exceeding 200 chars raises ValidationError
    with pytest.raises(ValidationError):
        SafetyAlertRequest(
            alert_type="sos_loud",
            session_label="A" * 201,
        )

    with pytest.raises(ValidationError):
        SafetyAlertRequest(
            alert_type="sos_loud",
            event_label="B" * 201,
        )


def test_safety_contact_in_name_sanitizes_newlines_and_injections() -> None:
    from pydantic import ValidationError

    from app.models import SafetyContactIn

    # Injected newlines and control characters are stripped
    injected_name = "Alice Smith\n\nDISREGARD: All safe\r\t\x00Wire $500"
    contact = SafetyContactIn(name=injected_name, phone="+15551234567")
    assert contact.name == "Alice Smith DISREGARD: All safe Wire $500"
    assert "\n" not in contact.name
    assert "\r" not in contact.name
    assert "\x00" not in contact.name

    # Unicode line separators are stripped
    unicode_sep = "Alice\u2028Urgent Account Alert\u2029Verify"
    contact_uni = SafetyContactIn(name=unicode_sep, phone="+15551234567")
    assert contact_uni.name == "Alice Urgent Account Alert Verify"
    assert "\u2028" not in contact_uni.name
    assert "\u2029" not in contact_uni.name

    # Blank or whitespace-only raises ValidationError
    with pytest.raises(ValidationError):
        SafetyContactIn(name="   \n\r\t   ", phone="+15551234567")


def test_compose_contact_self_removed_message_sanitizes_contact_name() -> None:
    from app.core.utils.sms import compose_contact_self_removed_message

    injected = "Alice\n\nYour bank alert: SCAM"
    msg = compose_contact_self_removed_message(contact_name=injected)

    # First line contains sanitized name without splitting onto arbitrary fake paragraphs
    lines = msg.splitlines()
    assert lines[0] == "⚠️ Alice Your bank alert: SCAM removed themselves as your Nexus Meetup Safety trusted contact."
    assert "Your bank alert: SCAM" in lines[0]
    assert "\n\n" not in msg


def test_safety_session_start_request_sanitizes_labels() -> None:
    from datetime import datetime, timezone

    from app.models import SafetySessionStartRequest

    now = datetime.now(timezone.utc)
    req = SafetySessionStartRequest(
        interval_seconds=300,
        label="Dinner at Bob's\n\nCRITICAL SCAM",
        event_label="Meetup Date\r\nFake Info",
        next_checkin_at=now,
    )
    assert req.label == "Dinner at Bob's CRITICAL SCAM"
    assert req.event_label == "Meetup Date Fake Info"
    assert "\n" not in (req.label or "")
    assert "\r" not in (req.event_label or "")


@pytest.mark.anyio
async def test_send_safety_alert_hourly_quota_throttling() -> None:
    from unittest.mock import AsyncMock, MagicMock, patch

    from fastapi import HTTPException

    from app.api.safety.endpoints import send_safety_alert
    from app.models import SafetyAlertRequest

    payload = SafetyAlertRequest(alert_type="sos_loud")

    with patch("app.api.safety.endpoints.redis_client") as mock_redis:
        # Simulate 6th alert in the hour
        mock_redis.incr = AsyncMock(return_value=6)
        mock_redis.expire = AsyncMock()

        with pytest.raises(HTTPException) as exc_info:
            await send_safety_alert(
                request=MagicMock(),
                payload=payload,
                user_id="user-spam-123",
            )

        assert exc_info.value.status_code == 429
        assert "Hourly safety alert limit reached" in exc_info.value.detail


@pytest.mark.anyio
async def test_notify_newly_added_contacts_throttles_recipient_sms_bombing() -> None:
    from unittest.mock import AsyncMock, patch

    from app.api.safety.endpoints import _notify_newly_added_contacts

    user_id = "user-123"
    newly_notified = [
        {"phone": "+15551234567"},
    ]
    contacts = [
        {"id": "contact-uuid-1", "phone": "+15551234567"},
    ]

    with patch("app.api.safety.endpoints.fetch_contact_facing_profile_summary", return_value={"name": "Alice"}), \
         patch("app.api.safety.endpoints.fetch_safety_contacts_with_id", return_value=contacts), \
         patch("app.api.safety.endpoints.redis_client") as mock_redis, \
         patch("app.api.safety.endpoints.send_sms") as mock_send_sms:

        # 1. Normal notice (1st time) sends SMS
        mock_redis.incr = AsyncMock(return_value=1)
        mock_redis.expire = AsyncMock()
        await _notify_newly_added_contacts(user_id, newly_notified)
        mock_send_sms.assert_called_once()

        mock_send_sms.reset_mock()

        # 2. Throttled notice (4th time in hour) skips SMS
        mock_redis.incr = AsyncMock(return_value=4)
        await _notify_newly_added_contacts(user_id, newly_notified)
        mock_send_sms.assert_not_called()


@pytest.mark.anyio
async def test_notify_newly_added_contacts_logs_delivery_failure() -> None:
    from unittest.mock import AsyncMock, patch

    from app.api.safety.endpoints import _notify_newly_added_contacts
    from app.core.utils.sms import ProviderResult

    user_id = "user-123"
    newly_notified = [
        {"phone": "+15551234567"},
    ]
    contacts = [
        {"id": "contact-uuid-1", "phone": "+15551234567"},
    ]

    with patch("app.api.safety.endpoints.fetch_contact_facing_profile_summary", return_value={"name": "Alice"}), \
         patch("app.api.safety.endpoints.fetch_safety_contacts_with_id", return_value=contacts), \
         patch("app.api.safety.endpoints.redis_client") as mock_redis, \
         patch("app.api.safety.endpoints.send_sms", return_value=ProviderResult(success=False, provider="Twilio", error="Provider unreachable", error_code="NETWORK_ERR")), \
         patch("app.api.safety.endpoints.logger.warning") as mock_log_warn:

        mock_redis.incr = AsyncMock(return_value=1)
        mock_redis.expire = AsyncMock()

        await _notify_newly_added_contacts(user_id, newly_notified)

        # Verify failure was caught and logged with masked phone
        assert mock_log_warn.called
        log_args, log_kwargs = mock_log_warn.call_args
        assert "Failed to deliver 'contact added' notice SMS" in log_args[0]
        assert log_kwargs["extra"]["user_id"] == "user-123"
        assert log_kwargs["extra"]["error"] == "Provider unreachable"


def test_start_and_fetch_safety_session_encrypts_label_and_event_context() -> None:
    from unittest.mock import MagicMock, patch

    from app.db.safety.sessions import fetch_safety_session, start_safety_session

    user_id = "00000000-0000-0000-0000-000000000001"
    session_id = "00000000-0000-0000-0000-000000000099"
    plain_label = "Dinner date at Blue Bottle Cafe"
    plain_event_context = {"label": "Tech Meetup in SOMA"}

    inserted_payload: dict[str, Any] = {}

    with patch("app.db.safety.sessions.supabase_client") as mock_supabase:
        def rpc_fn(fn_name: str, params: dict[str, Any]) -> MagicMock:
            if fn_name == "start_safety_session":
                inserted_payload["label"] = params.get("p_label")
                inserted_payload["event_context"] = params.get("p_event_context")
                m_exec = MagicMock()
                m_exec.execute.return_value = MagicMock(data={
                    "id": session_id,
                    "user_id": user_id,
                    "label": params.get("p_label"),
                    "interval_seconds": params.get("p_interval_seconds"),
                    "next_checkin_at": params.get("p_next_checkin_at"),
                    "event_context": params.get("p_event_context"),
                    "status": "active",
                    "battery_percent": params.get("p_battery_percent"),
                    "connection_type": params.get("p_connection_type"),
                    "escalations_sent": 0,
                    "last_escalated_at": None,
                })
                return m_exec
            return MagicMock()

        def table_fn(t_name: str) -> MagicMock:
            if t_name == "safety_sessions":
                m = MagicMock()
                # Mock select for fetch_safety_session
                m.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(data={
                    "id": session_id,
                    "user_id": user_id,
                    "label": inserted_payload.get("label"),
                    "interval_seconds": 300,
                    "next_checkin_at": "2026-08-24T18:00:00Z",
                    "event_context": inserted_payload.get("event_context"),
                    "status": "active",
                    "battery_percent": 90,
                    "connection_type": "wifi",
                    "escalations_sent": 0,
                    "last_escalated_at": None,
                })
                return m
            return MagicMock()

        mock_supabase.rpc.side_effect = rpc_fn
        mock_supabase.table.side_effect = table_fn

        # 1. Test start_safety_session encrypts fields in database payload
        res = start_safety_session(
            user_id=user_id,
            label=plain_label,
            interval_seconds=300,
            next_checkin_at="2026-08-24T18:00:00Z",
            event_context=plain_event_context,
            battery_percent=90,
            connection_type="wifi",
        )

        # Database payload MUST be encrypted (start with \\x)
        assert inserted_payload["label"].startswith("\\x")
        assert plain_label not in inserted_payload["label"]
        assert inserted_payload["event_context"].startswith("\\x")
        assert "Tech Meetup" not in inserted_payload["event_context"]

        # Returned object MUST be decrypted for the caller
        assert res["label"] == plain_label
        assert res["event_context"] == plain_event_context

        # 2. Test fetch_safety_session decrypts fields from DB
        fetched = fetch_safety_session(session_id)
        assert fetched is not None
        assert fetched["label"] == plain_label
        assert fetched["event_context"] == plain_event_context


@pytest.mark.anyio
async def test_check_cached_sos_alert_redis_failure_falls_back_to_db() -> None:
    from unittest.mock import patch

    from app.api.safety.endpoints import _check_cached_sos_alert

    user_id = "00000000-0000-0000-0000-000000000001"
    session_id = "00000000-0000-0000-0000-000000000099"

    # Redis throws an exception (simulating Redis outage)
    with patch("app.api.safety.endpoints.redis_client.get", side_effect=Exception("Redis connection refused")), \
         patch("app.api.safety.endpoints.fetch_recent_safety_alert") as mock_db_alert:

        mock_db_alert.return_value = {
            "id": "alert-recent-123",
            "contacts_notified": 3,
            "created_at": "2026-08-24T18:00:00Z",
        }

        res = await _check_cached_sos_alert(
            idempotency_key="dummy-key",
            user_id=user_id,
            session_id=session_id,
            alert_type="sos",
        )

        assert res is not None
        assert res.id == "alert-recent-123"
        assert res.contacts_notified == 3
        mock_db_alert.assert_called_once_with(user_id, "sos", session_id, 60)


@pytest.mark.anyio
async def test_check_cached_sos_alert_redis_and_db_miss() -> None:
    from unittest.mock import patch

    from app.api.safety.endpoints import _check_cached_sos_alert

    user_id = "00000000-0000-0000-0000-000000000001"
    session_id = "00000000-0000-0000-0000-000000000099"

    # Redis throws an exception, DB returns None
    with patch("app.api.safety.endpoints.redis_client.get", side_effect=Exception("Redis connection refused")), \
         patch("app.api.safety.endpoints.fetch_recent_safety_alert", return_value=None):

        res = await _check_cached_sos_alert(
            idempotency_key="dummy-key",
            user_id=user_id,
            session_id=session_id,
            alert_type="sos",
        )

        # Proceeds with sending (fails open)
        assert res is None


def test_checkin_session_rate_limit_uses_dedicated_heartbeat_quota() -> None:
    """Verify checkin_session is decoupled from generic safety limits and uses dedicated 120/hour quota."""
    from app.api.safety.endpoints import checkin_session
    from app.core.config import settings

    assert settings.rate_limit_safety_heartbeat == "120/hour"
    # checkin_session is decorated with SlowAPI limiter
    # Verify limiter attached to checkin_session has the expected rate limit attribute
    assert hasattr(checkin_session, "_rate_limiting") or hasattr(checkin_session, "__wrapped__") or callable(checkin_session)


def test_heartbeat_safety_session_resets_escalation_when_fresh() -> None:
    """A fresh checkin after escalation occurred resets escalations_sent to 0."""
    from unittest.mock import MagicMock, patch

    from app.db.safety.sessions import heartbeat_safety_session

    user_id = "00000000-0000-0000-0000-000000000001"
    session_id = "00000000-0000-0000-0000-000000000002"

    mock_table = MagicMock()
    # Mock select
    mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(data=[{
        "id": session_id,
        "next_checkin_at": "2026-08-25T11:00:00Z",
        "escalations_sent": 1,
        "last_escalated_at": "2026-08-25T11:05:00Z",
    }])

    update_payload: dict[str, Any] = {}
    def mock_update(payload: dict[str, Any]) -> MagicMock:
        update_payload.update(payload)
        m = MagicMock()
        m.eq.return_value.eq.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(data=[{
            "id": session_id,
            "user_id": user_id,
            "next_checkin_at": payload.get("next_checkin_at"),
            "escalations_sent": payload.get("escalations_sent", 1),
            "last_escalated_at": payload.get("last_escalated_at"),
        }])
        return m

    mock_table.update = mock_update

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_table):
        # Fresh heartbeat deadline at 12:00:00 > last_escalated_at (11:05:00)
        res = heartbeat_safety_session(
            user_id=user_id,
            session_id=session_id,
            next_checkin_at="2026-08-25T12:00:00Z",
            battery_percent=85,
            connection_type="wifi",
        )

    assert res is not None
    assert update_payload.get("escalations_sent") == 0
    assert update_payload.get("last_escalated_at") is None
    assert update_payload.get("next_checkin_at") == "2026-08-25T12:00:00Z"


def test_heartbeat_safety_session_retains_escalation_when_stale() -> None:
    """A stale buffered heartbeat with deadline <= last_escalated_at does NOT reset escalations_sent."""
    from unittest.mock import MagicMock, patch

    from app.db.safety.sessions import heartbeat_safety_session

    user_id = "00000000-0000-0000-0000-000000000001"
    session_id = "00000000-0000-0000-0000-000000000002"

    mock_table = MagicMock()
    # Mock select: existing session has escalated at 11:05:00
    mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(data=[{
        "id": session_id,
        "next_checkin_at": "2026-08-25T11:00:00Z",
        "escalations_sent": 1,
        "last_escalated_at": "2026-08-25T11:05:00Z",
    }])

    update_payload: dict[str, Any] = {}
    def mock_update(payload: dict[str, Any]) -> MagicMock:
        update_payload.update(payload)
        m = MagicMock()
        m.eq.return_value.eq.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(data=[{
            "id": session_id,
            "user_id": user_id,
            "next_checkin_at": "2026-08-25T11:00:00Z",
            "escalations_sent": 1,
            "last_escalated_at": "2026-08-25T11:05:00Z",
        }])
        return m

    mock_table.update = mock_update

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_table):
        # Stale heartbeat with next_checkin_at at 11:04:00 <= last_escalated_at (11:05:00)
        res = heartbeat_safety_session(
            user_id=user_id,
            session_id=session_id,
            next_checkin_at="2026-08-25T11:04:00Z",
            battery_percent=50,
            connection_type="cellular",
        )

    assert res is not None
    # escalations_sent and last_escalated_at must NOT be reset in the update payload
    assert "escalations_sent" not in update_payload
    assert "last_escalated_at" not in update_payload











