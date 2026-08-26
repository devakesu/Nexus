"""Phase 23 Coverage Suite: Comprehensive coverage for app/db/users/ (account_deletion.py, export.py, import_export.py, auth.py, consent.py)."""

from __future__ import annotations

from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from postgrest.exceptions import APIError

from app.core.config import settings
from app.core.security.crypto import DecryptFailedError
from app.db.client import DatabaseAccessError

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"


# =============================================================================
# 1. DB USERS ACCOUNT DELETION TESTS
# =============================================================================

def test_db_users_account_deletion_deep():
    from app.db.users.account_deletion import (
        _chunked_delete_by_field,
        _chunked_delete_by_or_filter,
        _fetch_accounts_due_for_long_tail_purge,
        _fetch_archive_source,
        _insert_archive_rows,
        _purge_single_due_account,
        cancel_deletion,
        compute_deletion_flag_reason,
        expire_blocklist_entries,
        fetch_deletion_status,
        hard_purge_long_tail_accounts,
        is_phone_blocklisted,
        purge_due_accounts,
        request_deletion,
    )

    # compute_deletion_flag_reason error handling when fetching reports
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().select().eq().in_().limit().execute.side_effect = APIError({"message": "report fail"})
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[{"is_suspended": True}])
        with pytest.raises(DatabaseAccessError, match="Failed to fetch reports"):
            compute_deletion_flag_reason(USER_1)

    # is_phone_blocklisted: empty blind index, APIError, and blocklist hit
    assert is_phone_blocklisted("") is False
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().select().eq().gt().limit().execute.side_effect = APIError({"message": "blocklist error"})
        with pytest.raises(DatabaseAccessError, match="Failed to check phone blocklist"):
            is_phone_blocklisted("blind-index-123456789012")

        # Blocklist hit with long and short blind index
        mock_sb.table().select().eq().gt().limit().execute.side_effect = None
        mock_sb.table().select().eq().gt().limit().execute.return_value = MagicMock(
            data=[{"id": "bl-1", "cooldown_expires_at": "2026-12-31T00:00:00Z"}],
        )
        assert is_phone_blocklisted("1234567890123456") is True
        assert is_phone_blocklisted("short") is True

    # fetch_deletion_status: APIError & empty/non-dict
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError, match="Failed to fetch deletion status"):
            fetch_deletion_status(USER_1)

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        assert fetch_deletion_status(USER_1) is None

    # request_deletion: APIErrors on users update & profiles update
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb, \
         patch("app.db.users.account_deletion.invalidate_user_status_cache"):
        
        # APIError on users update
        mock_sb.table().update().eq().execute.side_effect = APIError({"message": "users update fail"})
        with pytest.raises(DatabaseAccessError, match="Failed to request account deletion"):
            request_deletion(USER_1, flagged_reason_code="spam")

        # APIError on profiles update
        mock_sb.table().update().eq().execute.side_effect = [MagicMock(), APIError({"message": "profiles update fail"})]
        with pytest.raises(DatabaseAccessError, match="Failed to request account deletion"):
            request_deletion(USER_1, flagged_reason_code=None)

    # cancel_deletion: APIErrors on users / profiles updates, and best-effort device update APIError
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb, \
         patch("app.db.users.account_deletion.invalidate_user_status_cache"), \
         patch("app.db.users.account_deletion.reopen_conversations_for_reactivation"):
        
        # APIError on users update
        mock_sb.table().update().eq().execute.side_effect = APIError({"message": "users cancel fail"})
        with pytest.raises(DatabaseAccessError, match="Failed to cancel account deletion"):
            cancel_deletion(USER_1)

        # APIError on profiles update
        mock_sb.table().update().eq().execute.side_effect = [MagicMock(), APIError({"message": "profiles cancel fail"})]
        with pytest.raises(DatabaseAccessError, match="Failed to cancel account deletion"):
            cancel_deletion(USER_1)

        # APIError on devices update is swallowed (best-effort)
        mock_sb.table().update().eq().execute.side_effect = [MagicMock(), MagicMock(), APIError({"message": "devices fail"})]
        cancel_deletion(USER_1)

    # _purge_single_due_account: test exception handler inside it
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb, \
         patch("app.db.users.account_deletion.invalidate_user_status_cache"):
        mock_sb.table().select().eq().limit().execute.side_effect = Exception("single purge crash")
        _purge_single_due_account({"id": USER_1}, datetime.now(timezone.utc))

    # purge_due_accounts & expire_blocklist_entries APIError
    with patch("app.db.users.account_deletion._fetch_accounts_due_for_purge", return_value=[]):
        purge_due_accounts()

    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().delete().lte().execute.side_effect = APIError({"message": "expire fail"})
        expire_blocklist_entries()

    # _fetch_archive_source generic Exception & _insert_archive_rows APIError / Exception
    source = ("user_reports", "target_id", "reason_code", "review_status")
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().select().or_().execute.side_effect = Exception("DB crash")
        assert _fetch_archive_source(source, USER_1) is None

        # _insert_archive_rows APIError & generic Exception
        mock_sb.table().insert().execute.side_effect = APIError({"message": "insert fail"})
        assert _insert_archive_rows("user_reports", [{"created_at": "2026-08-01T00:00:00Z", "reason_code": "spam"}], "reason_code", "review_status", USER_1) is False

        mock_sb.table().insert().execute.side_effect = Exception("insert crash")
        assert _insert_archive_rows("user_reports", [{"created_at": "2026-08-01T00:00:00Z", "reason_code": "spam"}], "reason_code", "review_status", USER_1) is False

    # _fetch_accounts_due_for_long_tail_purge APIError
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().select().not_.is_().lte().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError, match="Failed to fetch accounts due for long-tail purge"):
            _fetch_accounts_due_for_long_tail_purge()

    # _chunked_delete_by_field and _chunked_delete_by_or_filter with exceptions
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = Exception("chunk fail")
        _chunked_delete_by_field("chat_messages", "sender_id", USER_1, chunk_size=10)

        mock_sb.table().select().or_().limit().execute.side_effect = Exception("chunk or fail")
        _chunked_delete_by_or_filter("matches", "liker_id.eq.1", USER_1, chunk_size=10)

    # hard_purge_long_tail_accounts with archival failure and exception
    with patch("app.db.users.account_deletion._fetch_accounts_due_for_long_tail_purge", return_value=[USER_1, USER_2]), \
         patch("app.db.users.account_deletion._archive_account_history", side_effect=[["user_reports"], []]), \
         patch("app.db.users.account_deletion._chunked_pre_purge_child_records"), \
         patch("app.db.users.account_deletion.supabase_client") as mock_sb, \
         patch("time.sleep"):
        mock_sb.auth.admin.delete_user.side_effect = Exception("Auth delete fail")
        hard_purge_long_tail_accounts()


