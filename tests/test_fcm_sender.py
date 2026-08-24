from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.fcm_sender import (
    send_chat_message_notification,
    send_like_notification,
)


@pytest.mark.anyio
@patch("app.services.fcm_sender._is_firebase_initialized")
@patch("app.services.fcm_sender.get_cached_active_block_ids")
@patch("app.services.fcm_sender._fetch_user_fcm_tokens")
@patch("app.services.fcm_sender._fetch_profile_name")
@patch("app.services.fcm_sender._send_to_tokens")
async def test_send_like_notification_not_blocked(
    mock_send: MagicMock,
    mock_fetch_name: MagicMock,
    mock_fetch_tokens: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_firebase_init: MagicMock,
) -> None:
    mock_firebase_init.return_value = True
    mock_get_blocks.return_value = set()  # No blocks
    mock_fetch_tokens.return_value = ["token1"]
    mock_fetch_name.return_value = "User B"

    await send_like_notification("actor-id", "target-id", False)

    mock_get_blocks.assert_called_once_with("target-id")
    mock_fetch_tokens.assert_called_once_with("target-id")
    mock_fetch_name.assert_called_once_with("actor-id")
    mock_send.assert_called_once()


@pytest.mark.anyio
@patch("app.services.fcm_sender._is_firebase_initialized")
@patch("app.services.fcm_sender.get_cached_active_block_ids")
@patch("app.services.fcm_sender._fetch_user_fcm_tokens")
@patch("app.services.fcm_sender._fetch_profile_name")
@patch("app.services.fcm_sender._send_to_tokens")
async def test_send_like_notification_blocked(
    mock_send: MagicMock,
    mock_fetch_name: MagicMock,
    mock_fetch_tokens: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_firebase_init: MagicMock,
) -> None:
    mock_firebase_init.return_value = True
    mock_get_blocks.return_value = {"actor-id"}  # Blocked!

    await send_like_notification("actor-id", "target-id", False)

    mock_get_blocks.assert_called_once_with("target-id")
    mock_fetch_tokens.assert_not_called()
    mock_fetch_name.assert_not_called()
    mock_send.assert_not_called()


@pytest.mark.anyio
@patch("app.services.fcm_sender._is_firebase_initialized")
@patch("app.services.fcm_sender.get_cached_active_block_ids")
@patch("app.services.fcm_sender._fetch_user_fcm_tokens")
@patch("app.services.fcm_sender._fetch_profile_name")
@patch("app.services.fcm_sender._send_to_tokens")
async def test_send_like_notification_deactivated_actor_skipped(
    mock_send: MagicMock,
    mock_fetch_name: MagicMock,
    mock_fetch_tokens: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_firebase_init: MagicMock,
) -> None:
    mock_firebase_init.return_value = True
    mock_get_blocks.return_value = set()
    mock_fetch_tokens.return_value = ["token1"]
    mock_fetch_name.return_value = None  # Deactivated or deleted liker!

    await send_like_notification("actor-id", "target-id", False)

    mock_fetch_tokens.assert_called_once_with("target-id")
    mock_fetch_name.assert_called_once_with("actor-id")
    # Must NOT send notification disclosing actor_id
    mock_send.assert_not_called()



@pytest.mark.anyio
@patch("app.services.fcm_sender._is_firebase_initialized")
@patch("app.services.fcm_sender.get_cached_active_block_ids")
@patch("app.services.fcm_sender._fetch_user_fcm_tokens")
@patch("app.services.fcm_sender._send_to_tokens")
async def test_send_chat_notification_not_blocked(
    mock_send: MagicMock,
    mock_fetch_tokens: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_firebase_init: MagicMock,
) -> None:
    mock_firebase_init.return_value = True
    mock_get_blocks.return_value = set()  # No blocks
    mock_fetch_tokens.return_value = ["token1"]

    await send_chat_message_notification(
        sender_id="sender-id",
        recipient_id="recipient-id",
        conversation_id="convo-id",
        tab="Dating",
        message_id="msg-id",
        ciphertext="secret",
        ciphertext_metadata="{}",
    )

    mock_get_blocks.assert_called_once_with("recipient-id")
    mock_fetch_tokens.assert_called_once_with("recipient-id")
    mock_send.assert_called_once()
    data = mock_send.call_args[0][3]
    assert data["ciphertext"] == "secret"
    assert data["ciphertext_metadata"] == "{}"
    assert data["message_id"] == "msg-id"
    assert data["actor_id"] == "sender-id"
    assert data["conversation_id"] == "convo-id"
    # Verify sensitive plaintext metadata is omitted from push payload
    assert "name" not in data
    assert "profile_pic" not in data
    assert "tab" not in data
    assert "msg_type" not in data


