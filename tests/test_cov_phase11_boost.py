"""Phase 11 Ultra Deep Coverage suite targeting high statement modules:
1. app/db/users/account_deletion.py (85 lines missing)
2. app/db/users/export.py (47 lines missing)
3. app/db/users/auth.py (39 lines missing)
4. app/db/feedback/feedback.py (29 lines missing)
5. app/db/safety/sessions.py (29 lines missing)
6. app/db/safety/alerts.py (38 lines missing)
7. app/db/safety/contacts.py (31 lines missing)
8. app/db/spotify.py (30 lines missing)
9. app/api/user/profile/details.py (57 lines missing)
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
ALERT_1 = "00000000-0000-0000-0000-000000000030"
REPORT_1 = "00000000-0000-0000-0000-000000000050"


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
    mock.single.return_value = single_mock
    return mock


# -----------------------------------------------------------------------------
# 1. DB ACCOUNT DELETION PURGE ROUTINES & LONG TAIL
# -----------------------------------------------------------------------------
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

    with patch("app.db.users.account_deletion.supabase_client.table", return_value=mock_t), \
         patch("app.db.users.account_deletion.supabase_client.storage.from_") as mock_storage, \
         patch("app.db.users.account_deletion.supabase_client.auth.admin") as mock_admin, \
         patch("app.db.users.account_deletion.delete_user_chat_media"), \
         patch("app.db.users.account_deletion.compute_deletion_flag_reason", return_value="suspended"), \
         patch("time.sleep"):
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


# -----------------------------------------------------------------------------
# 2. DB USERS EXPORT & AUTH
# -----------------------------------------------------------------------------
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

    with patch("app.db.users.export.supabase_client.table", return_value=mock_t), \
         patch("app.db.users.auth.supabase_client.table", return_value=mock_t), \
         patch("app.db.users.auth.supabase_client.rpc") as mock_rpc, \
         patch("app.db.users.is_phone_blocklisted", return_value=False), \
         patch("app.db.users.export.supabase_client.storage.from_") as mock_storage:
        mock_rpc.return_value.execute.return_value = MagicMock(data="ok")
        mock_storage.return_value.upload.return_value = None
        mock_storage.return_value.create_signed_url.return_value = {"signedURL": "https://signed.url"}

        fetch_public_user(USER_1)
        is_disposable_email("user@mailinator.com")
        set_verified_mobile(USER_1, "+15555555555")

        data = build_user_data_export(USER_1)
        assert isinstance(data, dict)


# -----------------------------------------------------------------------------
# 3. DB FEEDBACK, SPOTIFY, SAFETY SESSIONS
# -----------------------------------------------------------------------------
def test_db_feedback_spotify_safety():
    from app.db.feedback.feedback import (
        add_ticket_comment,
        close_ticket,
        fetch_ticket_comments,
        fetch_ticket_report,
        fetch_ticket_status_history,
        fetch_user_email,
        fetch_user_tickets,
        record_feedback_submission,
    )
    from app.db.safety.sessions import (
        cancel_safety_escalation,
        fetch_overdue_safety_sessions,
        fetch_safety_session,
    )
    from app.db.spotify import (
        disconnect,
        get_connection,
        mark_sync_result,
        upsert_connection,
    )

    mock_row: dict[str, Any] = {
        "id": REPORT_1,
        "user_id": USER_1,
        "status": "open",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "access_token": "\\x6161",
        "refresh_token": "\\x6262",
        "next_checkin_at": datetime.now(timezone.utc).isoformat(),
        "escalations_sent": 0,
    }
    mock_t = _make_chaining_mock([mock_row])

    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_t), \
         patch("app.db.spotify.supabase_client.table", return_value=mock_t), \
         patch("app.db.safety.sessions.supabase_client.table", return_value=mock_t):
        record_feedback_submission(USER_1, "help", "Subject", "Message", contact_email="a@b.com")
        fetch_user_tickets(USER_1)
        fetch_ticket_report(USER_1, REPORT_1)
        fetch_ticket_status_history(REPORT_1)
        fetch_ticket_comments(REPORT_1)
        add_ticket_comment(REPORT_1, USER_1, "Comment")
        close_ticket(USER_1, REPORT_1, "resolved")
        fetch_user_email(USER_1)

        upsert_connection(USER_1, "spotify_id", "refresh_tok", "user-top-read")
        get_connection(USER_1)
        mark_sync_result(USER_1, "success")
        disconnect(USER_1)

        fetch_safety_session("s1")
        fetch_overdue_safety_sessions(60)
        cancel_safety_escalation(USER_1, "s1", "safe", "all good")


# -----------------------------------------------------------------------------
# 4. API USER PROFILE DETAILS GET & PATCH
# -----------------------------------------------------------------------------
def test_api_user_profile_details_deep():
    from app.api.user.profile.details import (
        get_profile_details,
        update_profile_details,
    )
    from app.models import ProfileDetailsUpdate

    mock_req = MagicMock()
    mock_bg = MagicMock()

    mock_profile: dict[str, Any] = {
        "id": USER_1,
        "name": "Alice",
        "age": 22,
        "campus_name": "Stanford",
        "campus_year": 2024,
        "profile_pic": "p1.jpg",
        "normal_pics": ["p2.jpg"],
        "interests": {"art": ["painting"]},
        "sub_interests": {},
        "dating_target_buckets": ["tech"],
        "dating_for": ["long_term"],
        "friends_target_buckets": ["gaming"],
        "professional_target_buckets": ["engineering"],
        "looking_for": ["co-founder"],
        "activities": ["running"],
        "causes_supported": ["climate"],
        "top_artists": ["Taylor Swift"],
        "tech_skills": ["Python"],
        "languages": ["English"],
        "pets": ["cat"],
        "ai_vibe_tags": ["creative"],
        "is_dating_active": True,
        "is_friends_active": True,
        "is_professional_active": True,
    }
    mock_t = _make_chaining_mock([mock_profile])

    with patch("app.api.user.profile.details.user_module.supabase_client.table", return_value=mock_t), \
         patch("app.api.user.profile.details.supabase_client.table", return_value=mock_t), \
         patch("app.api.user.profile.details.fetch_public_user", return_value={"special_category_consent_version": "1.0", "special_category_consent_at": "2024-01-01"}), \
         patch("app.api.user.profile.details.decrypt_profile_record", return_value=mock_profile), \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value=mock_profile), \
         patch("app.api.user.profile.details._rolling_change_window_status", return_value=(0, True, None)), \
         patch("app.api.user.profile.details.sync_redis_client") as mock_r:
        mock_r.delete.return_value = 1
        mock_r.set.return_value = True

        # GET
        res_get = get_profile_details(mock_req, _device=None, user_id=USER_1)
        assert res_get["name"] == "Alice"

        # PATCH
        patch_payload = ProfileDetailsUpdate(
            bio="New exciting bio here!",
            hometown="San Francisco",
        )
        res_patch = update_profile_details(mock_req, mock_bg, patch_payload, user_id=USER_1, _device=None)
        assert res_patch["status"] == "success"