# =============================================================================
# 2. DB USERS EXPORT TESTS
# =============================================================================

def test_db_users_export_deep():
    from app.db.users.export import (
        _build_account_section,
        _build_chat_section,
        _build_consent_history,
        _build_feedback_section,
        _build_matches_and_discovery,
        _build_profile_section,
        _build_reports_section,
        _build_safety_alerts,
        _build_safety_evidence,
        _build_safety_section,
        _build_spotify_section,
        _fetch_and_decrypt_chat_events,
        _safe_select,
        _sign_urls,
        build_user_data_export,
    )

    # _safe_select APIError -> []
    with patch("app.db.users.export.supabase_client") as mock_sb:
        mock_sb.table().select().eq().execute.side_effect = APIError({"message": "fail"})
        assert _safe_select("matches", "id", USER_1, id_column="liker_id") == []

    # _sign_urls exception -> {}
    with patch("app.db.users.export.supabase_client") as mock_sb:
        mock_sb.storage.from_().create_signed_urls.side_effect = Exception("Storage fail")
        assert _sign_urls("media", ["pic1.jpg"]) == {}

    # _build_profile_section: APIError, DecryptFailedError, spotify affinity notes
    with patch("app.db.users.export.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError({"message": "fail"})
        assert _build_profile_section(USER_1) == {}

        # DecryptFailedError
        mock_sb.table().select().eq().maybe_single().execute.side_effect = None
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data={"id": USER_1, "name": "enc"})
        with patch("app.db.users.export.decrypt_profile_record", side_effect=DecryptFailedError("fail")):
            assert _build_profile_section(USER_1) == {}

        # Spotify affinities and photo URLs
        with patch("app.db.users.export.decrypt_profile_record", return_value={
            "id": USER_1,
            "name": "Alice",
            "artist_affinity": {"queen": 1.0},
            "profile_pic": "avatar.jpg",
            "normal_pics": ["p1.jpg", "p2.jpg"],
        }), patch("app.db.users.export._sign_urls", return_value={"avatar.jpg": "https://cdn/avatar.jpg", "p1.jpg": "https://cdn/p1.jpg"}):
            sec = _build_profile_section(USER_1)
            assert "derived_signals_note" in sec
            assert sec["profile_pic"] == "https://cdn/avatar.jpg"
            assert sec["normal_pics"] == ["https://cdn/p1.jpg"]

    # _build_account_section: APIError & deleted email
    with patch("app.db.users.export.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError({"message": "fail"})
        assert _build_account_section(USER_1) == {}

        mock_sb.table().select().eq().maybe_single().execute.side_effect = None
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data={"id": USER_1})
        with patch("app.db.users.export.get_user_email_by_id", return_value="deleted-123@deleted.nexus.internal"):
            acc = _build_account_section(USER_1)
            assert acc["email"] is None

    # _build_matches_and_discovery: APIError & success
    with patch("app.db.users.export.supabase_client") as mock_sb, \
         patch("app.db.users.export._safe_select", return_value=[]):
        mock_sb.table().select().or_().execute.side_effect = APIError({"message": "fail"})
        res = _build_matches_and_discovery(USER_1)
        assert res["matches"] == []

        mock_sb.table().select().or_().execute.side_effect = None
        mock_sb.table().select().or_().execute.return_value = MagicMock(data=[{"id": "match-1"}])
        res = _build_matches_and_discovery(USER_1)
        assert len(res["matches"]) == 1

    # _fetch_and_decrypt_chat_events with location coordinates and APIError
    with patch("app.db.users.export.supabase_client") as mock_sb, \
         patch("app.db.users.export.decrypt_event_row", return_value={
            "id": "ev-1",
            "event_time": "2026-08-26T20:00:00Z",
            "location_lat": 12.34,
            "location_lng": 56.78,
            "location_label": "Place",
        }):
        mock_sb.table().select().in_().execute.return_value = MagicMock(data=[{"id": "ev-1"}])
        events = _fetch_and_decrypt_chat_events(["conv-1"], USER_1)
        assert len(events) == 1
        assert "location_sensitivity_note" in events[0]

        mock_sb.table().select().in_().execute.side_effect = APIError({"message": "fail"})
        assert _fetch_and_decrypt_chat_events(["conv-1"], USER_1) == []

    # _build_chat_section: DecryptFailedError on message content & APIError on conversations
    with patch("app.db.users.export.supabase_client") as mock_sb:
        mock_sb.table().select().or_().execute.side_effect = APIError({"message": "convs fail"})
        chat = _build_chat_section(USER_1)
        assert chat["conversations"] == []
        assert chat["messages"] == []

        # Successful conversations fetch with message exclusion reason
        mock_sb.table().select().or_().execute.side_effect = None
        mock_sb.table().select().or_().execute.return_value = MagicMock(data=[{"id": "conv-1"}])
        mock_sb.table().select().in_().execute.return_value = MagicMock(data=[{"id": "msg-1"}])
        mock_sb.table().select().eq().execute.return_value = MagicMock(data=[{"is_online": True}])
        with patch("app.db.users.export._fetch_and_decrypt_chat_events", return_value=[]):
            chat_res = _build_chat_section(USER_1)
            assert len(chat_res["conversations"]) == 1
            assert len(chat_res["messages"]) == 1
            assert "content_excluded_reason" in chat_res["messages"][0]

    # _build_reports_section, _build_feedback_section, _build_safety_alerts, _build_safety_evidence, _build_safety_section, _build_spotify_section, _build_consent_history
    with patch("app.db.users.export.supabase_client") as mock_sb, \
         patch("app.db.users.export._safe_select", return_value=[]):
        mock_sb.table().select().or_().execute.return_value = MagicMock(data=[])
        assert _build_reports_section(USER_1) == {
            "reports_you_filed": [],
            "reports_against_you": [],
            "moderation_actions": [],
        }
        assert _build_feedback_section(USER_1) == []
        assert _build_safety_alerts(USER_1) == []
        assert _build_safety_evidence(USER_1) == []
        
        # _build_safety_section with contact fetch exception
        with patch("app.db.users.export.fetch_safety_contacts", side_effect=Exception("contacts fail")):
            safety_sec = _build_safety_section(USER_1)
            assert safety_sec["trusted_contacts"] == []
            assert safety_sec["checkin_sessions"] == []

        assert _build_spotify_section(USER_1) == []
        assert _build_consent_history(USER_1) == []

    # build_user_data_export integration check
    with patch("app.db.users.export._build_profile_section", return_value={"name": "Alice"}), \
         patch("app.db.users.export._build_account_section", return_value={"id": USER_1}), \
         patch("app.db.users.export._build_matches_and_discovery", return_value={}), \
         patch("app.db.users.export._build_chat_section", return_value={}), \
         patch("app.db.users.export._build_safety_section", return_value={}), \
         patch("app.db.users.export._build_feedback_section", return_value=[]), \
         patch("app.db.users.export._build_reports_section", return_value={}), \
         patch("app.db.users.export._build_spotify_section", return_value=[]), \
         patch("app.db.users.export._build_consent_history", return_value=[]), \
         patch("app.db.users.export._safe_select", return_value=[]):
        data = build_user_data_export(USER_1)
        assert data["profile"]["name"] == "Alice"
        assert data["account"]["id"] == USER_1