@pytest.mark.anyio
@patch("app.services.fcm_sender._is_firebase_initialized")
@patch("app.services.fcm_sender.get_cached_active_block_ids")
@patch("app.services.fcm_sender._fetch_user_fcm_tokens")
@patch("app.services.fcm_sender._send_to_tokens")
async def test_send_chat_notification_large_ciphertext_capped(
    mock_send: MagicMock,
    mock_fetch_tokens: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_firebase_init: MagicMock,
) -> None:
    mock_firebase_init.return_value = True
    mock_get_blocks.return_value = set()
    mock_fetch_tokens.return_value = ["token1"]

    large_ciphertext = "A" * 4000
    await send_chat_message_notification(
        sender_id="sender-id",
        recipient_id="recipient-id",
        conversation_id="convo-id",
        tab="Dating",
        message_id="msg-large-id",
        ciphertext=large_ciphertext,
        ciphertext_metadata="{}",
    )

    mock_send.assert_called_once()
    data = mock_send.call_args[0][3]
    assert "ciphertext" not in data
    assert "ciphertext_metadata" not in data
    assert data["message_id"] == "msg-large-id"
    assert data["type"] == "chat_message"
    assert "name" not in data
    assert "profile_pic" not in data
    assert "tab" not in data


@pytest.mark.anyio
@patch("app.services.fcm_sender._is_firebase_initialized")
@patch("app.services.fcm_sender.get_cached_active_block_ids")
@patch("app.services.fcm_sender._fetch_user_fcm_tokens")
@patch("app.services.fcm_sender._send_to_tokens")
async def test_send_chat_notification_blocked(
    mock_send: MagicMock,
    mock_fetch_tokens: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_firebase_init: MagicMock,
) -> None:
    mock_firebase_init.return_value = True
    mock_get_blocks.return_value = {"sender-id"}  # Blocked!

    await send_chat_message_notification(
        sender_id="sender-id",
        recipient_id="recipient-id",
        conversation_id="convo-id",
        tab="Dating",
        message_id="msg-id",
        ciphertext="secret",
        ciphertext_metadata="{}",
    )

    mock_get_blocks.assert_called_once_with("recipient-id")
    mock_fetch_tokens.assert_not_called()
    mock_send.assert_not_called()


@pytest.mark.anyio
@patch("app.services.fcm_sender._is_firebase_initialized")
@patch("app.services.fcm_sender.get_cached_active_block_ids")
@patch("app.services.fcm_sender._fetch_user_fcm_tokens")
@patch("app.db.chat.fetch_conversation_participants")
@patch("app.services.fcm_sender._send_to_tokens")
async def test_send_chat_event_reminder_notification_no_plaintext_location(
    mock_send: MagicMock,
    mock_fetch_convo: MagicMock,
    mock_fetch_tokens: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_firebase_init: MagicMock,
) -> None:
    from app.services.fcm_sender import send_chat_event_reminder_notification

    mock_firebase_init.return_value = True
    mock_fetch_convo.return_value = {"user_a_id": "u1", "user_b_id": "u2", "closed_at": None}
    mock_get_blocks.return_value = set()
    mock_fetch_tokens.return_value = ["token1"]

    await send_chat_event_reminder_notification(
        user_a_id="u1",
        user_b_id="u2",
        conversation_id="conv-123",
        tab="Dating",
        location_label="Starbucks on 5th Ave",
    )

    mock_send.assert_called()
    # Check args: tokens, title, body, data, notification_type
    for call in mock_send.call_args_list:
        body = call[0][2]
        data = call[0][3]
        assert "Starbucks on 5th Ave" not in body
        assert "Starbucks on 5th Ave" not in str(data)
        assert "Dating" not in str(data)
        assert data["type"] == "chat_event_reminder"
        assert data["conversation_id"] == "conv-123"


@pytest.mark.anyio
@patch("app.services.fcm_sender.supabase_client")
async def test_fetch_user_fcm_tokens_deactivated(mock_supabase: MagicMock) -> None:
    mock_profile_exec = MagicMock()
    mock_profile_exec.execute.return_value.data = [{"is_deactivated": True}]
    mock_supabase.table.return_value.select.return_value.eq.return_value.limit.return_value = mock_profile_exec

    from app.services.fcm_sender import _fetch_user_fcm_tokens
    tokens = _fetch_user_fcm_tokens("user-id")

    assert tokens == []
    mock_supabase.table.assert_called_once_with("profiles")


@pytest.mark.anyio
@patch("app.services.fcm_sender.supabase_client")
async def test_fetch_user_fcm_tokens_active(mock_supabase: MagicMock) -> None:
    mock_profile_exec = MagicMock()
    mock_profile_exec.execute.return_value.data = [{"is_deactivated": False}]

    mock_devices_exec = MagicMock()
    mock_devices_exec.execute.return_value.data = [{"fcm_token": "token123"}]

    def side_effect(t: str) -> MagicMock:
        return mock_profile_exec if t == "profiles" else mock_devices_exec

    mock_supabase.table.side_effect = side_effect

    mock_profile_exec.select.return_value.eq.return_value.limit.return_value = mock_profile_exec
    mock_devices_exec.select.return_value.eq.return_value.eq.return_value = mock_devices_exec

    from app.services.fcm_sender import _fetch_user_fcm_tokens
    tokens = _fetch_user_fcm_tokens("user-id")

    assert tokens == ["token123"]


