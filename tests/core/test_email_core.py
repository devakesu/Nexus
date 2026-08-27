"""Test Suite for Test Email Core.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import asyncio
import copy
from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.email.notifications.account import (
    send_account_deletion_otp_email,
    send_account_deletion_scheduled_email,
    send_account_reactivated_email,
    send_data_export_otp_email,
    send_login_otp_email,
    send_support_appeal_otp_email,
)
from app.core.email.notifications.feedback import (
    send_feedback_admin_notification_email,
    send_feedback_closed_admin_notification_email,
    send_feedback_comment_admin_notification_email,
    send_feedback_confirmation_email,
)
from app.core.email.senders import ProviderResult, SendEmailProps
from app.core.infra.tasks import (
    safe_create_task,
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


async def test_core_infra_tasks_and_email():
    from app.core.email.config import redact_email, strip_tags

    # 1. tasks
    async def sample_task():
        await asyncio.sleep(0.01)
        return "done"

    t = safe_create_task(sample_task())
    assert t is not None
    await t

    # 2. email redaction & stripping
    assert redact_email("alice@example.com") == "a***e@example.com"
    assert redact_email("invalid") == "invalid"
    assert strip_tags("<h1>Hello</h1>") == "Hello"


async def test_core_email_notifications_and_senders_deep():
    from app.core.email.notifications.account import (
        send_account_deletion_otp_email,
        send_account_deletion_scheduled_email,
        send_account_reactivated_email,
        send_data_export_otp_email,
        send_login_otp_email,
        send_support_appeal_otp_email,
    )
    from app.core.email.notifications.feedback import (
        send_feedback_admin_notification_email,
        send_feedback_confirmation_email,
    )
    from app.core.email.notifications.safety import (
        send_trusted_contact_removed_email,
    )
    from app.core.email.notifications.welcome import (
        send_bootstrap_welcome_email,
    )

    with (
        patch(
            "app.core.email.notifications.account.email_pkg.send_email",
            AsyncMock(return_value=MagicMock(success=True)),
        ),
        patch(
            "app.core.email.notifications.feedback.email_pkg.send_email",
            AsyncMock(return_value=MagicMock(success=True)),
        ),
        patch(
            "app.core.email.notifications.safety.email_pkg.send_email",
            AsyncMock(return_value=MagicMock(success=True)),
        ),
        patch(
            "app.core.email.notifications.welcome.email_pkg.send_email",
            AsyncMock(return_value=MagicMock(success=True)),
        ),
    ):
        await send_login_otp_email("a@b.com", "123456")
        await send_account_deletion_otp_email("a@b.com", "123456", 14)
        await send_data_export_otp_email("a@b.com", "123456")
        await send_support_appeal_otp_email("a@b.com", "123456")
        await send_account_deletion_scheduled_email(
            "a@b.com", datetime.now(timezone.utc),
        )
        await send_account_reactivated_email("a@b.com")

        await send_feedback_confirmation_email(
            "a@b.com", "bug_report", "Crash", "1", None,
        )
        await send_feedback_admin_notification_email(
            "1", "bug_report", "Crash", "Msg", USER_1, "a@b.com",
        )

        await send_trusted_contact_removed_email("a@b.com", "Alice", "Bob")
        await send_bootstrap_welcome_email("a@b.com", None)


async def test_email_notifications_exception_handlers():
    from app.core.email.notifications.account import (
        send_account_deletion_otp_email,
        send_account_deletion_scheduled_email,
        send_account_reactivated_email,
        send_data_export_otp_email,
        send_login_otp_email,
        send_support_appeal_otp_email,
    )
    from app.core.email.notifications.feedback import (
        send_feedback_admin_notification_email,
        send_feedback_closed_admin_notification_email,
        send_feedback_comment_admin_notification_email,
        send_feedback_confirmation_email,
    )
    from app.core.email.notifications.safety import send_trusted_contact_removed_email
    from app.core.email.notifications.welcome import send_bootstrap_welcome_email

    # Test failure results and exceptions for account emails
    with patch(
        "app.core.email.notifications.account.email_pkg.send_email",
        AsyncMock(side_effect=Exception("SMTP fail")),
    ):
        r1 = await send_login_otp_email("test@example.com", "123456")
        assert not r1.success
        assert "SMTP fail" in (r1.error or "")

        r2 = await send_account_deletion_otp_email("test@example.com", "123456")
        assert not r2.success

        r3 = await send_data_export_otp_email("test@example.com", "123456")
        assert not r3.success

        r4 = await send_support_appeal_otp_email("test@example.com", "123456")
        assert not r4.success

        r5 = await send_account_deletion_scheduled_email(
            "test@example.com", datetime.now(timezone.utc), 14,
        )
        assert not r5.success

        r6 = await send_account_reactivated_email("test@example.com")
        assert not r6.success

    # Feedback emails
    with patch(
        "app.core.email.notifications.feedback.email_pkg.send_email",
        AsyncMock(side_effect=Exception("Feedback SMTP fail")),
    ):
        f1 = await send_feedback_confirmation_email(
            "test@example.com", "help", "Help sub", "rep-1",
        )
        assert not f1.success

        f2 = await send_feedback_admin_notification_email(
            "rep-1", "help", "Help sub", "msg", USER_1, "test@example.com",
        )
        assert not f2.success

        f3 = await send_feedback_comment_admin_notification_email(
            "rep-1", "help", "Help sub", "comment msg", "admin", "test@example.com",
        )
        assert not f3.success

        f4 = await send_feedback_closed_admin_notification_email(
            "rep-1", "help", "Help sub", "closed", USER_1, "test@example.com",
        )
        assert not f4.success

    # Safety email exception
    with patch(
        "app.core.email.notifications.safety.email_pkg.send_email",
        AsyncMock(side_effect=Exception("Safety email fail")),
    ):
        s1 = await send_trusted_contact_removed_email(
            "contact@example.com", "Bob", "Alice",
        )
        assert not s1.success

    # Welcome email exception
    with patch(
        "app.core.email.notifications.welcome.email_pkg.send_email",
        AsyncMock(side_effect=Exception("Welcome fail")),
    ):
        w1 = await send_bootstrap_welcome_email("test@example.com")
        assert not w1.success


async def test_core_email_senders_deep():
    from app.core.email import senders

    # Reset globals
    senders._sendpulse_token = None
    senders._sendpulse_token_expires_at = 0.0

    props = SendEmailProps(
        to="user@example.com",
        subject="Test Email",
        html="<p>Hello User</p>",
        text="Hello User",
        from_name="Nexus",
        reply_to="reply@nexus.test",
    )

    # get_sendpulse_token: missing credentials & HTTP status error
    with patch.object(senders, "has_sendpulse", False), pytest.raises(ValueError):
        await senders.get_sendpulse_token()

    mock_client = MagicMock()
    with (
        patch.object(senders, "has_sendpulse", True),
        patch.object(senders, "_get_email_client", return_value=mock_client),
    ):
        mock_res = MagicMock()
        mock_res.status_code = 401
        mock_client.post = AsyncMock(return_value=mock_res)
        with pytest.raises(RuntimeError):
            await senders.get_sendpulse_token()

    # send_via_sendpulse: unconfigured, HTTP error with message, success
    with patch.object(senders, "has_sendpulse", False), pytest.raises(ValueError):
        await senders.send_via_sendpulse(props)

    with (
        patch.object(senders, "has_sendpulse", True),
        patch.object(senders, "get_sendpulse_token", return_value="tok-123"),
        patch.object(senders, "_get_email_client", return_value=mock_client),
    ):
        err_res = MagicMock()
        err_res.status_code = 400
        err_res.json.return_value = {"message": "Invalid recipient"}
        mock_client.post = AsyncMock(return_value=err_res)
        with pytest.raises(RuntimeError):
            await senders.send_via_sendpulse(props)

        ok_res = MagicMock()
        ok_res.status_code = 200
        ok_res.json.return_value = {"id": "msg-sp-123"}
        mock_client.post = AsyncMock(return_value=ok_res)
        sp_result = await senders.send_via_sendpulse(props)
        assert sp_result.success is True
        assert sp_result.id == "msg-sp-123"

    # send_via_brevo: unconfigured, HTTP error with message, success
    with patch.object(senders, "has_brevo", False), pytest.raises(ValueError):
        await senders.send_via_brevo(props)

    with (
        patch.object(senders, "has_brevo", True),
        patch.object(senders, "_get_email_client", return_value=mock_client),
    ):
        err_brevo = MagicMock()
        err_brevo.status_code = 500
        err_brevo.json.return_value = {"message": "Brevo down"}
        mock_client.post = AsyncMock(return_value=err_brevo)
        with pytest.raises(RuntimeError):
            await senders.send_via_brevo(props)

        ok_brevo = MagicMock()
        ok_brevo.status_code = 201
        ok_brevo.json.return_value = {"messageId": "msg-br-123"}
        mock_client.post = AsyncMock(return_value=ok_brevo)
        br_result = await senders.send_via_brevo(props)
        assert br_result.success is True
        assert br_result.id == "msg-br-123"

    # get_providers & execute_failover (both providers fail)
    p_config_sp = senders.get_providers(use_sp=True)
    assert p_config_sp.p_name == "SendPulse"

    p_config_br = senders.get_providers(use_sp=False)
    assert p_config_br.p_name == "Brevo"

    sec_fn = AsyncMock(side_effect=Exception("Secondary failed"))
    failover_res = await senders.execute_failover(
        sec_fn, props, "Brevo", Exception("Primary failed"),
    )
    assert failover_res.success is False
    assert "All providers failed" in str(failover_res.error)

    # send_email: no providers configured, failover triggered with secondary
    with (
        patch.object(senders, "has_brevo", False),
        patch.object(senders, "has_sendpulse", False),pytest.raises(RuntimeError),
    ):
        await senders.send_email(props)

    with (
        patch.object(senders, "has_brevo", True),
        patch.object(senders, "has_sendpulse", True),
        patch.object(senders, "send_via_brevo", side_effect=Exception("Brevo fail")),
        patch.object(
            senders,
            "send_via_sendpulse",
            return_value=ProviderResult(
                success=True, provider="SendPulse", id="msg-sp",
            ),
        ),
    ):
        email_res = await senders.send_email(props)
        assert email_res.success is True
        assert email_res.provider == "SendPulse"


async def test_core_email_notifications() -> None:
    mock_provider_ok = ProviderResult(provider="Brevo", id="msg-1", success=True)
    with patch("app.core.email.send_email", AsyncMock(return_value=mock_provider_ok)):
        # Account notifications
        r1 = await send_login_otp_email("user@berkeley.edu", "123456")
        assert r1.success is True

        r2 = await send_account_deletion_otp_email("user@berkeley.edu", "123456")
        assert r2.success is True

        r3 = await send_data_export_otp_email("user@berkeley.edu", "123456")
        assert r3.success is True

        r4 = await send_support_appeal_otp_email("user@berkeley.edu", "123456")
        assert r4.success is True

        r5 = await send_account_deletion_scheduled_email(
            "user@berkeley.edu", "2026-09-01T00:00:00Z",
        )
        assert r5.success is True

        r6 = await send_account_reactivated_email("user@berkeley.edu")
        assert r6.success is True

        # Feedback notifications
        fb1 = await send_feedback_confirmation_email(
            email="user@berkeley.edu",
            query_type="bug_report",
            subject="Bug report",
            report_id="rep-1",
        )
        assert fb1.success is True

        fb2 = await send_feedback_admin_notification_email(
            report_id="rep-1",
            query_type="bug_report",
            subject="Bug report",
            message="Something broken",
            user_id=USER_1,
            submitter_email="user@berkeley.edu",
        )
        assert fb2.success is True

        fb3 = await send_feedback_comment_admin_notification_email(
            report_id="rep-1",
            query_type="bug_report",
            subject="Bug report",
            comment_body="New details",
            user_id=USER_1,
            submitter_email="user@berkeley.edu",
        )
        assert fb3.success is True

        fb4 = await send_feedback_closed_admin_notification_email(
            report_id="rep-1",
            query_type="bug_report",
            subject="Bug report",
            reason="resolved",
            user_id=USER_1,
            submitter_email="user@berkeley.edu",
        )
        assert fb4.success is True
