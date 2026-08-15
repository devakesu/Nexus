from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import MagicMock, patch

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
        "11111111-1111-1111-1111-111111111111",
        "safe",
        "User checked in via phone call.",
    )


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