@pytest.mark.anyio
@patch("app.services.fcm_sender.supabase_client")
@patch("app.services.fcm_sender.decrypt_pii")
async def test_fetch_profile_name_decrypts_ciphertext(
    mock_decrypt: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    mock_exec = MagicMock()
    mock_exec.execute.return_value.data = [{"name": "encrypted_hex_123"}]
    mock_supabase.table.return_value.select.return_value.eq.return_value.limit.return_value = mock_exec
    mock_decrypt.return_value = "Alex"

    from app.services.fcm_sender import _fetch_profile_name
    name = _fetch_profile_name("user-id")

    assert name == "Alex"
    mock_decrypt.assert_called_once_with("encrypted_hex_123")



@pytest.mark.anyio
@patch("app.services.fcm_sender.supabase_client")
async def test_fetch_profile_name_deactivated_returns_none(
    mock_supabase: MagicMock,
) -> None:
    mock_exec = MagicMock()
    mock_exec.execute.return_value.data = [{"name": "encrypted_hex_123", "is_deactivated": True}]
    mock_supabase.table.return_value.select.return_value.eq.return_value.limit.return_value = mock_exec

    from app.services.fcm_sender import _fetch_profile_name
    name = _fetch_profile_name("user-id")

    assert name is None


@pytest.mark.anyio
@patch("app.services.fcm_sender.supabase_client")
async def test_deactivate_fcm_token_success(mock_supabase: MagicMock) -> None:
    mock_exec = MagicMock()
    mock_supabase.table.return_value.update.return_value.eq.return_value = mock_exec

    from app.services.fcm_sender import (
        _deactivate_fcm_token,
        _fcm_deactivate_fail_counts,
    )
    _fcm_deactivate_fail_counts["token123"] = 2

    _deactivate_fcm_token("some_long_token123")

    mock_supabase.table.assert_called_once_with("user_devices")
    mock_exec.execute.assert_called_once()
    assert "token123" not in _fcm_deactivate_fail_counts


@pytest.mark.anyio
@patch("app.services.fcm_sender.sentry_sdk.capture_exception")
@patch("app.services.fcm_sender.supabase_client")
async def test_deactivate_fcm_token_captures_sentry_on_repeated_failures(
    mock_supabase: MagicMock,
    mock_capture: MagicMock,
) -> None:
    mock_supabase.table.return_value.update.return_value.eq.return_value.execute.side_effect = Exception("DB timeout")

    from app.services.fcm_sender import (
        _deactivate_fcm_token,
        _fcm_deactivate_fail_counts,
    )
    _fcm_deactivate_fail_counts.clear()

    # Attempts 1 and 2: logged, Sentry not triggered yet
    _deactivate_fcm_token("fcm_err_token_999")
    _deactivate_fcm_token("fcm_err_token_999")
    assert mock_capture.call_count == 0

    # Attempt 3: triggers Sentry capture
    _deactivate_fcm_token("fcm_err_token_999")
    assert mock_capture.call_count == 1


def test_meetup_safety_reminder_nouns():
    from app.services.fcm_sender import _SAFETY_REMINDER_NOUN_BY_TAB

    assert _SAFETY_REMINDER_NOUN_BY_TAB.get("Dating", "meetup") == "date"
    assert _SAFETY_REMINDER_NOUN_BY_TAB.get("Friends", "meetup") == "meetup"
    assert _SAFETY_REMINDER_NOUN_BY_TAB.get("Professional", "meetup") == "meeting"
    assert _SAFETY_REMINDER_NOUN_BY_TAB.get("UnknownTab", "meetup") == "meetup"


@pytest.mark.anyio
@patch("app.services.fcm_sender._is_firebase_initialized", return_value=True)
@patch("app.services.fcm_sender.get_cached_active_block_ids", return_value=set())
@patch("app.services.fcm_sender._fetch_user_fcm_tokens", return_value=["token-123"])
@patch("app.services.fcm_sender.redis_client")
@patch("app.services.fcm_sender._send_to_tokens")
async def test_fcm_sender_per_recipient_throttling(
    mock_send: MagicMock,
    mock_redis: MagicMock,
    _mock_tokens: MagicMock,
    _mock_blocks: MagicMock,
    _mock_init: MagicMock,
) -> None:
    # First message: lock acquired (True)
    # Second message: lock rejected within cooldown (False/None)
    mock_redis.set = AsyncMock(side_effect=[True, None])
    mock_send.return_value = 1

    # First call: push dispatched
    await send_chat_message_notification(
        sender_id="sender-1",
        recipient_id="recipient-1",
        conversation_id="convo-1",
        tab="Dating",
        message_id="msg-1",
        ciphertext="secret-1",
        ciphertext_metadata="{}",
    )
    assert mock_send.call_count == 1
    mock_redis.set.assert_called_with("chat:push_cooldown:recipient-1:convo-1", "1", ex=3, nx=True)

    # Second call (immediate subsequent message): push suppressed by cooldown
    await send_chat_message_notification(
        sender_id="sender-1",
        recipient_id="recipient-1",
        conversation_id="convo-1",
        tab="Dating",
        message_id="msg-2",
        ciphertext="secret-2",
        ciphertext_metadata="{}",
    )
    # Call count remains 1
    assert mock_send.call_count == 1