# =============================================================================
# 3. DB USERS IMPORT/EXPORT, AUTH & CONSENT TESTS
# =============================================================================

async def test_db_users_auth_import_consent_deep():
    from app.db.users.auth import (
        _load_disposable_domains,
        fetch_public_user,
        find_user_id_by_phone,
        get_supabase_user_from_jwt,
        get_user_email_by_id,
        get_user_id_by_email,
        is_allowed_email,
        is_disposable_email,
        set_user_suspension,
        set_verified_mobile,
        upsert_public_user,
    )
    from app.db.users.consent import (
        _clear_consent_pair,
        _fetch_existing_consent_pair,
        _log_consent_event,
        _parse_terms_timestamp,
        _parse_version_tuple,
        _update_consent_pair,
        _validate_terms_versions,
        _verify_general_terms_accepted,
        update_community_guidelines_consent,
        update_safety_data_consent,
        update_special_category_consent,
        update_user_terms,
    )
    from app.db.users.import_export import (
        _fetch_import_profiles,
        _validate_import,
        execute_import,
        generate_export_code,
    )

    # _load_disposable_domains OSError test & is_disposable_email with mocked set
    with patch("builtins.open", side_effect=OSError("file not found")):
        domains = _load_disposable_domains()
        assert domains == set()

    with patch("app.db.users.auth.DISPOSABLE_DOMAINS", {"mailinator.com", "tempmail.com"}):
        assert is_disposable_email("user@mailinator.com") is True
        assert is_disposable_email("user@gmail.com") is False
        assert is_disposable_email("invalid_no_at") is False

    # is_allowed_email with domain whitelist
    with patch.object(settings, "allowed_signup_domains", {"campus_flavor": ["campus.edu"]}):
        assert is_allowed_email("user@campus.edu", app_variant="campus_flavor") is True
        assert is_allowed_email("user@other.edu", app_variant="campus_flavor") is False
        assert is_allowed_email("user@anywhere.com", app_variant="nexus") is True
        assert is_allowed_email("user@anywhere.com", app_variant="unconfigured_flavor") is True

    # get_supabase_user_from_jwt: token error (401), user is None (401)
    with patch("app.db.users.auth.supabase_client") as mock_sb:
        mock_sb.auth.get_user.side_effect = Exception("invalid jwt")
        with pytest.raises(HTTPException, match="Invalid or expired access token"):
            get_supabase_user_from_jwt("bad-jwt")

        mock_sb.auth.get_user.side_effect = None
        mock_sb.auth.get_user.return_value = MagicMock(user=None)
        with pytest.raises(HTTPException, match="Authenticated user not found"):
            get_supabase_user_from_jwt("jwt")

    # fetch_public_user: APIError (503), empty data (None), not dict (None), mobile DecryptFailedError
    with patch("app.db.users.auth.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(HTTPException, match="User service temporarily unavailable"):
            fetch_public_user(USER_1)

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        assert fetch_public_user(USER_1) is None

        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=["not-dict"])
        assert fetch_public_user(USER_1) is None

        # Mobile decryption failure logs and returns mobile as None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[{"id": USER_1, "mobile": "enc_mobile"}])
        with patch("app.db.users.auth.decrypt_pii", side_effect=DecryptFailedError("fail")):
            u = fetch_public_user(USER_1)
            assert u is not None
            assert u["mobile"] is None

    # set_verified_mobile: restricted phone (409), duplicate phone (409), generic APIError (503)
    with patch("app.db.users.is_phone_blocklisted", return_value=True):
        with pytest.raises(HTTPException, match="This phone number is restricted"):
            set_verified_mobile(USER_1, "+1234567890")

    with patch("app.db.users.is_phone_blocklisted", return_value=False), \
         patch("app.db.users.auth.supabase_client") as mock_sb:
        
        # Duplicate key 23505 -> 409
        err_dup = APIError({"message": "duplicate key value", "code": "23505"})
        err_dup.code = "23505"
        mock_sb.table().update().eq().execute.side_effect = err_dup
        with pytest.raises(HTTPException, match="already linked to another account"):
            set_verified_mobile(USER_1, "+1234567890")

        # Generic APIError -> 503
        mock_sb.table().update().eq().execute.side_effect = APIError({"message": "fatal"})
        with pytest.raises(HTTPException, match="Failed to save verified phone number"):
            set_verified_mobile(USER_1, "+1234567890")

    # set_user_suspension: APIError -> DatabaseAccessError
    with patch("app.db.users.auth.supabase_client") as mock_sb:
        mock_sb.table().update().eq().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError, match="Failed to update user suspension status"):
            set_user_suspension(
                USER_1,
                True,
                suspended_until=datetime.now(timezone.utc),
                moderation_status="flagged",
                moderation_reason_code="spam",
            )

    # find_user_id_by_phone: APIError -> 503, not found -> None
    with patch("app.db.users.auth.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(HTTPException, match="Service temporarily unavailable"):
            find_user_id_by_phone("+1234567890")

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        assert find_user_id_by_phone("+1234567890") is None

    # get_user_email_by_id & get_user_id_by_email
    with patch("app.db.users.auth.supabase_client") as mock_sb:
        mock_sb.auth.admin.get_user_by_id.side_effect = Exception("fail")
        assert get_user_email_by_id(USER_1) is None

        mock_sb.rpc().execute.side_effect = APIError({"message": "fail"})
        assert get_user_id_by_email("test@example.com") is None

    # upsert_public_user: APIError -> 503, empty -> 500, existing -> (existing, False)
    with patch("app.db.users.auth.fetch_public_user", return_value={"id": USER_1}):
        u, created = upsert_public_user(USER_1, "nexus")
        assert created is False

    with patch("app.db.users.auth.fetch_public_user", return_value=None), \
         patch("app.db.users.auth.invalidate_user_status_cache"), \
         patch("app.db.users.auth.supabase_client") as mock_sb:
        mock_sb.table().upsert().select().execute.side_effect = APIError({"message": "insert fail"})
        with pytest.raises(HTTPException, match="Failed to initialize user account"):
            upsert_public_user(USER_1, "nexus")

        mock_sb.table().upsert().select().execute.side_effect = None
        mock_sb.table().upsert().select().execute.return_value = MagicMock(data=[])
        with pytest.raises(HTTPException, match="User account initialization returned no row"):
            upsert_public_user(USER_1, "nexus")

        mock_sb.table().upsert().select().execute.return_value = MagicMock(data=[{"id": USER_1, "xmax": "0"}])
        u, created = upsert_public_user(USER_1, "nexus")
        assert created is True

    # Consent helpers: parsing & validation
    assert _parse_terms_timestamp("2026-08-01T00:00:00Z") is not None
    with pytest.raises(HTTPException, match="Unexpected terms acceptance timestamp payload"):
        _parse_terms_timestamp(None)
    assert _parse_version_tuple("1.2.3") == (1, 2, 3)
    _validate_terms_versions(settings.current_terms_version)

    with pytest.raises(HTTPException, match="must match the current server terms version"):
        _validate_terms_versions("0.0.1")

    with pytest.raises(HTTPException, match="must be a valid numeric version string"):
        _validate_terms_versions("invalid_ver")

    # _verify_general_terms_accepted without accepted version
    with patch("app.db.users.consent._fetch_existing_consent_pair", return_value={"accepted_terms_version": None}):
        with pytest.raises(HTTPException, match="General terms must be accepted"):
            _verify_general_terms_accepted(USER_1)

    # Consent update / clear / fetch APIErrors
    with patch("app.db.users.consent.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(HTTPException, match="Failed to verify current consent state"):
            _fetch_existing_consent_pair(USER_1, "accepted_terms_version", "terms_accepted_at")

        # _update_consent_pair APIError & no rows updated (500)
        with patch("app.db.users.consent._fetch_existing_consent_pair", return_value={"accepted_terms_version": None}):
            mock_sb.table().update().eq().execute.side_effect = APIError({"message": "fail"})
            with pytest.raises(HTTPException, match="Failed to record consent"):
                _update_consent_pair(USER_1, "accepted_terms_version", "terms_accepted_at", "1.0")

            mock_sb.table().update().eq().execute.side_effect = None
            mock_sb.table().update().eq().execute.return_value = MagicMock(data=[])
            with pytest.raises(HTTPException, match="Failed to record consent"):
                _update_consent_pair(USER_1, "accepted_terms_version", "terms_accepted_at", "1.0")

        # _clear_consent_pair APIError
        mock_sb.table().update().eq().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(HTTPException, match="Failed to record consent"):
            _clear_consent_pair(USER_1, "special_category_consent_version", "special_category_consent_at")

        # _log_consent_event APIError is logged best-effort without raising
        mock_sb.table().insert().execute.side_effect = APIError({"message": "fail"})
        _log_consent_event(USER_1, "terms", True, "1.0")

    # High-level consent functions
    ver = settings.current_terms_version
    with patch("app.db.users.consent._update_consent_pair", return_value=(ver, datetime.now(timezone.utc))), \
         patch("app.db.users.consent._clear_consent_pair"), \
         patch("app.db.users.consent._log_consent_event"):
        update_user_terms(USER_1, ver)
        update_community_guidelines_consent(USER_1, ver)
        with patch("app.db.users.consent._verify_general_terms_accepted"):
            update_special_category_consent(USER_1, ver, True)
            update_special_category_consent(USER_1, ver, False)
            update_safety_data_consent(USER_1, ver, True)
            update_safety_data_consent(USER_1, ver, False)

    # generate_export_code: Redis failure is caught, APIError -> 503
    with patch("app.db.users.import_export.supabase_client") as mock_sb, \
         patch("app.db.users.import_export.redis_client") as mock_redis:
        mock_redis.delete = AsyncMock(side_effect=Exception("redis down"))
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data={"import_sync_code": "ABCDEF"})
        mock_sb.table().update().eq().execute.side_effect = APIError({"message": "update code fail"})
        with pytest.raises(HTTPException, match="Failed to generate export code"):
            await generate_export_code(USER_1)

        mock_sb.table().update().eq().execute.side_effect = None
        mock_sb.table().update().eq().execute.return_value = MagicMock()
        code, exp = await generate_export_code(USER_1)
        assert len(code) == 6
        assert exp is not None

    # _validate_import validation checks
    with pytest.raises(HTTPException, match="Export code has no expiry"):
        _validate_import({"id": USER_2}, {"id": USER_1}, "nexus", {"app_variant": "flavor"})

    with pytest.raises(HTTPException, match="Export code has expired"):
        _validate_import({"id": USER_2, "import_sync_expires_at": "2020-01-01T00:00:00Z"}, {"id": USER_1}, "nexus", {"app_variant": "flavor"})

    future_iso = "2099-01-01T00:00:00Z"
    with pytest.raises(HTTPException, match="already imported data"):
        _validate_import({"id": USER_2, "import_sync_expires_at": future_iso}, {"id": USER_1, "has_imported_data": True}, "nexus", {"app_variant": "flavor"})

    with pytest.raises(HTTPException, match="only allowed into the main Nexus account"):
        _validate_import({"id": USER_2, "import_sync_expires_at": future_iso}, {"id": USER_1}, "flavor_app", {"app_variant": "flavor"})

    with pytest.raises(HTTPException, match="must originate from a flavor variant"):
        _validate_import({"id": USER_2, "import_sync_expires_at": future_iso}, {"id": USER_1}, "nexus", {"app_variant": "nexus"})

    with pytest.raises(HTTPException, match="pending deletion"):
        _validate_import({"id": USER_2, "import_sync_expires_at": future_iso}, {"id": USER_1}, "nexus", {"app_variant": "flavor", "deletion_requested_at": "2026-08-01T00:00:00Z"})

    # _fetch_import_profiles: not found (400) & APIError (503)
    with patch("app.db.users.import_export.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        with pytest.raises(HTTPException, match="Invalid or already-used export code"):
            _fetch_import_profiles("BADCOD", USER_1)

        mock_sb.table().select().eq().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(HTTPException, match="Import service temporarily unavailable"):
            _fetch_import_profiles("CODE12", USER_1)

    # execute_import full flow
    source_p = {"id": USER_2, "import_sync_expires_at": future_iso, "hometown": "NYC"}
    target_p = {"id": USER_1, "has_imported_data": False}
    with patch("app.db.users.import_export._fetch_import_profiles", return_value=(source_p, target_p)), \
         patch("app.db.users.import_export.fetch_public_user", return_value={"id": USER_2, "app_variant": "flavor"}), \
         patch("app.db.users.import_export.supabase_client") as mock_sb:
        mock_sb.table().update().eq().eq().execute.return_value = MagicMock(data=[{"id": USER_2}])
        mock_sb.table().update().eq().execute.return_value = MagicMock()
        mock_sb.table().insert().execute.return_value = MagicMock()
        fields = execute_import(USER_1, "CODE12", target_variant="nexus")
        assert "hometown" in fields
