"""Test Suite for Test Security Core.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.utils.sms import (
    compose_contact_added_message,
    compose_contact_self_removed_message,
    compose_inform_message,
    compose_sos_message,
    compose_unreachable_message,
    make_contact_portal_token,
    make_escalation_cancel_token,
    redact_phone,
    sanitize_sms_text,
    send_sms,
    send_via_twilio,
    verify_contact_portal_token,
    verify_escalation_cancel_token,
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


async def test_core_sms_utilities() -> None:
    # Sanitization
    assert sanitize_sms_text("Hello  World\n\t!") == "Hello World !"
    assert sanitize_sms_text(None) is None

    # Redaction
    assert redact_phone("+14155552671") == "***2671"

    # Messages
    sos = compose_sos_message(
        name="Alice", silent=False, location={"lat": 37.7749, "lng": -122.4194},
    )
    assert "Alice" in sos
    assert "maps.google.com" in sos

    inf = compose_inform_message(name="Alice", location=None, event_label="Cafe")
    assert "Alice" in inf

    cta = compose_contact_added_message(
        user_name="Alice", manage_link="https://nexus.test/c1",
    )
    assert "Alice" in cta

    csr = compose_contact_self_removed_message(contact_name="Bob")
    assert "Bob" in csr

    unr = compose_unreachable_message(
        name="Alice",
        escalation_number=1,
        battery_percent=80,
        connection_type="wifi",
        event_label="Cafe",
        cancel_link="https://nexus.test/cancel",
    )
    assert "Alice" in unr

    # Tokens
    tok = make_escalation_cancel_token(SESSION_1, 1)
    assert verify_escalation_cancel_token(SESSION_1, tok) == 1
    assert verify_escalation_cancel_token(SESSION_1, "invalid") is None

    c_tok = make_contact_portal_token("contact-1")
    assert verify_contact_portal_token(c_tok) == "contact-1"
    assert verify_contact_portal_token("invalid") is None

    # send_via_twilio and send_sms
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {"sid": "SM123"}
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value.post = AsyncMock(return_value=mock_resp)

    with (
        patch("app.core.utils.sms.httpx.AsyncClient", return_value=mock_client),
        patch("app.core.utils.sms.has_twilio", True),
        patch("app.core.utils.sms.settings.twilio_account_sid", "AC123"),
        patch("app.core.utils.sms.settings.twilio_auth_token", "secret"),
        patch("app.core.utils.sms.settings.twilio_from_number", "+14155550000"),
    ):
        res = await send_via_twilio("+14155552671", "Test")
        assert res.success is True

        res2 = await send_sms("+14155552671", "Test")
        assert res2.success is True
