"""Phase 1 DB Coverage Expansion.

Targets:
- app/db/chat/chat.py
- app/db/chat/keys.py
- app/db/users/account_deletion.py
- app/db/users/export.py
- app/db/discovery/exclusions.py
- app/db/discovery/matches.py
- app/db/safety/alerts.py
- app/db/safety/sessions.py
- app/db/safety/contacts.py
- app/db/safety/evidence.py
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError

from app.core.security.crypto import encrypt_to_hex
from app.db.client import ConversationClosedError, DatabaseAccessError

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
CONV_1 = "00000000-0000-0000-0000-000000000011"
MATCH_1 = "00000000-0000-0000-0000-000000000022"
EVENT_1 = "00000000-0000-0000-0000-000000000033"


def _make_chaining_mock(data: Any = None) -> MagicMock:
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

    def _exec() -> MagicMock:
        return MagicMock(data=data)

    def _single() -> MagicMock:
        if isinstance(data, list) and data:
            return MagicMock(data=data[0])
        return MagicMock(data=data)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    return mock


# -----------------------------------------------------------------------------
# 1. DB CHAT & KEYS
# -----------------------------------------------------------------------------
def test_db_chat_edge_cases():
    from app.db.chat.chat import (
        _apply_reactivation_updates,
        _collect_user_conv_media_paths,
        _partition_reactivation_conversations,
        create_event_with_message,
        insert_message,
        update_event_status,
    )

    # 1. insert_message error cases
    mock_table = MagicMock()
    mock_table.insert.return_value.execute.side_effect = APIError({"message": "closed conversation"})
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(ConversationClosedError):
            insert_message(CONV_1, USER_1, "signal_text", "cipher", {})

    mock_table.insert.return_value.execute.side_effect = APIError({"message": "random db error"})
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError):
            insert_message(CONV_1, USER_1, "signal_text", "cipher", {})

    # 2. _collect_user_conv_media_paths exception
    mock_storage = MagicMock()
    mock_storage.list.side_effect = Exception("Storage error")
    with patch("app.db.chat.chat.supabase_client.storage.from_", return_value=mock_storage):
        paths = _collect_user_conv_media_paths(CONV_1, USER_1)
        assert paths == []

    # 3. _partition_reactivation_conversations & _apply_reactivation_updates
    rows = [
        {"id": "c1", "user_a_id": USER_1, "user_b_id": USER_2, "match_id": "m1"},
        {"id": "c2", "user_a_id": USER_2, "user_b_id": USER_1, "match_id": "m2"},
    ]
    with patch("app.db.discovery.exclusions.fetch_active_block_ids", return_value={USER_2}):
        reopen, blocked = _partition_reactivation_conversations(rows, USER_1)
        assert reopen == []
        assert blocked == ["c1", "c2"]

    mock_table.update.return_value.in_.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        _apply_reactivation_updates(["c1"], ["c2"], USER_1)

    # 4. create_event_with_message error handling & rollback
    mock_table.insert.return_value.execute.side_effect = APIError({"message": "Event insert failed"})
    mock_table.delete.return_value.eq.return_value.execute.return_value = MagicMock()
    with patch("app.db.chat.chat.insert_message", return_value={"id": "m99"}), \
         patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError):
            create_event_with_message(CONV_1, USER_1, "cipher", {}, datetime.now(timezone.utc), None, None, None)

    # 5. update_event_status not found
    mock_table.update.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(data=[])
    mock_table.update.return_value.eq.return_value.select.return_value.execute.side_effect = None
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        res = update_event_status("ev_none", "cancelled")
        assert res is None


def test_db_chat_keys_edge_cases():
    from app.db.chat.keys import (
        _from_bytea,
        _to_bytea_hex,
        bulk_insert_one_time_prekeys,
        count_unused_one_time_prekeys,
        fetch_identity_key,
        fetch_key_bundle,
        fetch_x3dh_key_bundle_unified,
        mark_session_established,
        upsert_identity_key,
        upsert_signed_prekey,
    )

    # 1. Bytea helpers
    assert _to_bytea_hex(b"hello") == "\\x68656c6c6f"
    assert _from_bytea("\\x68656c6c6f") == b"hello"
    assert _from_bytea(b"hello") == b"hello"

    mock_table = MagicMock()
    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[])
    mock_table.delete.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        upsert_identity_key(USER_1, b"pubkey32bytes0000000000000000000", 12345)

    # 2. Signed prekey upsert
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data=None)
    with patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_rpc):
        upsert_signed_prekey(USER_1, 1, b"pubkey", b"sig")

    # 3. count_unused_one_time_prekeys
    mock_table.select.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(count=15)
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        count = count_unused_one_time_prekeys(USER_1)
        assert count == 15

    # 4. bulk_insert_one_time_prekeys
    bulk_insert_one_time_prekeys(USER_1, [])
    mock_table.insert.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"pub"}])

    # 5. mark_session_established
    mock_table.update.return_value.eq.return_value.or_.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        mark_session_established(USER_1, CONV_1)

    # 6. Key bundle fetches
    mock_key_t = _make_chaining_mock([
        {"identity_public_key": "\\x68656c6c6f", "registration_id": 123, "key_id": 1, "public_key": "\\x68656c6c6f", "signature": "\\x68656c6c6f"}
    ])
    mock_claim_rpc = MagicMock()
    mock_claim_rpc.execute.return_value = MagicMock(data=[{"key_id": 9, "public_key": "\\x68656c6c6f"}])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_key_t), \
         patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_claim_rpc):
        ident = fetch_identity_key(USER_1)
        assert ident is not None
        bundle = fetch_key_bundle(USER_1)
        assert bundle is not None
        u_bundle, u_err = fetch_x3dh_key_bundle_unified(USER_1, USER_2)
        assert u_bundle is not None or u_err is not None


# -----------------------------------------------------------------------------
# 2. DB USERS ACCOUNT DELETION & EXPORT
# -----------------------------------------------------------------------------
def test_db_users_account_deletion_deep():
    from app.db.users.account_deletion import (
        _reason_code_for_flag,
        cancel_deletion,
        compute_deletion_flag_reason,
        expire_blocklist_entries,
        fetch_deletion_status,
        hard_purge_long_tail_accounts,
        is_phone_blocklisted,
        purge_due_accounts,
        request_deletion,
    )

    mock_table = MagicMock()

    # 1. _reason_code_for_flag
    assert _reason_code_for_flag({"moderation_status": "banned"}, False) == "banned"
    assert _reason_code_for_flag({"moderation_status": "restricted"}, False) == "restricted"
    assert _reason_code_for_flag({"is_suspended": True}, False) == "suspended"
    assert _reason_code_for_flag({}, True) == "unresolved_report"
    assert _reason_code_for_flag({}, False) is None

    # 2. compute_deletion_flag_reason
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"moderation_status": "restricted", "is_suspended": False}]
    )
    mock_table.select.return_value.eq.return_value.in_.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[]
    )
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_table):
        code = compute_deletion_flag_reason(USER_1)
        assert code == "restricted"

    # 3. is_phone_blocklisted
    assert is_phone_blocklisted("") is False
    mock_table.select.return_value.eq.return_value.gt.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": "b1", "cooldown_expires_at": "2026-12-31T00:00:00Z"}]
    )
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_table):
        assert is_phone_blocklisted("abcdef1234567890") is True

    # 4. fetch_deletion_status
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"deletion_requested_at": "2026-08-01T00:00:00Z", "scheduled_purge_at": "2026-08-31T00:00:00Z"}]
    )
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_table):
        status = fetch_deletion_status(USER_1)
        assert status is not None
        assert status["deletion_requested_at"] == "2026-08-01T00:00:00Z"

    # 5. request_deletion & cancel_deletion
    mock_table.update.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(
        data=[{"deletion_requested_at": "2026-08-01T00:00:00Z", "scheduled_purge_at": "2026-08-31T00:00:00Z"}]
    )
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.account_deletion.invalidate_user_status_cache"), \
         patch("app.db.users.account_deletion._close_all_conversations"), \
         patch("app.db.users.account_deletion.supabase_client.auth.admin.sign_out"):
        res = request_deletion(USER_1, flagged_reason_code="banned", access_token="mock_token")
        assert res is not None

    mock_table.update.return_value.eq.return_value.not_.is_.return_value.is_.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}]
    )
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.account_deletion.invalidate_user_status_cache"), \
         patch("app.db.users.account_deletion.reopen_conversations_for_reactivation"):
        cancel_deletion(USER_1)

    # 6. expire_blocklist_entries & purge_due_accounts
    mock_table.delete.return_value.lte.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_table):
        expire_blocklist_entries()

    with patch("app.db.users.account_deletion._fetch_accounts_due_for_purge", return_value=[{"id": USER_1, "mobile_blind_index": "m1"}]), \
         patch("app.db.users.account_deletion._purge_single_due_account") as mock_purge_single, \
         patch("app.db.users.account_deletion.time.sleep"):
        purge_due_accounts()
        mock_purge_single.assert_called_once()

    # 7. hard_purge_long_tail_accounts
    with patch("app.db.users.account_deletion._fetch_accounts_due_for_long_tail_purge", return_value=[USER_1]), \
         patch("app.db.users.account_deletion._archive_account_history", return_value=[{"id": USER_1}]), \
         patch("app.db.users.account_deletion._chunked_pre_purge_child_records"), \
         patch("app.db.users.account_deletion.supabase_client.auth.admin.delete_user"), \
         patch("app.db.users.account_deletion.time.sleep"):
        hard_purge_long_tail_accounts()


def test_db_users_export_deep():
    from app.db.users.export import (
        _build_account_section,
        _build_consent_history,
        _build_matches_and_discovery,
        _build_reports_section,
        _build_safety_section,
        _build_spotify_section,
        _safe_select,
        _sign_urls,
        build_user_data_export,
    )

    mock_t = _make_chaining_mock([
        {"id": USER_1, "name": "Alice", "email": "alice@example.com"}
    ])

    with patch("app.db.users.export.supabase_client.table", return_value=mock_t), \
         patch("app.db.users.export.get_user_email_by_id", return_value="alice@example.com"), \
         patch("app.db.users.export.fetch_safety_contacts", return_value=[]), \
         patch("app.db.users.export.fetch_playlists_for_owner", return_value=[]), \
         patch("app.db.users.export._sign_urls", return_value={}):

        s_rows = _safe_select("profiles", "name", USER_1)
        assert isinstance(s_rows, list)
        s_urls = _sign_urls("media_bucket", ["a.jpg"])
        assert isinstance(s_urls, dict)

        acc = _build_account_section(USER_1)
        assert acc.get("email") == "alice@example.com"

        matches_disc = _build_matches_and_discovery(USER_1)
        assert "matches" in matches_disc
        assert "discovery_actions" in matches_disc

        reports = _build_reports_section(USER_1)
        assert "reports_you_filed" in reports
        assert "reports_against_you" in reports

        safety = _build_safety_section(USER_1)
        assert "trusted_contacts" in safety
        assert "checkin_sessions" in safety

        spotify = _build_spotify_section(USER_1)
        assert spotify == []

        consent = _build_consent_history(USER_1)
        assert isinstance(consent, list)

        full_export = build_user_data_export(USER_1)
        assert "account" in full_export
        assert full_export["account"]["email"] == "alice@example.com"


# -----------------------------------------------------------------------------
# 3. DB DISCOVERY EXCLUSIONS & MATCHES
# -----------------------------------------------------------------------------
def test_db_discovery_exclusions_and_matches():
    from app.db.discovery.exclusions import (
        _block_ids_cache_key,
        _check_pass_expiry,
        fetch_active_discovery_excluded_ids,
        fetch_active_like_action,
        record_discovery_action,
    )
    from app.db.discovery.matches import (
        fetch_active_match_between,
        record_match,
        set_match_unmatched,
    )

    mock_t = _make_chaining_mock([
        {"id": MATCH_1, "tab": "Dating", "actor_id": USER_1, "target_id": USER_2, "action": "like", "liker_id": USER_1, "liked_back_id": USER_2}
    ])
    now = datetime.now(timezone.utc)

    # 1. exclusions helper logic
    assert _block_ids_cache_key(USER_1) == f"discovery:block_ids:{USER_1}"
    excl: set[str] = set()
    _check_pass_expiry("2026-09-01T00:00:00Z", USER_2, now, excl)
    assert USER_2 in excl

    # 2. fetch_active_discovery_excluded_ids
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_t):
        excluded = fetch_active_discovery_excluded_ids(USER_1, "Dating")
        assert isinstance(excluded, set)

    # 3. fetch_active_like_action & record_discovery_action
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_t):
        act = fetch_active_like_action(USER_1, USER_2)
        assert act is not None
        record_discovery_action(USER_1, USER_2, "like", "Dating")

    # 4. matches.py
    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_t):
        m = fetch_active_match_between(USER_1, USER_2)
        assert m is not None
        assert m["id"] == MATCH_1
        rec = record_match(USER_1, USER_2, "Dating")
        assert rec == MATCH_1
        set_match_unmatched(USER_1, USER_2, "Dating")


# -----------------------------------------------------------------------------
# 4. DB SAFETY (ALERTS, SESSIONS, CONTACTS, EVIDENCE)
# -----------------------------------------------------------------------------
def test_db_safety_modules_deep():
    from app.db.safety.alerts import (
        fetch_contact_facing_profile_summary,
        fetch_safety_alert,
        record_safety_alert,
        update_alert_contacts_notified,
    )
    from app.db.safety.contacts import (
        fetch_safety_contacts,
        remove_safety_contact_self_service,
        sync_safety_contacts,
    )
    from app.db.safety.evidence import (
        create_evidence_download_url,
        register_safety_evidence,
    )
    from app.db.safety.sessions import (
        cancel_safety_escalation,
        end_safety_session,
        heartbeat_safety_session,
        start_safety_session,
    )

    mock_profile_raw = {
        "id": USER_1,
        "name": encrypt_to_hex("Alice", category="profile"),
        "display_gender": encrypt_to_hex("Woman", category="profile"),
        "profile_pic": encrypt_to_hex("pic.jpg", category="profile"),
        "normal_pics": encrypt_to_hex("[]", category="profile"),
        "hometown": encrypt_to_hex("SF", category="profile"),
        "current_place": encrypt_to_hex("Berkeley", category="profile"),
    }
    mock_t = _make_chaining_mock([mock_profile_raw])

    with patch("app.db.safety.alerts.supabase_client.table", return_value=mock_t), \
         patch("app.db.safety.alerts.sign_profile_media", return_value={"name": "Alice"}):
        a = record_safety_alert(USER_1, "sos_silent", {"lat": 37.77, "lng": -122.41})
        assert a is not None
        al = fetch_safety_alert("alert_1")
        assert al is not None
        update_alert_contacts_notified("alert_1", 2)
        summary = fetch_contact_facing_profile_summary(USER_1)
        assert summary is not None
        assert summary.get("name") == "Alice"

    # 2. contacts.py
    mock_contact_raw = {
        "id": "ct_1",
        "user_id": USER_1,
        "name": encrypt_to_hex("Bob", category="contact"),
        "phone": encrypt_to_hex("+15555555555", category="contact"),
    }
    mock_ct_t = _make_chaining_mock([mock_contact_raw])
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data={"blocked_indices": [], "newly_notified_indices": []})
    with patch("app.db.safety.contacts.supabase_client.rpc", return_value=mock_rpc), \
         patch("app.db.safety.contacts.supabase_client.table", return_value=mock_ct_t), \
         patch("app.db.safety.contacts.fetch_safety_contact_by_id", return_value={"id": "ct_1", "user_id": USER_1, "name": "Bob", "phone": "+15555555555"}):
        contacts = fetch_safety_contacts(USER_1)
        assert len(contacts) == 1
        assert contacts[0]["name"] == "Bob"
        sync_safety_contacts(USER_1, [{"name": "Bob", "phone": "+15555555555"}])
        removed = remove_safety_contact_self_service("ct_1")
        assert removed is not None
        assert removed["name"] == "Bob"

    SESS_1 = "00000000-0000-0000-0000-000000000044"
    # 3. sessions.py
    mock_sess_raw = {
        "id": SESS_1,
        "user_id": USER_1,
        "status": "active",
        "interval_seconds": 900,
        "next_checkin_at": "2026-08-26T15:00:00Z",
        "escalations_sent": 0,
        "last_escalated_at": None,
    }
    mock_sess_t = _make_chaining_mock([mock_sess_raw])
    mock_rpc.execute.return_value = MagicMock(data=[mock_sess_raw])
    with patch("app.db.safety.sessions.supabase_client.rpc", return_value=mock_rpc), \
         patch("app.db.safety.sessions.supabase_client.table", return_value=mock_sess_t):
        s = start_safety_session(USER_1, "Date", 900, "2026-08-26T16:00:00Z", {"mode": "test"}, 80, "wifi")
        assert s is not None
        hb = heartbeat_safety_session(USER_1, SESS_1, "2026-08-26T17:00:00Z", 75, "wifi")
        assert hb is not None
        end_safety_session(USER_1, SESS_1)
        cancel_safety_escalation(USER_1, SESS_1, "false_alarm", "I am okay")

    # 4. evidence.py
    mock_ev_raw = {"id": "ev_1", "alert_id": "alert_1", "file_path": "path/to/ev.enc"}
    mock_ev_t = _make_chaining_mock([mock_ev_raw])
    mock_storage = MagicMock()
    mock_storage.create_signed_url.return_value = {"signedURL": "https://download.url"}
    with patch("app.db.safety.evidence.supabase_client.table", return_value=mock_ev_t), \
         patch("app.db.safety.evidence.supabase_client.storage.from_", return_value=mock_storage):
        ev = register_safety_evidence(USER_1, "alert_1", "path/to/ev.enc", "media_key", "audio/mp4", 60.0)
        assert ev is not None
        url = create_evidence_download_url("path/to/ev.enc", 3600)
        assert url == "https://download.url"
