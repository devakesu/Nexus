"""Phase 5 Test Suite: Deep Branch & Exception Path Coverage for Database Layer.

Covers:
- app/db/profiles/crud.py
- app/db/chat/chat.py
- app/db/chat/keys.py
- app/db/discovery/exclusions.py
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError

from app.core.security.crypto import encrypt_to_hex
from app.db.client import (
    ConversationClosedError,
    DatabaseAccessError,
    ProfileNotFoundError,
)
from app.db.profiles.crud import (
    _apply_blind_index_filters,
    _apply_post_fetch_filters,
    _check_candidate_match,
    _enrich_candidates_with_vectors,
    _fetch_and_decrypt_viewer,
    _filter_candidate_matches,
    _map_vector_embeddings,
    _unpack_chat_presence,
)
from app.db.chat.chat import (
    _apply_reactivation_updates,
    _collect_user_conv_media_paths,
    _decrypt_float_field,
    _decrypt_str_field,
    _partition_reactivation_conversations,
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
from app.db.discovery.exclusions import (
    _block_ids_cache_key,
    _check_pass_expiry,
    _collect_blocked_counterparty_ids,
    _process_exclusion_row,
    fetch_active_block_ids,
    fetch_active_discovery_excluded_ids,
    fetch_active_like_action,
    fetch_expired_pass_candidates,
    fetch_likes_for_user,
    has_active_discovery_action,
    mark_likes_seen,
    record_discovery_action,
    record_user_report,
    revoke_incoming_like,
    unrevoke_incoming_like,
)
from app.models import DiscoveryFilters

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
MATCH_1 = "00000000-0000-0000-0000-000000000010"
CONV_1 = "00000000-0000-0000-0000-000000000020"


# ==============================================================================
# 1. DB PROFILES CRUD DEEP COVERAGE
# ==============================================================================

def test_db_profiles_crud_blind_index_and_unpack():
    # 1. _apply_blind_index_filters
    mock_query = MagicMock()
    mock_query.in_.return_value = mock_query
    filters = DiscoveryFilters(campus_branches=["CS", "EE"])
    res_q = _apply_blind_index_filters(mock_query, filters)
    assert res_q is mock_query
    mock_query.in_.assert_called_once()

    # 2. _unpack_chat_presence
    cand_a: dict[str, Any] = {"chat_presence": {"last_active_at": "2026-08-25T10:00:00Z"}}
    _unpack_chat_presence(cand_a)
    assert cand_a["last_active_at"] == "2026-08-25T10:00:00Z"

    cand_b: dict[str, Any] = {"chat_presence": [{"last_active_at": "2026-08-25T11:00:00Z"}]}
    _unpack_chat_presence(cand_b)
    assert cand_b["last_active_at"] == "2026-08-25T11:00:00Z"

    cand_c: dict[str, Any] = {"chat_presence": []}
    _unpack_chat_presence(cand_c)
    assert "last_active_at" not in cand_c


def test_db_profiles_crud_filter_candidate_matches():
    raw_data: list[Any] = [
        "not_a_dict",
        {"id": USER_2, "dating_target_buckets": "not_a_list"},
        {"id": USER_2, "dating_target_buckets": []},
        {"id": USER_2, "dating_target_buckets": ["b_other"]},
        {
            "id": USER_3,
            "dating_target_buckets": ["b_viewer"],
            "users": {"app_variant": "nexus"},
            "chat_presence": {"last_active_at": "2026-08-25T12:00:00Z"},
        },
    ]

    filtered = _filter_candidate_matches(
        candidates_data=raw_data,
        viewer_search_expanded=["b_viewer"],
        target_bucket_column="dating_target_buckets",
    )
    assert len(filtered) == 1
    assert filtered[0]["id"] == USER_3
    assert filtered[0]["last_active_at"] == "2026-08-25T12:00:00Z"
    assert "users" not in filtered[0]


def test_db_profiles_crud_check_candidate_match_filters():
    cand: dict[str, Any] = {
        "id": USER_2,
        "looking_for": encrypt_to_hex(json.dumps(["Relationship"])),
        "causes_supported": encrypt_to_hex(json.dumps(["Climate"])),
        "tech_skills": encrypt_to_hex(json.dumps(["Python", "Rust"])),
        "partner_values": encrypt_to_hex("Honesty, Kindness"),
    }

    f_ok = DiscoveryFilters(
        looking_for=["Relationship"],
        causes_supported=["Climate"],
        tech_skills=["Python"],
        partner_values=["Honesty"],
        dealbreaker_fields=["partner_values"],
    )
    assert _check_candidate_match(cand.copy(), f_ok, dealbreakers={"partner_values"}) is True

    f_bad_pv = DiscoveryFilters(
        partner_values=["Ambition"],
        dealbreaker_fields=["partner_values"],
    )
    assert _check_candidate_match(cand.copy(), f_bad_pv, dealbreakers={"partner_values"}) is False

    cand_list_pv: dict[str, Any] = {
        "id": USER_2,
        "partner_values": encrypt_to_hex(json.dumps(["Honesty", "Humor"])),
    }
    f_match_pv_list = DiscoveryFilters(
        partner_values=["Humor"],
        dealbreaker_fields=["partner_values"],
    )
    assert _check_candidate_match(cand_list_pv.copy(), f_match_pv_list, dealbreakers={"partner_values"}) is True

    post_res = _apply_post_fetch_filters([cand.copy()], f_ok)
    assert len(post_res) == 1


def test_db_profiles_crud_vector_enrichment_and_exceptions():
    viewer: dict[str, Any] = {"id": USER_1}
    cand_1: dict[str, Any] = {"id": USER_2}
    candidates: list[dict[str, Any]] = [cand_1]

    records: list[Any] = [
        "invalid_record",
        {"user_id": None},
        {"user_id": USER_1, "vector_profiles": "not_a_dict"},
        {"user_id": USER_1, "vector_profiles": {"bio_embedding": [0.1], "career_embedding": [0.2], "identity_embedding": [0.3]}},
        {"user_id": USER_2, "vector_profiles": {"bio_embedding": [0.4], "career_embedding": [0.5], "identity_embedding": [0.6]}},
        {"user_id": "other_id", "vector_profiles": {"bio_embedding": [0.7]}},
    ]
    cand_map = {USER_2: cand_1}
    _map_vector_embeddings(records, viewer, cand_map, USER_1)
    assert viewer["bio_embedding"] == [0.1]
    assert cand_1["bio_embedding"] == [0.4]

    mock_table = MagicMock()
    mock_table.select.return_value.in_.return_value.execute.side_effect = APIError({"message": "DB error"})
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError, match="Failed to fetch vector profiles"):
            _enrich_candidates_with_vectors(viewer, candidates, USER_1)

    mock_table.select.return_value.in_.return_value.execute.side_effect = RuntimeError("Crash")
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError, match="Unexpected error fetching vector profiles"):
            _enrich_candidates_with_vectors(viewer, candidates, USER_1)

    mock_table.select.return_value.eq.return_value.limit.return_value.execute.side_effect = RuntimeError("Crash")
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError, match="Unexpected error fetching viewer profile"):
            _fetch_and_decrypt_viewer(USER_1, "Dating")

    mock_table.select.return_value.eq.return_value.limit.return_value.execute.side_effect = None
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        assert _fetch_and_decrypt_viewer(USER_1, "Dating") is None


# ==============================================================================
# 2. DB CHAT & CONVERSATIONS DEEP COVERAGE
# ==============================================================================

def test_db_chat_conversations_and_messages():
    mock_table = MagicMock()

    # 1. fetch_conversation_for_match APIError
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.side_effect = APIError({"message": "DB error"})
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError):
            fetch_conversation_for_match(MATCH_1)

    # 2. get_or_create_conversation
    existing_conv = {"id": CONV_1, "user_a_id": USER_2, "user_b_id": USER_3, "match_id": MATCH_1}
    with patch("app.db.chat.chat.fetch_conversation_for_match", return_value=existing_conv):
        with pytest.raises(DatabaseAccessError, match="User is not a participant of this match"):
            get_or_create_conversation(USER_1, MATCH_1)

    mock_table.select.return_value.eq.return_value.is_.return_value.maybe_single.return_value.execute.side_effect = None
    mock_table.select.return_value.eq.return_value.is_.return_value.maybe_single.return_value.execute.return_value = MagicMock(data=None)
    with patch("app.db.chat.chat.fetch_conversation_for_match", return_value=None), \
         patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError, match="No active match found"):
            get_or_create_conversation(USER_1, MATCH_1)

    mock_table.select.return_value.eq.return_value.is_.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": MATCH_1, "liker_id": USER_2, "liked_back_id": USER_3, "tab": "Dating"}
    )
    with patch("app.db.chat.chat.fetch_conversation_for_match", return_value=None), \
         patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError, match="User is not a participant of this match"):
            get_or_create_conversation(USER_1, MATCH_1)

    mock_table.select.return_value.eq.return_value.is_.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": MATCH_1, "liker_id": USER_1, "liked_back_id": USER_2, "tab": "Dating"}
    )
    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.chat.chat.fetch_conversation_for_match", side_effect=[None, {"id": CONV_1, "user_a_id": USER_1, "user_b_id": USER_2}]), \
         patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        c = get_or_create_conversation(USER_1, MATCH_1)
        assert c["id"] == CONV_1

    # 3. fetch_conversations_for_user & fetch_started_match_ids & close_conversation_for_match_action
    conv_data = [{"id": CONV_1, "user_a_id": USER_1, "user_b_id": USER_2, "last_message_at": "2026-08-25T10:00:00Z"}]
    mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.not_.is_.return_value.order.return_value.limit.return_value.execute.return_value = MagicMock(
        data=conv_data
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        convs = fetch_conversations_for_user(USER_1, tab="Dating")
        assert len(convs) == 1

        mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.not_.is_.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[{"match_id": MATCH_1}]
        )
        started = fetch_started_match_ids(USER_1, tab="Dating")
        assert MATCH_1 in started

        mock_table.update.return_value.or_.return_value.is_.return_value.select.return_value.execute.return_value = MagicMock(data=[])
        close_conversation_for_match_action(USER_1, USER_2, tab="Dating", reason="unmatched")

    # 4. insert_message (success & closed error)
    mock_table.insert.return_value.execute.return_value = MagicMock(
        data=[{"id": "msg-100", "conversation_id": CONV_1, "sender_id": USER_1, "ciphertext": "cipher"}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        m = insert_message(CONV_1, USER_1, "text", "cipher", {})
        assert m["id"] == "msg-100"

    mock_table.insert.return_value.execute.side_effect = APIError({"message": "closed conversation"})
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(ConversationClosedError):
            insert_message(CONV_1, USER_1, "text", "cipher", {})

    # 5. Media cleanup and participants
    mock_storage = MagicMock()
    mock_storage.remove.return_value = MagicMock()
    mock_table.select.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[{"ciphertext_metadata": {"attachment_paths": [f"{CONV_1}/{USER_1}/img.jpg"]}}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table), \
         patch("app.db.chat.chat.supabase_client.storage.from_", return_value=mock_storage):
        delete_conversation_chat_media(CONV_1)
        delete_user_chat_media(USER_1, [CONV_1])
        batch_delete_conversations_chat_media([CONV_1])
        _collect_user_conv_media_paths(CONV_1, USER_1)

    # 6. Reactivation partition, updates, reopen
    conv_rows = [
        {"id": CONV_1, "user_a_id": USER_1, "user_b_id": USER_2},
        {"id": "conv-2", "user_a_id": USER_1, "user_b_id": USER_3},
    ]
    with patch("app.db.discovery.exclusions.fetch_active_block_ids", return_value={USER_3}):
        reopen_ids, blocked_ids = _partition_reactivation_conversations(conv_rows, USER_1)
        assert CONV_1 in reopen_ids
        assert "conv-2" in blocked_ids

        mock_table.update.return_value.in_.return_value.execute.return_value = MagicMock(data=[])
        mock_table.select.return_value.or_.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
        with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
            _apply_reactivation_updates(reopen_ids, blocked_ids, USER_1)
            reopen_conversations_for_reactivation(USER_1)

    # 7. fetch_presence & batch_fetch_presence_from_db & flags & heartbeat
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.side_effect = None
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"user_id": USER_1, "is_online": True, "last_active_at": "2026-08-25T10:00:00Z"}
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        p = fetch_presence(USER_1)
        assert p is not None
        assert p["is_online"] is True

        mock_table.select.return_value.in_.return_value.execute.return_value = MagicMock(
            data=[{"user_id": USER_1, "is_online": True}]
        )
        batch_p = batch_fetch_presence_from_db([USER_1])
        assert USER_1 in batch_p

        mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[{"share_active_status": True, "share_read_receipts": True}]
        )
        flags = fetch_user_share_flags(USER_1)
        assert flags.get("share_active_status") is True

        mock_table.select.return_value.in_.return_value.execute.return_value = MagicMock(
            data=[{"id": USER_1, "share_active_status": True, "share_read_receipts": True}]
        )
        b_flags = batch_fetch_user_share_flags([USER_1])
        assert USER_1 in b_flags

        upsert_presence_heartbeat(USER_1, is_online=True)
        fetch_conversation_participants(CONV_1)
        mark_messages_read(CONV_1, USER_1)

    # 8. Event helpers and reminders
    mock_table.insert.return_value.execute.side_effect = None
    enc_lat = encrypt_to_hex("37.7749", category="chat")
    enc_name = encrypt_to_hex("Coffee Shop", category="chat")
    assert _decrypt_float_field(enc_lat) == 37.7749
    assert _decrypt_str_field(enc_name) == "Coffee Shop"
    assert _decrypt_float_field(None) is None
    assert _decrypt_str_field(None) is None

    ev_row = {
        "id": "ev-1",
        "location_lat": enc_lat,
        "location_lng": encrypt_to_hex("-122.4194", category="chat"),
        "location_label": enc_name,
    }
    dec_ev = decrypt_event_row(ev_row)
    assert dec_ev is not None
    assert dec_ev["location_lat"] == 37.7749

    mock_table.insert.return_value.execute.return_value = MagicMock(
        data=[{"id": "ev-1", "conversation_id": CONV_1, "creator_id": USER_1}]
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        ev = create_event_with_message(
            CONV_1,
            USER_1,
            "cipher",
            {},
            datetime.now(timezone.utc),
            37.77,
            -122.41,
            "Cafe",
        )
        assert ev["message"]["id"] == "ev-1"

        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
            data={"id": "ev-1", "location_lat": None, "location_lng": None, "location_label": None}
        )
        assert fetch_event("ev-1") is not None

        mock_table.update.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(
            data=[{"id": "ev-1", "status": "confirmed"}]
        )
        up_ev = update_event_status("ev-1", "confirmed")
        assert up_ev is not None

        enc_due_time = encrypt_to_hex((datetime.now(timezone.utc) + timedelta(minutes=15)).isoformat(), category="chat")
        mock_table.select.return_value.is_.return_value.neq.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[{"id": "ev-1", "event_time": enc_due_time, "location_lat": None, "location_lng": None, "location_label": None}]
        )
        due_evs = fetch_due_event_reminders(window_minutes=60)
        assert len(due_evs) == 1

        mock_table.update.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(
            data=[{"id": "ev-1"}]
        )
        assert mark_reminder_sent("ev-1") is True

        mock_table.select.return_value.eq.return_value.is_.return_value.neq.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[{"id": "ev-1", "event_time": enc_due_time, "location_lat": None, "location_lng": None, "location_label": None}]
        )
        due_saf = fetch_due_safety_reminders(window_minutes=35)
        assert len(due_saf) == 1

        assert mark_safety_reminder_sent("ev-1") is True


# ==============================================================================
# 3. DB CHAT KEYS DEEP COVERAGE
# ==============================================================================

def test_db_chat_keys_operations():
    mock_table = MagicMock()

    # 1. upsert_identity_key
    err_23503 = APIError({"message": "foreign key", "code": "23503"})
    mock_table.upsert.return_value.execute.side_effect = err_23503
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        with pytest.raises(ProfileNotFoundError):
            upsert_identity_key(USER_1, b"pk_bytes", 100)

    # 2. fetch_identity_key
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.side_effect = None
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(data=None)
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        assert fetch_identity_key(USER_1) is None

    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"identity_public_key": "\\x010203", "registration_id": 999}
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        k = fetch_identity_key(USER_1)
        assert k is not None
        assert k["registration_id"] == 999

    # 3. upsert_signed_prekey
    mock_rpc = MagicMock()
    mock_rpc.execute.side_effect = err_23503
    with patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_rpc):
        with pytest.raises(ProfileNotFoundError):
            upsert_signed_prekey(USER_1, 1, b"pk", b"sig")

    # 4. bulk_insert_one_time_prekeys & count_unused_one_time_prekeys
    mock_table.insert.return_value.execute.return_value = MagicMock(data=[{"id": 1}])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"pk1"}])

    mock_table.select.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(
        count=42, data=[]
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        assert count_unused_one_time_prekeys(USER_1) == 42

    # 5. has_active_match & fetch_active_matches_for_targets & fetch_key_bundle & unified
    mock_table.select.return_value.or_.return_value.or_.return_value.is_.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": MATCH_1}]
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        assert has_active_match(USER_1, USER_2) is True

    mock_table.select.return_value.or_.return_value.is_.return_value.execute.return_value = MagicMock(
        data=[{"liker_id": USER_2, "liked_back_id": USER_1}]
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        targets = fetch_active_matches_for_targets(USER_1, [USER_2])
        assert USER_2 in targets

    # mock for fetch_key_bundle
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"identity_public_key": "\\x0102", "registration_id": 123}
    )
    mock_table.select.return_value.eq.return_value.is_.return_value.order.return_value.limit.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"key_id": 1, "public_key": "\\x0304", "signature": "\\x0506"}
    )
    mock_rpc.execute.side_effect = None
    mock_rpc.execute.return_value = MagicMock(
        data=[{"key_id": 10, "public_key": "\\x0708"}]
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table), \
         patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_rpc):
        bundle = fetch_key_bundle(USER_1)
        assert bundle is not None
        assert bundle.get("registration_id") == 123

        with patch("app.db.chat.keys.has_active_match", return_value=True):
            u_bundle, err_code = fetch_x3dh_key_bundle_unified(USER_1, USER_2)
            assert u_bundle is not None
            assert u_bundle["registration_id"] == 123
            assert err_code is None

    mock_table.update.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": 1}])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        mark_session_established(USER_1, CONV_1)


# ==============================================================================
# 4. DB DISCOVERY EXCLUSIONS DEEP COVERAGE
# ==============================================================================

def test_db_discovery_exclusions_operations():
    # 1. Helper functions
    assert _block_ids_cache_key(USER_1) == f"discovery:block_ids:{USER_1}"
    counterparts = _collect_blocked_counterparty_ids(
        [{"actor_id": USER_1, "target_id": USER_2}, {"actor_id": USER_3, "target_id": USER_1}],
        USER_1,
    )
    assert USER_2 in counterparts
    assert USER_3 in counterparts

    # 2. Check pass expiry & process exclusion row
    now = datetime.now(timezone.utc)
    excluded_set: set[str] = set()
    _check_pass_expiry(
        (now + timedelta(hours=2)).isoformat(),
        USER_2,
        now,
        excluded_set,
    )
    assert USER_2 in excluded_set

    # _process_exclusion_row
    ex_row = {
        "action": "pass",
        "actor_id": USER_1,
        "target_id": USER_2,
        "tab": "Dating",
        "expires_at": (now + timedelta(hours=2)).isoformat(),
    }
    _process_exclusion_row(ex_row, USER_1, "Dating", now, excluded_set)
    assert USER_2 in excluded_set

    # 3. Database operations
    mock_table = MagicMock()
    mock_table.select.return_value.is_.return_value.or_.return_value.execute.return_value = MagicMock(
        data=[{"action": "block", "actor_id": USER_1, "target_id": USER_3, "tab": "Dating"}]
    )
    mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(
        data=[]
    )
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_table):
        ex_set = fetch_active_discovery_excluded_ids(USER_1, active_tab="Dating")
        assert USER_3 in ex_set

        b_ids = fetch_active_block_ids(USER_1)
        assert isinstance(b_ids, set)

        mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(
            data=[{"id": 1}]
        )
        assert has_active_discovery_action(USER_1, USER_2, "like", tab="Dating") is True

        mock_table.upsert.return_value.execute.return_value = MagicMock(data=[{"id": 1}])
        record_discovery_action(USER_1, USER_2, "like")

        mock_table.insert.return_value.execute.return_value = MagicMock(data=[{"id": 1}])
        record_user_report(USER_1, USER_2, "harassment", "notes")

        mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.is_.return_value.not_.is_.return_value.execute.return_value = MagicMock(
            data=[{"target_id": USER_2, "expires_at": (now - timedelta(hours=1)).isoformat()}]
        )
        exp_cands = fetch_expired_pass_candidates(USER_1, active_tab="Dating")
        assert len(exp_cands) == 1

        mock_table.select.return_value.eq.return_value.eq.return_value.in_.return_value.is_.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[{"id": 1, "actor_id": USER_2}]
        )
        likes = fetch_likes_for_user(USER_1)
        assert len(likes) == 1

        mock_table.update.return_value.eq.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
        mark_likes_seen(USER_1, [USER_2])

        mock_table.update.return_value.eq.return_value.eq.return_value.eq.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(
            data=[{"id": 1}]
        )
        rev = revoke_incoming_like(USER_1, USER_2)
        assert rev is True

        unrevoke_incoming_like(USER_1, USER_2)

        mock_table.select.return_value.eq.return_value.eq.return_value.in_.return_value.is_.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[{"id": 1, "action": "like"}]
        )
        assert fetch_active_like_action(USER_1, USER_2) is not None
