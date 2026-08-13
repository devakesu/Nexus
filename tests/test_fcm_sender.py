from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch
import pytest
from app.services.fcm_sender import (
    send_like_notification,
    send_chat_message_notification,
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
@patch("app.services.fcm_sender._fetch_profile_details")
@patch("app.services.fcm_sender._send_to_tokens")
async def test_send_chat_notification_not_blocked(
    mock_send: MagicMock,
    mock_fetch_details: MagicMock,
    mock_fetch_tokens: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_firebase_init: MagicMock,
) -> None:
    mock_firebase_init.return_value = True
    mock_get_blocks.return_value = set()  # No blocks
    mock_fetch_tokens.return_value = ["token1"]
    mock_fetch_details.return_value = ("Sender", "pic_url")

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
    mock_fetch_details.assert_called_once_with("sender-id")
    mock_send.assert_called_once()


@pytest.mark.anyio
@patch("app.services.fcm_sender._is_firebase_initialized")
@patch("app.services.fcm_sender.get_cached_active_block_ids")
@patch("app.services.fcm_sender._fetch_user_fcm_tokens")
@patch("app.services.fcm_sender._fetch_profile_details")
@patch("app.services.fcm_sender._send_to_tokens")
async def test_send_chat_notification_blocked(
    mock_send: MagicMock,
    mock_fetch_details: MagicMock,
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
    mock_fetch_details.assert_not_called()
    mock_send.assert_not_called()


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
@patch("app.services.fcm_sender.decrypt_pii")
async def test_fetch_profile_details_returns_raw_storage_path(
    mock_decrypt: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    mock_exec = MagicMock()
    mock_exec.execute.return_value.data = [
        {"name": "enc_name", "profile_pic": "enc_pic_path"},
    ]
    mock_supabase.table.return_value.select.return_value.eq.return_value.limit.return_value = mock_exec
    def _mock_decrypt(val: Any) -> str:
        return "Alex" if val == "enc_name" else "user_123/avatar.jpg"

    mock_decrypt.side_effect = _mock_decrypt

    from app.services.fcm_sender import _fetch_profile_details
    name, pic_path = _fetch_profile_details("user-id")

    assert name == "Alex"
    assert pic_path == "user_123/avatar.jpg"  # Raw storage path, not short-lived signed URL


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

    from app.services.fcm_sender import _deactivate_fcm_token, _fcm_deactivate_fail_counts
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

    from app.services.fcm_sender import _deactivate_fcm_token, _fcm_deactivate_fail_counts
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




