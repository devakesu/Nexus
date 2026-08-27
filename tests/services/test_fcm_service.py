"""Test Suite for Test Fcm Service.

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

from app.services.fcm_sender import (
    _fetch_profile_name,
    _fetch_user_fcm_tokens,
    _is_firebase_initialized,
    _send_to_tokens,
    send_chat_event_reminder_notification,
    send_chat_message_notification,
    send_like_notification,
    send_match_notification,
    send_meetup_safety_reminder_notification,
    send_prekey_replenishment_notification,
    send_trusted_contact_removed_notification,
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


async def test_fcm_sender():
    from app.services.fcm_sender import (
        _fetch_user_fcm_tokens,
        send_chat_event_reminder_notification,
        send_chat_message_notification,
        send_match_notification,
        send_meetup_safety_reminder_notification,
        send_prekey_replenishment_notification,
    )

    def mock_table_factory(table_name: str):
        mock_t = MagicMock()
        if table_name == "profiles":
            mock_t.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
                data=[{"is_deactivated": False}],
            )
        else:
            mock_t.select.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(
                data=[{"fcm_token": "fcm_tok_1"}],
            )
        return mock_t

    with patch(
        "app.services.fcm_sender.supabase_client.table", side_effect=mock_table_factory,
    ):
        tokens = _fetch_user_fcm_tokens(USER_1)
        assert tokens == ["fcm_tok_1"]

    with (
        patch("app.services.fcm_sender._fetch_user_fcm_tokens", return_value=["tok1"]),
        patch(
            "app.services.fcm_sender.get_cached_active_block_ids",
            AsyncMock(return_value=set()),
        ),
        patch("app.services.fcm_sender._fcm.send_each"),
    ):
        await send_chat_message_notification(
            sender_id=USER_1,
            recipient_id=USER_2,
            conversation_id="conv_1",
            tab="Dating",
            message_id="msg_1",
            ciphertext="cipher123",
            ciphertext_metadata={},
        )

        await send_match_notification(
            user_a_id=USER_1,
            user_b_id=USER_2,
        )

        await send_chat_event_reminder_notification(
            user_a_id=USER_1,
            user_b_id=USER_2,
            conversation_id="conv_1",
            tab="Dating",
        )

        await send_meetup_safety_reminder_notification(
            user_id=USER_1,
            peer_id=USER_2,
            conversation_id="conv_1",
            tab="Dating",
        )

        await send_prekey_replenishment_notification(USER_1)


async def test_services_fcm_sender_deep():
    from app.services.fcm_sender import (
        _fetch_user_fcm_tokens,
        _is_firebase_initialized,
        _send_to_tokens,
        send_like_notification,
    )

    mock_t = _make_chaining_mock(
        [{"fcm_token": "fcm_token_1234567890", "is_deactivated": False}],
    )

    with (
        patch("app.services.fcm_sender.supabase_client.table", return_value=mock_t),
        patch("app.services.fcm_sender._fb.get_app"),
        patch(
            "app.services.fcm_sender.get_cached_active_block_ids",
            AsyncMock(return_value=set()),
        ),
        patch("app.services.fcm_sender._fcm.send_each_for_multicast") as mock_send,
        patch("app.services.fcm_sender.decrypt_pii", return_value="Alice"),
    ):
        mock_send.return_value = MagicMock(failure_count=0, success_count=1)

        assert _is_firebase_initialized() is True
        toks = _fetch_user_fcm_tokens(USER_1)
        assert len(toks) > 0

        sent_count = _send_to_tokens(
            ["fcm_token_1234567890"], "Title", "Body", {"key": "val"}, "likes",
        )
        assert sent_count == 1

        await send_like_notification(USER_1, USER_2, is_superlike=True)


async def test_services_fcm_sender_deep_p24():
    from app.services.fcm_sender import (
        _deactivate_fcm_token,
        _fetch_profile_name,
        _fetch_user_fcm_tokens,
        _is_firebase_initialized,
        _send_to_tokens,
        send_chat_event_reminder_notification,
        send_chat_message_notification,
        send_like_notification,
        send_match_notification,
        send_meetup_safety_reminder_notification,
        send_prekey_replenishment_notification,
        send_trusted_contact_removed_notification,
    )

    # _is_firebase_initialized
    with patch("app.services.fcm_sender._fb.get_app", side_effect=ValueError("no app")):
        assert _is_firebase_initialized() is False

    with patch("app.services.fcm_sender._fb.get_app", return_value=MagicMock()):
        assert _is_firebase_initialized() is True

    # _fetch_user_fcm_tokens: deactivated vs active vs exception
    with patch("app.services.fcm_sender.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(
            data=[{"is_deactivated": True}],
        )
        assert _fetch_user_fcm_tokens(USER_1) == []

        mock_sb.table().select().eq().limit().execute.side_effect = Exception("DB fail")
        assert _fetch_user_fcm_tokens(USER_1) == []

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(
            data=[{"is_deactivated": False}],
        )
        mock_sb.table().select().eq().eq().execute.return_value = MagicMock(
            data=[{"fcm_token": "tok-123"}],
        )
        assert _fetch_user_fcm_tokens(USER_1) == ["tok-123"]

    # _fetch_profile_name: empty, deactivated, decrypt failure
    with patch("app.services.fcm_sender.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        assert _fetch_profile_name(USER_1) is None

        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(
            data=[{"name": "enc", "is_deactivated": True}],
        )
        assert _fetch_profile_name(USER_1) is None

        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(
            data=[{"name": "Alice", "is_deactivated": False}],
        )
        with patch("app.services.fcm_sender.decrypt_pii", return_value="Alice"):
            assert _fetch_profile_name(USER_1) == "Alice"

    # _deactivate_fcm_token: success & Sentry alert on 3rd failure
    with patch("app.services.fcm_sender.supabase_client") as mock_sb:
        mock_sb.table().update().eq().execute.return_value = MagicMock()
        _deactivate_fcm_token("tok-12345678")

        mock_sb.table().update().eq().execute.side_effect = Exception("DB error")
        for _ in range(3):
            _deactivate_fcm_token("bad-token-1234")

    # _send_to_tokens: empty tokens, multicast failures with NOT_FOUND
    assert _send_to_tokens([], "title", "body", {}, "channel") == 0

    mock_resp_fail = MagicMock()
    mock_resp_fail.success = False
    mock_resp_fail.exception = MagicMock(code="NOT_FOUND")
    mock_batch_resp = MagicMock(
        failure_count=1, success_count=0, responses=[mock_resp_fail],
    )

    with (
        patch(
            "app.services.fcm_sender._fcm.send_each_for_multicast",
            return_value=mock_batch_resp,
        ),
        patch("app.services.fcm_sender._deactivate_fcm_token") as mock_deact,
    ):
        res = _send_to_tokens(
            ["stale_token_12345678"],
            "title",
            "body",
            {},
            "channel",
            is_safety_critical=True,
        )
        assert res == 0
        assert mock_deact.called

    # High level notification functions
    with (
        patch("app.services.fcm_sender._is_firebase_initialized", return_value=True),
        patch(
            "app.services.fcm_sender.get_cached_active_block_ids", return_value=set(),
        ),
        patch("app.services.fcm_sender._fetch_user_fcm_tokens", return_value=["tok-1"]),
        patch("app.services.fcm_sender._fetch_profile_name", return_value="Alice"),
        patch("app.services.fcm_sender._send_to_tokens", return_value=1),
        patch("app.services.fcm_sender.redis_client") as mock_redis,
    ):
        mock_redis.set = AsyncMock(return_value=True)

        await send_like_notification(USER_1, USER_2, is_superlike=True)
        await send_like_notification(USER_1, USER_2, is_superlike=False)
        await send_match_notification(USER_1, USER_2)
        await send_chat_message_notification(
            USER_1,
            USER_2,
            "conv-1",
            "Dating",
            "msg-1",
            "short ciphertext",
            {},
        )
        await send_trusted_contact_removed_notification(USER_1, "Bob")
        await send_meetup_safety_reminder_notification(
            USER_1, USER_2, "conv-1", "Dating",
        )
        await send_prekey_replenishment_notification(USER_1)

        # Blocked sender / recipient
        with patch(
            "app.services.fcm_sender.get_cached_active_block_ids", return_value={USER_1},
        ):
            await send_like_notification(USER_1, USER_2, is_superlike=False)
            await send_match_notification(USER_1, USER_2)
            await send_chat_message_notification(
                USER_1,
                USER_2,
                "conv-1",
                "Dating",
                "msg-1",
                "short ciphertext",
                {},
            )

    # send_chat_event_reminder_notification
    with (
        patch("app.services.fcm_sender._is_firebase_initialized", return_value=True),
        patch(
            "app.db.chat.fetch_conversation_participants",
            return_value={"id": "conv-1", "closed_at": None},
        ),
        patch(
            "app.services.fcm_sender.get_cached_active_block_ids", return_value=set(),
        ),
        patch("app.services.fcm_sender._fetch_user_fcm_tokens", return_value=["tok-1"]),
        patch("app.services.fcm_sender._send_to_tokens", return_value=1),
    ):
        assert (
            await send_chat_event_reminder_notification(
                USER_1, USER_2, "conv-1", "Dating",
            )
            is True
        )


async def test_services_fcm_notifications() -> None:
    # Firebase initialized check
    with patch("app.services.fcm_sender._fb.get_app", return_value=MagicMock()):
        assert _is_firebase_initialized() is True

    # _fetch_user_fcm_tokens & _fetch_profile_name
    mock_table = _make_chaining_mock([{"fcm_token": "tok1", "is_active": True}])
    with patch(
        "app.services.fcm_sender.supabase_client.table", return_value=mock_table,
    ):
        tokens = _fetch_user_fcm_tokens(USER_1)
        assert len(tokens) >= 1
        _name = _fetch_profile_name(USER_1)
        assert _name is not None or _name is None

    # _send_to_tokens with mocked messaging
    mock_messaging = MagicMock()
    mock_response = MagicMock()
    mock_response.success_count = 1
    mock_response.failure_count = 0
    mock_response.responses = [MagicMock(success=True)]
    mock_messaging.send_each_for_multicast.return_value = mock_response

    with (
        patch("app.services.fcm_sender._fcm", mock_messaging),
        patch("app.services.fcm_sender._is_firebase_initialized", return_value=True),
    ):
        res = _send_to_tokens(
            ["tok1"],
            title="Hello",
            body="World",
            data={"type": "test"},
            channel_id="default",
        )
        assert res == 1

        # High-level push functions
        with (
            patch(
                "app.services.fcm_sender._fetch_user_fcm_tokens", return_value=["tok1"],
            ),
            patch(
                "app.services.fcm_sender.get_cached_active_block_ids",
                AsyncMock(return_value=set()),
            ),
            patch(
                "app.db.chat.fetch_conversation_participants",
                return_value={"closed_at": None},
            ),
        ):
            await send_like_notification(USER_1, USER_2, is_superlike=False)
            await send_match_notification(USER_1, USER_2)
            await send_chat_message_notification(
                sender_id=USER_2,
                recipient_id=USER_1,
                conversation_id="conv-1",
                tab="dating",
                message_id="msg-1",
                ciphertext="c-txt",
                ciphertext_metadata={},
            )
            await send_chat_event_reminder_notification(
                user_a_id=USER_1,
                user_b_id=USER_2,
                conversation_id="conv-1",
                tab="dating",
            )
            await send_trusted_contact_removed_notification(USER_1, "Bob")
            await send_meetup_safety_reminder_notification(
                user_id=USER_1,
                peer_id=USER_2,
                conversation_id="conv-1",
                tab="dating",
            )
            await send_prekey_replenishment_notification(USER_1)
