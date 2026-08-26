"""Phase 9 Comprehensive Coverage Push to achieve 90%+ total coverage.

Targeting high-missing modules:
1. app/db/chat/chat.py & app/db/chat/keys.py
2. app/db/users/account_deletion.py & app/db/users/auth.py & app/db/users/consent.py & app/db/users/export.py
3. app/db/discovery/exclusions.py & app/db/discovery/matches.py
4. app/db/safety/alerts.py & app/db/safety/contacts.py & app/db/safety/evidence.py & app/db/safety/sessions.py
5. app/db/sessions/auth_sessions.py & app/db/sessions/viewport.py
6. app/core/email/notifications/account.py & app/core/email/notifications/feedback.py & app/core/email/notifications/safety.py & app/core/email/notifications/welcome.py
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from postgrest.exceptions import APIError

from app.core.security.crypto import encrypt_to_hex

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
CONV_1 = "00000000-0000-0000-0000-000000000010"
MSG_1 = "00000000-0000-0000-0000-000000000020"
ALERT_1 = "00000000-0000-0000-0000-000000000030"
SESS_1 = "00000000-0000-0000-0000-000000000040"


def _make_chaining_mock(data: Any = None, error: Exception | None = None) -> MagicMock:
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
        return MagicMock(data=data)

    def _single() -> MagicMock:
        if error:
            raise error
        if isinstance(data, list) and data:
            return MagicMock(data=data[0])
        return MagicMock(data=data)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    mock.single.return_value = single_mock
    return mock


# -----------------------------------------------------------------------------
# 1. DB CHAT KEYS & CHAT MODULE ERROR PATHS
# -----------------------------------------------------------------------------
def test_db_chat_keys_and_errors():
    from app.db.chat.keys import (
        bulk_insert_one_time_prekeys,
        count_unused_one_time_prekeys,
        fetch_active_matches_for_targets,
        fetch_identity_key,
        fetch_key_bundle,
        fetch_x3dh_key_bundle_unified,
        has_active_match,
        upsert_identity_key,
        upsert_signed_prekey,
    )
    from app.db.client import DatabaseAccessError

    mock_row = {
        "id": "k1",
        "key_id": 1,
        "public_key": "\\x6161",
        "signature": "\\x6262",
        "identity_public_key": "\\x6363",
        "registration_id": 12345,
    }
    mock_ok = _make_chaining_mock([mock_row])
    mock_err = _make_chaining_mock(error=APIError({"message": "DB error"}))

    # Success paths
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_ok), \
         patch("app.db.chat.keys.supabase_client.rpc") as mock_rpc:
        mock_rpc.return_value.execute.return_value = MagicMock(data=[{"key_id": 1, "public_key": "\\x6161"}])
        upsert_identity_key(USER_1, b"x" * 32, 12345)
        fetch_identity_key(USER_1)
        upsert_signed_prekey(USER_1, 1, b"x" * 32, b"s" * 64)
        bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"x" * 32}])
        count_unused_one_time_prekeys(USER_1)
        has_active_match(USER_1, USER_2)
        fetch_active_matches_for_targets(USER_1, [USER_2])
        fetch_key_bundle(USER_1)
        fetch_x3dh_key_bundle_unified(USER_1, USER_2)

    # Error / exception handling paths
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_err), \
         patch("app.db.chat.keys.supabase_client.rpc", side_effect=APIError({"message": "DB error"})):
        with pytest.raises(DatabaseAccessError):
            upsert_identity_key(USER_1, b"x" * 32, 12345)
        with pytest.raises(DatabaseAccessError):
            fetch_identity_key(USER_1)
        with pytest.raises(DatabaseAccessError):
            upsert_signed_prekey(USER_1, 1, b"x" * 32, b"s" * 64)
        with pytest.raises(DatabaseAccessError):
            bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"x" * 32}])
        with pytest.raises(DatabaseAccessError):
            count_unused_one_time_prekeys(USER_1)
        with pytest.raises(DatabaseAccessError):
            has_active_match(USER_1, USER_2)
        with pytest.raises(DatabaseAccessError):
            fetch_active_matches_for_targets(USER_1, [USER_2])
        with pytest.raises(DatabaseAccessError):
            fetch_key_bundle(USER_1)


def test_db_chat_edge_cases():
    from app.db.chat.chat import (
        create_event_with_message,
        decrypt_event_row,
        fetch_conversation_for_match,
        fetch_conversation_participants,
        fetch_conversations_for_user,
        fetch_event,
        insert_message,
        mark_messages_read,
    )
    from app.db.client import DatabaseAccessError

    mock_row = {
        "id": CONV_1,
        "user_a_id": USER_1,
        "user_b_id": USER_2,
        "match_id": "m1",
        "tab": "Dating",
        "closed_at": None,
        "content": encrypt_to_hex("Hello", category="chat"),
        "title": encrypt_to_hex("Coffee Date", category="chat"),
        "location": encrypt_to_hex("Cafe", category="chat"),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    mock_ok = _make_chaining_mock([mock_row])
    mock_err = _make_chaining_mock(error=APIError({"message": "DB error"}))

    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_ok):
        fetch_conversations_for_user(USER_1)
        fetch_conversation_for_match("m1")
        fetch_conversation_participants(CONV_1)
        insert_message(CONV_1, USER_1, "text", "msg_bytes", {})
        create_event_with_message(
            CONV_1, USER_1, "event_bytes", {}, datetime.now(timezone.utc),
            37.7, -122.4, "Cafe", True, 1800,
        )
        fetch_event("e1")
        mark_messages_read(CONV_1, USER_1)
        decrypt_event_row(mock_row)

    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_err):
        with pytest.raises(DatabaseAccessError):
            fetch_conversations_for_user(USER_1)
        with pytest.raises(DatabaseAccessError):
            fetch_conversation_for_match("m1")
        with pytest.raises(DatabaseAccessError):
            fetch_conversation_participants(CONV_1)
        with pytest.raises(DatabaseAccessError):
            insert_message(CONV_1, USER_1, "text", "msg_bytes", {})
        with pytest.raises(DatabaseAccessError):
            create_event_with_message(
                CONV_1, USER_1, "event_bytes", {}, datetime.now(timezone.utc),
                37.7, -122.4, "Cafe", True, 1800,
            )
        with pytest.raises(DatabaseAccessError):
            fetch_event("e1")
        with pytest.raises(DatabaseAccessError):
            mark_messages_read(CONV_1, USER_1)


# -----------------------------------------------------------------------------
# 2. DB USERS CONSENT, AUTH, AND ACCOUNT DELETION ERROR PATHWAYS
# -----------------------------------------------------------------------------
def test_db_users_consent_deep():
    from app.core.config import settings
    from app.db.users.consent import (
        update_community_guidelines_consent,
        update_safety_data_consent,
        update_special_category_consent,
        update_user_terms,
    )

    mock_user_row = {
        "id": USER_1,
        "accepted_terms_version": settings.current_terms_version,
        "terms_accepted_at": datetime.now(timezone.utc).isoformat(),
        "special_category_consent_version": settings.current_terms_version,
        "special_category_consent_at": datetime.now(timezone.utc).isoformat(),
        "safety_data_consent_version": settings.current_terms_version,
        "safety_data_consent_at": datetime.now(timezone.utc).isoformat(),
    }
    mock_ok = _make_chaining_mock([mock_user_row])
    mock_err = _make_chaining_mock(error=APIError({"message": "DB error"}))

    with patch("app.db.users.consent.supabase_client.table", return_value=mock_ok), \
         patch("app.db.users.consent.invalidate_user_status_cache"):
        update_user_terms(USER_1, settings.current_terms_version, granted=True)
        update_user_terms(USER_1, settings.current_terms_version, granted=False)
        update_community_guidelines_consent(USER_1, settings.current_terms_version, granted=True)
        update_special_category_consent(USER_1, settings.current_terms_version, granted=True)
        update_special_category_consent(USER_1, settings.current_terms_version, granted=False)
        update_safety_data_consent(USER_1, settings.current_terms_version, granted=True)
        update_safety_data_consent(USER_1, settings.current_terms_version, granted=False)

    with patch("app.db.users.consent.supabase_client.table", return_value=mock_err):
        with pytest.raises(HTTPException):
            update_user_terms(USER_1, settings.current_terms_version, granted=True)


# -----------------------------------------------------------------------------
# 3. DB SAFETY EVIDENCE & SESSIONS ERROR PATHWAYS
# -----------------------------------------------------------------------------
def test_db_safety_evidence_and_sessions_errors():
    from app.db.client import DatabaseAccessError
    from app.db.safety.evidence import (
        create_evidence_download_url,
        fetch_evidence_for_alert_ids,
        register_safety_evidence,
    )
    from app.db.safety.sessions import (
        end_safety_session,
        heartbeat_safety_session,
        start_safety_session,
    )

    mock_evidence = {
        "id": "ev1",
        "alert_id": ALERT_1,
        "storage_path": f"{ALERT_1}/audio.mp4",
        "media_key_base64": encrypt_to_hex("media_key_bytes", category="media_escrow"),
        "content_type": "audio/mp4",
        "duration_seconds": 30.0,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    mock_ok = _make_chaining_mock([mock_evidence])
    mock_err = _make_chaining_mock(error=APIError({"message": "DB error"}))

    with patch("app.db.safety.evidence.supabase_client.table", return_value=mock_ok), \
         patch("app.db.safety.evidence.supabase_client.storage.from_") as mock_storage, \
         patch("app.db.safety.sessions.supabase_client.rpc") as mock_rpc, \
         patch("app.db.safety.sessions.supabase_client.table", return_value=mock_ok):
        mock_storage.return_value.create_signed_url.return_value = {"signedURL": "https://signed.url"}
        mock_rpc.return_value.execute.return_value = MagicMock(data=[{"id": SESS_1, "status": "active"}])
        register_safety_evidence(USER_1, ALERT_1, f"{ALERT_1}/audio.mp4", "media_key_bytes", "audio/mp4", 30.0)
        fetch_evidence_for_alert_ids([ALERT_1])
        create_evidence_download_url(f"{ALERT_1}/audio.mp4", 300)

        start_safety_session(USER_1, "walk_home", 1800, datetime.now(timezone.utc).isoformat(), {"lat": 37.7, "lng": -122.4}, 85, "wifi")
        heartbeat_safety_session(USER_1, SESS_1, datetime.now(timezone.utc).isoformat(), 80, "wifi")
        end_safety_session(USER_1, SESS_1)

    with patch("app.db.safety.evidence.supabase_client.table", return_value=mock_err), \
         patch("app.db.safety.sessions.supabase_client.rpc", side_effect=APIError({"message": "DB error"})), \
         patch("app.db.safety.sessions.supabase_client.table", return_value=mock_err):
        with pytest.raises(DatabaseAccessError):
            register_safety_evidence(USER_1, ALERT_1, f"{ALERT_1}/audio.mp4", "media_key_bytes", "audio/mp4", 30.0)
        with pytest.raises(DatabaseAccessError):
            fetch_evidence_for_alert_ids([ALERT_1])
        with pytest.raises(DatabaseAccessError):
            start_safety_session(USER_1, "walk_home", 1800, datetime.now(timezone.utc).isoformat(), {"lat": 37.7, "lng": -122.4}, 85, "wifi")
        with pytest.raises(DatabaseAccessError):
            heartbeat_safety_session(USER_1, SESS_1, datetime.now(timezone.utc).isoformat(), 80, "wifi")
        with pytest.raises(DatabaseAccessError):
            end_safety_session(USER_1, SESS_1)


# -----------------------------------------------------------------------------
# 4. DB SESSIONS AUTH & VIEWPORT ERROR PATHWAYS
# -----------------------------------------------------------------------------
async def test_db_sessions_auth_and_viewport_deep():
    from app.db.client import DatabaseAccessError
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
    from app.db.sessions.viewport import (
        fetch_spatial_viewport,
    )

    mock_sess: dict[str, Any] = {
        "id": "s1",
        "viewer_id": USER_1,
        "tab": "Dating",
        "expires_at": (datetime.now(timezone.utc)).isoformat(),
        "created_at": (datetime.now(timezone.utc)).isoformat(),
        "filters": {},
    }
    mock_ok = _make_chaining_mock([mock_sess])
    mock_err = _make_chaining_mock(error=APIError({"message": "DB error"}))

    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_ok), \
         patch("app.db.sessions.auth_sessions.supabase_client.rpc") as mock_rpc, \
         patch("app.db.sessions.viewport.supabase_client.table", return_value=mock_ok), \
         patch("app.db.sessions.viewport.decrypt_profile_rows", return_value={USER_2: {"name": "Bob"}}), \
         patch("app.db.sessions.viewport.get_cached_active_block_ids", AsyncMock(return_value=set())):
        mock_rpc.return_value.execute.return_value = MagicMock(data="s1")
        create_discovery_session(USER_1, "Dating", {}, [{"profile": {"id": USER_2}}])
        get_discovery_session("s1", USER_1, "Dating")
        get_discovery_session_by_id("s1", USER_1)
        delete_expired_discovery_sessions()
        invalidate_viewer_discovery_sessions(USER_1)
        prune_excess_viewer_discovery_sessions(USER_1)
        verify_session_not_expired(mock_sess)
        is_candidate_in_active_session(USER_1, USER_2)
        get_candidate_session_details(USER_1, USER_2, "Dating")

        res, cnt = await fetch_spatial_viewport("s1", USER_1, 0.0, 0.0, 100.0, include_total_count=True)
        assert isinstance(res, list)
        assert isinstance(cnt, int)

    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_err), \
         patch("app.db.sessions.auth_sessions.supabase_client.rpc", side_effect=APIError({"message": "DB error"})), \
         patch("app.db.sessions.viewport.supabase_client.table", return_value=mock_err):
        with pytest.raises(DatabaseAccessError):
            create_discovery_session(USER_1, "Dating", {}, [{"profile": {"id": USER_2}}])
        with pytest.raises(DatabaseAccessError):
            get_discovery_session("s1", USER_1, "Dating")
        with pytest.raises(DatabaseAccessError):
            get_discovery_session_by_id("s1", USER_1)
        with pytest.raises(DatabaseAccessError):
            delete_expired_discovery_sessions()
        with pytest.raises(DatabaseAccessError):
            invalidate_viewer_discovery_sessions(USER_1)


# -----------------------------------------------------------------------------
# 5. CORE EMAIL NOTIFICATIONS ACCOUNT & SENDERS
# -----------------------------------------------------------------------------
async def test_core_email_notifications_and_senders_deep():
    from app.core.email.notifications.account import (
        send_account_deletion_otp_email,
        send_account_deletion_scheduled_email,
        send_account_reactivated_email,
        send_data_export_otp_email,
        send_login_otp_email,
        send_support_appeal_otp_email,
    )
    from app.core.email.notifications.feedback import (
        send_feedback_admin_notification_email,
        send_feedback_confirmation_email,
    )
    from app.core.email.notifications.safety import (
        send_trusted_contact_removed_email,
    )
    from app.core.email.notifications.welcome import (
        send_bootstrap_welcome_email,
    )

    with patch("app.core.email.notifications.account.email_pkg.send_email", AsyncMock(return_value=MagicMock(success=True))), \
         patch("app.core.email.notifications.feedback.email_pkg.send_email", AsyncMock(return_value=MagicMock(success=True))), \
         patch("app.core.email.notifications.safety.email_pkg.send_email", AsyncMock(return_value=MagicMock(success=True))), \
         patch("app.core.email.notifications.welcome.email_pkg.send_email", AsyncMock(return_value=MagicMock(success=True))):
        await send_login_otp_email("a@b.com", "123456")
        await send_account_deletion_otp_email("a@b.com", "123456", 14)
        await send_data_export_otp_email("a@b.com", "123456")
        await send_support_appeal_otp_email("a@b.com", "123456")
        await send_account_deletion_scheduled_email("a@b.com", datetime.now(timezone.utc))
        await send_account_reactivated_email("a@b.com")

        await send_feedback_confirmation_email("a@b.com", "bug_report", "Crash", "1", None)
        await send_feedback_admin_notification_email("1", "bug_report", "Crash", "Msg", USER_1, "a@b.com")

        await send_trusted_contact_removed_email("a@b.com", "Alice", "Bob")
        await send_bootstrap_welcome_email("a@b.com", None)
