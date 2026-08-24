from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request, status

from app.api.chat.messages import send_message
from app.models import SendMessageRequest


@pytest.mark.anyio
@patch("app.api.chat.messages.fetch_conversation_participants")
@patch("app.api.chat.messages.get_cached_active_block_ids")
@patch("app.api.chat.messages.insert_message")
@patch("app.api.chat.messages.send_chat_message_notification")
async def test_send_message_not_blocked(
    mock_notify: MagicMock,
    mock_insert: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_fetch_convo: MagicMock,
) -> None:
    # 1. Mock database records
    mock_fetch_convo.return_value = {
        "user_a_id": "user-a",
        "user_b_id": "user-b",
        "closed_at": None,
        "tab": "Dating",
    }
    mock_get_blocks.return_value = set()  # No blocks
    mock_insert.return_value = {
        "id": "msg-123",
        "created_at": "2026-08-11T21:00:00Z",
    }

    # 2. Call endpoint
    payload = SendMessageRequest(
        message_type="text",
        ciphertext="c2VjcmV0",
        ciphertext_metadata={},
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    res = await send_message(
        request=request,
        conversation_id="convo-123",
        payload=payload,
        user_id="user-a",
    )

    # 3. Assertions
    assert res.message_id == "msg-123"
    assert mock_get_blocks.call_count == 2
    mock_insert.assert_called_once_with(
        "convo-123", "user-a", "text", "c2VjcmV0", {},
    )
    mock_notify.assert_called_once()


@pytest.mark.anyio
@patch("app.api.chat.messages.fetch_conversation_participants")
@patch("app.api.chat.messages.get_cached_active_block_ids")
@patch("app.api.chat.messages.insert_message")
@patch("app.api.chat.messages.send_chat_message_notification")
async def test_send_message_blocked_by_recipient(
    mock_notify: MagicMock,
    mock_insert: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_fetch_convo: MagicMock,
) -> None:
    # 1. Mock database records indicating user-a is blocked by user-b
    mock_fetch_convo.return_value = {
        "user_a_id": "user-a",
        "user_b_id": "user-b",
        "closed_at": None,
        "tab": "Dating",
    }
    mock_get_blocks.return_value = {"user-a"}  # user-a is blocked!

    # 2. Call endpoint
    payload = SendMessageRequest(
        message_type="text",
        ciphertext="c2VjcmV0",
        ciphertext_metadata={},
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await send_message(
            request=request,
            conversation_id="convo-123",
            payload=payload,
            user_id="user-a",
        )

    # 3. Assertions
    assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
    assert exc_info.value.detail == "Not a participant of this conversation."
    mock_get_blocks.assert_called_with("user-b")
    mock_insert.assert_not_called()
    mock_notify.assert_not_called()


@pytest.mark.anyio
@patch("app.api.chat.messages.fetch_conversation_participants")
@patch("app.api.chat.messages.get_cached_active_block_ids")
@patch("app.api.chat.messages.insert_message")
@patch("app.api.chat.messages.send_chat_message_notification")
async def test_send_message_blocked_by_sender(
    mock_notify: MagicMock,
    mock_insert: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_fetch_convo: MagicMock,
) -> None:
    # 1. Mock database records indicating user-a blocked user-b
    mock_fetch_convo.return_value = {
        "user_a_id": "user-a",
        "user_b_id": "user-b",
        "closed_at": None,
        "tab": "Dating",
    }
    # Recipient has no blocks, but sender blocked recipient
    mock_get_blocks.side_effect = [set(), {"user-b"}]

    # 2. Call endpoint
    payload = SendMessageRequest(
        message_type="text",
        ciphertext="c2VjcmV0",
        ciphertext_metadata={},
    )
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    with pytest.raises(HTTPException) as exc_info:
        await send_message(
            request=request,
            conversation_id="convo-123",
            payload=payload,
            user_id="user-a",
        )

    # 3. Assertions
    assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
    assert exc_info.value.detail == "Not a participant of this conversation."
    mock_insert.assert_not_called()
    mock_notify.assert_not_called()


@pytest.mark.anyio
@patch("app.api.chat.messages.fetch_conversation_participants")
@patch("app.api.chat.messages.get_cached_active_block_ids")
@patch("app.api.chat.messages.fetch_user_share_flags")
@patch("app.api.chat.messages.mark_messages_read")
async def test_mark_messages_read_not_blocked(
    mock_mark: MagicMock,
    mock_fetch_flags: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_fetch_convo: MagicMock,
) -> None:
    # 1. Mock parameters
    mock_fetch_convo.return_value = {
        "user_a_id": "user-a",
        "user_b_id": "user-b",
        "closed_at": None,
        "tab": "Dating",
    }
    mock_get_blocks.return_value = set()  # No blocks
    mock_fetch_flags.return_value = {"share_read_receipts": True}
    mock_mark.return_value = 5

    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    # 2. Call endpoint

    from app.api.chat.messages import mark_conversation_messages_read
    res_read = await mark_conversation_messages_read(
        request=request,
        conversation_id="convo-123",
        user_id="user-a",
    )

    # 3. Assertions
    assert res_read.marked_count == 5
    mock_get_blocks.assert_any_call("user-b")
    mock_get_blocks.assert_any_call("user-a")
    mock_mark.assert_called_once_with("convo-123", "user-a")


@pytest.mark.anyio
@patch("app.api.chat.messages.fetch_conversation_participants")
@patch("app.api.chat.messages.get_cached_active_block_ids")
@patch("app.api.chat.messages.fetch_user_share_flags")
@patch("app.api.chat.messages.mark_messages_read")
async def test_mark_messages_read_blocked(
    mock_mark: MagicMock,
    _mock_fetch_flags: MagicMock,
    mock_get_blocks: AsyncMock,
    mock_fetch_convo: MagicMock,
) -> None:
    # 1. Mock parameters indicating user-a is blocked by user-b
    mock_fetch_convo.return_value = {
        "user_a_id": "user-a",
        "user_b_id": "user-b",
        "closed_at": None,
        "tab": "Dating",
    }
    mock_get_blocks.return_value = {"user-a"}  # Blocked!

    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    # 2. Call endpoint
    from app.api.chat.messages import mark_conversation_messages_read
    with pytest.raises(HTTPException) as exc_info:
        await mark_conversation_messages_read(
            request=request,
            conversation_id="convo-123",
            user_id="user-a",
        )

    # 3. Assertions
    assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
    assert exc_info.value.detail == "Not a participant of this conversation."
    mock_get_blocks.assert_called_once_with("user-b")
    mock_mark.assert_not_called()


@pytest.mark.anyio
@patch("app.api.chat.messages.fetch_conversation_participants")
@patch("app.api.chat.messages.mark_messages_read")
async def test_mark_messages_read_closed_conversation(
    mock_mark: MagicMock,
    mock_fetch_convo: MagicMock,
) -> None:
    # Mock parameters indicating conversation is closed
    mock_fetch_convo.return_value = {
        "user_a_id": "user-a",
        "user_b_id": "user-b",
        "closed_at": "2026-08-12T12:00:00Z",
        "tab": "Dating",
    }

    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/",
    }
    request = Request(scope)

    from app.api.chat.messages import mark_conversation_messages_read
    with pytest.raises(HTTPException) as exc_info:
        await mark_conversation_messages_read(
            request=request,
            conversation_id="convo-123",
            user_id="user-a",
        )

    assert exc_info.value.status_code == status.HTTP_400_BAD_REQUEST
    assert exc_info.value.detail == "Conversation is closed."
    mock_mark.assert_not_called()


def test_send_message_request_metadata_valid() -> None:
    req = SendMessageRequest(
        ciphertext="c2VjcmV0",
        ciphertext_metadata={
            "ephemeral_key": "valid_key_string",
            "sequence_number": 42,
            "ratchet_flag": True,
            "latency": 12.34,
        },
    )
    assert len(req.ciphertext_metadata) == 4
    assert req.ciphertext_metadata["sequence_number"] == 42


def test_send_message_request_metadata_rejects_nested_or_non_primitive() -> None:
    from pydantic import ValidationError

    with pytest.raises(ValidationError) as exc_info:
        SendMessageRequest(
            ciphertext="c2VjcmV0",
            ciphertext_metadata={
                "nested_obj": {"malicious": "payload"},
            },
        )
    assert "only string, number, or boolean allowed" in str(exc_info.value)

    with pytest.raises(ValidationError) as exc_info:
        SendMessageRequest(
            ciphertext="c2VjcmV0",
            ciphertext_metadata={
                "long_val": "x" * 501,
            },
        )
    assert "exceeds 500 characters" in str(exc_info.value)



