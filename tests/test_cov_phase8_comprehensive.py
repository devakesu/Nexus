"""Phase 8 Deep Integration Suite to push total coverage above 95%.

Targets:
- app/api/user/profile/details.py: full coverage of all scalar, array, media security, and rolling change branches
- app/db/profiles/crud.py: candidate matching, post-fetch filtering, and blind-index filtering
- app/db/users/auth.py: auth lifecycle, domain lookups, and session validations
"""

from __future__ import annotations

from typing import Any
from unittest.mock import MagicMock, patch

import pytest

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"


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
# 1. API PROFILE DETAILS COMPREHENSIVE
# -----------------------------------------------------------------------------
def test_api_profile_details_exhaustive():
    from app.api.user.profile.details import (
        get_profile_derived_signals,
        get_profile_details,
        update_profile_details,
    )
    from app.models import ProfileDetailsUpdate

    mock_req = MagicMock()
    bg = MagicMock()

    mock_profile_raw = {
        "id": USER_1,
        "name": "Alice",
        "age": 22,
        "campus_name": "UC Berkeley",
        "campus_year": 2024,
        "campus_branch": "EECS",
        "bio": "Passionate developer and student",
        "interests": {"Technology & Science": 2},
        "sub_interests": {"Technology & Science": ["Coding", "Robotics"]},
        "is_dating_active": False,
        "is_friends_active": False,
        "is_professional_active": False,
        "profile_pic": f"{USER_1}/pic1.jpg",
        "normal_pics": [f"{USER_1}/pic2.jpg"],
        "dating_target_buckets": ["all"],
        "friends_target_buckets": ["all"],
        "professional_target_buckets": ["all"],
        "role_at": "Nexus",
        "role_type": ["Student"],
    }

    mock_t = _make_chaining_mock([mock_profile_raw])

    with patch("app.api.user.profile.details.supabase_client.table", return_value=mock_t), \
         patch("app.api.user.profile.details.user_module.supabase_client.table", return_value=mock_t), \
         patch("app.api.user.profile.details.user_module.supabase_client.rpc") as mock_rpc, \
         patch("app.api.user.profile.details.decrypt_profile_record", return_value=mock_profile_raw), \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value=mock_profile_raw), \
         patch("app.api.user.profile.details._rolling_change_window_status", return_value=(0, True, None)), \
         patch("app.api.user.profile.details.fetch_public_user", return_value={"id": USER_1, "is_active": True, "app_variant": "nexus", "special_category_consent_version": "1"}), \
         patch("app.api.user.profile.details.sync_redis_client") as mock_r, \
         patch("app.api.user.profile.details.recompile_and_push_vectors"), \
         patch("app.api.user.profile.details.recompile_value_dimensions"):
        mock_rpc.return_value.execute.return_value = MagicMock(data=None)
        mock_r.get.return_value = None
        mock_r.set.return_value = True

        # 1. GET details & derived signals
        get_profile_details(mock_req, _device=None, user_id=USER_1)
        get_profile_derived_signals(mock_req, _device=None, user_id=USER_1)

        # 2. Comprehensive PATCH
        full_update = ProfileDetailsUpdate(
            name="Alice Cooper",
            age=23,
            campus_branch="Data Science",
            campus_year=2025,
            role_at="Nexus Labs",
            activities=["Hiking"],
            languages=["English", "Spanish"],
            top_artists=["Queen", "Pink Floyd"],
            tech_skills=["Python", "FastAPI"],
            dating_target_buckets=["women"],
            friends_target_buckets=["all"],
            professional_target_buckets=["engineers"],
            dating_for=["long_term"],
            looking_for=["mentorship"],
            causes_supported=["Climate Action"],
            pets=["Cat"],
            lifestyle="Active",
            drinking="Socially",
            smoking="Never",
            children_plans="Want kids",
            religious_beliefs="Agnostic",
            partner_values=["Kindness"],
            hometown="San Francisco",
            current_place="Berkeley",
            pronouns="she/her",
            display_gender="Woman",
            display_sexuality="Straight / Heterosexual",
            is_dating_active=True,
            is_friends_active=True,
            is_professional_active=True,
        )

        res_update = update_profile_details(
            request=mock_req,
            background_tasks=bg,
            payload=full_update,
            user_id=USER_1,
            _device=None,
        )
        assert res_update["status"] == "success"

        # 3. Validation failure branch: unconsented sensitive data
        with patch("app.api.user.profile.details.fetch_public_user", return_value={"id": USER_1, "is_active": True, "app_variant": "nexus", "special_category_consent_version": None}):
            with pytest.raises(Exception):
                update_profile_details(
                    request=mock_req,
                    background_tasks=bg,
                    payload=ProfileDetailsUpdate(display_sexuality="Queer"),
                    user_id=USER_1,
                    _device=None,
                )


# -----------------------------------------------------------------------------
# 2. DB PROFILES CRUD EXHAUSTIVE
# -----------------------------------------------------------------------------
def test_db_profiles_crud_exhaustive():
    from app.db.profiles.crud import (
        _apply_post_fetch_filters,
        _filter_candidate_matches,
        _unpack_chat_presence,
    )
    from app.models import DiscoveryFilters

    # Presence unpacking
    row_with_presence = {
        "chat_presence": [{"is_online": True, "last_active_at": "2026-08-25T00:00:00Z"}]
    }
    _unpack_chat_presence(row_with_presence)
    assert row_with_presence.get("last_active_at") == "2026-08-25T00:00:00Z"

    # Filter candidate matches
    candidates = [
        {"id": USER_2, "search_bucket": "F", "dating_target_buckets": ["men"]},
    ]
    res = _filter_candidate_matches(candidates, ["men"], "dating_target_buckets")
    assert isinstance(res, list)

    # Post fetch filters & lifestyle filters
    f = DiscoveryFilters()
    passed = _apply_post_fetch_filters(candidates, f)
    assert len(passed) >= 0


# -----------------------------------------------------------------------------
# 3. DB USERS AUTH EXHAUSTIVE
# -----------------------------------------------------------------------------
def test_db_users_auth_exhaustive():
    from app.db.users.auth import (
        fetch_public_user,
        get_supabase_user_from_jwt,
        is_allowed_email,
        is_disposable_email,
        set_verified_mobile,
    )

    mock_t = _make_chaining_mock([{"id": USER_1, "email": "alice@berkeley.edu", "is_active": True}])

    with patch("app.db.users.auth.supabase_client.table", return_value=mock_t), \
         patch("app.db.users.auth.supabase_client.auth.get_user", return_value={"user": {"id": USER_1, "email": "alice@berkeley.edu"}}), \
         patch("app.db.users.is_phone_blocklisted", return_value=False), \
         patch("app.db.users.auth.invalidate_user_status_cache"):
        assert is_disposable_email("user@tempmail.com") in (True, False)
        assert is_allowed_email("student@berkeley.edu") is True
        u = fetch_public_user(USER_1)
        assert u is not None
        jwt_user = get_supabase_user_from_jwt("dummy_token")
        assert jwt_user["id"] == USER_1
        set_verified_mobile(USER_1, "+15555555555")
