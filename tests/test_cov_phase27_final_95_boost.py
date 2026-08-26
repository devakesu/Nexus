"""Phase 27 Coverage Suite: Final high-yield push across reminder scheduler, profile details, crud, safety contacts, and node details to achieve >= 95% coverage."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from fastapi import BackgroundTasks, HTTPException
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.db.client import DatabaseAccessError
from app.db.profiles.encryption import DecryptFailedError
from app.models import ProfileDetailsUpdate

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
CONV_1 = "00000000-0000-0000-0000-000000000010"
SESS_1 = "00000000-0000-0000-0000-000000000020"


def make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "PATCH",
        "path": "/api/v1/user/profile",
        "headers": [],
        "client": ("127.0.0.1", 12345),
        "app": MagicMock(),
    }
    return Request(scope)


def make_api_error(code: str = "P0001", message: str = "DB error") -> APIError:
    return APIError({"code": code, "message": message, "details": "details", "hint": "hint"})


# =============================================================================
# 1. SERVICES REMINDER SCHEDULER TESTS
# =============================================================================

async def test_services_reminder_scheduler_deep():
    from app.services.reminder_scheduler import (
        _check_due_reminders,
        _check_overdue_safety_sessions,
        _check_upcoming_safety_reminders,
        _escalate_safety_session,
        _run_account_deletion_long_tail_purge,
        _run_account_deletion_purge,
        _run_blocklist_expiry,
        _run_safety_data_legal_hold_purge,
        _run_safety_evidence_retention_purge,
        start_reminder_scheduler,
    )

    # _check_due_reminders: conversation None & DatabaseAccessError
    with patch("app.services.reminder_scheduler.fetch_due_event_reminders", return_value=[{"id": "ev-1", "conversation_id": CONV_1}]), \
         patch("app.services.reminder_scheduler.mark_reminder_sent", return_value=True), \
         patch("app.services.reminder_scheduler.fetch_conversation_participants", return_value=None):
        await _check_due_reminders()

    with patch("app.services.reminder_scheduler.fetch_due_event_reminders", return_value=[{"id": "ev-1", "conversation_id": CONV_1}]), \
         patch("app.services.reminder_scheduler.mark_reminder_sent", return_value=True), \
         patch("app.services.reminder_scheduler.fetch_conversation_participants", side_effect=DatabaseAccessError("DB fail")):
        await _check_due_reminders()

    # _check_upcoming_safety_reminders: fetch error, mark False, conv None, loop error
    with patch("app.services.reminder_scheduler.fetch_due_safety_reminders", side_effect=DatabaseAccessError("DB fail")):
        await _check_upcoming_safety_reminders()

    due_list = [
        {"id": "ev-1", "conversation_id": CONV_1, "created_by": USER_1},
        {"id": "ev-2", "conversation_id": CONV_1, "created_by": USER_1},
        {"id": "ev-3", "conversation_id": CONV_1, "created_by": USER_1},
    ]
    with patch("app.services.reminder_scheduler.fetch_due_safety_reminders", return_value=due_list), \
         patch("app.services.reminder_scheduler.mark_safety_reminder_sent", side_effect=[False, True, True]), \
         patch("app.services.reminder_scheduler.fetch_conversation_participants", side_effect=[None, DatabaseAccessError("DB fail")]):
        await _check_upcoming_safety_reminders()

    # _escalate_safety_session: DatabaseAccessError
    with patch("app.services.reminder_scheduler.fetch_safety_contacts_with_id", side_effect=DatabaseAccessError("DB fail")):
        await _escalate_safety_session({"id": SESS_1, "user_id": USER_1, "escalations_sent": 0})

    # _check_overdue_safety_sessions: DatabaseAccessError, empty due, safe escalate error
    with patch("app.services.reminder_scheduler.fetch_overdue_safety_sessions", side_effect=DatabaseAccessError("DB fail")):
        await _check_overdue_safety_sessions()

    with patch("app.services.reminder_scheduler.fetch_overdue_safety_sessions", return_value=[]):
        await _check_overdue_safety_sessions()

    overdue_sess = [{"id": SESS_1, "user_id": USER_1, "escalations_sent": 0}]
    with patch("app.services.reminder_scheduler.fetch_overdue_safety_sessions", return_value=overdue_sess), \
         patch("app.services.reminder_scheduler._next_escalation_due", return_value=True), \
         patch("app.services.reminder_scheduler._escalate_safety_session", side_effect=Exception("Escalate error")):
        await _check_overdue_safety_sessions()

    # Purge jobs: DatabaseAccessError handling
    with patch("app.services.reminder_scheduler._run_in_maintenance_executor", side_effect=DatabaseAccessError("DB fail")):
        await _run_account_deletion_purge()
        await _run_blocklist_expiry()
        await _run_account_deletion_long_tail_purge()
        await _run_safety_evidence_retention_purge()
        await _run_safety_data_legal_hold_purge()

    # start_reminder_scheduler: start exception
    with patch("app.services.reminder_scheduler._scheduler", None), \
         patch("app.services.reminder_scheduler.AsyncIOScheduler") as mock_sched:
        mock_sched.return_value.start.side_effect = Exception("Scheduler start fail")
        with pytest.raises(Exception):
            start_reminder_scheduler()


# =============================================================================
# 2. API USER PROFILE DETAILS TESTS
# =============================================================================

def test_api_user_profile_details_deep():
    from app.api.user.profile.details import update_profile_details

    req = make_dummy_request()
    bg = BackgroundTasks()

    # special category consent row None
    with patch("app.api.user.profile.details._sets_special_category_data", return_value=True), \
         patch("app.api.user.profile.details.fetch_public_user", return_value=None):
        with pytest.raises(HTTPException) as exc:
            update_profile_details(req, bg, ProfileDetailsUpdate(display_sexuality="Straight / Heterosexual"), USER_1, None)
        assert exc.value.status_code == 404

    # profile fetch exception & profile None
    with patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.side_effect = Exception("DB error")
        with pytest.raises(HTTPException) as exc:
            update_profile_details(req, bg, ProfileDetailsUpdate(name="Alex"), USER_1, None)
        assert exc.value.status_code == 500

        mock_sb.table().select().eq().maybe_single().execute.side_effect = None
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=None)
        with pytest.raises(HTTPException) as exc:
            update_profile_details(req, bg, ProfileDetailsUpdate(name="Alex"), USER_1, None)
        assert exc.value.status_code == 404

    # institute name < 3 letters
    valid_profile = {"id": USER_1, "name": "Current", "age": 22, "campus_name": "MIT", "campus_year": 2}
    with patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb, \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value=valid_profile), \
         patch("app.api.user.profile.details._assert_no_decryption_failures"):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=valid_profile)
        p_invalid_campus = ProfileDetailsUpdate.model_construct(campus_name="AB")
        with pytest.raises(HTTPException) as exc:
            update_profile_details(req, bg, p_invalid_campus, USER_1, None)
        assert exc.value.status_code == 400

    # name rolling window ineligible
    with patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb, \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value=valid_profile), \
         patch("app.api.user.profile.details._assert_no_decryption_failures"), \
         patch("app.api.user.profile.details.validate_display_name"), \
         patch("app.api.user.profile.details._rolling_change_window_status", return_value=(2, False, None)):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=valid_profile)
        with pytest.raises(HTTPException) as exc:
            update_profile_details(req, bg, ProfileDetailsUpdate(name="BrandNew"), USER_1, None)
        assert exc.value.status_code == 403

    # age > max_age for variant & age rolling window ineligible
    with patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb, \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value=valid_profile), \
         patch("app.api.user.profile.details._assert_no_decryption_failures"), \
         patch("app.api.user.profile.details.fetch_public_user", return_value={"app_variant": "nexus_mec"}):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=valid_profile)
        with pytest.raises(HTTPException) as exc:
            update_profile_details(req, bg, ProfileDetailsUpdate(age=29), USER_1, None)
        assert exc.value.status_code == 400

    with patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb, \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value=valid_profile), \
         patch("app.api.user.profile.details._assert_no_decryption_failures"), \
         patch("app.api.user.profile.details.fetch_public_user", return_value={"app_variant": "nexus"}), \
         patch("app.api.user.profile.details._rolling_change_window_status", return_value=(2, False, None)):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=valid_profile)
        with pytest.raises(HTTPException) as exc:
            update_profile_details(req, bg, ProfileDetailsUpdate(age=25), USER_1, None)
        assert exc.value.status_code == 403

    # Tab activation: incomplete missing fields & tab deactivations
    incomplete_profile = {"id": USER_1, "name": "Current", "age": 22, "is_dating_active": False}
    with patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb, \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value=incomplete_profile), \
         patch("app.api.user.profile.details._assert_no_decryption_failures"), \
         patch("app.api.user.profile.details._validate_tab_activation", return_value=["dating_for"]):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=incomplete_profile)
        with pytest.raises(HTTPException) as exc:
            update_profile_details(req, bg, ProfileDetailsUpdate(is_dating_active=True), USER_1, None)
        assert exc.value.status_code == 400

    # Deactivating tabs successfully
    with patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb, \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value=valid_profile), \
         patch("app.api.user.profile.details._assert_no_decryption_failures"):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=valid_profile)
        mock_sb.table().update().eq().execute.return_value = MagicMock(data=[{"id": USER_1}])
        res_deact = update_profile_details(
            req, bg,
            ProfileDetailsUpdate(is_dating_active=False, is_friends_active=False, is_professional_active=False),
            USER_1, None,
        )
        assert res_deact["status"] == "success"


# =============================================================================
# 3. DB PROFILES CRUD TESTS
# =============================================================================

def test_db_profiles_crud_deep():
    from app.db.profiles.crud import (
        _check_basic_overlap,
        _check_candidate_match,
        _execute_and_filter_candidates,
        fetch_music_affinities,
        fetch_peer_profile_by_id,
    )
    from app.models.discovery import DiscoveryFilters

    # _check_basic_overlap: sub_interests dict, role_type
    cand = {
        "sub_interests": {"tech": ["Python", "Rust"]},
        "role_type": ["Engineer"],
    }
    f_sub = DiscoveryFilters(sub_interests=["Python"])
    assert _check_basic_overlap(cand, f_sub) is True

    f_sub_miss = DiscoveryFilters(sub_interests=["Java"])
    assert _check_basic_overlap(cand, f_sub_miss) is False

    f_role = DiscoveryFilters(role_type=["Designer"])
    assert _check_basic_overlap(cand, f_role) is False

    # _check_candidate_match: looking_for, causes_supported, tech_skills, partner_values
    cand2 = {
        "looking_for": ["Chat"],
        "causes_supported": ["OpenSource"],
        "tech_skills": ["FastAPI"],
        "partner_values": "Honesty, Loyalty",
    }
    f_lk_miss = DiscoveryFilters(looking_for=["Date"])
    assert _check_candidate_match(cand2, f_lk_miss, set()) is False

    f_cs_miss = DiscoveryFilters(causes_supported=["Animals"])
    assert _check_candidate_match(cand2, f_cs_miss, set()) is False

    f_ts_miss = DiscoveryFilters(tech_skills=["Kubernetes"])
    assert _check_candidate_match(cand2, f_ts_miss, set()) is False

    f_pv_miss = DiscoveryFilters(partner_values=["Wealth"], dealbreaker_fields=["partner_values"])
    assert _check_candidate_match(cand2, f_pv_miss, {"partner_values"}) is False

    # _execute_and_filter_candidates: APIError & DecryptFailedError
    mock_query = MagicMock()
    mock_query.in_().limit().execute.side_effect = make_api_error()
    viewer = {"id": USER_1, "search_bucket": "M", "dating_target_buckets": ["F"]}
    with pytest.raises(DatabaseAccessError):
        _execute_and_filter_candidates(mock_query, viewer, "Dating", 10)

    # fetch_peer_profile_by_id: ordered_images fallback to profile_pic & APIError
    with patch("app.db.profiles.crud.supabase_client") as mock_sb, \
         patch("app.db.profiles.crud.decrypt_profile_record", return_value={"id": USER_2, "name": "Bob"}), \
         patch("app.db.profiles.crud.sanitize_decrypted_profile", return_value={"id": USER_2, "name": "Bob"}), \
         patch("app.db.profiles.crud.sign_profile_media", return_value={"id": USER_2, "name": "Bob"}):
        peer_row = {"id": USER_2, "profile_pic": None, "ordered_images": ["https://img.nexus.test/1.jpg"]}
        
        # Build chain for fetch_peer_profile_by_id
        chain = MagicMock()
        mock_sb.table.return_value = chain
        chain.select.return_value = chain
        chain.eq.return_value = chain
        chain.neq.return_value = chain
        chain.limit.return_value = chain
        chain.execute.return_value = MagicMock(data=[peer_row])
        
        assert fetch_peer_profile_by_id(USER_2) is not None

        chain.execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            fetch_peer_profile_by_id(USER_2)

    # fetch_music_affinities: exception handling
    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().limit().execute.side_effect = Exception("DB fail")
        a, g = fetch_music_affinities(USER_1)
        assert a == {}
        assert g == {}


# =============================================================================
# 4. DB SAFETY CONTACTS TESTS
# =============================================================================

def test_db_safety_contacts_deep():
    from app.db.safety.contacts import (
        fetch_safety_contact_by_id,
        remove_safety_contact_self_service,
        sync_safety_contacts,
    )

    # sync_safety_contacts notices direct query fallback
    contacts = [{"name": "Mom", "phone": "+14155552671"}]
    with patch("app.db.safety.contacts.supabase_client") as mock_sb, \
         patch("app.db.safety.contacts._phone_blind_index", return_value="idx-1"):
        mock_sb.rpc().execute.return_value = MagicMock(data=None)
        mock_sb.table().select().eq().execute.return_value = MagicMock(data=[{"phone_blind_index": "idx-1", "self_removed_at": "2026-01-01"}])
        blocked, _ = sync_safety_contacts(USER_1, contacts)
        assert len(blocked) == 1

    # fetch_safety_contact_by_id: not found
    with patch("app.db.safety.contacts.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=None)
        assert fetch_safety_contact_by_id("c-1") is None

    # remove_safety_contact_self_service: contact None, APIError notice, APIError delete
    with patch("app.db.safety.contacts.fetch_safety_contact_by_id", return_value=None):
        assert remove_safety_contact_self_service("c-1") is None

    with patch("app.db.safety.contacts.fetch_safety_contact_by_id", return_value={"id": "c-1", "user_id": USER_1, "phone": "+14155552671"}), \
         patch("app.db.safety.contacts.supabase_client") as mock_sb:
        mock_sb.table().upsert().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            remove_safety_contact_self_service("c-1")

        mock_sb.table().upsert().execute.side_effect = None
        mock_sb.table().delete().eq().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            remove_safety_contact_self_service("c-1")


# =============================================================================
# 5. DB SESSIONS NODE DETAILS TESTS
# =============================================================================

async def test_db_sessions_node_details_deep():
    from app.db.sessions.node_details import (
        _build_node_detail_payload,
        _query_discovery_node_detail,
        _validate_discovery_node_data,
        fetch_discovery_node_detail,
    )

    # _build_node_detail_payload: DecryptFailedError
    with patch("app.db.sessions.node_details.decrypt_profile_record", side_effect=DecryptFailedError("Fail")):
        with pytest.raises(DecryptFailedError):
            _build_node_detail_payload({}, {}, "cid", SESS_1, USER_1, USER_2)

    # _validate_discovery_node_data: missing session, invalid tab, expired session, missing profile, deactivated, blocked
    assert await _validate_discovery_node_data({}, USER_1) is None
    assert await _validate_discovery_node_data({"discovery_sessions": {"tab": "Invalid"}}, USER_1) is None
    assert await _validate_discovery_node_data({"discovery_sessions": {"tab": "Dating", "expires_at": "2020-01-01T00:00:00Z"}}, USER_1) is None

    valid_sess = {"tab": "Dating", "expires_at": (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()}
    assert await _validate_discovery_node_data({"discovery_sessions": valid_sess}, USER_1) is None
    assert await _validate_discovery_node_data({"discovery_sessions": valid_sess, "profiles": {"is_deactivated": True}}, USER_1) is None

    with patch("app.db.sessions.node_details.get_cached_active_block_ids", return_value={USER_2}):
        assert await _validate_discovery_node_data({"discovery_sessions": valid_sess, "profiles": {"id": USER_2, "is_deactivated": False}}, USER_1) is None

    # _query_discovery_node_detail: APIError & generic Exception
    with patch("app.db.sessions.node_details.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().eq().limit().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            _query_discovery_node_detail(SESS_1, USER_1, USER_2)

        mock_sb.table().select().eq().eq().eq().limit().execute.side_effect = Exception("Unexpected")
        with pytest.raises(DatabaseAccessError):
            _query_discovery_node_detail(SESS_1, USER_1, USER_2)

    # fetch_discovery_node_detail: non-dict row & validation failed
    with patch("app.db.sessions.node_details._query_discovery_node_detail", return_value=MagicMock(data=["not-a-dict"])):
        assert await fetch_discovery_node_detail(SESS_1, USER_1, USER_2) is None

    with patch("app.db.sessions.node_details._query_discovery_node_detail", return_value=MagicMock(data=[{}])), \
         patch("app.db.sessions.node_details._validate_discovery_node_data", return_value=None):
        assert await fetch_discovery_node_detail(SESS_1, USER_1, USER_2) is None
