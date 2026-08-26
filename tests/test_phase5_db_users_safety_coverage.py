"""Phase 5 Test Suite: Deep Branch Coverage for DB Users, Sessions & Safety.

Covers:
- app/db/users/account_deletion.py
- app/db/users/export.py
- app/db/users/consent.py
- app/db/users/auth.py
- app/db/safety/alerts.py
- app/db/safety/sessions.py
- app/db/safety/contacts.py
- app/db/sessions/auth_sessions.py
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.core.security.crypto import encrypt_to_hex
from app.db.safety.alerts import (
    fetch_alerts_for_session,
    fetch_contact_facing_profile_summary,
    fetch_recent_safety_alert,
    fetch_safety_alert,
    purge_expired_safety_evidence,
    purge_safety_data_for_purged_accounts,
    record_safety_alert,
    update_alert_contacts_notified,
)
from app.db.safety.contacts import (
    _phone_blind_index,
    fetch_safety_contact_by_id,
    fetch_safety_contacts,
    fetch_safety_contacts_with_id,
    remove_safety_contact_self_service,
    sync_safety_contacts,
)
from app.db.safety.sessions import (
    _decrypt_session_row,
    cancel_safety_escalation,
    end_safety_session,
    fetch_overdue_safety_sessions,
    fetch_safety_session,
    fetch_safety_session_for_user,
    heartbeat_safety_session,
    record_safety_escalation_sent,
    start_safety_session,
)
from app.db.sessions.auth_sessions import (
    create_discovery_session,
    delete_expired_discovery_sessions,
    get_candidate_session_details,
    get_discovery_session,
    get_discovery_session_by_id,
    invalidate_viewer_discovery_sessions,
    is_candidate_in_active_session,
    prune_excess_viewer_discovery_sessions,
    verify_session_not_expired,
)
from app.db.users.account_deletion import (
    _anonymize_profile_and_user,
    _archive_account_history,
    _chunked_delete_by_field,
    _chunked_delete_by_or_filter,
    _chunked_pre_purge_child_records,
    _delete_no_retention_rows,
    _delete_user_media_objects,
    _permanently_unmatch_all,
    _purge_discovery_for_user,
    _purge_single_due_account,
    _purge_vector_profiles_for_user,
    _reason_code_for_flag,
    cancel_deletion,
    expire_blocklist_entries,
    fetch_deletion_status,
    hard_purge_long_tail_accounts,
    is_phone_blocklisted,
    purge_due_accounts,
    request_deletion,
)
from app.db.users.auth import (
    _decrypt_mobile,
    _dump_user_object,
    _load_disposable_domains,
    fetch_public_user,
    find_user_id_by_phone,
    get_user_email_by_id,
    get_user_id_by_email,
    is_allowed_email,
    is_disposable_email,
    set_user_suspension,
    set_verified_mobile,
    upsert_public_user,
)
from app.db.users.consent import (
    _parse_terms_timestamp,
    _parse_version_tuple,
    _validate_terms_versions,
    _verify_general_terms_accepted,
    update_community_guidelines_consent,
    update_safety_data_consent,
    update_special_category_consent,
    update_user_terms,
)
from app.db.users.export import (
    _build_account_section,
    _build_chat_section,
    _build_consent_history,
    _build_feedback_section,
    _build_matches_and_discovery,
    _build_profile_section,
    _build_reports_section,
    _build_safety_section,
    _build_spotify_section,
    _sign_urls,
    build_user_data_export,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
ALERT_1 = "00000000-0000-0000-0000-000000000010"
SESSION_1 = "00000000-0000-0000-0000-000000000020"


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
        import copy
        return MagicMock(data=copy.deepcopy(data))  # pyright: ignore[reportUnknownArgumentType,reportUnknownMemberType]

    def _single() -> MagicMock:
        import copy
        if isinstance(data, list) and data:
            return MagicMock(data=copy.deepcopy(data[0]))  # pyright: ignore[reportUnknownArgumentType,reportUnknownMemberType]
        return MagicMock(data=copy.deepcopy(data))  # pyright: ignore[reportUnknownArgumentType,reportUnknownMemberType]

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    return mock


# ==============================================================================
# 1. DB USERS ACCOUNT DELETION
# ==============================================================================

def test_db_users_account_deletion():
    # Helper reason checks
    assert _reason_code_for_flag({"moderation_status": "banned"}, False) == "banned"
    assert _reason_code_for_flag({"moderation_status": "restricted"}, False) == "restricted"
    assert _reason_code_for_flag({"is_suspended": True}, False) == "suspended"
    assert _reason_code_for_flag({}, True) == "unresolved_report"
    assert _reason_code_for_flag({}, False) is None

    # is_phone_blocklisted
    mock_table = _make_chaining_mock([{"id": 1, "cooldown_expires_at": "2026-09-01T00:00:00Z"}])
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_table):
        assert is_phone_blocklisted("blind_idx_123") is True

    # fetch_deletion_status
    mock_table = _make_chaining_mock([{"deletion_requested_at": "2026-08-25T10:00:00Z", "scheduled_purge_at": "2026-09-25T10:00:00Z"}])
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_table):
        status = fetch_deletion_status(USER_1)
        assert status is not None
        assert "deletion_requested_at" in status

    # request_deletion & cancel_deletion
    mock_table = _make_chaining_mock([{"id": 1}])
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_table):
        request_deletion(USER_1, "HARASS")
        cancel_deletion(USER_1)

    # Purge helpers
    now = datetime.now(timezone.utc)
    mock_table = _make_chaining_mock([{"user_id": USER_1, "phone_blind_index": "idx", "flag_reason": "HARASS"}])
    mock_storage = MagicMock()
    mock_storage.list.return_value = []
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.account_deletion.supabase_client.storage.from_", return_value=mock_storage), \
         patch("app.core.infra.cache.invalidate_user_status_cache"):
        _permanently_unmatch_all(USER_1)
        _anonymize_profile_and_user(USER_1, now)
        _purge_vector_profiles_for_user(USER_1)
        _purge_discovery_for_user(USER_1)
        _delete_no_retention_rows(USER_1)
        _delete_user_media_objects(USER_1)
        _purge_single_due_account({"user_id": USER_1, "phone_blind_index": "idx", "flag_reason": "HARASS"}, now)
        purge_due_accounts()
        expire_blocklist_entries()

    # Long tail archive & purge helpers
    mock_table = _make_chaining_mock([])
    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_table):
        _archive_account_history(USER_1)
        _chunked_delete_by_field("profile_discovery_actions", "actor_id", USER_1)
        _chunked_delete_by_or_filter("matches", f"liker_id.eq.{USER_1},liked_back_id.eq.{USER_1}", USER_1)
        _chunked_pre_purge_child_records(USER_1)
        hard_purge_long_tail_accounts()


# ==============================================================================
# 2. DB USERS EXPORT
# ==============================================================================

def test_db_users_export():
    # _sign_urls
    mock_storage = MagicMock()
    mock_storage.create_signed_urls.return_value = [{"path": "u1/pic.jpg", "signedURL": "https://signed.url"}]
    with patch("app.db.users.export.supabase_client.storage.from_", return_value=mock_storage):
        signed = _sign_urls("avatars", ["u1/pic.jpg"])
        assert isinstance(signed, dict)
        assert "u1/pic.jpg" in signed

    # Section builders with mocked tables
    mock_table = _make_chaining_mock([
        {"id": USER_1, "display_name": encrypt_to_hex("Alice"), "event_time": encrypt_to_hex("2026-08-25T12:00:00Z", category="chat"), "action": "like", "user_a_id": USER_1}
    ])

    with patch("app.db.users.export.supabase_client.table", return_value=mock_table):
        prof = _build_profile_section(USER_1)
        assert prof is not None

        acc = _build_account_section(USER_1)
        assert acc is not None

        mat = _build_matches_and_discovery(USER_1)
        assert mat is not None

        chat = _build_chat_section(USER_1)
        assert chat is not None

        rep = _build_reports_section(USER_1)
        assert rep is not None

        fb = _build_feedback_section(USER_1)
        assert isinstance(fb, list)

        saf = _build_safety_section(USER_1)
        assert saf is not None

        spot = _build_spotify_section(USER_1)
        assert isinstance(spot, list)

        con = _build_consent_history(USER_1)
        assert isinstance(con, list)

        full_exp = build_user_data_export(USER_1)
        assert "profile" in full_exp
        assert "account" in full_exp


# ==============================================================================
# 3. DB USERS CONSENT
# ==============================================================================

def test_db_users_consent():
    # Parsing & validation helpers
    now = datetime.now(timezone.utc)
    ts = _parse_terms_timestamp(now.isoformat())
    assert ts.year == now.year
    with pytest.raises(HTTPException):
        _parse_terms_timestamp(None)

    v_tuple = _parse_version_tuple("2.1.0")
    assert v_tuple == (2, 1, 0)
    with patch("app.db.users.consent.settings.current_terms_version", "2.0.0"):
        _validate_terms_versions("2.0.0")

    # Consent update / log / verify
    mock_table = _make_chaining_mock([
        {"accepted_terms_version": "2.0.0", "terms_accepted_at": now.isoformat()}
    ])

    with patch("app.db.users.consent.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.consent.settings.current_terms_version", "2.0.0"), \
         patch("app.core.infra.cache.invalidate_user_status_cache"):
        _verify_general_terms_accepted(USER_1)
        update_user_terms(USER_1, "2.0.0", granted=True)
        update_community_guidelines_consent(USER_1, "2.0.0")
        update_special_category_consent(USER_1, "2.0.0", True)
        update_safety_data_consent(USER_1, "2.0.0", True)


# ==============================================================================
# 4. DB USERS AUTH
# ==============================================================================

def test_db_users_auth():
    # Disposable & allowed email
    domains = _load_disposable_domains()
    assert isinstance(domains, set)
    with patch("app.db.users.auth.DISPOSABLE_DOMAINS", {"mailinator.com"}):
        assert is_disposable_email("user@mailinator.com") is True
        assert is_disposable_email("user@gmail.com") is False
    assert is_allowed_email("student@berkeley.edu", app_variant="nexus") is True

    # User dump and decrypt mobile
    dumped = _dump_user_object({"id": USER_1, "email": "test@test.com"})
    assert dumped["id"] == USER_1

    dec_mob = _decrypt_mobile({"mobile": encrypt_to_hex("+14155552671", category="contact")})
    assert dec_mob["mobile"] == "+14155552671"

    # Public user queries and suspensions
    mock_table = _make_chaining_mock([
        {"id": USER_1, "mobile": encrypt_to_hex("+14155552671", category="contact"), "is_suspended": False}
    ])

    with patch("app.db.users.auth.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.is_phone_blocklisted", return_value=False), \
         patch("app.core.infra.cache.invalidate_user_status_cache"):
        pub = fetch_public_user(USER_1)
        assert pub is not None
        set_verified_mobile(USER_1, "+14155552671")
        set_user_suspension(USER_1, is_suspended=True, moderation_reason_code="abuse")
        find_user_id_by_phone("+14155552671")
        get_user_email_by_id(USER_1)
        get_user_id_by_email("test@berkeley.edu")
        upsert_public_user(USER_1, app_variant="nexus")


# ==============================================================================
# 5. DB SAFETY ALERTS, SESSIONS & CONTACTS
# ==============================================================================

def test_db_safety_alerts_sessions_and_contacts():
    # Contacts
    idx = _phone_blind_index("+14155552671")
    assert isinstance(idx, str)

    def fresh_contact():
        return {
            "id": "contact-1",
            "user_id": USER_1,
            "name": encrypt_to_hex("Bob", category="contact"),
            "phone": encrypt_to_hex("+14155552671", category="contact"),
        }

    mock_table = _make_chaining_mock([fresh_contact()])
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data={"blocked_indices": [], "newly_notified_indices": []})

    with patch("app.db.safety.contacts.supabase_client.table", return_value=mock_table), \
         patch("app.db.safety.contacts.supabase_client.rpc", return_value=mock_rpc):
        sync_safety_contacts(USER_1, [{"phone": "+14155552671", "name": "Bob"}])
        c_list = fetch_safety_contacts(USER_1)
        assert len(c_list) >= 1
        fetch_safety_contacts_with_id(USER_1)
        fetch_safety_contact_by_id("contact-1")
        remove_safety_contact_self_service("contact-1")

    # Sessions
    enc_label = encrypt_to_hex("Home", category="media_escrow")
    dec_sess = _decrypt_session_row({"id": SESSION_1, "label": enc_label})
    assert dec_sess["label"] == "Home"

    now = datetime.now(timezone.utc)
    mock_sess_table = _make_chaining_mock([
        {"id": SESSION_1, "user_id": USER_1, "status": "active", "label": enc_label, "next_checkin_at": (now + timedelta(hours=2)).isoformat()}
    ])
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(
        data={"id": SESSION_1, "user_id": USER_1, "status": "active", "label": enc_label}
    )

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_sess_table), \
         patch("app.db.safety.sessions.supabase_client.rpc", return_value=mock_rpc):
        s_row = start_safety_session(
            USER_1,
            label="Cafe",
            interval_seconds=3600,
            next_checkin_at=(now + timedelta(hours=1)).isoformat(),
            event_context={},
            battery_percent=90,
            connection_type="wifi",
        )
        assert s_row is not None
        heartbeat_safety_session(
            USER_1,
            SESSION_1,
            next_checkin_at=(now + timedelta(minutes=15)).isoformat(),
            battery_percent=85,
            connection_type="wifi",
        )
        end_safety_session(USER_1, SESSION_1)
        fetch_overdue_safety_sessions(grace_seconds=60)
        record_safety_escalation_sent(SESSION_1, new_count=1)
        fetch_safety_session(SESSION_1)
        fetch_safety_session_for_user(USER_1, SESSION_1)
        cancel_safety_escalation(USER_1, SESSION_1, reason="safe", note="ok")

    # Alerts
    mock_alert_table = _make_chaining_mock([
        {"id": ALERT_1, "session_id": SESSION_1, "alert_type": "overdue", "storage_path": "u1/alert.jpg"}
    ])
    mock_storage = MagicMock()
    with patch("app.db.safety.alerts.supabase_client.table", return_value=mock_alert_table), \
         patch("app.db.safety.alerts.supabase_client.storage.from_", return_value=mock_storage):
        fetch_contact_facing_profile_summary(USER_1)
        record_safety_alert(USER_1, "overdue", None, session_id=SESSION_1)
        fetch_safety_alert(ALERT_1)
        fetch_recent_safety_alert(USER_1, alert_type="overdue")
        update_alert_contacts_notified(ALERT_1, count=2)
        fetch_alerts_for_session(SESSION_1)
        purge_expired_safety_evidence()
        purge_safety_data_for_purged_accounts()


# ==============================================================================
# 6. DB SESSIONS AUTH & DISCOVERY SESSIONS
# ==============================================================================

def test_db_sessions_auth_and_discovery():
    now = datetime.now(timezone.utc)
    sess_valid = {"id": SESSION_1, "viewer_id": USER_1, "candidate_ids": [USER_2], "expires_at": (now + timedelta(hours=1)).isoformat()}
    sess_expired = {"id": SESSION_1, "viewer_id": USER_1, "candidate_ids": [USER_2], "expires_at": (now - timedelta(hours=1)).isoformat()}
    assert verify_session_not_expired(sess_valid) is True
    assert verify_session_not_expired(sess_expired) is False

    mock_table = _make_chaining_mock([sess_valid])
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data=SESSION_1)

    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table), \
         patch("app.db.sessions.auth_sessions.supabase_client.rpc", return_value=mock_rpc):
        prune_excess_viewer_discovery_sessions(USER_1)
        sess_id, exp_dt = create_discovery_session(
            viewer_id=USER_1,
            active_tab="Dating",
            filters={},
            ranked_items=[{"candidate_id": USER_2, "profile": {"id": USER_2}}],
        )
        assert sess_id == SESSION_1
        assert exp_dt is not None
        get_discovery_session(SESSION_1, USER_1, "Dating")
        get_discovery_session_by_id(SESSION_1, USER_1)
        delete_expired_discovery_sessions()
        invalidate_viewer_discovery_sessions(USER_1)
        is_candidate_in_active_session(USER_1, USER_2)
        get_candidate_session_details(USER_1, USER_2)
