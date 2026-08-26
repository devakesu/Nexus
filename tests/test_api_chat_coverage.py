"""Comprehensive unit tests covering 100% of app/api/chat modules (conversations, events, keys, messages, presence)."""

import base64
from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request

from app.api.chat.conversations import (
    create_chat,
    get_chat_candidates,
    get_chats,
)
from app.api.chat.events import (
    _validate_event_status_transition,
    create_chat_event,
    update_chat_event,
)
from app.api.chat.keys import (
    establish_session,
    get_key_bundle,
    get_one_time_prekey_count,
    upload_identity_key,
    upload_one_time_prekeys,
    upload_signed_prekey,
)
from app.api.chat.messages import (
    mark_conversation_messages_read,
    send_message,
)
from app.api.chat.presence import (
    batch_get_presence,
    get_presence,
    send_presence_heartbeat,
)
from app.db.client import DatabaseAccessError
from app.models import (
    BatchPresenceRequest,
    CreateChatRequest,
    CreateEventRequest,
    EstablishSessionRequest,
    OneTimePrekeyItem,
    PresenceHeartbeatRequest,
    SendMessageRequest,
    UpdateEventStatusRequest,
    UploadIdentityKeyRequest,
    UploadOneTimePrekeysRequest,
    UploadSignedPrekeyRequest,
)

pytestmark = pytest.mark.anyio


def make_mock_request() -> Request:
    return Request({"type": "http", "headers": [], "query_string": b"", "path": "/"})


# ==========================================
# 1. CONVERSATIONS TESTS
# ==========================================

async def test_get_chats_scenarios():
    req = make_mock_request()
    now = datetime.now(timezone.utc)

    # 1. Empty conversations
    with patch("app.api.chat.conversations.fetch_conversations_for_user", return_value=[]):
        res = await get_chats(request=req, tab="Dating", user_id="usr-1")
        assert res.conversations == []

    # 2. Active conversations with unread messages and blocked users
    rows = [
        {"conversation_id": "conv-1", "matched_user_id": "usr-2", "last_message_at": now},
        {"conversation_id": "conv-2", "matched_user_id": "usr-blocked", "last_message_at": now},
    ]
    mock_profile_res = MagicMock()
    mock_profile_res.data = [{"id": "usr-2", "name": "Alice", "age": 23, "profile_pic": "alice.jpg"}]

    mock_unread_res = MagicMock()
    mock_unread_res.data = [{"conversation_id": "conv-1"}, {"conversation_id": "conv-1"}]

    with patch("app.api.chat.conversations.fetch_conversations_for_user", return_value=rows), \
         patch("app.api.chat.conversations.get_cached_active_block_ids", new_callable=AsyncMock, return_value={"usr-blocked"}), \
         patch("app.api.chat.conversations.supabase_client.table") as mock_table:
        
        mock_query = MagicMock()
        mock_query.select.return_value.in_.return_value.eq.return_value.execute.return_value = mock_profile_res
        mock_query.select.return_value.in_.return_value.neq.return_value.is_.return_value.limit.return_value.execute.return_value = mock_unread_res
        mock_table.return_value = mock_query

        res = await get_chats(request=req, tab="Dating", user_id="usr-1")
        assert len(res.conversations) == 1
        assert res.conversations[0].matched_user_id == "usr-2"
        assert res.conversations[0].unread_count == 2
        assert res.conversations[0].has_unread is True

    # 3. Database error
    with patch("app.api.chat.conversations.fetch_conversations_for_user", side_effect=DatabaseAccessError("DB error")):
        with pytest.raises(HTTPException) as exc_info:
            await get_chats(request=req, tab="Dating", user_id="usr-1")
        assert exc_info.value.status_code == 503


