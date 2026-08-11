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

