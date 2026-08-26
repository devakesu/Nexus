"""Test coverage suite for DB Chat and E2EE Keys layers.

Covers:
- app/db/chat/chat.py
- app/db/chat/keys.py
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError

from app.core.security.crypto import encrypt_to_hex
from app.db.client import (
    DatabaseAccessError,
)
from app.db.chat.chat import (
    batch_delete_conversations_chat_media,
    batch_fetch_presence_from_db,
    batch_fetch_user_share_flags,
    close_conversation_for_match_action,
    create_event_with_message,
    decrypt_event_row,
    delete_conversation_chat_media,
    delete_user_chat_media,
    fetch_conversation_for_match,
    fetch_conversation_participants,
    fetch_conversations_for_user,
    fetch_due_event_reminders,
    fetch_due_safety_reminders,
    fetch_event,
    fetch_presence,
    fetch_started_match_ids,
    fetch_user_share_flags,
    get_or_create_conversation,
    insert_message,
    mark_messages_read,
    mark_reminder_sent,
    mark_safety_reminder_sent,
    reopen_conversations_for_reactivation,
    update_event_status,
    upsert_presence_heartbeat,
)
from app.db.chat.keys import (
    bulk_insert_one_time_prekeys,
    count_unused_one_time_prekeys,
    fetch_active_matches_for_targets,
    fetch_identity_key,
    fetch_key_bundle,
    fetch_x3dh_key_bundle_unified,
    has_active_match,
    mark_session_established,
    upsert_identity_key,
    upsert_signed_prekey,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
CONV_1 = "00000000-0000-0000-0000-000000000011"
MATCH_1 = "00000000-0000-0000-0000-000000000022"
EVENT_1 = "00000000-0000-0000-0000-000000000033"


# ==============================================================================
# 1. CHAT CONVERSATIONS & MESSAGING TESTS
# ==============================================================================

def test_chat_conversations_and_started_matches():
    now = datetime.now(timezone.utc)
    mock_table = MagicMock()

    # 1. fetch_conversations_for_user
    mock_query = MagicMock()
    mock_table.select.return_value = mock_query
    mock_query.or_.return_value = mock_query
    mock_query.eq.return_value = mock_query
    mock_query.is_.return_value = mock_query
    mock_query.not_.is_.return_value = mock_query
    mock_query.order.return_value = mock_query
    mock_query.limit.return_value = mock_query
    mock_query.execute.return_value = MagicMock(
        data=[
            {
                "id": CONV_1,
                "user_a_id": USER_1,
                "user_b_id": USER_2,
                "last_message_at": now.isoformat(),
            }
        ]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        convs = fetch_conversations_for_user(USER_1, "Dating")
        assert len(convs) == 1
        assert convs[0]["conversation_id"] == CONV_1
        assert convs[0]["matched_user_id"] == USER_2

    # APIError -> DatabaseAccessError
    mock_query.execute.side_effect = APIError({"message": "DB err"})
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError):
            fetch_conversations_for_user(USER_1, "Dating")

    # 2. fetch_started_match_ids
    mock_query.execute.side_effect = None
    mock_query.execute.return_value = MagicMock(data=[{"match_id": MATCH_1}])
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        m_ids = fetch_started_match_ids(USER_1, "Dating")
        assert MATCH_1 in m_ids

    mock_query.execute.side_effect = APIError({"message": "DB err"})
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError):
            fetch_started_match_ids(USER_1, "Dating")


def test_get_or_create_and_participants():
    mock_table = MagicMock()

    # 1. get_or_create_conversation (existing)
    with patch("app.db.chat.chat.fetch_conversation_for_match", return_value={"id": CONV_1, "user_a_id": USER_1, "user_b_id": USER_2}):
        conv = get_or_create_conversation(USER_1, MATCH_1)
        assert conv["id"] == CONV_1

    # non-participant -> DatabaseAccessError
    with patch("app.db.chat.chat.fetch_conversation_for_match", return_value={"id": CONV_1, "user_a_id": "other_1", "user_b_id": "other_2"}):
        with pytest.raises(DatabaseAccessError):
            get_or_create_conversation(USER_1, MATCH_1)

    # create new conversation
    mock_table.select.return_value.eq.return_value.is_.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": MATCH_1, "liker_id": USER_1, "liked_back_id": USER_2, "tab": "Dating"}
    )
    mock_table.upsert.return_value.execute.return_value = MagicMock(
        data=[{"id": CONV_1, "user_a_id": USER_1, "user_b_id": USER_2, "match_id": MATCH_1}]
    )
    with patch("app.db.chat.chat.fetch_conversation_for_match", side_effect=[None, {"id": CONV_1}]), \
         patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        conv_new = get_or_create_conversation(USER_1, MATCH_1)
        assert conv_new["id"] == CONV_1

    # 2. fetch_conversation_participants
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"user_a_id": USER_1, "user_b_id": USER_2, "closed_at": None}
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        parts = fetch_conversation_participants(CONV_1)
        assert parts is not None
        assert parts["user_a_id"] == USER_1
        assert parts["user_b_id"] == USER_2

    # fetch_conversation_for_match
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": CONV_1, "match_id": MATCH_1}
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        cm = fetch_conversation_for_match(MATCH_1)
        assert cm is not None
        assert cm["id"] == CONV_1


def test_insert_message_and_read_receipts():
    now = datetime.now(timezone.utc)
    mock_table = MagicMock()

    # 1. insert_message
    mock_table.insert.return_value.execute.return_value = MagicMock(
        data=[
            {
                "id": "00000000-0000-0000-0000-000000000099",
                "conversation_id": CONV_1,
                "sender_id": USER_1,
                "created_at": now.isoformat(),
            }
        ]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        msg = insert_message(
            conversation_id=CONV_1,
            sender_id=USER_1,
            message_type="signal_text",
            ciphertext="msg_cipher",
            ciphertext_metadata={"version": 1},
        )
        assert msg is not None
        assert msg["conversation_id"] == CONV_1

    # 2. mark_messages_read
    mock_table.update.return_value.eq.return_value.neq.return_value.is_.return_value.execute.return_value = MagicMock(
        data=[{"id": "msg1"}, {"id": "msg2"}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        count = mark_messages_read(CONV_1, USER_1)
        assert count == 2

    # 3. close_conversation_for_match_action & reopen_conversations_for_reactivation
    mock_table.update.return_value.or_.return_value.is_.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": CONV_1}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table), \
         patch("app.db.chat.chat.delete_conversation_chat_media"):
        close_conversation_for_match_action(USER_1, USER_2, reason="unmatch")

    mock_table.select.return_value.or_.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[{"id": CONV_1, "user_a_id": USER_1, "user_b_id": USER_2}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table), \
         patch("app.db.chat.chat._partition_reactivation_conversations", return_value=([CONV_1], [])):
        reopen_conversations_for_reactivation(USER_1)


def test_media_cleanup_and_presence():
    now = datetime.now(timezone.utc)

    # 1. delete_conversation_chat_media, batch_delete_conversations_chat_media, delete_user_chat_media
    mock_from = MagicMock()
    mock_from.return_value.list.return_value = [{"name": "image.jpg"}]
    mock_from.return_value.remove.return_value = [{"name": "image.jpg"}]
    with patch("app.db.chat.chat.supabase_client.storage.from_", mock_from):
        delete_conversation_chat_media(CONV_1)
        batch_delete_conversations_chat_media([CONV_1])
        delete_user_chat_media(USER_1, [CONV_1])

    # 2. upsert_presence_heartbeat & fetch_presence
    with patch("app.db.chat.chat.sync_redis_client.set") as mock_set:
        upsert_presence_heartbeat(USER_1, is_online=True)
        assert mock_set.called

    with patch("app.db.chat.chat.sync_redis_client.get", return_value=json.dumps({"is_online": True})):
        pres = fetch_presence(USER_1)
        assert pres is not None
        assert pres["is_online"] is True

    # 3. batch_fetch_presence_from_db
    mock_table = MagicMock()
    mock_table.select.return_value.in_.return_value.execute.return_value = MagicMock(
        data=[{"user_id": USER_1, "last_active_at": now.isoformat(), "is_online": True}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        b_pres = batch_fetch_presence_from_db([USER_1])
        assert USER_1 in b_pres

    # 4. fetch_user_share_flags & batch_fetch_user_share_flags
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"share_active_status": True, "share_read_receipts": True}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        flags = fetch_user_share_flags(USER_1)
        assert flags["share_active_status"] is True

    mock_table.select.return_value.in_.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1, "share_active_status": True, "share_read_receipts": True}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        b_flags = batch_fetch_user_share_flags([USER_1])
        assert USER_1 in b_flags


def test_chat_events_and_reminders():
    now = datetime.now(timezone.utc)
    mock_table = MagicMock()

    # 1. create_event_with_message
    mock_table.insert.return_value.execute.return_value = MagicMock(
        data=[
            {
                "id": EVENT_1,
                "conversation_id": CONV_1,
                "message_id": "msg_1",
                "created_by": USER_1,
                "event_time": encrypt_to_hex(now.isoformat(), category="chat"),
                "location_lat": encrypt_to_hex("37.7749", category="chat"),
                "location_lng": encrypt_to_hex("-122.4194", category="chat"),
                "location_label": encrypt_to_hex("Cafe", category="chat"),
                "safety_enabled": False,
            }
        ]
    )
    with patch("app.db.chat.chat.insert_message", return_value={"id": "msg_1"}), \
         patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        res = create_event_with_message(
            conversation_id=CONV_1,
            sender_id=USER_1,
            ciphertext="msg_cipher",
            ciphertext_metadata={"v": 1},
            event_time=now,
            location_lat=37.7749,
            location_lng=-122.4194,
            location_label="Cafe",
        )
        assert res["event"]["id"] == EVENT_1

    # 2. fetch_event & update_event_status
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": EVENT_1, "status": "proposed", "title": encrypt_to_hex("Coffee Date", category="chat")}
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        ev_row = fetch_event(EVENT_1)
        assert ev_row is not None

    mock_table.update.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": EVENT_1, "status": "accepted"}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        up_ev = update_event_status(EVENT_1, "accepted")
        assert up_ev is not None
        assert up_ev["status"] == "accepted"

    # 3. fetch_due_event_reminders & mark_reminder_sent
    mock_table.select.return_value.is_.return_value.neq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": EVENT_1, "event_time": encrypt_to_hex((now + timedelta(minutes=10)).isoformat(), category="chat")}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        due_evs = fetch_due_event_reminders(window_minutes=60)
        assert len(due_evs) == 1

    mock_table.update.return_value.eq.return_value.is_.return_value.select.return_value.execute.return_value = MagicMock(data=[{"id": EVENT_1}])
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        assert mark_reminder_sent(EVENT_1) is True

    # 4. fetch_due_safety_reminders & mark_safety_reminder_sent
    mock_table.select.return_value.eq.return_value.is_.return_value.neq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": EVENT_1, "event_time": encrypt_to_hex((now + timedelta(minutes=10)).isoformat(), category="chat")}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        due_safety = fetch_due_safety_reminders(window_minutes=35)
        assert len(due_safety) == 1

    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        assert mark_safety_reminder_sent(EVENT_1) is True

    now = datetime.now(timezone.utc)
    dec_ev = decrypt_event_row({
        "id": EVENT_1,
        "event_time": encrypt_to_hex(now.isoformat(), category="chat"),
        "location_label": encrypt_to_hex("Restaurant", category="chat"),
    })
    assert dec_ev is not None
    assert dec_ev["location_label"] == "Restaurant"


# ==============================================================================
# 2. E2EE KEYS & MATCHES TESTS
# ==============================================================================

def test_keys_matches_and_bundles():
    mock_table = MagicMock()

    # 1. has_active_match & fetch_active_matches_for_targets
    mock_table.select.return_value.or_.return_value.is_.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": MATCH_1}]
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        assert has_active_match(USER_1, USER_2) is True

    mock_table.select.return_value.or_.return_value.is_.return_value.execute.return_value = MagicMock(
        data=[{"liker_id": USER_1, "liked_back_id": USER_2}]
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        active_set = fetch_active_matches_for_targets(USER_1, [USER_2])
        assert USER_2 in active_set

    # 2. upsert_identity_key & fetch_identity_key
    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[{"user_id": USER_1}])
    mock_table.delete.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        upsert_identity_key(USER_1, b"public_identity_key_32_bytes_x00", registration_id=12345)

    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"identity_public_key": "\\x616263", "registration_id": 12345}
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        ik = fetch_identity_key(USER_1)
        assert ik is not None
        assert ik["registration_id"] == 12345

    # 3. upsert_signed_prekey & bulk_insert_one_time_prekeys & count_unused_one_time_prekeys
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data=None)
    with patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_rpc):
        upsert_signed_prekey(USER_1, 1, b"signed_prekey_bytes", b"signature_bytes")

    mock_table.insert.return_value.execute.return_value = MagicMock(data=[{"id": "opk1"}])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"opk_pub1"}])

    mock_table.select.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(count=15)
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        cnt = count_unused_one_time_prekeys(USER_1)
        assert cnt == 15

    # 4. fetch_key_bundle & fetch_x3dh_key_bundle_unified & mark_session_established
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"identity_public_key": "\\x616263", "registration_id": 12345}
    )
    mock_table.select.return_value.eq.return_value.is_.return_value.order.return_value.limit.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"key_id": 1, "public_key": "\\x646566", "signature": "\\x736967"}
    )
    mock_rpc.execute.return_value = MagicMock(data=[{"key_id": 10, "public_key": "\\x6f706b"}])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table), \
         patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_rpc):
        bundle = fetch_key_bundle(USER_1)
        assert bundle is not None
        assert bundle["registration_id"] == 12345

    # fetch_x3dh_key_bundle_unified
    rpc_unified = MagicMock()
    rpc_unified.execute.return_value = MagicMock(
        data={
            "identity_public_key": "\\x616263",
            "registration_id": 12345,
            "signed_prekey_id": 1,
            "signed_prekey_public": "\\x646566",
            "signed_prekey_signature": "\\x736967",
            "one_time_prekey_id": 10,
            "one_time_prekey_public": "\\x6f706b",
            "one_time_prekey_used": True,
        }
    )
    with patch("app.db.chat.keys.supabase_client.rpc", return_value=rpc_unified):
        u_bundle, err = fetch_x3dh_key_bundle_unified(USER_1, USER_2)
        assert u_bundle is not None
        assert err is None

    mock_table.update.return_value.eq.return_value.or_.return_value.execute.return_value = MagicMock(data=[{"id": CONV_1}])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        mark_session_established(USER_1, CONV_1)