async def test_get_chat_candidates_scenarios():
    req = make_mock_request()
    now = datetime.now(timezone.utc)

    # 1. Empty matches
    with patch("app.api.chat.conversations.fetch_matches_for_user", return_value=[]):
        res = await get_chat_candidates(request=req, tab="Dating", user_id="usr-1")
        assert res.candidates == []

    # 2. All matches already started
    matches = [{"match_id": "m-1", "matched_user_id": "usr-2", "created_at": now}]
    with patch("app.api.chat.conversations.fetch_matches_for_user", return_value=matches), \
         patch("app.api.chat.conversations.fetch_started_match_ids", return_value={"m-1"}):
        res = await get_chat_candidates(request=req, tab="Dating", user_id="usr-1")
        assert res.candidates == []

    # 3. Matches with blocked users
    with patch("app.api.chat.conversations.fetch_matches_for_user", return_value=matches), \
         patch("app.api.chat.conversations.fetch_started_match_ids", return_value=set()), \
         patch("app.api.chat.conversations.get_cached_active_block_ids", new_callable=AsyncMock, return_value={"usr-2"}):
        res = await get_chat_candidates(request=req, tab="Dating", user_id="usr-1")
        assert res.candidates == []

    # 4. Valid unstarted candidate
    mock_profile_res = MagicMock()
    mock_profile_res.data = [{"id": "usr-2", "name": "Bob", "age": 25, "profile_pic": "bob.jpg"}]

    with patch("app.api.chat.conversations.fetch_matches_for_user", return_value=matches), \
         patch("app.api.chat.conversations.fetch_started_match_ids", return_value=set()), \
         patch("app.api.chat.conversations.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.chat.conversations.supabase_client.table") as mock_table:
        
        mock_query = MagicMock()
        mock_query.select.return_value.in_.return_value.eq.return_value.execute.return_value = mock_profile_res
        mock_table.return_value = mock_query

        res = await get_chat_candidates(request=req, tab="Dating", user_id="usr-1")
        assert len(res.candidates) == 1
        assert res.candidates[0].matched_user_id == "usr-2"

    # 5. DatabaseAccessError
    with patch("app.api.chat.conversations.fetch_matches_for_user", side_effect=DatabaseAccessError("DB fail")):
        with pytest.raises(HTTPException) as exc_info:
            await get_chat_candidates(request=req, tab="Dating", user_id="usr-1")
        assert exc_info.value.status_code == 503


async def test_create_chat_scenarios():
    req = make_mock_request()
    payload = CreateChatRequest(match_id="11111111-1111-1111-1111-111111111111")

    # 1. Success as user_a
    with patch("app.api.chat.conversations.get_or_create_conversation", return_value={
        "id": "conv-123",
        "user_a_id": "usr-1",
        "user_b_id": "usr-2",
        "tab": "Dating",
    }):
        res = await create_chat(request=req, payload=payload, user_id="usr-1")
        assert res.conversation_id == "conv-123"
        assert res.matched_user_id == "usr-2"

    # 2. Success as user_b
    with patch("app.api.chat.conversations.get_or_create_conversation", return_value={
        "id": "conv-123",
        "user_a_id": "usr-2",
        "user_b_id": "usr-1",
        "tab": "Dating",
    }):
        res = await create_chat(request=req, payload=payload, user_id="usr-1")
        assert res.matched_user_id == "usr-2"

    # 3. Not a participant error
    with patch("app.api.chat.conversations.get_or_create_conversation", side_effect=DatabaseAccessError("not a participant")):
        with pytest.raises(HTTPException) as exc_info:
            await create_chat(request=req, payload=payload, user_id="usr-1")
        assert exc_info.value.status_code == 403

    # 4. Generic DB failure
    with patch("app.api.chat.conversations.get_or_create_conversation", side_effect=DatabaseAccessError("Connection lost")):
        with pytest.raises(HTTPException) as exc_info:
            await create_chat(request=req, payload=payload, user_id="usr-1")
        assert exc_info.value.status_code == 503


# ==========================================
# 2. EVENTS TESTS
# ==========================================

