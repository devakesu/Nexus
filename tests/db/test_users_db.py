"""Test Suite for Test Users Db.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
import json
from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.config import settings
from app.core.security.crypto import DecryptFailedError, encrypt_to_hex
from app.db.client import DatabaseAccessError
from app.db.safety.alerts import (
    fetch_contact_facing_profile_summary,
    fetch_recent_safety_alert,
    fetch_safety_alert,
    record_safety_alert,
)
from app.db.safety.contacts import (
    fetch_safety_contacts,
    sync_safety_contacts,
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
SESS_1 = "00000000-0000-0000-0000-000000000040"
SESSION_1 = "00000000-0000-0000-0000-000000000020"
ALERT_1 = "00000000-0000-0000-0000-000000000010"
CONV_1 = "00000000-0000-0000-0000-000000000020"
CONVO_1 = "00000000-0000-0000-0000-000000000020"
MATCH_1 = "00000000-0000-0000-0000-000000000010"
MSG_1 = "00000000-0000-0000-0000-000000000020"
PHONE_VALID = "+14155552671"
REPORT_1 = "00000000-0000-0000-0000-000000000050"
EVENT_1 = "00000000-0000-0000-0000-000000000033"
CONTACT_1 = "00000000-0000-0000-0000-000000000030"


def _make_chaining_mock(
    data: Any = None, error: Exception | None = None,
) -> MagicMock:
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
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    def _single() -> MagicMock:
        if error:
            raise error
        if isinstance(data, list) and data:
            return MagicMock(data=copy.deepcopy(data[0]))
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    mock.single.return_value = single_mock
    return mock


def make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/test",
        "headers": [],
        "client": ("127.0.0.1", 12345),
        "app": MagicMock(),
    }
    return Request(scope)


def _make_mock_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/test",
        "headers": [(b"host", b"localhost"), (b"user-agent", b"pytest")],
        "client": ("127.0.0.1", 12345),
        "app": {},
    }
    return Request(scope)


def make_api_error(code: str = "P0001", message: str = "DB error") -> APIError:
    return APIError(
        {"code": code, "message": message, "details": "details", "hint": "hint"},
    )


pytestmark = pytest.mark.anyio


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
    assert (
        _reason_code_for_flag({"moderation_status": "restricted"}, False)
        == "restricted"
    )
    assert _reason_code_for_flag({"is_suspended": True}, False) == "suspended"
    assert _reason_code_for_flag({}, True) == "unresolved_report"
    assert _reason_code_for_flag({}, False) is None

    # 2. compute_deletion_flag_reason
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"moderation_status": "restricted", "is_suspended": False}],
    )
    mock_table.select.return_value.eq.return_value.in_.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[],
    )
    with patch(
        "app.db.users.account_deletion.supabase_client.table", return_value=mock_table,
    ):
        code = compute_deletion_flag_reason(USER_1)
        assert code == "restricted"

    # 3. is_phone_blocklisted
    assert is_phone_blocklisted("") is False
    mock_table.select.return_value.eq.return_value.gt.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": "b1", "cooldown_expires_at": "2026-12-31T00:00:00Z"}],
    )
    with patch(
        "app.db.users.account_deletion.supabase_client.table", return_value=mock_table,
    ):
        assert is_phone_blocklisted("abcdef1234567890") is True

    # 4. fetch_deletion_status
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[
            {
                "deletion_requested_at": "2026-08-01T00:00:00Z",
                "scheduled_purge_at": "2026-08-31T00:00:00Z",
            },
        ],
    )
    with patch(
        "app.db.users.account_deletion.supabase_client.table", return_value=mock_table,
    ):
        status = fetch_deletion_status(USER_1)
        assert status is not None
        assert status["deletion_requested_at"] == "2026-08-01T00:00:00Z"

    # 5. request_deletion & cancel_deletion
    mock_table.update.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(
        data=[
            {
                "deletion_requested_at": "2026-08-01T00:00:00Z",
                "scheduled_purge_at": "2026-08-31T00:00:00Z",
            },
        ],
    )
    with (
        patch(
            "app.db.users.account_deletion.supabase_client.table",
            return_value=mock_table,
        ),
        patch("app.db.users.account_deletion.invalidate_user_status_cache"),
        patch("app.db.users.account_deletion._close_all_conversations"),
        patch("app.db.users.account_deletion.supabase_client.auth.admin.sign_out"),
    ):
        res = request_deletion(
            USER_1, flagged_reason_code="banned", access_token="mock_token",
        )
        assert res is not None

    mock_table.update.return_value.eq.return_value.not_.is_.return_value.is_.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}],
    )
    with (
        patch(
            "app.db.users.account_deletion.supabase_client.table",
            return_value=mock_table,
        ),
        patch("app.db.users.account_deletion.invalidate_user_status_cache"),
        patch("app.db.users.account_deletion.reopen_conversations_for_reactivation"),
    ):
        cancel_deletion(USER_1)

    # 6. expire_blocklist_entries & purge_due_accounts
    mock_table.delete.return_value.lte.return_value.execute.return_value = MagicMock(
        data=[],
    )
    with patch(
        "app.db.users.account_deletion.supabase_client.table", return_value=mock_table,
    ):
        expire_blocklist_entries()

    with (
        patch(
            "app.db.users.account_deletion._fetch_accounts_due_for_purge",
            return_value=[{"id": USER_1, "mobile_blind_index": "m1"}],
        ),
        patch(
            "app.db.users.account_deletion._purge_single_due_account",
        ) as mock_purge_single,
        patch("app.db.users.account_deletion.time.sleep"),
    ):
        purge_due_accounts()
        mock_purge_single.assert_called_once()

    # 7. hard_purge_long_tail_accounts
    with (
        patch(
            "app.db.users.account_deletion._fetch_accounts_due_for_long_tail_purge",
            return_value=[USER_1],
        ),
        patch(
            "app.db.users.account_deletion._archive_account_history",
            return_value=[{"id": USER_1}],
        ),
        patch("app.db.users.account_deletion._chunked_pre_purge_child_records"),
        patch("app.db.users.account_deletion.supabase_client.auth.admin.delete_user"),
        patch("app.db.users.account_deletion.time.sleep"),
    ):
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

    mock_t = _make_chaining_mock(
        [{"id": USER_1, "name": "Alice", "email": "alice@example.com"}],
    )

    with (
        patch("app.db.users.export.supabase_client.table", return_value=mock_t),
        patch(
            "app.db.users.export.get_user_email_by_id", return_value="alice@example.com",
        ),
        patch("app.db.users.export.fetch_safety_contacts", return_value=[]),
        patch("app.db.users.export.fetch_playlists_for_owner", return_value=[]),
        patch("app.db.users.export._sign_urls", return_value={}),
    ):
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


async def test_db_users_submodules():
    from app.db.users.auth import (
        fetch_public_user,
        find_user_id_by_phone,
        is_allowed_email,
        is_disposable_email,
        set_user_suspension,
        set_verified_mobile,
        upsert_public_user,
    )
    from app.db.users.consent import (
        update_community_guidelines_consent,
        update_safety_data_consent,
        update_special_category_consent,
        update_user_terms,
    )
    from app.db.users.import_export import (
        execute_import,
        generate_export_code,
    )
    from app.db.users.profile import (
        fetch_profile,
        upsert_profile_variant,
    )

    mock_table = MagicMock()

    # 1. auth.py
    assert is_disposable_email("user@0-mail.com") is True
    assert is_disposable_email("user@gmail.com") is False
    assert is_allowed_email("user@gmail.com") is True

    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1, "is_active": True}],
    )
    with patch("app.db.users.auth.supabase_client.table", return_value=mock_table):
        pub_u = fetch_public_user(USER_1)
        assert pub_u is not None
        assert pub_u["id"] == USER_1

    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}],
    )
    with patch("app.db.users.auth.supabase_client.table", return_value=mock_table):
        uid = find_user_id_by_phone("+1234567890")
        assert uid == USER_1

    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}],
    )
    with (
        patch("app.db.users.auth.supabase_client.table", return_value=mock_table),
        patch("app.db.users.auth.invalidate_user_status_cache"),
    ):
        set_user_suspension(USER_1, True)
        set_verified_mobile(USER_1, "+1234567890")

    mock_table.upsert.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}],
    )
    with patch("app.db.users.auth.supabase_client.table", return_value=mock_table):
        upsert_public_user(USER_1, "nexus")

    # 2. consent.py
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={
            "accepted_terms_version": "1",
            "terms_accepted_at": "2026-01-01T00:00:00Z",
        },
    )
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}],
    )
    mock_table.insert.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.users.consent.supabase_client.table", return_value=mock_table):
        update_user_terms(USER_1, "1")
        update_special_category_consent(USER_1, "1", True)
        update_safety_data_consent(USER_1, "1", True)
        update_community_guidelines_consent(USER_1, "1", True)

    # 3. import_export.py
    mock_redis = AsyncMock()
    mock_redis.delete.return_value = True
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"import_sync_code": "ABC123"},
    )
    with (
        patch("app.db.users.import_export.redis_client", mock_redis),
        patch(
            "app.db.users.import_export.supabase_client.table", return_value=mock_table,
        ),
    ):
        code, exp = await generate_export_code(USER_1)
        assert len(code) == 6
        assert exp is not None

    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[
            {
                "id": USER_2,
                "import_sync_expires_at": "2026-09-01T00:00:00Z",
                "has_imported_data": False,
                "display_gender": encrypt_to_hex("Non-binary", category="profile"),
            },
        ],
    )
    with (
        patch(
            "app.db.users.import_export.supabase_client.table", return_value=mock_table,
        ),
        patch(
            "app.db.users.import_export.fetch_public_user",
            return_value={"id": USER_2, "app_variant": "campus"},
        ),
    ):
        copied = execute_import(USER_1, "ABC123", "nexus")
        assert copied is not None

    # 4. profile.py
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": USER_1, "name": encrypt_to_hex("Alice", category="profile")},
    )
    mock_table.upsert.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}],
    )
    with patch("app.db.users.profile.supabase_client.table", return_value=mock_table):
        prof = fetch_profile(USER_1)
        assert prof is not None
        prof_res, _ = upsert_profile_variant(USER_1, "Alice", "CS", 2026, 22)
        assert prof_res is not None


def test_db_account_deletion_deep():
    from app.db.users.account_deletion import (
        _anonymize_profile_and_user,
        _archive_account_history,
        _ban_and_scrub_auth_user,
        _chunked_delete_by_field,
        _chunked_delete_by_or_filter,
        _chunked_pre_purge_child_records,
        _delete_no_retention_rows,
        _delete_user_media_objects,
        _permanently_unmatch_all,
        _purge_discovery_for_user,
        _purge_single_due_account,
        _purge_vector_profiles_for_user,
        cancel_deletion,
        compute_deletion_flag_reason,
        expire_blocklist_entries,
        hard_purge_long_tail_accounts,
        is_phone_blocklisted,
        purge_due_accounts,
        request_deletion,
    )

    now = datetime.now(timezone.utc)

    # 1. compute_deletion_flag_reason & is_phone_blocklisted
    mock_t = _make_chaining_mock(
        [{"moderation_status": "restricted", "is_suspended": True}],
    )
    with patch(
        "app.db.users.account_deletion.supabase_client.table", return_value=mock_t,
    ):
        reason = compute_deletion_flag_reason(USER_1)
        assert reason in ("restricted", "banned", "suspended")
        assert is_phone_blocklisted("blind_idx_123456789012") is True
        assert is_phone_blocklisted("") is False

    # 2. request_deletion & cancel_deletion
    with (
        patch(
            "app.db.users.account_deletion.supabase_client.table", return_value=mock_t,
        ),
        patch("app.db.users.account_deletion.invalidate_user_status_cache"),
        patch("app.db.users.account_deletion._close_all_conversations"),
        patch("app.db.users.account_deletion.supabase_client.auth.admin.sign_out"),
        patch("app.db.users.account_deletion.reopen_conversations_for_reactivation"),
    ):
        res_del = request_deletion(
            USER_1, flagged_reason_code="banned", access_token="tok",
        )
        assert res_del is not None
        cancel_deletion(USER_1)

    # 3. purges and media deletions
    with (
        patch(
            "app.db.users.account_deletion.supabase_client.table", return_value=mock_t,
        ),
        patch(
            "app.db.users.account_deletion.supabase_client.storage.from_",
        ) as mock_storage,
        patch(
            "app.db.users.account_deletion.supabase_client.auth.admin.update_user_by_id",
        ),
        patch("app.db.users.account_deletion.supabase_client.auth.admin.sign_out"),
        patch("app.db.users.account_deletion.supabase_client.auth.admin.delete_user"),
        patch("app.db.users.account_deletion.delete_user_chat_media"),
    ):
        mock_storage.return_value.list.return_value = [{"name": "pic1.jpg"}]
        mock_storage.return_value.remove.return_value = True

        _permanently_unmatch_all(USER_1)
        _anonymize_profile_and_user(USER_1, now)
        _purge_vector_profiles_for_user(USER_1)
        _purge_discovery_for_user(USER_1)
        _delete_no_retention_rows(USER_1)
        _delete_user_media_objects(USER_1)
        _ban_and_scrub_auth_user(USER_1)
        _purge_single_due_account(
            {
                "id": USER_1,
                "mobile_blind_index": "b_idx",
                "deletion_flagged_reason_code": "banned",
            },
            now,
        )
        _chunked_delete_by_field("chat_messages", "sender_id", USER_1, chunk_size=10)
        _chunked_delete_by_or_filter("matches", "liker_id.eq.1", USER_1, chunk_size=10)
        _chunked_pre_purge_child_records(USER_1)
        _archive_account_history(USER_1)

    with (
        patch(
            "app.db.users.account_deletion._fetch_accounts_due_for_purge",
            return_value=[{"id": USER_1}],
        ),
        patch("app.db.users.account_deletion._purge_single_due_account"),
        patch("app.db.users.account_deletion.time.sleep"),
    ):
        purge_due_accounts()

    with patch(
        "app.db.users.account_deletion.supabase_client.table", return_value=mock_t,
    ):
        expire_blocklist_entries()

    with (
        patch(
            "app.db.users.account_deletion._fetch_accounts_due_for_long_tail_purge",
            return_value=[USER_1],
        ),
        patch(
            "app.db.users.account_deletion._archive_account_history", return_value=[],
        ),
        patch("app.db.users.account_deletion._chunked_pre_purge_child_records"),
        patch("app.db.users.account_deletion.supabase_client.auth.admin.delete_user"),
        patch("app.db.users.account_deletion.time.sleep"),
    ):
        hard_purge_long_tail_accounts()


def test_db_users_export_deep_p7():
    from app.db.users.export import (
        build_user_data_export,
    )

    mock_t = _make_chaining_mock(
        [
            {
                "id": USER_1,
                "name": "Alice",
                "profile_pic": "pic1.jpg",
                "normal_pics": ["pic2.jpg"],
                "current_location": json.dumps({"lat": 37.7, "lng": -122.4}),
                "storage_path": "rec1.mp4",
            },
        ],
    )

    with (
        patch("app.db.users.export.supabase_client.table", return_value=mock_t),
        patch(
            "app.db.users.export._sign_urls",
            return_value={
                "pic1.jpg": "https://signed/pic1.jpg",
                "pic2.jpg": "https://signed/pic2.jpg",
                "rec1.mp4": "https://signed/rec1.mp4",
            },
        ),
        patch(
            "app.db.users.export.get_user_email_by_id", return_value="alice@example.com",
        ),
        patch(
            "app.db.users.export.fetch_safety_contacts",
            return_value=[{"name": "Bob", "phone": "+15555555555"}],
        ),
        patch("app.db.users.export.fetch_playlists_for_owner", return_value=[]),
    ):
        export_data = build_user_data_export(USER_1)
        assert "profile" in export_data
        assert "account" in export_data
        assert "safety" in export_data
        assert "feedback_tickets" in export_data


def test_db_users_auth_exhaustive():
    from app.db.users.auth import (
        fetch_public_user,
        get_supabase_user_from_jwt,
        is_allowed_email,
        is_disposable_email,
        set_verified_mobile,
    )

    mock_t = _make_chaining_mock(
        [{"id": USER_1, "email": "alice@berkeley.edu", "is_active": True}],
    )

    with (
        patch("app.db.users.auth.supabase_client.table", return_value=mock_t),
        patch(
            "app.db.users.auth.supabase_client.auth.get_user",
            return_value={"user": {"id": USER_1, "email": "alice@berkeley.edu"}},
        ),
        patch("app.db.users.is_phone_blocklisted", return_value=False),
        patch("app.db.users.auth.invalidate_user_status_cache"),
    ):
        assert is_disposable_email("user@tempmail.com") in (True, False)
        assert is_allowed_email("student@berkeley.edu") is True
        u = fetch_public_user(USER_1)
        assert u is not None
        jwt_user = get_supabase_user_from_jwt("dummy_token")
        assert jwt_user["id"] == USER_1
        set_verified_mobile(USER_1, "+15555555555")


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

    with (
        patch("app.db.users.consent.supabase_client.table", return_value=mock_ok),
        patch("app.db.users.consent.invalidate_user_status_cache"),
    ):
        update_user_terms(USER_1, settings.current_terms_version, granted=True)
        update_user_terms(USER_1, settings.current_terms_version, granted=False)
        update_community_guidelines_consent(
            USER_1, settings.current_terms_version, granted=True,
        )
        update_special_category_consent(
            USER_1, settings.current_terms_version, granted=True,
        )
        update_special_category_consent(
            USER_1, settings.current_terms_version, granted=False,
        )
        update_safety_data_consent(USER_1, settings.current_terms_version, granted=True)
        update_safety_data_consent(
            USER_1, settings.current_terms_version, granted=False,
        )

    with patch("app.db.users.consent.supabase_client.table", return_value=mock_err):
        with pytest.raises(HTTPException):
            update_user_terms(USER_1, settings.current_terms_version, granted=True)


def test_db_account_deletion_and_exclusions_deep():
    from app.db.discovery.exclusions import (
        fetch_active_block_ids,
        fetch_active_discovery_excluded_ids,
    )
    from app.db.discovery.matches import (
        fetch_matches_for_user,
        record_match,
    )
    from app.db.users.account_deletion import (
        cancel_deletion,
        compute_deletion_flag_reason,
        fetch_deletion_status,
        is_phone_blocklisted,
        request_deletion,
    )

    mock_row = {
        "id": "1",
        "user_id": USER_1,
        "moderation_status": "active",
        "is_suspended": False,
        "phone_blind_index": "blind1",
        "cooldown_expires_at": (datetime.now(timezone.utc)).isoformat(),
        "deletion_requested_at": (datetime.now(timezone.utc)).isoformat(),
        "scheduled_purge_at": (datetime.now(timezone.utc)).isoformat(),
        "actor_id": USER_1,
        "target_id": USER_2,
        "action": "block",
        "tab": "Dating",
        "liker_id": USER_1,
        "liked_back_id": USER_2,
        "created_at": (datetime.now(timezone.utc)).isoformat(),
    }
    mock_ok: MagicMock = MagicMock()
    mock_ok.select.return_value = mock_ok
    mock_ok.insert.return_value = mock_ok
    mock_ok.update.return_value = mock_ok
    mock_ok.delete.return_value = mock_ok
    mock_ok.upsert.return_value = mock_ok
    mock_ok.eq.return_value = mock_ok
    mock_ok.gt.return_value = mock_ok
    mock_ok.lt.return_value = mock_ok
    mock_ok.in_.return_value = mock_ok
    mock_ok.or_.return_value = mock_ok
    mock_ok.is_.return_value = mock_ok
    mock_ok.not_.is_.return_value = mock_ok
    mock_ok.order.return_value = mock_ok
    mock_ok.limit.return_value = mock_ok
    mock_ok.execute.return_value = MagicMock(data=[mock_row])
    single_mock: MagicMock = MagicMock()
    single_mock.execute.return_value = MagicMock(data=mock_row)
    mock_ok.maybe_single.return_value = single_mock
    mock_ok.single.return_value = single_mock

    # 1. DB Account deletion
    with (
        patch(
            "app.db.users.account_deletion.supabase_client.table", return_value=mock_ok,
        ),
        patch("app.db.users.account_deletion.invalidate_user_status_cache"),
        patch("app.db.users.account_deletion._close_all_conversations"),
        patch("app.db.users.account_deletion.reopen_conversations_for_reactivation"),
    ):
        compute_deletion_flag_reason(USER_1)
        is_phone_blocklisted("blind_idx_12345678")
        fetch_deletion_status(USER_1)
        request_deletion(USER_1, None)
        cancel_deletion(USER_1)

    # 2. DB Exclusions & Matches
    with (
        patch(
            "app.db.discovery.exclusions.supabase_client.table", return_value=mock_ok,
        ),
        patch("app.db.discovery.matches.supabase_client.table", return_value=mock_ok),
    ):
        fetch_active_block_ids(USER_1)
        fetch_active_discovery_excluded_ids(USER_1, "Dating")
        record_match(USER_1, USER_2, "Dating")
        fetch_matches_for_user(USER_1, "Dating")

    # 3. DB Safety alerts & Contacts
    with (
        patch("app.db.safety.alerts.supabase_client.table", return_value=mock_ok),
        patch("app.db.safety.contacts.supabase_client.table", return_value=mock_ok),
        patch("app.db.safety.contacts.supabase_client.rpc") as mock_rpc,
    ):
        mock_rpc.return_value.execute.return_value = MagicMock(
            data={"blocked_indices": [], "newly_notified_indices": []},
        )
        record_safety_alert(USER_1, "sos_silent", {"lat": 37.7, "lng": -122.4})
        fetch_safety_alert(ALERT_1)
        fetch_recent_safety_alert(USER_1, "sos_silent")
        fetch_contact_facing_profile_summary(USER_1)
        fetch_safety_contacts(USER_1)
        sync_safety_contacts(USER_1, [{"name": "Bob", "phone": "+15555555555"}])


def test_db_account_deletion_purge_and_hard_purge():
    from app.db.users.account_deletion import (
        _anonymize_profile_and_user,
        _ban_and_scrub_auth_user,
        _delete_no_retention_rows,
        _delete_user_media_objects,
        _fetch_accounts_due_for_purge,
        _permanently_unmatch_all,
        _purge_single_due_account,
        hard_purge_long_tail_accounts,
        purge_due_accounts,
    )

    mock_row: dict[str, Any] = {
        "id": USER_1,
        "mobile_blind_index": "blind123",
        "deletion_flagged_reason_code": "suspended",
        "deletion_requested_at": datetime.now(timezone.utc).isoformat(),
        "scheduled_purge_at": datetime.now(timezone.utc).isoformat(),
        "name": "\\x6161",
    }
    mock_t = _make_chaining_mock([mock_row])

    with (
        patch(
            "app.db.users.account_deletion.supabase_client.table", return_value=mock_t,
        ),
        patch(
            "app.db.users.account_deletion.supabase_client.storage.from_",
        ) as mock_storage,
        patch("app.db.users.account_deletion.supabase_client.auth.admin") as mock_admin,
        patch("app.db.users.account_deletion.delete_user_chat_media"),
        patch(
            "app.db.users.account_deletion.compute_deletion_flag_reason",
            return_value="suspended",
        ),
        patch("time.sleep"),
    ):
        mock_storage.return_value.list.return_value = [{"name": "pic1.jpg"}]
        mock_storage.return_value.remove.return_value = None
        mock_admin.update_user_by_id.return_value = None
        mock_admin.sign_out.return_value = None

        _fetch_accounts_due_for_purge()
        _permanently_unmatch_all(USER_1)
        _anonymize_profile_and_user(USER_1, datetime.now(timezone.utc))
        _delete_no_retention_rows(USER_1)
        _delete_user_media_objects(USER_1)
        _ban_and_scrub_auth_user(USER_1)
        _purge_single_due_account(mock_row, datetime.now(timezone.utc))
        purge_due_accounts()
        hard_purge_long_tail_accounts()


def test_db_users_export_and_auth():
    from app.db.users.auth import (
        fetch_public_user,
        is_disposable_email,
        set_verified_mobile,
    )
    from app.db.users.export import (
        build_user_data_export,
    )

    mock_row: dict[str, Any] = {
        "id": USER_1,
        "is_suspended": False,
        "phone": "\\x6161",
        "name": "\\x6262",
    }
    mock_t = _make_chaining_mock([mock_row])

    with (
        patch("app.db.users.export.supabase_client.table", return_value=mock_t),
        patch("app.db.users.auth.supabase_client.table", return_value=mock_t),
        patch("app.db.users.auth.supabase_client.rpc") as mock_rpc,
        patch("app.db.users.is_phone_blocklisted", return_value=False),
        patch("app.db.users.export.supabase_client.storage.from_") as mock_storage,
    ):
        mock_rpc.return_value.execute.return_value = MagicMock(data="ok")
        mock_storage.return_value.upload.return_value = None
        mock_storage.return_value.create_signed_url.return_value = {
            "signedURL": "https://signed.url",
        }

        fetch_public_user(USER_1)
        is_disposable_email("user@mailinator.com")
        set_verified_mobile(USER_1, "+15555555555")

        data = build_user_data_export(USER_1)
        assert isinstance(data, dict)


async def test_db_users_import_export_deep():

    from app.db.users.import_export import (
        execute_import,
        generate_export_code,
    )

    future_iso = (datetime.now(timezone.utc) + timedelta(minutes=15)).isoformat()
    mock_source = {
        "id": USER_2,
        "import_sync_code": "CODE12",
        "import_sync_expires_at": future_iso,
        "display_gender": "\\x6161",
        "hometown": "\\x6262",
    }
    mock_target = {
        "id": USER_1,
        "has_imported_data": False,
    }
    mock_source_user = {
        "id": USER_2,
        "app_variant": "nexus_flavor_a",
        "deletion_requested_at": None,
    }

    mock_t = _make_chaining_mock([mock_source])

    with (
        patch("app.db.users.import_export.supabase_client.table", return_value=mock_t),
        patch("app.db.users.import_export.redis_client") as mock_r,
        patch(
            "app.db.users.import_export._fetch_import_profiles",
            return_value=(mock_source, mock_target),
        ),
        patch(
            "app.db.users.import_export.fetch_public_user",
            return_value=mock_source_user,
        ),
        patch("app.db.users.import_export.decrypt_pii", return_value="Male"),
        patch("app.db.users.import_export.encrypt_to_hex", return_value="\\x6161"),
    ):
        mock_r.delete = AsyncMock(return_value=True)

        _code, _exp = await generate_export_code(USER_1)
        assert len(_code) == 6

        copied = execute_import(USER_1, "CODE12", target_variant="nexus")
        assert len(copied) > 0


def test_db_users_profile_deep():
    from app.db.users.profile import (
        fetch_profile,
        upsert_profile_variant,
    )

    mock_prof = {
        "id": USER_1,
        "name": "\\x6161",
        "campus_branch": "\\x6262",
        "campus_year": 2024,
        "campus_name": "\\x6363",
        "age": 21,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    mock_t = _make_chaining_mock([mock_prof])

    with patch("app.db.users.profile.supabase_client.table", return_value=mock_t):
        prof = fetch_profile(USER_1)
        assert prof is not None

        row, _created = upsert_profile_variant(
            USER_1, "Alice", "CS", 2024, 21, "Stanford", "tech",
        )
        assert row is not None


def test_db_account_deletion_error_branches():
    from app.db.users.account_deletion import (
        _anonymize_profile_and_user,
        _ban_and_scrub_auth_user,
        _delete_no_retention_rows,
        _delete_user_media_objects,
        _permanently_unmatch_all,
        _purge_discovery_for_user,
        _purge_single_due_account,
        _purge_vector_profiles_for_user,
        compute_deletion_flag_reason,
        is_phone_blocklisted,
        purge_due_accounts,
    )

    err_table = MagicMock()
    err_table.select.return_value = err_table
    err_table.update.return_value = err_table
    err_table.delete.return_value = err_table
    err_table.eq.return_value = err_table
    err_table.limit.return_value = err_table
    err_table.in_.return_value = err_table
    err_table.or_.return_value = err_table
    err_table.gt.return_value = err_table
    err_table.is_.return_value = err_table
    err_table.execute.side_effect = APIError({"message": "DB Error", "code": "500"})

    mock_client = MagicMock()
    mock_client.table.return_value = err_table
    mock_client.auth.admin.update_user_by_id.side_effect = Exception("Auth Error")
    mock_client.auth.admin.sign_out.side_effect = Exception("Signout Error")
    mock_client.storage.from_.return_value.list.side_effect = Exception(
        "Storage List Error",
    )

    with patch("app.db.users.account_deletion.supabase_client", mock_client):
        # compute_deletion_flag_reason error
        with pytest.raises(DatabaseAccessError):
            compute_deletion_flag_reason(USER_1)

        # is_phone_blocklisted error
        with pytest.raises(DatabaseAccessError):
            is_phone_blocklisted("blind_index_123")

        # _permanently_unmatch_all error
        with pytest.raises(DatabaseAccessError):
            _permanently_unmatch_all(USER_1)

        # _anonymize_profile_and_user error
        with pytest.raises(DatabaseAccessError):
            _anonymize_profile_and_user(USER_1, datetime.now(timezone.utc))

        # private helpers log exceptions and suppress gracefully
        _purge_vector_profiles_for_user(USER_1)
        _purge_discovery_for_user(USER_1)
        _delete_no_retention_rows(USER_1)
        _delete_user_media_objects(USER_1)
        _ban_and_scrub_auth_user(USER_1)
        _purge_single_due_account({"id": USER_1}, datetime.now(timezone.utc))
        purge_due_accounts()


def test_db_users_profile_deep_p22():
    from app.db.users.profile import fetch_profile, upsert_profile_variant

    # fetch_profile: APIError & not a dict row
    with patch("app.db.users.profile.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(
            HTTPException, match="Profile service temporarily unavailable",
        ):
            fetch_profile(USER_1)

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(
            data=["not-dict"],
        )
        assert fetch_profile(USER_1) is None

    # upsert_profile_variant: APIError, fallback fetch returns None, name/age change log insert APIErrors
    with (
        patch("app.db.users.profile.fetch_profile", return_value=None),
        patch("app.db.users.profile.supabase_client") as mock_sb,
    ):
        # upsert APIError
        mock_sb.table().upsert().execute.side_effect = APIError(
            {"message": "upsert fail"},
        )
        with pytest.raises(HTTPException, match="Failed to save profile"):
            upsert_profile_variant(USER_1, "Alice", "CS", 2024, 21, "MIT", "NB")

        # result.data empty and fallback fetch_profile returns None -> 500
        mock_sb.table().upsert().execute.side_effect = None
        mock_sb.table().upsert().execute.return_value = MagicMock(data=[])
        with patch("app.db.users.profile.fetch_profile", side_effect=[None, None]):
            with pytest.raises(HTTPException, match="Profile save returned no row"):
                upsert_profile_variant(USER_1, "Alice", "CS", 2024, 21, "MIT", "NB")

        # Initial logs insert APIErrors caught gracefully
        mock_sb.table().upsert().execute.return_value = MagicMock(
            data=[{"id": USER_1, "name": "Alice"}],
        )
        mock_sb.table().insert().execute.side_effect = APIError(
            {"message": "log insert fail"},
        )
        row, created = upsert_profile_variant(
            USER_1, "Alice", "CS", 2024, 21, "MIT", "NB",
        )
        assert row["id"] == USER_1
        assert created is True


def test_db_users_account_deletion_deep_p23():
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
        mock_sb.table().select().eq().in_().limit().execute.side_effect = APIError(
            {"message": "report fail"},
        )
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(
            data=[{"is_suspended": True}],
        )
        with pytest.raises(DatabaseAccessError, match="Failed to fetch reports"):
            compute_deletion_flag_reason(USER_1)

    # is_phone_blocklisted: empty blind index, APIError, and blocklist hit
    assert is_phone_blocklisted("") is False
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().select().eq().gt().limit().execute.side_effect = APIError(
            {"message": "blocklist error"},
        )
        with pytest.raises(
            DatabaseAccessError, match="Failed to check phone blocklist",
        ):
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
        mock_sb.table().select().eq().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(
            DatabaseAccessError, match="Failed to fetch deletion status",
        ):
            fetch_deletion_status(USER_1)

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        assert fetch_deletion_status(USER_1) is None

    # request_deletion: APIErrors on users update & profiles update
    with (
        patch("app.db.users.account_deletion.supabase_client") as mock_sb,
        patch("app.db.users.account_deletion.invalidate_user_status_cache"),
    ):
        # APIError on users update
        mock_sb.table().update().eq().execute.side_effect = APIError(
            {"message": "users update fail"},
        )
        with pytest.raises(
            DatabaseAccessError, match="Failed to request account deletion",
        ):
            request_deletion(USER_1, flagged_reason_code="spam")

        # APIError on profiles update
        mock_sb.table().update().eq().execute.side_effect = [
            MagicMock(),
            APIError({"message": "profiles update fail"}),
        ]
        with pytest.raises(
            DatabaseAccessError, match="Failed to request account deletion",
        ):
            request_deletion(USER_1, flagged_reason_code=None)

    # cancel_deletion: APIErrors on users / profiles updates, and best-effort device update APIError
    with (
        patch("app.db.users.account_deletion.supabase_client") as mock_sb,
        patch("app.db.users.account_deletion.invalidate_user_status_cache"),
        patch("app.db.users.account_deletion.reopen_conversations_for_reactivation"),
    ):
        # APIError on users update
        mock_sb.table().update().eq().execute.side_effect = APIError(
            {"message": "users cancel fail"},
        )
        with pytest.raises(
            DatabaseAccessError, match="Failed to cancel account deletion",
        ):
            cancel_deletion(USER_1)

        # APIError on profiles update
        mock_sb.table().update().eq().execute.side_effect = [
            MagicMock(),
            APIError({"message": "profiles cancel fail"}),
        ]
        with pytest.raises(
            DatabaseAccessError, match="Failed to cancel account deletion",
        ):
            cancel_deletion(USER_1)

        # APIError on devices update is swallowed (best-effort)
        mock_sb.table().update().eq().execute.side_effect = [
            MagicMock(),
            MagicMock(),
            APIError({"message": "devices fail"}),
        ]
        cancel_deletion(USER_1)

    # _purge_single_due_account: test exception handler inside it
    with (
        patch("app.db.users.account_deletion.supabase_client") as mock_sb,
        patch("app.db.users.account_deletion.invalidate_user_status_cache"),
    ):
        mock_sb.table().select().eq().limit().execute.side_effect = Exception(
            "single purge crash",
        )
        _purge_single_due_account({"id": USER_1}, datetime.now(timezone.utc))

    # purge_due_accounts & expire_blocklist_entries APIError
    with patch(
        "app.db.users.account_deletion._fetch_accounts_due_for_purge", return_value=[],
    ):
        purge_due_accounts()

    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().delete().lte().execute.side_effect = APIError(
            {"message": "expire fail"},
        )
        expire_blocklist_entries()

    # _fetch_archive_source generic Exception & _insert_archive_rows APIError / Exception
    source = ("user_reports", "target_id", "reason_code", "review_status")
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().select().or_().execute.side_effect = Exception("DB crash")
        assert _fetch_archive_source(source, USER_1) is None

        # _insert_archive_rows APIError & generic Exception
        mock_sb.table().insert().execute.side_effect = APIError(
            {"message": "insert fail"},
        )
        assert (
            _insert_archive_rows(
                "user_reports",
                [{"created_at": "2026-08-01T00:00:00Z", "reason_code": "spam"}],
                "reason_code",
                "review_status",
                USER_1,
            )
            is False
        )

        mock_sb.table().insert().execute.side_effect = Exception("insert crash")
        assert (
            _insert_archive_rows(
                "user_reports",
                [{"created_at": "2026-08-01T00:00:00Z", "reason_code": "spam"}],
                "reason_code",
                "review_status",
                USER_1,
            )
            is False
        )

    # _fetch_accounts_due_for_long_tail_purge APIError
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().select().not_.is_().lte().limit().execute.side_effect = (
            APIError({"message": "fail"})
        )
        with pytest.raises(
            DatabaseAccessError,
            match="Failed to fetch accounts due for long-tail purge",
        ):
            _fetch_accounts_due_for_long_tail_purge()

    # _chunked_delete_by_field and _chunked_delete_by_or_filter with exceptions
    with patch("app.db.users.account_deletion.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = Exception(
            "chunk fail",
        )
        _chunked_delete_by_field("chat_messages", "sender_id", USER_1, chunk_size=10)

        mock_sb.table().select().or_().limit().execute.side_effect = Exception(
            "chunk or fail",
        )
        _chunked_delete_by_or_filter("matches", "liker_id.eq.1", USER_1, chunk_size=10)

    # hard_purge_long_tail_accounts with archival failure and exception
    with (
        patch(
            "app.db.users.account_deletion._fetch_accounts_due_for_long_tail_purge",
            return_value=[USER_1, USER_2],
        ),
        patch(
            "app.db.users.account_deletion._archive_account_history",
            side_effect=[["user_reports"], []],
        ),
        patch("app.db.users.account_deletion._chunked_pre_purge_child_records"),
        patch("app.db.users.account_deletion.supabase_client") as mock_sb,
        patch("time.sleep"),
    ):
        mock_sb.auth.admin.delete_user.side_effect = Exception("Auth delete fail")
        hard_purge_long_tail_accounts()


def test_db_users_export_deep_p23():
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
        mock_sb.table().select().eq().execute.side_effect = APIError(
            {"message": "fail"},
        )
        assert _safe_select("matches", "id", USER_1, id_column="liker_id") == []

    # _sign_urls exception -> {}
    with patch("app.db.users.export.supabase_client") as mock_sb:
        mock_sb.storage.from_().create_signed_urls.side_effect = Exception(
            "Storage fail",
        )
        assert _sign_urls("media", ["pic1.jpg"]) == {}

    # _build_profile_section: APIError, DecryptFailedError, spotify affinity notes
    with patch("app.db.users.export.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError(
            {"message": "fail"},
        )
        assert _build_profile_section(USER_1) == {}

        # DecryptFailedError
        mock_sb.table().select().eq().maybe_single().execute.side_effect = None
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data={"id": USER_1, "name": "enc"},
        )
        with patch(
            "app.db.users.export.decrypt_profile_record",
            side_effect=DecryptFailedError("fail"),
        ):
            assert _build_profile_section(USER_1) == {}

        # Spotify affinities and photo URLs
        with (
            patch(
                "app.db.users.export.decrypt_profile_record",
                return_value={
                    "id": USER_1,
                    "name": "Alice",
                    "artist_affinity": {"queen": 1.0},
                    "profile_pic": "avatar.jpg",
                    "normal_pics": ["p1.jpg", "p2.jpg"],
                },
            ),
            patch(
                "app.db.users.export._sign_urls",
                return_value={
                    "avatar.jpg": "https://cdn/avatar.jpg",
                    "p1.jpg": "https://cdn/p1.jpg",
                },
            ),
        ):
            sec = _build_profile_section(USER_1)
            assert "derived_signals_note" in sec
            assert sec["profile_pic"] == "https://cdn/avatar.jpg"
            assert sec["normal_pics"] == ["https://cdn/p1.jpg"]

    # _build_account_section: APIError & deleted email
    with patch("app.db.users.export.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError(
            {"message": "fail"},
        )
        assert _build_account_section(USER_1) == {}

        mock_sb.table().select().eq().maybe_single().execute.side_effect = None
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data={"id": USER_1},
        )
        with patch(
            "app.db.users.export.get_user_email_by_id",
            return_value="deleted-123@deleted.nexus.internal",
        ):
            acc = _build_account_section(USER_1)
            assert acc["email"] is None

    # _build_matches_and_discovery: APIError & success
    with (
        patch("app.db.users.export.supabase_client") as mock_sb,
        patch("app.db.users.export._safe_select", return_value=[]),
    ):
        mock_sb.table().select().or_().execute.side_effect = APIError(
            {"message": "fail"},
        )
        res = _build_matches_and_discovery(USER_1)
        assert res["matches"] == []

        mock_sb.table().select().or_().execute.side_effect = None
        mock_sb.table().select().or_().execute.return_value = MagicMock(
            data=[{"id": "match-1"}],
        )
        res = _build_matches_and_discovery(USER_1)
        assert len(res["matches"]) == 1

    # _fetch_and_decrypt_chat_events with location coordinates and APIError
    with (
        patch("app.db.users.export.supabase_client") as mock_sb,
        patch(
            "app.db.users.export.decrypt_event_row",
            return_value={
                "id": "ev-1",
                "event_time": "2026-08-26T20:00:00Z",
                "location_lat": 12.34,
                "location_lng": 56.78,
                "location_label": "Place",
            },
        ),
    ):
        mock_sb.table().select().in_().execute.return_value = MagicMock(
            data=[{"id": "ev-1"}],
        )
        events = _fetch_and_decrypt_chat_events(["conv-1"], USER_1)
        assert len(events) == 1
        assert "location_sensitivity_note" in events[0]

        mock_sb.table().select().in_().execute.side_effect = APIError(
            {"message": "fail"},
        )
        assert _fetch_and_decrypt_chat_events(["conv-1"], USER_1) == []

    # _build_chat_section: DecryptFailedError on message content & APIError on conversations
    with patch("app.db.users.export.supabase_client") as mock_sb:
        mock_sb.table().select().or_().execute.side_effect = APIError(
            {"message": "convs fail"},
        )
        chat = _build_chat_section(USER_1)
        assert chat["conversations"] == []
        assert chat["messages"] == []

        # Successful conversations fetch with message exclusion reason
        mock_sb.table().select().or_().execute.side_effect = None
        mock_sb.table().select().or_().execute.return_value = MagicMock(
            data=[{"id": "conv-1"}],
        )
        mock_sb.table().select().in_().execute.return_value = MagicMock(
            data=[{"id": "msg-1"}],
        )
        mock_sb.table().select().eq().execute.return_value = MagicMock(
            data=[{"is_online": True}],
        )
        with patch(
            "app.db.users.export._fetch_and_decrypt_chat_events", return_value=[],
        ):
            chat_res = _build_chat_section(USER_1)
            assert len(chat_res["conversations"]) == 1
            assert len(chat_res["messages"]) == 1
            assert "content_excluded_reason" in chat_res["messages"][0]

    # _build_reports_section, _build_feedback_section, _build_safety_alerts, _build_safety_evidence, _build_safety_section, _build_spotify_section, _build_consent_history
    with (
        patch("app.db.users.export.supabase_client") as mock_sb,
        patch("app.db.users.export._safe_select", return_value=[]),
    ):
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
        with patch(
            "app.db.users.export.fetch_safety_contacts",
            side_effect=Exception("contacts fail"),
        ):
            safety_sec = _build_safety_section(USER_1)
            assert safety_sec["trusted_contacts"] == []
            assert safety_sec["checkin_sessions"] == []

        assert _build_spotify_section(USER_1) == []
        assert _build_consent_history(USER_1) == []

    # build_user_data_export integration check
    with (
        patch(
            "app.db.users.export._build_profile_section", return_value={"name": "Alice"},
        ),
        patch(
            "app.db.users.export._build_account_section", return_value={"id": USER_1},
        ),
        patch("app.db.users.export._build_matches_and_discovery", return_value={}),
        patch("app.db.users.export._build_chat_section", return_value={}),
        patch("app.db.users.export._build_safety_section", return_value={}),
        patch("app.db.users.export._build_feedback_section", return_value=[]),
        patch("app.db.users.export._build_reports_section", return_value={}),
        patch("app.db.users.export._build_spotify_section", return_value=[]),
        patch("app.db.users.export._build_consent_history", return_value=[]),
        patch("app.db.users.export._safe_select", return_value=[]),
    ):
        data = build_user_data_export(USER_1)
        assert data["profile"]["name"] == "Alice"
        assert data["account"]["id"] == USER_1


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

    with patch(
        "app.db.users.auth.DISPOSABLE_DOMAINS", {"mailinator.com", "tempmail.com"},
    ):
        assert is_disposable_email("user@mailinator.com") is True
        assert is_disposable_email("user@gmail.com") is False
        assert is_disposable_email("invalid_no_at") is False

    # is_allowed_email with domain whitelist
    with patch.object(
        settings, "allowed_signup_domains", {"campus_flavor": ["campus.edu"]},
    ):
        assert is_allowed_email("user@campus.edu", app_variant="campus_flavor") is True
        assert is_allowed_email("user@other.edu", app_variant="campus_flavor") is False
        assert is_allowed_email("user@anywhere.com", app_variant="nexus") is True
        assert (
            is_allowed_email("user@anywhere.com", app_variant="unconfigured_flavor")
            is True
        )

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
        mock_sb.table().select().eq().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(HTTPException, match="User service temporarily unavailable"):
            fetch_public_user(USER_1)

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        assert fetch_public_user(USER_1) is None

        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(
            data=["not-dict"],
        )
        assert fetch_public_user(USER_1) is None

        # Mobile decryption failure logs and returns mobile as None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(
            data=[{"id": USER_1, "mobile": "enc_mobile"}],
        )
        with patch(
            "app.db.users.auth.decrypt_pii", side_effect=DecryptFailedError("fail"),
        ):
            u = fetch_public_user(USER_1)
            assert u is not None
            assert u["mobile"] is None

    # set_verified_mobile: restricted phone (409), duplicate phone (409), generic APIError (503)
    with patch("app.db.users.is_phone_blocklisted", return_value=True):
        with pytest.raises(HTTPException, match="This phone number is restricted"):
            set_verified_mobile(USER_1, "+1234567890")

    with (
        patch("app.db.users.is_phone_blocklisted", return_value=False),
        patch("app.db.users.auth.supabase_client") as mock_sb,
    ):
        # Duplicate key 23505 -> 409
        err_dup = APIError({"message": "duplicate key value", "code": "23505"})
        err_dup.code = "23505"
        mock_sb.table().update().eq().execute.side_effect = err_dup
        with pytest.raises(HTTPException, match="already linked to another account"):
            set_verified_mobile(USER_1, "+1234567890")

        # Generic APIError -> 503
        mock_sb.table().update().eq().execute.side_effect = APIError(
            {"message": "fatal"},
        )
        with pytest.raises(HTTPException, match="Failed to save verified phone number"):
            set_verified_mobile(USER_1, "+1234567890")

    # set_user_suspension: APIError -> DatabaseAccessError
    with patch("app.db.users.auth.supabase_client") as mock_sb:
        mock_sb.table().update().eq().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(
            DatabaseAccessError, match="Failed to update user suspension status",
        ):
            set_user_suspension(
                USER_1,
                True,
                suspended_until=datetime.now(timezone.utc),
                moderation_status="flagged",
                moderation_reason_code="spam",
            )

    # find_user_id_by_phone: APIError -> 503, not found -> None
    with patch("app.db.users.auth.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
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

    with (
        patch("app.db.users.auth.fetch_public_user", return_value=None),
        patch("app.db.users.auth.invalidate_user_status_cache"),
        patch("app.db.users.auth.supabase_client") as mock_sb,
    ):
        mock_sb.table().upsert().select().execute.side_effect = APIError(
            {"message": "insert fail"},
        )
        with pytest.raises(HTTPException, match="Failed to initialize user account"):
            upsert_public_user(USER_1, "nexus")

        mock_sb.table().upsert().select().execute.side_effect = None
        mock_sb.table().upsert().select().execute.return_value = MagicMock(data=[])
        with pytest.raises(
            HTTPException, match="User account initialization returned no row",
        ):
            upsert_public_user(USER_1, "nexus")

        mock_sb.table().upsert().select().execute.return_value = MagicMock(
            data=[{"id": USER_1, "xmax": "0"}],
        )
        u, created = upsert_public_user(USER_1, "nexus")
        assert created is True

    # Consent helpers: parsing & validation
    assert _parse_terms_timestamp("2026-08-01T00:00:00Z") is not None
    with pytest.raises(
        HTTPException, match="Unexpected terms acceptance timestamp payload",
    ):
        _parse_terms_timestamp(None)
    assert _parse_version_tuple("1.2.3") == (1, 2, 3)
    _validate_terms_versions(settings.current_terms_version)

    with pytest.raises(
        HTTPException, match="must match the current server terms version",
    ):
        _validate_terms_versions("0.0.1")

    with pytest.raises(HTTPException, match="must be a valid numeric version string"):
        _validate_terms_versions("invalid_ver")

    # _verify_general_terms_accepted without accepted version
    with patch(
        "app.db.users.consent._fetch_existing_consent_pair",
        return_value={"accepted_terms_version": None},
    ), pytest.raises(HTTPException, match="General terms must be accepted"):
        _verify_general_terms_accepted(USER_1)

    # Consent update / clear / fetch APIErrors
    with patch("app.db.users.consent.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(
            HTTPException, match="Failed to verify current consent state",
        ):
            _fetch_existing_consent_pair(
                USER_1, "accepted_terms_version", "terms_accepted_at",
            )

        # _update_consent_pair APIError & no rows updated (500)
        with patch(
            "app.db.users.consent._fetch_existing_consent_pair",
            return_value={"accepted_terms_version": None},
        ):
            mock_sb.table().update().eq().execute.side_effect = APIError(
                {"message": "fail"},
            )
            with pytest.raises(HTTPException, match="Failed to record consent"):
                _update_consent_pair(
                    USER_1, "accepted_terms_version", "terms_accepted_at", "1.0",
                )

            mock_sb.table().update().eq().execute.side_effect = None
            mock_sb.table().update().eq().execute.return_value = MagicMock(data=[])
            with pytest.raises(HTTPException, match="Failed to record consent"):
                _update_consent_pair(
                    USER_1, "accepted_terms_version", "terms_accepted_at", "1.0",
                )

        # _clear_consent_pair APIError
        mock_sb.table().update().eq().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(HTTPException, match="Failed to record consent"):
            _clear_consent_pair(
                USER_1,
                "special_category_consent_version",
                "special_category_consent_at",
            )

        # _log_consent_event APIError is logged best-effort without raising
        mock_sb.table().insert().execute.side_effect = APIError({"message": "fail"})
        _log_consent_event(USER_1, "terms", True, "1.0")

    # High-level consent functions
    ver = settings.current_terms_version
    with (
        patch(
            "app.db.users.consent._update_consent_pair",
            return_value=(ver, datetime.now(timezone.utc)),
        ),
        patch("app.db.users.consent._clear_consent_pair"),
        patch("app.db.users.consent._log_consent_event"),
    ):
        update_user_terms(USER_1, ver)
        update_community_guidelines_consent(USER_1, ver)
        with patch("app.db.users.consent._verify_general_terms_accepted"):
            update_special_category_consent(USER_1, ver, True)
            update_special_category_consent(USER_1, ver, False)
            update_safety_data_consent(USER_1, ver, True)
            update_safety_data_consent(USER_1, ver, False)

    # generate_export_code: Redis failure is caught, APIError -> 503
    with (
        patch("app.db.users.import_export.supabase_client") as mock_sb,
        patch("app.db.users.import_export.redis_client") as mock_redis,
    ):
        mock_redis.delete = AsyncMock(side_effect=Exception("redis down"))
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data={"import_sync_code": "ABCDEF"},
        )
        mock_sb.table().update().eq().execute.side_effect = APIError(
            {"message": "update code fail"},
        )
        with pytest.raises(HTTPException, match="Failed to generate export code"):
            await generate_export_code(USER_1)

        mock_sb.table().update().eq().execute.side_effect = None
        mock_sb.table().update().eq().execute.return_value = MagicMock()
        code, exp = await generate_export_code(USER_1)
        assert len(code) == 6
        assert exp is not None

    # _validate_import validation checks
    with pytest.raises(HTTPException, match="Export code has no expiry"):
        _validate_import(
            {"id": USER_2}, {"id": USER_1}, "nexus", {"app_variant": "flavor"},
        )

    with pytest.raises(HTTPException, match="Export code has expired"):
        _validate_import(
            {"id": USER_2, "import_sync_expires_at": "2020-01-01T00:00:00Z"},
            {"id": USER_1},
            "nexus",
            {"app_variant": "flavor"},
        )

    future_iso = "2099-01-01T00:00:00Z"
    with pytest.raises(HTTPException, match="already imported data"):
        _validate_import(
            {"id": USER_2, "import_sync_expires_at": future_iso},
            {"id": USER_1, "has_imported_data": True},
            "nexus",
            {"app_variant": "flavor"},
        )

    with pytest.raises(HTTPException, match="only allowed into the main Nexus account"):
        _validate_import(
            {"id": USER_2, "import_sync_expires_at": future_iso},
            {"id": USER_1},
            "flavor_app",
            {"app_variant": "flavor"},
        )

    with pytest.raises(HTTPException, match="must originate from a flavor variant"):
        _validate_import(
            {"id": USER_2, "import_sync_expires_at": future_iso},
            {"id": USER_1},
            "nexus",
            {"app_variant": "nexus"},
        )

    with pytest.raises(HTTPException, match="pending deletion"):
        _validate_import(
            {"id": USER_2, "import_sync_expires_at": future_iso},
            {"id": USER_1},
            "nexus",
            {"app_variant": "flavor", "deletion_requested_at": "2026-08-01T00:00:00Z"},
        )

    # _fetch_import_profiles: not found (400) & APIError (503)
    with patch("app.db.users.import_export.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        with pytest.raises(HTTPException, match="Invalid or already-used export code"):
            _fetch_import_profiles("BADCOD", USER_1)

        mock_sb.table().select().eq().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(
            HTTPException, match="Import service temporarily unavailable",
        ):
            _fetch_import_profiles("CODE12", USER_1)

    # execute_import full flow
    source_p = {"id": USER_2, "import_sync_expires_at": future_iso, "hometown": "NYC"}
    target_p = {"id": USER_1, "has_imported_data": False}
    with (
        patch(
            "app.db.users.import_export._fetch_import_profiles",
            return_value=(source_p, target_p),
        ),
        patch(
            "app.db.users.import_export.fetch_public_user",
            return_value={"id": USER_2, "app_variant": "flavor"},
        ),
        patch("app.db.users.import_export.supabase_client") as mock_sb,
    ):
        mock_sb.table().update().eq().eq().execute.return_value = MagicMock(
            data=[{"id": USER_2}],
        )
        mock_sb.table().update().eq().execute.return_value = MagicMock()
        mock_sb.table().insert().execute.return_value = MagicMock()
        fields = execute_import(USER_1, "CODE12", target_variant="nexus")
        assert "hometown" in fields


def test_db_users_account_deletion():
    # Helper reason checks
    assert _reason_code_for_flag({"moderation_status": "banned"}, False) == "banned"
    assert (
        _reason_code_for_flag({"moderation_status": "restricted"}, False)
        == "restricted"
    )
    assert _reason_code_for_flag({"is_suspended": True}, False) == "suspended"
    assert _reason_code_for_flag({}, True) == "unresolved_report"
    assert _reason_code_for_flag({}, False) is None

    # is_phone_blocklisted
    mock_table = _make_chaining_mock(
        [{"id": 1, "cooldown_expires_at": "2026-09-01T00:00:00Z"}],
    )
    with patch(
        "app.db.users.account_deletion.supabase_client.table", return_value=mock_table,
    ):
        assert is_phone_blocklisted("blind_idx_123") is True

    # fetch_deletion_status
    mock_table = _make_chaining_mock(
        [
            {
                "deletion_requested_at": "2026-08-25T10:00:00Z",
                "scheduled_purge_at": "2026-09-25T10:00:00Z",
            },
        ],
    )
    with patch(
        "app.db.users.account_deletion.supabase_client.table", return_value=mock_table,
    ):
        status = fetch_deletion_status(USER_1)
        assert status is not None
        assert "deletion_requested_at" in status

    # request_deletion & cancel_deletion
    mock_table = _make_chaining_mock([{"id": 1}])
    with patch(
        "app.db.users.account_deletion.supabase_client.table", return_value=mock_table,
    ):
        request_deletion(USER_1, "HARASS")
        cancel_deletion(USER_1)

    # Purge helpers
    now = datetime.now(timezone.utc)
    mock_table = _make_chaining_mock(
        [{"user_id": USER_1, "phone_blind_index": "idx", "flag_reason": "HARASS"}],
    )
    mock_storage = MagicMock()
    mock_storage.list.return_value = []
    with (
        patch(
            "app.db.users.account_deletion.supabase_client.table",
            return_value=mock_table,
        ),
        patch(
            "app.db.users.account_deletion.supabase_client.storage.from_",
            return_value=mock_storage,
        ),
        patch("app.core.infra.cache.invalidate_user_status_cache"),
    ):
        _permanently_unmatch_all(USER_1)
        _anonymize_profile_and_user(USER_1, now)
        _purge_vector_profiles_for_user(USER_1)
        _purge_discovery_for_user(USER_1)
        _delete_no_retention_rows(USER_1)
        _delete_user_media_objects(USER_1)
        _purge_single_due_account(
            {"user_id": USER_1, "phone_blind_index": "idx", "flag_reason": "HARASS"},
            now,
        )
        purge_due_accounts()
        expire_blocklist_entries()

    # Long tail archive & purge helpers
    mock_table = _make_chaining_mock([])
    with patch(
        "app.db.users.account_deletion.supabase_client.table", return_value=mock_table,
    ):
        _archive_account_history(USER_1)
        _chunked_delete_by_field("profile_discovery_actions", "actor_id", USER_1)
        _chunked_delete_by_or_filter(
            "matches", f"liker_id.eq.{USER_1},liked_back_id.eq.{USER_1}", USER_1,
        )
        _chunked_pre_purge_child_records(USER_1)
        hard_purge_long_tail_accounts()


def test_db_users_export():
    # _sign_urls
    mock_storage = MagicMock()
    mock_storage.create_signed_urls.return_value = [
        {"path": "u1/pic.jpg", "signedURL": "https://signed.url"},
    ]
    with patch(
        "app.db.users.export.supabase_client.storage.from_", return_value=mock_storage,
    ):
        signed = _sign_urls("avatars", ["u1/pic.jpg"])
        assert isinstance(signed, dict)
        assert "u1/pic.jpg" in signed

    # Section builders with mocked tables
    mock_table = _make_chaining_mock(
        [
            {
                "id": USER_1,
                "display_name": encrypt_to_hex("Alice"),
                "event_time": encrypt_to_hex("2026-08-25T12:00:00Z", category="chat"),
                "action": "like",
                "user_a_id": USER_1,
            },
        ],
    )

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
    mock_table = _make_chaining_mock(
        [{"accepted_terms_version": "2.0.0", "terms_accepted_at": now.isoformat()}],
    )

    with (
        patch("app.db.users.consent.supabase_client.table", return_value=mock_table),
        patch("app.db.users.consent.settings.current_terms_version", "2.0.0"),
        patch("app.core.infra.cache.invalidate_user_status_cache"),
    ):
        _verify_general_terms_accepted(USER_1)
        update_user_terms(USER_1, "2.0.0", granted=True)
        update_community_guidelines_consent(USER_1, "2.0.0")
        update_special_category_consent(USER_1, "2.0.0", True)
        update_safety_data_consent(USER_1, "2.0.0", True)


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

    dec_mob = _decrypt_mobile(
        {"mobile": encrypt_to_hex("+14155552671", category="contact")},
    )
    assert dec_mob["mobile"] == "+14155552671"

    # Public user queries and suspensions
    mock_table = _make_chaining_mock(
        [
            {
                "id": USER_1,
                "mobile": encrypt_to_hex("+14155552671", category="contact"),
                "is_suspended": False,
            },
        ],
    )

    with (
        patch("app.db.users.auth.supabase_client.table", return_value=mock_table),
        patch("app.db.users.is_phone_blocklisted", return_value=False),
        patch("app.core.infra.cache.invalidate_user_status_cache"),
    ):
        pub = fetch_public_user(USER_1)
        assert pub is not None
        set_verified_mobile(USER_1, "+14155552671")
        set_user_suspension(USER_1, is_suspended=True, moderation_reason_code="abuse")
        find_user_id_by_phone("+14155552671")
        get_user_email_by_id(USER_1)
        get_user_id_by_email("test@berkeley.edu")
        upsert_public_user(USER_1, app_variant="nexus")
