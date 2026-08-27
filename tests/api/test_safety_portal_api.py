"""Test Suite for Test Safety Portal Api.

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

from app.api.safety.endpoints import (
    cancel_escalation,
    checkin_session,
    end_session,
    start_session,
)
from app.api.safety.portal.endpoints import contact_portal_page, portal_page
from app.db.client import DatabaseAccessError
from app.models import (
    SafetyContactPortalOtpRequestRequest,
    SafetyContactPortalOtpVerifyRequest,
    SafetyPortalOtpRequestRequest,
    SafetyPortalOtpVerifyRequest,
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


async def test_safety_portal_endpoints_deep():
    from app.api.safety.portal.endpoints import (
        _enforce_contact_remove_rate_limit,
        _notify_user_of_contact_self_removal,
        contact_portal_page,
        get_contact_portal_details,
        get_portal_details,
        portal_page,
        remove_trusted_contact,
        request_contact_portal_otp,
        request_portal_otp,
        verify_contact_portal_otp,
        verify_portal_otp,
    )

    req = make_dummy_request()

    # request_portal_otp: resend cooldown, session not found vs ended stale, DB error, sentinel OTP
    with patch("app.api.safety.portal.endpoints.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(return_value=False)
        with pytest.raises(HTTPException) as exc:
            await request_portal_otp(
                req, "sess-1", SafetyPortalOtpRequestRequest(phone=PHONE_VALID),
            )
        assert exc.value.status_code == 429

        mock_redis.set = AsyncMock(return_value=True)
        with patch(
            "app.api.safety.portal.endpoints.fetch_safety_session",
            side_effect=DatabaseAccessError("fail"),
        ):
            with pytest.raises(HTTPException) as exc:
                await request_portal_otp(
                    req, "sess-1", SafetyPortalOtpRequestRequest(phone=PHONE_VALID),
                )
            assert exc.value.status_code == 503

        # Stale session
        with (
            patch(
                "app.api.safety.portal.endpoints.fetch_safety_session",
                return_value={
                    "status": "ended",
                    "last_escalated_at": "2020-01-01T00:00:00Z",
                },
            ),
            patch(
                "app.api.safety.portal.endpoints.redis_client.setex",
                new_callable=AsyncMock,
            ),
        ):
            res_stale = await request_portal_otp(
                req, "sess-1", SafetyPortalOtpRequestRequest(phone=PHONE_VALID),
            )
            assert res_stale.sent is True

    # verify_portal_otp
    with (
        patch(
            "app.api.safety.portal.endpoints.verify_and_consume_hashed_otp",
            new_callable=AsyncMock,
        ),
        patch(
            "app.api.safety.portal.endpoints.make_portal_access_token",
            return_value="tok-portal",
        ),
    ):
        v_res = await verify_portal_otp(
            req,
            "sess-1",
            SafetyPortalOtpVerifyRequest(phone=PHONE_VALID, code="123456"),
        )
        assert v_res.token == "tok-portal"

    # get_portal_details: unauth, session not found, DB error, active location, download url
    with pytest.raises(HTTPException) as exc:
        await get_portal_details(req, "sess-1", authorization=None)
    assert exc.value.status_code == 401

    with (
        patch(
            "app.api.safety.portal.endpoints.verify_portal_access_token",
            return_value="phone-hash",
        ),
        patch(
            "app.api.safety.portal.endpoints.hash_phone_identifier",
            return_value="phone-hash",
        ),
    ):
        with patch(
            "app.api.safety.portal.endpoints.fetch_safety_session", return_value=None,
        ):
            with pytest.raises(HTTPException) as exc:
                await get_portal_details(req, "sess-1", authorization="Bearer tok")
            assert exc.value.status_code == 404

        with (
            patch(
                "app.api.safety.portal.endpoints.fetch_safety_session",
                return_value={"id": "sess-1", "user_id": USER_1, "status": "active"},
            ),
            patch(
                "app.api.safety.portal.endpoints.fetch_safety_contacts",
                return_value=[{"phone": PHONE_VALID}],
            ),
            patch(
                "app.api.safety.portal.endpoints.fetch_alerts_for_session",
                side_effect=DatabaseAccessError("fail"),
            ),
        ):
            with pytest.raises(HTTPException) as exc:
                await get_portal_details(req, "sess-1", authorization="Bearer tok")
            assert exc.value.status_code == 503

        with (
            patch(
                "app.api.safety.portal.endpoints.fetch_safety_session",
                return_value={
                    "id": "sess-1",
                    "user_id": USER_1,
                    "status": "active",
                    "event_context": {"label": "Meet"},
                },
            ),
            patch(
                "app.api.safety.portal.endpoints.fetch_safety_contacts",
                return_value=[{"phone": PHONE_VALID}],
            ),
            patch(
                "app.api.safety.portal.endpoints.fetch_alerts_for_session",
                return_value=[
                    {
                        "id": "a-1",
                        "current_location": {"lat": 40.0, "lng": -73.0},
                        "created_at": "2026-08-26T00:00:00Z",
                    },
                ],
            ),
            patch(
                "app.api.safety.portal.endpoints.fetch_evidence_for_alert_ids",
                return_value=[
                    {
                        "id": "ev-1",
                        "storage_path": "path",
                        "content_type": "audio",
                        "media_key_base64": "key",
                        "created_at": "2026-08-26T00:00:00Z",
                    },
                ],
            ),
            patch(
                "app.api.safety.portal.endpoints.create_evidence_download_url",
                return_value="https://download.test/ev",
            ),
        ):
            det = await get_portal_details(req, "sess-1", authorization="Bearer tok")
            assert det.event_label == "Meet"
            assert det.last_location is not None
            assert len(det.evidence) == 1

    # request_contact_portal_otp & verify_contact_portal_otp: bad token, cooldown, DB error
    with patch(
        "app.api.safety.portal.endpoints.verify_contact_portal_token", return_value=None,
    ):
        with pytest.raises(HTTPException) as exc:
            await request_contact_portal_otp(
                req, "bad-tok", SafetyContactPortalOtpRequestRequest(phone=PHONE_VALID),
            )
        assert exc.value.status_code == 400

        with pytest.raises(HTTPException) as exc:
            await verify_contact_portal_otp(
                req,
                "bad-tok",
                SafetyContactPortalOtpVerifyRequest(phone=PHONE_VALID, code="123456"),
            )
        assert exc.value.status_code == 400

    with (
        patch(
            "app.api.safety.portal.endpoints.verify_contact_portal_token",
            return_value="cnt-1",
        ),
        patch("app.api.safety.portal.endpoints.redis_client") as mock_redis,
    ):
        mock_redis.set = AsyncMock(return_value=False)
        with pytest.raises(HTTPException) as exc:
            await request_contact_portal_otp(
                req, "cnt-1", SafetyContactPortalOtpRequestRequest(phone=PHONE_VALID),
            )
        assert exc.value.status_code == 429

        mock_redis.set = AsyncMock(return_value=True)
        with patch(
            "app.api.safety.portal.endpoints.fetch_safety_contact_by_id",
            side_effect=DatabaseAccessError("fail"),
        ):
            with pytest.raises(HTTPException) as exc:
                await request_contact_portal_otp(
                    req,
                    "cnt-1",
                    SafetyContactPortalOtpRequestRequest(phone=PHONE_VALID),
                )
            assert exc.value.status_code == 503

    # get_contact_portal_details: bad token, unauth, contact not found, phone mismatch, DB error, profile not found, success
    with patch(
        "app.api.safety.portal.endpoints.verify_contact_portal_token", return_value=None,
    ):
        with pytest.raises(HTTPException) as exc:
            await get_contact_portal_details(req, "bad-tok")
        assert exc.value.status_code == 400

    with (
        patch(
            "app.api.safety.portal.endpoints.verify_contact_portal_token",
            return_value="cnt-1",
        ),
        patch(
            "app.api.safety.portal.endpoints.verify_portal_access_token",
            return_value=None,
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await get_contact_portal_details(req, "cnt-1", authorization="Bearer tok")
        assert exc.value.status_code == 401

    with (
        patch(
            "app.api.safety.portal.endpoints.verify_contact_portal_token",
            return_value="cnt-1",
        ),
        patch(
            "app.api.safety.portal.endpoints.verify_portal_access_token",
            return_value="bad-hash",
        ),
        patch(
            "app.api.safety.portal.endpoints.fetch_safety_contact_by_id",
            return_value=None,
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await get_contact_portal_details(req, "cnt-1", authorization="Bearer tok")
        assert exc.value.status_code == 404

    with (
        patch(
            "app.api.safety.portal.endpoints.verify_contact_portal_token",
            return_value="cnt-1",
        ),
        patch(
            "app.api.safety.portal.endpoints.verify_portal_access_token",
            return_value="different-hash",
        ),
        patch(
            "app.api.safety.portal.endpoints.fetch_safety_contact_by_id",
            return_value={"id": "cnt-1", "user_id": USER_1, "phone": PHONE_VALID},
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await get_contact_portal_details(req, "cnt-1", authorization="Bearer tok")
        assert exc.value.status_code == 401

    with (
        patch(
            "app.api.safety.portal.endpoints.verify_contact_portal_token",
            return_value="cnt-1",
        ),
        patch(
            "app.api.safety.portal.endpoints.hash_phone_identifier",
            return_value="matching-hash",
        ),
        patch(
            "app.api.safety.portal.endpoints.verify_portal_access_token",
            return_value="matching-hash",
        ),
        patch(
            "app.api.safety.portal.endpoints.fetch_safety_contact_by_id",
            return_value={"id": "cnt-1", "user_id": USER_1, "phone": PHONE_VALID},
        ),
        patch(
            "app.api.safety.portal.endpoints.fetch_contact_facing_profile_summary",
            side_effect=DatabaseAccessError("fail"),
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await get_contact_portal_details(req, "cnt-1", authorization="Bearer tok")
        assert exc.value.status_code == 503

    # _notify_user_of_contact_self_removal: DB error vs success
    with patch(
        "app.api.safety.portal.endpoints.fetch_public_user",
        side_effect=DatabaseAccessError("fail"),
    ):
        await _notify_user_of_contact_self_removal(USER_1, "Bob")

    with (
        patch(
            "app.api.safety.portal.endpoints.fetch_public_user",
            return_value={"mobile": PHONE_VALID},
        ),
        patch(
            "app.api.safety.portal.endpoints.fetch_contact_facing_profile_summary",
            return_value={"name": "Alice"},
        ),
        patch(
            "app.api.safety.portal.endpoints.get_user_email_by_id",
            return_value="alice@nexus.test",
        ),
        patch(
            "app.api.safety.portal.endpoints.send_trusted_contact_removed_notification",
        ),
        patch(
            "app.api.safety.portal.endpoints.send_sms",
            return_value=MagicMock(success=True),
        ),
        patch("app.api.safety.portal.endpoints.send_trusted_contact_removed_email"),
    ):
        await _notify_user_of_contact_self_removal(USER_1, "Bob")

    # _enforce_contact_remove_rate_limit: under vs over limit
    with patch("app.api.safety.portal.endpoints.redis_client") as mock_redis:
        mock_redis.incr = AsyncMock(return_value=1)
        mock_redis.expire = AsyncMock()
        await _enforce_contact_remove_rate_limit("token-1")

        mock_redis.incr = AsyncMock(return_value=10)
        with pytest.raises(HTTPException) as exc:
            await _enforce_contact_remove_rate_limit("token-1")
        assert exc.value.status_code == 429

    # remove_trusted_contact & pages
    with (
        patch(
            "app.api.safety.portal.endpoints.verify_contact_portal_token",
            return_value="cnt-1",
        ),
        patch(
            "app.api.safety.portal.endpoints.hash_phone_identifier",
            return_value="matching-hash",
        ),
        patch(
            "app.api.safety.portal.endpoints.verify_portal_access_token",
            return_value="matching-hash",
        ),
        patch("app.api.safety.portal.endpoints._enforce_contact_remove_rate_limit"),
        patch(
            "app.api.safety.portal.endpoints.fetch_safety_contact_by_id",
            return_value={"id": "cnt-1", "user_id": USER_1, "phone": PHONE_VALID},
        ),
        patch(
            "app.api.safety.portal.endpoints.remove_safety_contact_self_service",
            return_value={"user_id": USER_1, "name": "Bob"},
        ),
        patch("app.api.safety.portal.endpoints.safe_create_task"),
    ):
        res = await remove_trusted_contact(req, "cnt-1", authorization="Bearer tok")
        assert res.removed is True

    await portal_page(req, "sess-1")
    with patch(
        "app.api.safety.portal.endpoints.verify_contact_portal_token",
        return_value="cnt-1",
    ):
        await contact_portal_page(req, "cnt-1")


async def test_api_safety_endpoints_and_portal() -> None:
    mock_request = MagicMock()
    now = datetime.now(timezone.utc)

    with (
        patch(
            "app.api.safety.endpoints.start_safety_session",
            return_value={"id": SESSION_1, "status": "active"},
        ),
        patch(
            "app.api.safety.endpoints.heartbeat_safety_session",
            return_value={"id": SESSION_1, "status": "active"},
        ),
        patch(
            "app.api.safety.endpoints.end_safety_session",
            return_value={"id": SESSION_1, "status": "ended"},
        ),
        patch(
            "app.api.safety.endpoints.cancel_safety_escalation",
            return_value={"id": SESSION_1},
        ),
        patch("app.api.safety.endpoints.sync_safety_contacts"),
        patch("app.api.safety.endpoints.fetch_safety_contacts", return_value=[]),
        patch(
            "app.api.safety.endpoints.fetch_contact_facing_profile_summary",
            return_value={"display_name": "Alice"},
        ),
        patch("app.api.safety.endpoints.send_sms", AsyncMock(return_value=True)),
    ):
        # Start session
        st = await start_session(
            mock_request,
            SafetySessionStartRequest(
                interval_seconds=3600,
                label="Cafe",
                next_checkin_at=now + timedelta(hours=1),
            ),
            user_id=USER_1,
        )
        assert st.id == SESSION_1

        # Checkin & Active
        ck = await checkin_session(
            mock_request,
            SafetySessionCheckinRequest(
                session_id=SESSION_1, next_checkin_at=now + timedelta(minutes=15),
            ),
            user_id=USER_1,
        )
        assert ck.get("ok") is True

        # End & Cancel Escalation
        stp = await end_session(
            mock_request,
            SafetySessionEndRequest(session_id=SESSION_1),
            user_id=USER_1,
        )
        assert stp.get("ok") is True

        mock_sess = {
            "id": SESSION_1,
            "status": "active",
            "escalations_sent": 1,
            "user_id": USER_1,
            "escalation_cancelled_at": None,
        }
        with (
            patch(
                "app.api.safety.endpoints.verify_escalation_cancel_token",
                return_value=1,
            ),
            patch(
                "app.api.safety.endpoints.fetch_safety_session", return_value=mock_sess,
            ),
            patch("app.api.safety.endpoints.redis_client", AsyncMock()),
        ):
            c_esc = await cancel_escalation(
                mock_request,
                session_id=SESSION_1,
                token="tok",
                reason="safe",
                note=None,
            )
            assert c_esc.status_code == 200

    # Safety Portal HTML
    html_page = await portal_page(mock_request, SESSION_1)
    assert "<!doctype html>" in bytes(html_page.body).decode("utf-8").lower()

    with patch(
        "app.api.safety.portal.endpoints.verify_contact_portal_token",
        return_value="contact-1",
    ):
        c_html_page = await contact_portal_page(mock_request, "contact-1")
        assert "<!doctype html>" in bytes(c_html_page.body).decode("utf-8").lower()