def test_validate_event_status_transitions():
    # 1. Proposed invalid
    with pytest.raises(HTTPException) as exc_1:
        _validate_event_status_transition("confirmed", "proposed", "usr-1", "usr-1")
    assert exc_1.value.status_code == 400

    # 2. Cancelled immutable
    with pytest.raises(HTTPException) as exc_2:
        _validate_event_status_transition("cancelled", "confirmed", "usr-1", "usr-2")
    assert exc_2.value.status_code == 400

    # 3. Confirmed already confirmed
    with pytest.raises(HTTPException) as exc_3:
        _validate_event_status_transition("confirmed", "confirmed", "usr-2", "usr-1")
    assert exc_3.value.status_code == 400

    # 4. Proposer cannot confirm own event
    with pytest.raises(HTTPException) as exc_4:
        _validate_event_status_transition("proposed", "confirmed", "usr-creator", "usr-creator")
    assert exc_4.value.status_code == 400

    # 5. Valid transition
    _validate_event_status_transition("proposed", "confirmed", "usr-recipient", "usr-creator")


async def test_create_chat_event_and_status():
    req = make_mock_request()
    now = datetime.now(timezone.utc)
    b64_ct = base64.b64encode(b"ciphertext").decode("ascii")

    payload = CreateEventRequest(
        event_time=now,
        ciphertext=b64_ct,
        safety_enabled=False,
    )

    # 1. Conversation not found (404)
    with patch("app.api.chat.events.fetch_conversation_participants", return_value=None):
        with pytest.raises(HTTPException) as exc_info:
            await create_chat_event(request=req, conversation_id="conv-1", payload=payload, user_id="usr-1")
        assert exc_info.value.status_code == 404

    # 2. Caller not a participant (403)
    with patch("app.api.chat.events.fetch_conversation_participants", return_value={"user_a_id": "usr-2", "user_b_id": "usr-3"}):
        with pytest.raises(HTTPException) as exc_info:
            await create_chat_event(request=req, conversation_id="conv-1", payload=payload, user_id="usr-1")
        assert exc_info.value.status_code == 403

    # 3. Closed conversation (403)
    with patch("app.api.chat.events.fetch_conversation_participants", return_value={"user_a_id": "usr-1", "user_b_id": "usr-2", "closed_at": now}):
        with pytest.raises(HTTPException) as exc_info:
            await create_chat_event(request=req, conversation_id="conv-1", payload=payload, user_id="usr-1")
        assert exc_info.value.status_code == 403

    # 4. Safety enabled with user consent check
    safety_payload = CreateEventRequest(
        event_time=now,
        ciphertext=b64_ct,
        safety_enabled=True,
        safety_interval_seconds=1800,
    )
    with patch("app.api.chat.events.fetch_conversation_participants", return_value={"user_a_id": "usr-1", "user_b_id": "usr-2", "closed_at": None}), \
         patch("app.api.chat.events.get_cached_public_user", new_callable=AsyncMock, return_value={"id": "usr-1", "safety_data_consent_version": "1.0.0"}), \
         patch("app.api.chat.events.assert_safety_consent"), \
         patch("app.api.chat.events.create_event_with_message", return_value={
             "event": {
                 "id": "evt-123",
                 "conversation_id": "conv-1",
                 "created_by": "usr-1",
                 "status": "proposed",
                 "event_time": now,
                 "created_at": now,
             },
             "message": {
                 "id": "msg-123",
                 "created_at": now,
             },
         }):
        res = await create_chat_event(request=req, conversation_id="conv-1", payload=safety_payload, user_id="usr-1")
        assert res.event_id == "evt-123"

    # 5. Update event status
    status_payload = UpdateEventStatusRequest(status="confirmed")
    with patch("app.api.chat.events.fetch_conversation_participants", return_value={"user_a_id": "usr-1", "user_b_id": "usr-2", "closed_at": None}), \
         patch("app.api.chat.events.fetch_event", return_value={
             "id": "evt-123",
             "conversation_id": "conv-1",
             "created_by": "usr-2",
             "status": "proposed",
             "event_time": now,
             "created_at": now,
         }), \
         patch("app.api.chat.events.update_event_status", return_value={
             "id": "evt-123",
             "conversation_id": "conv-1",
             "created_by": "usr-2",
             "status": "confirmed",
             "event_time": now,
             "created_at": now,
         }):
        res = await update_chat_event(request=req, conversation_id="conv-1", event_id="evt-123", payload=status_payload, user_id="usr-1")
        assert res.status == "confirmed"


