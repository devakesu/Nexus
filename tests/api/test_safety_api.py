"""Test Suite for Test Safety Api.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.db.client import DatabaseAccessError
from app.db.safety import EscalationInProgressError
from app.models import (
    EscalationCancelRequest,
    SafetyAlertRequest,
    SafetyContactIn,
    SafetyContactsSyncRequest,
    SafetyEvidenceRegisterRequest,
    SafetyLocation,
    SafetySessionCheckinRequest,
    SafetySessionEndRequest,
    SafetySessionStartRequest,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
SESS_1 = "00000000-0000-0000-0000-000000000040"
SESSION_1 = "00000000-0000-0000-0000-000000000020"
ALERT_1 = "00000000-0000-0000-0000-000000000010"
CONV_1 = "00000000-0000-0000-0000-000000000020"
CONVO_1 = "00000000-0000-0000-0000-000000000020"
MATCH_1 = "00000000-0000-0000-0000-000000000010"
MSG_1 = "00000000-0000-0000-0000-000000000020"
PHONE_VALID = "+14155552671"
REPORT_1 = "00000000-0000-0000-0000-000000000050"
EVENT_1 = "00000000-0000-0000-0000-000000000033"
CONTACT_1 = "00000000-0000-0000-0000-000000000030"


def _make_chaining_mock(
    data: Any = None, error: Exception | None = None,
) -> MagicMock:
    mock: MagicMock = MagicMock()
    mock.select.return_value = mock
    mock.insert.return_value = mock
    mock.update.return_value = mock
    mock.delete.return_value = mock
    mock.upsert.return_value = mock
    mock.eq.return_value = mock
    mock.neq.return_value = mock
    mock.gt.return_value = mock
    mock.gte.return_value = mock
    mock.lt.return_value = mock
    mock.lte.return_value = mock
    mock.is_.return_value = mock
    mock.in_.return_value = mock
    mock.or_.return_value = mock
    mock.not_.is_.return_value = mock
    mock.order.return_value = mock
    mock.limit.return_value = mock
    mock.range.return_value = mock
    mock.contains.return_value = mock
    mock.contained_by.return_value = mock
    mock.overlaps.return_value = mock

    def _exec() -> MagicMock:
        if error:
            raise error
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    def _single() -> MagicMock:
        if error:
            raise error
        if isinstance(data, list) and data:
            return MagicMock(data=copy.deepcopy(data[0]))
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    mock.single.return_value = single_mock
    return mock


def make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/test",
        "headers": [],
        "client": ("127.0.0.1", 12345),
        "app": MagicMock(),
    }
    return Request(scope)


def _make_mock_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/test",
        "headers": [(b"host", b"localhost"), (b"user-agent", b"pytest")],
        "client": ("127.0.0.1", 12345),
        "app": {},
    }
    return Request(scope)


def make_api_error(code: str = "P0001", message: str = "DB error") -> APIError:
    return APIError(
        {"code": code, "message": message, "details": "details", "hint": "hint"},
    )


pytestmark = pytest.mark.anyio


async def test_api_safety_endpoints():
    from app.api.safety.endpoints import (
        cancel_escalation,
        checkin_session,
        end_session,
        put_safety_contacts,
        send_safety_alert,
        start_session,
    )
    from app.models import (
        SafetyAlertRequest,
        SafetyAlertResponse,
        SafetyContactIn,
        SafetyContactsSyncRequest,
        SafetyLocation,
        SafetySessionCheckinRequest,
        SafetySessionEndRequest,
        SafetySessionStartRequest,
    )

    req = _make_mock_request()

    # 1. put_safety_contacts
    payload = SafetyContactsSyncRequest(
        contacts=[SafetyContactIn(name="Bob", phone="+15555555555")],
    )
    with patch("app.api.safety.endpoints.sync_safety_contacts", return_value=([], [])):
        res = await put_safety_contacts(req, payload, _device=None, user_id=USER_1)
        assert res.count == 1

    # 2. start_session
    sess_in = SafetySessionStartRequest(
        label="Date",
        interval_seconds=900,
        next_checkin_at=datetime.fromtimestamp(
            datetime.now(timezone.utc).timestamp() + 300, tz=timezone.utc,
        ),
    )
    with patch(
        "app.api.safety.endpoints.start_safety_session",
        return_value={"id": SESS_1, "interval_seconds": 900},
    ):
        sess = await start_session(req, sess_in, _device=None, user_id=USER_1)
        assert sess is not None

    # 3. checkin_session
    hb_in = SafetySessionCheckinRequest(
        session_id=SESS_1,
        next_checkin_at=datetime.fromtimestamp(
            datetime.now(timezone.utc).timestamp() + 600, tz=timezone.utc,
        ),
    )
    with patch(
        "app.api.safety.endpoints.heartbeat_safety_session",
        return_value={"id": SESS_1, "status": "active"},
    ):
        hb = await checkin_session(req, hb_in, _device=None, user_id=USER_1)
        assert hb is not None

    # 4. end_session
    end_in = SafetySessionEndRequest(session_id=SESS_1)
    with patch("app.api.safety.endpoints.end_safety_session"):
        ended = await end_session(req, end_in, _device=None, user_id=USER_1)
        assert ended is not None

    # 5. send_safety_alert
    alert_in = SafetyAlertRequest(
        alert_type="sos_loud",
        current_location=SafetyLocation(lat=37.7749, lng=-122.4194),
    )
    with (
        patch(
            "app.api.safety.endpoints.fetch_safety_contacts",
            return_value=[{"phone": "+15555555555"}],
        ),
        patch(
            "app.api.safety.endpoints._send_alert_sms_to_contacts",
            AsyncMock(return_value=1),
        ),
        patch(
            "app.api.safety.endpoints._record_safety_alert_response",
            AsyncMock(
                return_value=SafetyAlertResponse(
                    id=ALERT_1, contacts_notified=1, contacts_total=1,
                ),
            ),
        ),
        patch("app.api.safety.endpoints._cache_sos_alert", AsyncMock()),
    ):
        alt = await send_safety_alert(req, alert_in, _device=None, user_id=USER_1)
        assert alt.id == ALERT_1

    # 6. cancel_escalation
    with (
        patch(
            "app.api.safety.endpoints.verify_escalation_cancel_token", return_value=1,
        ),
        patch(
            "app.api.safety.endpoints.fetch_safety_session",
            return_value={
                "id": SESS_1,
                "user_id": USER_1,
                "status": "active",
                "escalations_sent": 1,
            },
        ),
        patch(
            "app.api.safety.endpoints.cancel_safety_escalation",
            return_value={"id": SESS_1},
        ),
        patch("app.api.safety.endpoints.redis_client") as mock_r,
    ):
        mock_r.set.return_value = True
        canc = await cancel_escalation(
            req, SESS_1, token="valid_tok", reason="safe", note=None,
        )
        assert canc.status_code == 200


async def test_api_safety_endpoints_exhaustive():
    from datetime import timedelta

    from app.api.safety.endpoints import (
        checkin_session,
        end_session,
        put_safety_contacts,
        send_safety_alert,
        start_session,
    )
    from app.models import (
        SafetyAlertRequest,
        SafetyContactIn,
        SafetyContactsSyncRequest,
        SafetyLocation,
        SafetySessionCheckinRequest,
        SafetySessionEndRequest,
        SafetySessionStartRequest,
    )

    mock_req = MagicMock()
    mock_req.client.host = "127.0.0.1"

    with (
        patch(
            "app.api.safety.endpoints.record_safety_alert",
            return_value={
                "id": ALERT_1,
                "created_at": datetime.now(timezone.utc).isoformat(),
            },
        ),
        patch("app.api.safety.endpoints.update_alert_contacts_notified"),
        patch(
            "app.api.safety.endpoints.fetch_safety_contacts",
            return_value=[{"name": "Bob", "phone": "+15555555555"}],
        ),
        patch(
            "app.api.safety.endpoints.fetch_contact_facing_profile_summary",
            return_value={"name": "Alice"},
        ),
        patch("app.api.safety.endpoints.sync_safety_contacts", return_value=([], [])),
        patch(
            "app.api.safety.endpoints.start_safety_session",
            return_value={"id": "s1", "status": "active"},
        ),
        patch(
            "app.api.safety.endpoints.heartbeat_safety_session",
            return_value={"id": "s1", "status": "active"},
        ),
        patch("app.api.safety.endpoints.end_safety_session"),
        patch("app.api.safety.endpoints.fetch_recent_safety_alert", return_value=None),
        patch(
            "app.api.safety.endpoints.send_sms",
            AsyncMock(return_value=MagicMock(success=True)),
        ),
        patch("app.api.safety.endpoints.redis_client") as mock_r,
    ):
        mock_r.get = AsyncMock(return_value=None)
        mock_r.set = AsyncMock(return_value=True)
        mock_r.incr = AsyncMock(return_value=1)
        mock_r.expire = AsyncMock(return_value=True)

        # 1. Alert
        alert_req = SafetyAlertRequest(
            alert_type="sos_silent",
            current_location=SafetyLocation(lat=37.7, lng=-122.4),
        )
        a_res = await send_safety_alert(
            mock_req, alert_req, _device=None, user_id=USER_1,
        )
        assert a_res.id == ALERT_1

        # 2. Sync contacts
        c_res = await put_safety_contacts(
            mock_req,
            SafetyContactsSyncRequest(
                contacts=[SafetyContactIn(name="Bob", phone="+15555555555")],
            ),
            _device=None,
            user_id=USER_1,
        )
        assert c_res is not None

        # 3. Start, heartbeat, end safety session
        future_time = datetime.now(timezone.utc) + timedelta(minutes=15)
        s_start = SafetySessionStartRequest(
            interval_seconds=1800,
            next_checkin_at=future_time,
            event_label="Dinner",
        )
        s_res = await start_session(mock_req, s_start, _device=None, user_id=USER_1)
        assert s_res is not None

        hb_req = SafetySessionCheckinRequest(
            session_id="00000000-0000-0000-0000-000000000040",
            next_checkin_at=future_time + timedelta(minutes=15),
            battery_percent=85,
            connection_type="wifi",
        )
        hb_res = await checkin_session(mock_req, hb_req, _device=None, user_id=USER_1)
        assert hb_res is not None

        end_res = await end_session(
            mock_req,
            SafetySessionEndRequest(session_id="00000000-0000-0000-0000-000000000040"),
            _device=None,
            user_id=USER_1,
        )
        assert end_res is not None


async def test_safety_endpoints_deep():
    from app.api.safety.endpoints import (
        _check_cached_sos_alert,
        _handle_cancel_escalation,
        _notify_newly_added_contacts,
        cancel_escalation,
        cancel_escalation_post,
        checkin_session,
        end_session,
        put_safety_contacts,
        register_evidence,
        send_safety_alert,
        start_session,
    )

    req = make_dummy_request()

    # _notify_newly_added_contacts: empty, DB error, redis throttle, success
    await _notify_newly_added_contacts(USER_1, [])

    with patch(
        "app.api.safety.endpoints.fetch_contact_facing_profile_summary",
        side_effect=DatabaseAccessError("fail"),
    ):
        await _notify_newly_added_contacts(USER_1, [{"phone": PHONE_VALID}])

    with (
        patch(
            "app.api.safety.endpoints.fetch_contact_facing_profile_summary",
            return_value={"name": "Alice"},
        ),
        patch(
            "app.api.safety.endpoints.fetch_safety_contacts_with_id",
            return_value=[{"id": "cnt-1", "phone": PHONE_VALID}],
        ),
        patch("app.api.safety.endpoints.redis_client") as mock_redis,
        patch(
            "app.api.safety.endpoints.send_sms",
            return_value=MagicMock(success=False, error="SMS fail", error_code="400"),
        ),
    ):
        mock_redis.incr = AsyncMock(return_value=1)
        mock_redis.expire = AsyncMock()
        await _notify_newly_added_contacts(USER_1, [{"phone": PHONE_VALID}])

        # Over throttle limit
        mock_redis.incr = AsyncMock(return_value=10)
        await _notify_newly_added_contacts(USER_1, [{"phone": PHONE_VALID}])

        # Redis exception
        mock_redis.incr = AsyncMock(side_effect=Exception("Redis down"))
        await _notify_newly_added_contacts(USER_1, [{"phone": PHONE_VALID}])

    # put_safety_contacts: DB error vs success
    sync_req = SafetyContactsSyncRequest(
        contacts=[SafetyContactIn(name="Bob", phone=PHONE_VALID)],
    )
    with patch(
        "app.api.safety.endpoints.sync_safety_contacts",
        side_effect=DatabaseAccessError("fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await put_safety_contacts(req, sync_req, None, USER_1)
        assert exc.value.status_code == 503

    with (
        patch(
            "app.api.safety.endpoints.sync_safety_contacts",
            return_value=([], [{"phone": PHONE_VALID}]),
        ),
        patch("app.api.safety.endpoints.safe_create_task"),
    ):
        res = await put_safety_contacts(req, sync_req, None, USER_1)
        assert res.count == 1

    # _check_cached_sos_alert: redis hit, malformed json, db hit, db error
    with patch("app.api.safety.endpoints.redis_client") as mock_redis:
        mock_redis.get = AsyncMock(
            return_value='{"id": "alert-1", "contacts_notified": 2, "contacts_total": 2}',
        )
        hit = await _check_cached_sos_alert("key", USER_1, "sess-1", "sos_loud")
        assert hit is not None
        assert hit.id == "alert-1"

        mock_redis.get = AsyncMock(side_effect=Exception("Redis down"))
        with patch(
            "app.api.safety.endpoints.fetch_recent_safety_alert",
            return_value={"id": "alert-db", "contacts_notified": 1},
        ):
            db_hit = await _check_cached_sos_alert("key", USER_1, "sess-1", "sos_loud")
            assert db_hit is not None
            assert db_hit.id == "alert-db"

        with patch(
            "app.api.safety.endpoints.fetch_recent_safety_alert",
            side_effect=Exception("DB fail"),
        ):
            assert (
                await _check_cached_sos_alert("key", USER_1, "sess-1", "sos_loud")
                is None
            )

    # send_safety_alert: DB error, no contacts, inform vs sos
    alert_req = SafetyAlertRequest(
        alert_type="inform",
        session_id=USER_1,
        event_label="Coffee",
        current_location=SafetyLocation(lat=40.0, lng=-73.0),
    )
    with (
        patch("app.api.safety.endpoints._check_cached_sos_alert", return_value=None),
        patch(
            "app.api.safety.endpoints.fetch_safety_contacts",
            side_effect=DatabaseAccessError("fail"),
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await send_safety_alert(req, alert_req, None, USER_1)
        assert exc.value.status_code == 503

    with (
        patch("app.api.safety.endpoints._check_cached_sos_alert", return_value=None),
        patch("app.api.safety.endpoints.fetch_safety_contacts", return_value=[]),
    ):
        with pytest.raises(HTTPException) as exc:
            await send_safety_alert(req, alert_req, None, USER_1)
        assert exc.value.status_code == 400

    with (
        patch("app.api.safety.endpoints._check_cached_sos_alert", return_value=None),
        patch(
            "app.api.safety.endpoints.fetch_safety_contacts",
            return_value=[{"phone": PHONE_VALID}],
        ),
        patch(
            "app.api.safety.endpoints.fetch_contact_facing_profile_summary",
            side_effect=Exception("fail"),
        ),
        patch("app.api.safety.endpoints._send_alert_sms_to_contacts", return_value=1),
        patch(
            "app.api.safety.endpoints._record_safety_alert_response",
            return_value=MagicMock(id="alert-rec"),
        ),
        patch("app.api.safety.endpoints._cache_sos_alert"),
    ):
        res = await send_safety_alert(req, alert_req, None, USER_1)
        assert res.id == "alert-rec"

    # register_evidence: path traversal, prefix mismatch, alert lookup error, alert not found, DB error, success
    ev_req_bad = SafetyEvidenceRegisterRequest(
        alert_id="00000000-0000-0000-0000-000000000009",
        storage_path=f"{USER_2}/file.enc",
        media_key_base64="key",
        content_type="audio",
        duration_seconds=10,
    )
    with pytest.raises(HTTPException) as exc:
        await register_evidence(req, ev_req_bad, None, USER_1)
    assert exc.value.status_code == 422

    ev_req_good = SafetyEvidenceRegisterRequest(
        alert_id="00000000-0000-0000-0000-000000000009",
        storage_path=f"{USER_1}/audio.enc",
        media_key_base64="key",
        content_type="audio",
        duration_seconds=10,
    )
    with patch(
        "app.api.safety.endpoints.fetch_safety_alert",
        side_effect=DatabaseAccessError("fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await register_evidence(req, ev_req_good, None, USER_1)
        assert exc.value.status_code == 503

    with patch(
        "app.api.safety.endpoints.fetch_safety_alert", return_value={"user_id": USER_2},
    ):
        with pytest.raises(HTTPException) as exc:
            await register_evidence(req, ev_req_good, None, USER_1)
        assert exc.value.status_code == 404

    with (
        patch(
            "app.api.safety.endpoints.fetch_safety_alert",
            return_value={"user_id": USER_1},
        ),
        patch(
            "app.api.safety.endpoints.register_safety_evidence",
            side_effect=DatabaseAccessError("fail"),
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await register_evidence(req, ev_req_good, None, USER_1)
        assert exc.value.status_code == 503

    with (
        patch(
            "app.api.safety.endpoints.fetch_safety_alert",
            return_value={"user_id": USER_1},
        ),
        patch(
            "app.api.safety.endpoints.register_safety_evidence",
            return_value={"id": "ev-1"},
        ),
    ):
        res = await register_evidence(req, ev_req_good, None, USER_1)
        assert res.id == "ev-1"

    # start_session: past time, window exceeded, escalation in progress, DB error, success
    now = datetime.now(timezone.utc)
    start_req_past = SafetySessionStartRequest(
        label="Dinner", interval_seconds=300, next_checkin_at=now - timedelta(minutes=5),
    )
    with pytest.raises(HTTPException) as exc:
        await start_session(req, start_req_past, None, USER_1)
    assert exc.value.status_code == 400

    start_req_far = SafetySessionStartRequest(
        label="Dinner", interval_seconds=300, next_checkin_at=now + timedelta(days=10),
    )
    with pytest.raises(HTTPException) as exc:
        await start_session(req, start_req_far, None, USER_1)
    assert exc.value.status_code == 400

    start_req_ok = SafetySessionStartRequest(
        label="Dinner",
        interval_seconds=300,
        next_checkin_at=now + timedelta(minutes=10),
        event_label="Date",
    )
    with patch(
        "app.api.safety.endpoints.start_safety_session",
        side_effect=EscalationInProgressError("busy"),
    ):
        with pytest.raises(HTTPException) as exc:
            await start_session(req, start_req_ok, None, USER_1)
        assert exc.value.status_code == 400

    with patch(
        "app.api.safety.endpoints.start_safety_session",
        side_effect=DatabaseAccessError("fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await start_session(req, start_req_ok, None, USER_1)
        assert exc.value.status_code == 503

    with patch(
        "app.api.safety.endpoints.start_safety_session",
        return_value={"id": "sess-start"},
    ):
        res = await start_session(req, start_req_ok, None, USER_1)
        assert res.id == "sess-start"

    # checkin_session: past time, far window, DB error, not found, success
    checkin_past = SafetySessionCheckinRequest(
        session_id="00000000-0000-0000-0000-000000000001",
        next_checkin_at=now - timedelta(minutes=1),
    )
    with pytest.raises(HTTPException) as exc:
        await checkin_session(req, checkin_past, None, USER_1)
    assert exc.value.status_code == 400

    checkin_far = SafetySessionCheckinRequest(
        session_id="00000000-0000-0000-0000-000000000001",
        next_checkin_at=now + timedelta(days=5),
    )
    with pytest.raises(HTTPException) as exc:
        await checkin_session(req, checkin_far, None, USER_1)
    assert exc.value.status_code == 400

    checkin_ok = SafetySessionCheckinRequest(
        session_id="00000000-0000-0000-0000-000000000001",
        next_checkin_at=now + timedelta(minutes=15),
    )
    with patch(
        "app.api.safety.endpoints.heartbeat_safety_session",
        side_effect=DatabaseAccessError("fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await checkin_session(req, checkin_ok, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.safety.endpoints.heartbeat_safety_session", return_value=None):
        with pytest.raises(HTTPException) as exc:
            await checkin_session(req, checkin_ok, None, USER_1)
        assert exc.value.status_code == 404

    with patch(
        "app.api.safety.endpoints.heartbeat_safety_session",
        return_value={"id": "sess-1"},
    ):
        assert await checkin_session(req, checkin_ok, None, USER_1) == {"ok": True}

    # end_session: DB error vs success
    end_req = SafetySessionEndRequest(session_id="00000000-0000-0000-0000-000000000001")
    with patch(
        "app.api.safety.endpoints.end_safety_session",
        side_effect=DatabaseAccessError("fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await end_session(req, end_req, None, USER_1)
        assert exc.value.status_code == 503

    with patch("app.api.safety.endpoints.end_safety_session"):
        assert await end_session(req, end_req, None, USER_1) == {"ok": True}

    # _handle_cancel_escalation: invalid reason, bad token, replay token, session not found, session ended, already cancelled, escalation mismatch, DB error, success
    res_bad_reason = await _handle_cancel_escalation("sess-1", "tok", "invalid", None)
    assert res_bad_reason.status_code == 400

    with patch(
        "app.api.safety.endpoints.verify_escalation_cancel_token", return_value=None,
    ):
        assert (
            await _handle_cancel_escalation("sess-1", "tok", "safe", None)
        ).status_code == 403

    with (
        patch(
            "app.api.safety.endpoints.verify_escalation_cancel_token", return_value=1,
        ),
        patch("app.api.safety.endpoints.redis_client") as mock_redis,
    ):
        mock_redis.set = AsyncMock(return_value=False)
        assert (
            await _handle_cancel_escalation("sess-1", "tok", "safe", None)
        ).status_code == 400

        mock_redis.set = AsyncMock(return_value=True)
        with patch("app.api.safety.endpoints.fetch_safety_session", return_value=None):
            assert (
                await _handle_cancel_escalation("sess-1", "tok", "safe", None)
            ).status_code == 404

        with patch(
            "app.api.safety.endpoints.fetch_safety_session",
            return_value={"status": "ended"},
        ):
            assert (
                await _handle_cancel_escalation("sess-1", "tok", "safe", None)
            ).status_code == 200

        with patch(
            "app.api.safety.endpoints.fetch_safety_session",
            return_value={
                "status": "active",
                "escalation_cancelled_at": "2026-08-26T00:00:00Z",
            },
        ):
            assert (
                await _handle_cancel_escalation("sess-1", "tok", "safe", None)
            ).status_code == 200

        with patch(
            "app.api.safety.endpoints.fetch_safety_session",
            return_value={
                "status": "active",
                "escalation_cancelled_at": None,
                "escalations_sent": 2,
            },
        ):
            assert (
                await _handle_cancel_escalation("sess-1", "tok", "safe", None)
            ).status_code == 400

        with (
            patch(
                "app.api.safety.endpoints.fetch_safety_session",
                return_value={
                    "status": "active",
                    "escalation_cancelled_at": None,
                    "escalations_sent": 1,
                    "user_id": USER_1,
                },
            ),
            patch(
                "app.api.safety.endpoints.cancel_safety_escalation",
                side_effect=DatabaseAccessError("fail"),
            ),
        ):
            with pytest.raises(HTTPException) as exc:
                await _handle_cancel_escalation("sess-1", "tok", "safe", "note")
            assert exc.value.status_code == 503

        with (
            patch(
                "app.api.safety.endpoints.fetch_safety_session",
                return_value={
                    "status": "active",
                    "escalation_cancelled_at": None,
                    "escalations_sent": 1,
                    "user_id": USER_1,
                },
            ),
            patch("app.api.safety.endpoints.cancel_safety_escalation"),
        ):
            res_ok = await _handle_cancel_escalation(
                "sess-1", "tok", "safe", "all good",
            )
            assert res_ok.status_code == 200

    # cancel_escalation & cancel_escalation_post
    with patch(
        "app.api.safety.endpoints._handle_cancel_escalation", return_value=MagicMock(),
    ):
        await cancel_escalation(req, "sess-1", "tok", "safe", "note")
        await cancel_escalation_post(
            req,
            "sess-1",
            EscalationCancelRequest(token="tok", reason="safe", note="note"),
        )