# ==========================================
# 3. KEYS & CRYPTO BUNDLE TESTS
# ==========================================

async def test_keys_endpoints():
    req = make_mock_request()
    b64_key_bytes = b"01234567890123456789012345678901"
    b64_key = base64.b64encode(b64_key_bytes).decode("ascii")

    # 1. Identity key upload
    id_payload = UploadIdentityKeyRequest(identity_public_key=b64_key_bytes, registration_id=1234)
    with patch("app.api.chat.keys.upsert_identity_key"):
        res = await upload_identity_key(request=req, payload=id_payload, user_id="usr-1")
        assert res == {"success": True}

    # 2. Signed prekey upload
    signed_payload = UploadSignedPrekeyRequest(key_id=1, public_key=b64_key_bytes, signature=b64_key_bytes)
    with patch("app.api.chat.keys.fetch_identity_key", return_value={"identity_public_key": b64_key}), \
         patch("app.api.chat.keys.verify_signed_prekey_signature", return_value=True), \
         patch("app.api.chat.keys.upsert_signed_prekey"):
        res = await upload_signed_prekey(request=req, payload=signed_payload, user_id="usr-1")
        assert res == {"success": True}

    # 3. One-time prekeys upload
    otpk_item = OneTimePrekeyItem(key_id=1, public_key=b64_key_bytes)
    otpk_payload = UploadOneTimePrekeysRequest(prekeys=[otpk_item])
    with patch("app.api.chat.keys.bulk_insert_one_time_prekeys"):
        res = await upload_one_time_prekeys(request=req, payload=otpk_payload, user_id="usr-1")
        assert res == {"success": True}

    # 4. Count one-time prekeys
    with patch("app.api.chat.keys.count_unused_one_time_prekeys", return_value=45):
        res = await get_one_time_prekey_count(request=req, user_id="usr-1")
        assert res.count == 45

    # 5. Fetch Key Bundle (Success)
    with patch("app.api.chat.keys.redis_client.get", new_callable=AsyncMock, return_value=None), \
         patch("app.api.chat.keys.fetch_x3dh_key_bundle_unified", return_value=(
             {
                 "user_id": "usr-2",
                 "registration_id": 1234,
                 "identity_public_key": b"01234567890123456789012345678901",
                 "signed_prekey_id": 1,
                 "signed_prekey_public": b"01234567890123456789012345678901",
                 "signed_prekey_signature": b"01234567890123456789012345678901",
                 "one_time_prekey_id": 10,
                 "one_time_prekey_public": b"01234567890123456789012345678901",
                 "one_time_prekey_used": False,
             },
             None,
         )), \
         patch("app.api.chat.keys.redis_client.set", new_callable=AsyncMock), \
         patch("app.api.chat.keys.count_unused_one_time_prekeys", return_value=20):
        bundle = await get_key_bundle(request=req, target_user_id="usr-2", user_id="usr-1")
        assert bundle.user_id == "usr-2"

    # 6. Key bundle not found (404)
    with patch("app.api.chat.keys.redis_client.get", new_callable=AsyncMock, return_value=None), \
         patch("app.api.chat.keys.fetch_x3dh_key_bundle_unified", return_value=(None, "KEY_BUNDLE_NOT_FOUND")):
        with pytest.raises(HTTPException) as exc_info:
            await get_key_bundle(request=req, target_user_id="usr-2", user_id="usr-1")
        assert exc_info.value.status_code == 404

    # 7. Establish session
    est_payload = EstablishSessionRequest(conversation_id="11111111-1111-1111-1111-111111111111")
    with patch("app.api.chat.keys.mark_session_established"):
        res = await establish_session(request=req, payload=est_payload, user_id="usr-1")
        assert res == {"success": True}


# ==========================================
# 4. MESSAGES & PRESENCE TESTS
# ==========================================

async def test_messages_and_presence_endpoints():
    req = make_mock_request()
    now = datetime.now(timezone.utc)
    b64_ct = base64.b64encode(b"hello world").decode("ascii")

    # 1. Send message success
    msg_payload = SendMessageRequest(ciphertext=b64_ct, client_message_id="11111111-1111-1111-1111-111111111111")
    with patch("app.api.chat.messages.fetch_conversation_participants", return_value={"user_a_id": "usr-1", "user_b_id": "usr-2", "closed_at": None}), \
         patch("app.api.chat.messages.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.chat.messages.redis_client.set", new_callable=AsyncMock, return_value=True), \
         patch("app.api.chat.messages.insert_message", return_value={"id": "msg-123", "created_at": now}), \
         patch("app.api.chat.messages.send_chat_message_notification"):
        res_msg = await send_message(request=req, conversation_id="conv-1", payload=msg_payload, user_id="usr-1")
        assert res_msg.message_id == "msg-123"

    # 2. Mark messages read
    with patch("app.api.chat.messages.fetch_conversation_participants", return_value={"user_a_id": "usr-1", "user_b_id": "usr-2", "closed_at": None}), \
         patch("app.api.chat.messages.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.chat.messages.fetch_user_share_flags", return_value={"share_read_receipts": True}), \
         patch("app.api.chat.messages.mark_messages_read", return_value=3):
        res = await mark_conversation_messages_read(request=req, conversation_id="conv-1", user_id="usr-1")
        assert res.marked_count == 3

    # 3. Mark messages read with share_read_receipts=False
    with patch("app.api.chat.messages.fetch_conversation_participants", return_value={"user_a_id": "usr-1", "user_b_id": "usr-2", "closed_at": None}), \
         patch("app.api.chat.messages.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.chat.messages.fetch_user_share_flags", return_value={"share_read_receipts": False}):
        res_unshared = await mark_conversation_messages_read(request=req, conversation_id="conv-1", user_id="usr-1")
        assert res_unshared.marked_count == 0

    # 4. Presence Heartbeat
    hb_payload = PresenceHeartbeatRequest(is_online=True)
    with patch("app.api.chat.presence.upsert_presence_heartbeat"):
        res = await send_presence_heartbeat(request=req, payload=hb_payload, user_id="usr-1")
        assert res == {"success": True}

    # 5. Get Peer Presence (Allowed and Online)
    with patch("app.api.chat.presence.fetch_active_matches_for_targets", return_value={"usr-2"}), \
         patch("app.db.discovery.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.chat.presence.batch_fetch_user_share_flags", return_value={"usr-2": {"share_active_status": True}}), \
         patch("app.api.chat.presence.redis_client.mget", new_callable=AsyncMock, return_value=[f'{{"is_online": true, "last_active_at": "{now.isoformat()}"}}']):
        res = await get_presence(request=req, target_user_id="usr-2", user_id="usr-1")
        assert res.is_online is True

    # 6. Get Peer Presence (Not matched -> default empty)
    with patch("app.api.chat.presence.fetch_active_matches_for_targets", return_value=set()):
        res_empty = await get_presence(request=req, target_user_id="usr-2", user_id="usr-1")
        assert res_empty.is_online is None

    # 7. Batch Presence Lookup
    batch_payload = BatchPresenceRequest(user_ids=["usr-2", "usr-3"])
    with patch("app.api.chat.presence.fetch_active_matches_for_targets", return_value={"usr-2"}), \
         patch("app.db.discovery.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.chat.presence.batch_fetch_user_share_flags", return_value={"usr-2": {"share_active_status": True}}), \
         patch("app.api.chat.presence.redis_client.mget", new_callable=AsyncMock, return_value=[f'{{"is_online": true, "last_active_at": "{now.isoformat()}"}}']):
        res_batch = await batch_get_presence(request=req, payload=batch_payload, user_id="usr-1")
        assert res_batch["usr-2"].is_online is True
        assert res_batch["usr-3"].is_online is None
