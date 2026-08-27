"""Test Suite for Test User Api.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import BackgroundTasks, HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.api.dependencies import (
    assert_account_active,
    assert_safety_consent,
    assert_special_category_consent,
    get_authenticated_user_id,
    get_bearer_token,
    get_optional_authenticated_user_id,
    get_optional_bearer_token,
    require_safety_consent,
)
from app.api.user.auth_otp import (
    accept_terms,
    auth_bootstrap,
    request_account_phone_otp,
    verify_account_phone_otp,
)
from app.api.user.profile.details import (
    get_profile_derived_signals,
    get_profile_details,
    update_profile_details,
)
from app.api.user.profile.helpers import (
    _assert_no_decryption_failures,
    _build_ordered_images,
    _sets_special_category_data,
    _validate_common_activation,
    _validate_dating_activation,
    _validate_friends_activation,
    _validate_professional_activation,
)
from app.core.config import settings
from app.core.security.crypto import encrypt_to_hex
from app.models import (
    AccountPhoneOtpRequestRequest,
    AccountPhoneOtpVerifyRequest,
    ConsentUpdateRequest,
    EmailNotificationSettingsUpdate,
    LoginByPhoneRequestRequest,
    LoginByPhoneVerifyRequest,
    MECOnboardingRequest,
    NexusOnboardingRequest,
    PrivacySettingsUpdate,
    ProfileDetailsUpdate,
    RegisterDeviceRequest,
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


async def test_api_user_settings():
    from app.api.user.settings import (
        get_email_notification_settings,
        get_privacy_settings,
        update_email_notification_settings,
        update_privacy_settings,
    )
    from app.models import (
        EmailNotificationSettingsUpdate,
        PrivacySettingsUpdate,
    )

    req = _make_mock_request()
    mock_row = {
        "id": USER_1,
        "hidden_profile_fields": ["pronouns"],
        "share_active_status": True,
        "share_read_receipts": True,
        "email_notify_matches": True,
        "email_notify_messages": True,
        "email_notify_digest": False,
        "email_notify_product_updates": True,
        "email_notify_promotions": False,
    }
    mock_t = MagicMock()
    mock_t.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data=mock_row,
    )
    mock_t.update.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(
        data=[mock_row],
    )

    with patch("app.api.user.settings.supabase_client.table", return_value=mock_t):
        priv = get_privacy_settings(req, _device=None, user_id=USER_1)
        assert priv.share_active_status is True

        up_priv = update_privacy_settings(
            req,
            payload=PrivacySettingsUpdate(
                hidden_fields=["pronouns"], share_active_status=False,
            ),
            _device=None,
            user_id=USER_1,
        )
        assert up_priv is not None

        email_s = get_email_notification_settings(req, _device=None, user_id=USER_1)
        assert email_s.email_notify_matches is True

        up_email = update_email_notification_settings(
            req,
            payload=EmailNotificationSettingsUpdate(email_notify_digest=True),
            _device=None,
            user_id=USER_1,
        )
        assert up_email is not None


def test_api_profile_details_validations():
    from app.api.user.profile.details import (
        _validate_common_activation,
        _validate_dating_activation,
        _validate_friends_activation,
        _validate_professional_activation,
    )
    from app.models import ProfileDetailsUpdate

    # Test missing fields in activations
    empty_profile: dict[str, Any] = {}
    missing: list[str] = []
    _validate_common_activation(empty_profile, ProfileDetailsUpdate(), missing)
    assert len(missing) > 0

    missing_dating: list[str] = []
    _validate_dating_activation(empty_profile, ProfileDetailsUpdate(), missing_dating)
    assert len(missing_dating) > 0

    missing_friends: list[str] = []
    _validate_friends_activation(empty_profile, ProfileDetailsUpdate(), missing_friends)
    assert len(missing_friends) > 0

    missing_pro: list[str] = []
    _validate_professional_activation(
        empty_profile, ProfileDetailsUpdate(), missing_pro,
    )
    assert len(missing_pro) > 0


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

    with (
        patch(
            "app.api.user.profile.details.supabase_client.table", return_value=mock_t,
        ),
        patch(
            "app.api.user.profile.details.user_module.supabase_client.table",
            return_value=mock_t,
        ),
        patch(
            "app.api.user.profile.details.user_module.supabase_client.rpc",
        ) as mock_rpc,
        patch(
            "app.api.user.profile.details.decrypt_profile_record",
            return_value=mock_profile_raw,
        ),
        patch(
            "app.api.user.profile.details.user_module.decrypt_profile_record",
            return_value=mock_profile_raw,
        ),
        patch(
            "app.api.user.profile.details._rolling_change_window_status",
            return_value=(0, True, None),
        ),
        patch(
            "app.api.user.profile.details.fetch_public_user",
            return_value={
                "id": USER_1,
                "is_active": True,
                "app_variant": "nexus",
                "special_category_consent_version": "1",
            },
        ),
        patch("app.api.user.profile.details.sync_redis_client") as mock_r,
        patch("app.api.user.profile.details.recompile_and_push_vectors"),
        patch("app.api.user.profile.details.recompile_value_dimensions"),
    ):
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
        with patch(
            "app.api.user.profile.details.fetch_public_user",
            return_value={
                "id": USER_1,
                "is_active": True,
                "app_variant": "nexus",
                "special_category_consent_version": None,
            },
        ), pytest.raises(Exception):
            update_profile_details(
                request=mock_req,
                background_tasks=bg,
                payload=ProfileDetailsUpdate(display_sexuality="Queer"),
                user_id=USER_1,
                _device=None,
            )


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

    with (
        patch(
            "app.api.user.profile.details.user_module.supabase_client.table",
            return_value=mock_t,
        ),
        patch(
            "app.api.user.profile.details.supabase_client.table", return_value=mock_t,
        ),
        patch(
            "app.api.user.profile.details.fetch_public_user",
            return_value={
                "special_category_consent_version": "1.0",
                "special_category_consent_at": "2024-01-01",
            },
        ),
        patch(
            "app.api.user.profile.details.decrypt_profile_record",
            return_value=mock_profile,
        ),
        patch(
            "app.api.user.profile.details.user_module.decrypt_profile_record",
            return_value=mock_profile,
        ),
        patch(
            "app.api.user.profile.details._rolling_change_window_status",
            return_value=(0, True, None),
        ),
        patch("app.api.user.profile.details.sync_redis_client") as mock_r,
    ):
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
        res_patch = update_profile_details(
            mock_req, mock_bg, patch_payload, user_id=USER_1, _device=None,
        )
        assert res_patch["status"] == "success"


def test_api_user_settings_deep():
    from app.api.user.settings import (
        get_email_notification_settings,
        get_privacy_settings,
        update_email_notification_settings,
        update_privacy_settings,
    )
    from app.models import (
        EmailNotificationSettingsUpdate,
        PrivacySettingsUpdate,
    )

    mock_req = MagicMock()
    mock_settings_row: dict[str, Any] = {
        "hidden_profile_fields": ["hometown"],
        "share_active_status": True,
        "share_read_receipts": True,
        "email_notify_matches": True,
        "email_notify_messages": True,
        "email_notify_digest": False,
        "email_notify_product_updates": True,
        "email_notify_promotions": False,
    }
    mock_t = _make_chaining_mock([mock_settings_row])

    with patch("app.api.user.settings.supabase_client.table", return_value=mock_t):
        # Privacy GET & PATCH
        priv_get = get_privacy_settings(mock_req, _device=None, user_id=USER_1)
        assert priv_get.share_active_status is True

        priv_patch = update_privacy_settings(
            mock_req,
            PrivacySettingsUpdate(
                hidden_fields=["hometown"], share_active_status=False,
            ),
            _device=None,
            user_id=USER_1,
        )
        assert priv_patch is not None

        # Email Notifications GET & PATCH
        notif_get = get_email_notification_settings(
            mock_req, _device=None, user_id=USER_1,
        )
        assert notif_get.email_notify_matches is True

        notif_patch = update_email_notification_settings(
            mock_req,
            EmailNotificationSettingsUpdate(email_notify_digest=True),
            _device=None,
            user_id=USER_1,
        )
        assert notif_patch is not None


async def test_api_user_devices_and_passwordless_email():
    from app.api.user.devices import (
        register_device,
        unregister_device,
    )
    from app.core.auth.passwordless_email import (
        _scoped_auth_client,
        send_login_email_otp,
        verify_login_email_otp,
    )
    from app.models import RegisterDeviceRequest

    mock_req = MagicMock()
    mock_t = _make_chaining_mock(
        [{"id": "d1", "user_id": USER_1, "platform": "ios", "is_active": True}],
    )

    with patch("app.api.user.devices.supabase_client.table", return_value=mock_t):
        reg_req = RegisterDeviceRequest(
            fcm_token="fcm_token_1234567890",
            platform="ios",
            device_id="d1",
        )
        reg_res = await register_device(mock_req, reg_req, _device=None, user_id=USER_1)
        assert reg_res["success"] is True

        unreg_res = await unregister_device(
            mock_req, reg_req, _device=None, user_id=USER_1,
        )
        assert unreg_res["success"] is True

    with patch("app.core.auth.passwordless_email.create_client") as mock_cc:
        mock_auth = MagicMock()
        mock_cc.return_value.auth = mock_auth
        mock_auth.sign_in_with_otp.return_value = None
        mock_auth.verify_otp.return_value = MagicMock(
            session=MagicMock(access_token="tok"),
        )

        _scoped_auth_client()
        send_login_email_otp("a@b.com")
        res_ver = verify_login_email_otp("a@b.com", "123456")
        assert res_ver.session is not None


def test_user_profile_details_deep_branches():
    from app.api.user.profile.details import get_profile_details, update_profile_details
    from app.models import ProfileDetailsUpdate

    mock_req = MagicMock()
    bg = BackgroundTasks()

    # get_profile_details: 404 not found, 500 invalid structure, 500 generic exception
    with (
        patch("app.api.user.profile.details.supabase_client") as mock_sb,
        patch(
            "app.api.user.profile.details._rolling_change_window_status",
            return_value=(0, True, None),
        ),
    ):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        with pytest.raises(HTTPException, match="Profile not found"):
            get_profile_details(mock_req, _device=None, user_id=USER_1)

        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data="not-a-dict",
        )
        with pytest.raises(HTTPException, match="Invalid profile data structure"):
            get_profile_details(mock_req, _device=None, user_id=USER_1)

        mock_sb.table().select().eq().maybe_single().execute.side_effect = RuntimeError(
            "Fatal DB error",
        )
        with pytest.raises(HTTPException, match="Internal server error"):
            get_profile_details(mock_req, _device=None, user_id=USER_1)

    # update_profile_details: age change limit reached, profile not found, generic error
    mock_profile_row = {
        "name": "Alice",
        "age": 20,
        "campus_name": "MIT",
        "campus_year": 2024,
    }
    with (
        patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb,
        patch("app.api.user.profile.helpers.supabase_client"),
        patch(
            "app.api.user.profile.details._rolling_change_window_status",
            return_value=(0, True, None),
        ),
        patch(
            "app.api.user.profile.details.fetch_public_user",
            return_value={"id": USER_1, "is_active": True},
        ),
        patch(
            "app.api.user.profile.details.user_module.decrypt_profile_record",
            return_value=mock_profile_row,
        ),
        patch("app.api.user.profile.details._assert_no_decryption_failures"),
    ):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=mock_profile_row,
        )

        # apply_age_change age_change_limit_reached
        err_age_limit = APIError({"message": "age_change_limit_reached"})
        err_age_limit.message = "age_change_limit_reached"
        mock_sb.rpc.return_value.execute.side_effect = err_age_limit
        with pytest.raises(
            HTTPException, match="You've used both age changes allowed this year",
        ):
            update_profile_details(
                mock_req, bg, ProfileDetailsUpdate(age=25), user_id=USER_1, _device=None,
            )

        # apply_age_change profile_not_found
        err_not_found = APIError({"message": "profile_not_found"})
        err_not_found.message = "profile_not_found"
        mock_sb.rpc.return_value.execute.side_effect = err_not_found
        with pytest.raises(HTTPException, match="Profile not found"):
            update_profile_details(
                mock_req, bg, ProfileDetailsUpdate(age=25), user_id=USER_1, _device=None,
            )

        # apply_age_change generic APIError
        mock_sb.rpc.return_value.execute.side_effect = APIError({"message": "db_crash"})
        with pytest.raises(HTTPException, match="Internal server error"):
            update_profile_details(
                mock_req, bg, ProfileDetailsUpdate(age=25), user_id=USER_1, _device=None,
            )

        # apply_name_change name_change_limit_reached
        err_name_limit = APIError({"message": "name_change_limit_reached"})
        err_name_limit.message = "name_change_limit_reached"
        mock_sb.rpc.return_value.execute.side_effect = err_name_limit
        with pytest.raises(
            HTTPException, match="You've used both name changes allowed this year",
        ):
            update_profile_details(
                mock_req,
                bg,
                ProfileDetailsUpdate(name="Bobby"),
                user_id=USER_1,
                _device=None,
            )

        # apply_name_change profile_not_found
        mock_sb.rpc.return_value.execute.side_effect = err_not_found
        with pytest.raises(HTTPException, match="Profile not found"):
            update_profile_details(
                mock_req,
                bg,
                ProfileDetailsUpdate(name="Bobby"),
                user_id=USER_1,
                _device=None,
            )

        # apply_name_change generic APIError
        mock_sb.rpc.return_value.execute.side_effect = APIError({"message": "db_crash"})
        with pytest.raises(HTTPException, match="Internal server error"):
            update_profile_details(
                mock_req,
                bg,
                ProfileDetailsUpdate(name="Bobby"),
                user_id=USER_1,
                _device=None,
            )

        # update_data execute returns empty without conditional check -> 404
        mock_sb.rpc.return_value.execute.side_effect = None
        mock_sb.rpc.return_value.execute.return_value = MagicMock()
        mock_sb.table().update().eq().execute.return_value = MagicMock(data=[])
        with pytest.raises(HTTPException, match="Profile not found"):
            update_profile_details(
                mock_req,
                bg,
                ProfileDetailsUpdate(bio="New bio"),
                user_id=USER_1,
                _device=None,
            )


def test_api_user_settings_deep_p22():
    from app.api.user.settings import (
        get_email_notification_settings,
        get_privacy_settings,
        update_email_notification_settings,
        update_privacy_settings,
    )

    mock_req = MagicMock()

    # get_privacy_settings: 404 & 500
    with patch("app.api.user.settings.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        with pytest.raises(HTTPException, match="Profile not found"):
            get_privacy_settings(mock_req, _device=None, user_id=USER_1)

        mock_sb.table().select().eq().maybe_single().execute.side_effect = RuntimeError(
            "DB fail",
        )
        with pytest.raises(HTTPException, match="Internal server error"):
            get_privacy_settings(mock_req, _device=None, user_id=USER_1)

    # update_privacy_settings: no fields (400), not rows (404), exception (500)
    with pytest.raises(HTTPException, match="No fields to update"):
        update_privacy_settings(
            mock_req, PrivacySettingsUpdate(), _device=None, user_id=USER_1,
        )

    with patch("app.api.user.settings.supabase_client") as mock_sb:
        mock_sb.table().update().eq().select().execute.return_value = MagicMock(data=[])
        with pytest.raises(HTTPException, match="Profile not found"):
            update_privacy_settings(
                mock_req,
                PrivacySettingsUpdate(share_active_status=False),
                _device=None,
                user_id=USER_1,
            )

        mock_sb.table().update().eq().select().execute.side_effect = RuntimeError(
            "DB error",
        )
        with pytest.raises(HTTPException, match="Internal server error"):
            update_privacy_settings(
                mock_req,
                PrivacySettingsUpdate(share_active_status=False),
                _device=None,
                user_id=USER_1,
            )

    # get_email_notification_settings: 404 & 500
    with patch("app.api.user.settings.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        with pytest.raises(HTTPException, match="Profile not found"):
            get_email_notification_settings(mock_req, _device=None, user_id=USER_1)

        mock_sb.table().select().eq().maybe_single().execute.side_effect = RuntimeError(
            "DB fail",
        )
        with pytest.raises(HTTPException, match="Internal server error"):
            get_email_notification_settings(mock_req, _device=None, user_id=USER_1)

    # update_email_notification_settings: no fields (400), not rows (404), exception (500)
    with pytest.raises(HTTPException, match="No fields to update"):
        update_email_notification_settings(
            mock_req, EmailNotificationSettingsUpdate(), _device=None, user_id=USER_1,
        )

    with patch("app.api.user.settings.supabase_client") as mock_sb:
        mock_sb.table().update().eq().select().execute.return_value = MagicMock(data=[])
        with pytest.raises(HTTPException, match="Profile not found"):
            update_email_notification_settings(
                mock_req,
                EmailNotificationSettingsUpdate(email_notify_matches=False),
                _device=None,
                user_id=USER_1,
            )

        mock_sb.table().update().eq().select().execute.side_effect = RuntimeError(
            "DB error",
        )
        with pytest.raises(HTTPException, match="Internal server error"):
            update_email_notification_settings(
                mock_req,
                EmailNotificationSettingsUpdate(email_notify_matches=False),
                _device=None,
                user_id=USER_1,
            )


async def test_api_user_devices_deep():
    from app.api.user.devices import (
        _deactivate_device_token,
        _upsert_device_token,
        register_device,
        unregister_device,
    )

    mock_req = MagicMock()
    valid_fcm = "a" * 152

    # _upsert_device_token with prior deactivation exception
    with patch("app.api.user.devices.supabase_client") as mock_sb:
        mock_sb.table().update().eq().eq().neq().execute.side_effect = Exception(
            "deactivate error",
        )
        mock_sb.table().upsert().execute.return_value = MagicMock()
        _upsert_device_token(USER_1, valid_fcm, "android", "device-id-12345678")

    # _deactivate_device_token without device_id
    with patch("app.api.user.devices.supabase_client") as mock_sb:
        mock_sb.table().update().eq().eq().execute.return_value = MagicMock(
            data=[{"id": 1}],
        )
        res = _deactivate_device_token(USER_1, valid_fcm, None)
        assert res is True

    # register_device & unregister_device exception -> 503
    with patch(
        "app.api.user.devices._upsert_device_token", side_effect=Exception("DB fail"),
    ), pytest.raises(HTTPException, match="Service temporarily unavailable"):
        await register_device(
            mock_req,
            RegisterDeviceRequest(fcm_token=valid_fcm, platform="android"),
            _device=None,
            user_id=USER_1,
        )

    with patch(
        "app.api.user.devices._deactivate_device_token",
        side_effect=Exception("DB fail"),
    ), pytest.raises(HTTPException, match="Service temporarily unavailable"):
        await unregister_device(
            mock_req,
            RegisterDeviceRequest(fcm_token=valid_fcm, platform="android"),
            _device=None,
            user_id=USER_1,
        )


async def test_user_auth_otp_deep():
    from app.api.user.auth_otp import (
        _resolve_onboarding_profile_fields,
        _unhide_special_category_fields,
        _validate_auth_user_allowed,
        accept_terms,
        auth_bootstrap,
        complete_onboarding,
        get_attestation_status,
        request_account_phone_otp,
        request_login_by_phone,
        revoke_all_sessions,
        verify_account_phone_otp,
        verify_login_by_phone,
    )

    req = make_dummy_request()

    # _validate_auth_user_allowed: disposable email, unauthorized domain
    with patch("app.api.user.auth_otp.is_disposable_email", return_value=True):
        with pytest.raises(HTTPException) as exc:
            await _validate_auth_user_allowed("temp@trash.com", {})
        assert exc.value.status_code == 400

    with (
        patch("app.api.user.auth_otp.is_disposable_email", return_value=False),
        patch("app.api.user.auth_otp.is_allowed_email", return_value=False),
    ):
        with pytest.raises(HTTPException) as exc:
            await _validate_auth_user_allowed("user@outside.edu", {})
        assert exc.value.status_code == 400

    # auth_bootstrap: incomplete payload, welcome email send failure
    with pytest.raises(HTTPException) as exc:
        await auth_bootstrap(req, None, {})
    assert exc.value.status_code == 401

    with (
        patch("app.api.user.auth_otp._validate_auth_user_allowed"),
        patch("app.api.user.auth_otp.fetch_public_user", return_value=None),
        patch(
            "app.api.user.auth_otp.upsert_public_user",
            return_value=({"id": USER_1, "is_active": True}, True),
        ),
        patch("app.api.user.auth_otp.fetch_profile", return_value=None),
        patch("app.api.user.auth_otp.redis_client") as mock_redis,
        patch(
            "app.api.user.auth_otp.send_bootstrap_welcome_email",
            side_effect=Exception("SMTP fail"),
        ),
    ):
        mock_redis.set = AsyncMock(return_value=True)
        res = await auth_bootstrap(
            req, None, {"id": USER_1, "email": "test@nexus.test"},
        )
        assert res.user_id == USER_1

    # _resolve_onboarding_profile_fields MEC branch
    mec_payload = MECOnboardingRequest(
        app_variant="nexus_mec",
        age=20,
        campus_branch="CS",
        campus_year=3,
        campus_name="Model Engineering College",
    )
    with pytest.raises(HTTPException) as exc:
        _resolve_onboarding_profile_fields(mec_payload, None, {})
    assert exc.value.status_code == 400

    # complete_onboarding: variant mismatch & success
    nexus_payload = NexusOnboardingRequest(
        app_variant="nexus",
        age=25,
        name="User",
        demographic_bucket="M",
    )
    with (
        patch(
            "app.api.user.auth_otp.fetch_public_user",
            return_value={
                "id": USER_1,
                "app_variant": "nexus_mec",
                "accepted_terms_version": "1.0",
                "is_active": True,
            },
        ),
        patch("app.api.user.auth_otp.fetch_profile", return_value=None),
    ):
        with pytest.raises(HTTPException) as exc:
            await complete_onboarding(
                req, nexus_payload, None, {"id": USER_1, "email": "test@mec.ac.in"},
            )
        assert exc.value.status_code == 400

    with (
        patch(
            "app.api.user.auth_otp.fetch_public_user",
            return_value={
                "id": USER_1,
                "app_variant": "nexus",
                "accepted_terms_version": "1.0",
                "is_active": True,
            },
        ),
        patch("app.api.user.auth_otp.fetch_profile", return_value=None),
        patch(
            "app.api.user.auth_otp.upsert_profile_variant",
            return_value=({"id": USER_1, "name": "User"}, True),
        ),
    ):
        onboard_res = await complete_onboarding(
            req, nexus_payload, None, {"id": USER_1, "email": "test@nexus.test"},
        )
        assert onboard_res.user_id == USER_1

    # request_account_phone_otp & verify_account_phone_otp
    with patch("app.api.user.auth_otp.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(return_value=False)
        with pytest.raises(HTTPException) as exc:
            await request_account_phone_otp(
                req, AccountPhoneOtpRequestRequest(phone=PHONE_VALID), None, USER_1,
            )
        assert exc.value.status_code == 429

    with (
        patch(
            "app.api.user.auth_otp.verify_and_consume_hashed_otp",
            new_callable=AsyncMock,
        ),
        patch("app.api.user.auth_otp.set_verified_mobile"),
    ):
        ver_res = await verify_account_phone_otp(
            req,
            AccountPhoneOtpVerifyRequest(phone=PHONE_VALID, code="123456"),
            None,
            USER_1,
        )
        assert ver_res.verified is True

    # request_login_by_phone: rate limits, blocklisted, no user
    with patch("app.api.user.auth_otp.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(return_value=True)
        mock_redis.get = AsyncMock(return_value="5")
        with pytest.raises(HTTPException) as exc:
            await request_login_by_phone(
                req, LoginByPhoneRequestRequest(phone=PHONE_VALID), None,
            )
        assert exc.value.status_code == 429

        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.incr = AsyncMock(return_value=1)
        mock_redis.expire = AsyncMock()
        with (
            patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=True),
            patch("app.api.user.auth_otp.dummy_email_send_delay"),
        ):
            assert (
                await request_login_by_phone(
                    req, LoginByPhoneRequestRequest(phone=PHONE_VALID), None,
                )
            ).sent is True

    # verify_login_by_phone: blocklisted, user not found, auth session None
    with patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=True):
        with pytest.raises(HTTPException) as exc:
            await verify_login_by_phone(
                req, LoginByPhoneVerifyRequest(phone=PHONE_VALID, code="123456"), None,
            )
        assert exc.value.status_code == 400

    with (
        patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=False),
        patch("app.api.user.auth_otp.find_user_id_by_phone", return_value=None),
    ):
        with pytest.raises(HTTPException) as exc:
            await verify_login_by_phone(
                req, LoginByPhoneVerifyRequest(phone=PHONE_VALID, code="123456"), None,
            )
        assert exc.value.status_code == 400

    with (
        patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=False),
        patch("app.api.user.auth_otp.find_user_id_by_phone", return_value=USER_1),
        patch(
            "app.api.user.auth_otp.get_user_email_by_id",
            return_value="alice@nexus.test",
        ),
        patch(
            "app.api.user.auth_otp.fetch_public_user",
            return_value={"id": USER_1, "is_active": True},
        ),
        patch(
            "app.api.user.auth_otp.verify_login_email_otp",
            return_value=MagicMock(session=None),
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await verify_login_by_phone(
                req, LoginByPhoneVerifyRequest(phone=PHONE_VALID, code="123456"), None,
            )
        assert exc.value.status_code == 400

    # _unhide_special_category_fields
    with patch("app.api.user.auth_otp.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data={"hidden_profile_fields": ["display_sexuality", "hometown"]},
        )
        mock_sb.table().update().eq().execute.return_value = MagicMock()
        _unhide_special_category_fields(USER_1)

    # accept_terms: declined general, declined guidelines, success
    from app.core.config import settings

    tv = settings.current_terms_version
    consent_req_general_declined = ConsentUpdateRequest(
        terms_version=tv, general_accepted=False, community_guidelines_accepted=True,
    )
    with (
        patch(
            "app.api.user.auth_otp.fetch_public_user",
            return_value={"id": USER_1, "is_active": True},
        ),
        patch("app.api.user.auth_otp.update_user_terms"),
        patch("app.api.user.auth_otp.update_community_guidelines_consent"),
    ):
        with pytest.raises(HTTPException) as exc:
            await accept_terms(
                req,
                consent_req_general_declined,
                None,
                {"id": USER_1, "email": "alice@nexus.test"},
            )
        assert exc.value.status_code == 400

    consent_req_guidelines_declined = ConsentUpdateRequest(
        terms_version=tv, general_accepted=True, community_guidelines_accepted=False,
    )
    with (
        patch(
            "app.api.user.auth_otp.fetch_public_user",
            return_value={"id": USER_1, "is_active": True},
        ),
        patch("app.api.user.auth_otp.update_user_terms"),
        patch("app.api.user.auth_otp.update_community_guidelines_consent"),
    ):
        with pytest.raises(HTTPException) as exc:
            await accept_terms(
                req,
                consent_req_guidelines_declined,
                None,
                {"id": USER_1, "email": "alice@nexus.test"},
            )
        assert exc.value.status_code == 400

    consent_req_ok = ConsentUpdateRequest(
        terms_version=tv,
        general_accepted=True,
        community_guidelines_accepted=True,
        special_category_accepted=True,
        safety_data_accepted=True,
    )
    with (
        patch(
            "app.api.user.auth_otp.fetch_public_user",
            return_value={"id": USER_1, "is_active": True},
        ),
        patch(
            "app.api.user.auth_otp.update_user_terms",
            return_value=(tv, datetime.now(timezone.utc)),
        ),
        patch("app.api.user.auth_otp.update_community_guidelines_consent"),
        patch(
            "app.api.user.auth_otp.update_special_category_consent",
            return_value=(tv, datetime.now(timezone.utc)),
        ),
        patch("app.api.user.auth_otp._unhide_special_category_fields"),
        patch(
            "app.api.user.auth_otp.update_safety_data_consent",
            return_value=(tv, datetime.now(timezone.utc)),
        ),
        patch("app.api.user.auth_otp.redis_client"),
    ):
        res = await accept_terms(
            req, consent_req_ok, None, {"id": USER_1, "email": "alice@nexus.test"},
        )
        assert res.user_id == USER_1

    # revoke_all_sessions & get_attestation_status
    with (
        patch("app.api.user.auth_otp.supabase_client") as mock_sb,
        patch("app.api.user.auth_otp.redis_client"),
    ):
        mock_sb.auth.admin.sign_out.side_effect = Exception("fail")
        mock_sb.table().update().eq().execute.side_effect = Exception("fail")
        res = await revoke_all_sessions(req, None, USER_1)
        assert res == {"success": True}

    att = await get_attestation_status(
        req,
        {
            "app_id": "com.nexus",
            "iss": "Firebase",
            "iat": 1234,
            "exp": 5678,
            "aud": "aud",
        },
    )
    assert att.verified is True
    assert att.appCheck is True


def test_api_user_profile_details_deep_p27():
    from app.api.user.profile.details import update_profile_details

    req = make_dummy_request()
    bg = BackgroundTasks()

    # special category consent row None
    with (
        patch(
            "app.api.user.profile.details._sets_special_category_data",
            return_value=True,
        ),
        patch("app.api.user.profile.details.fetch_public_user", return_value=None),
    ):
        with pytest.raises(HTTPException) as exc:
            update_profile_details(
                req,
                bg,
                ProfileDetailsUpdate(display_sexuality="Straight / Heterosexual"),
                USER_1,
                None,
            )
        assert exc.value.status_code == 404

    # profile fetch exception & profile None
    with patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.side_effect = Exception(
            "DB error",
        )
        with pytest.raises(HTTPException) as exc:
            update_profile_details(
                req, bg, ProfileDetailsUpdate(name="Alex"), USER_1, None,
            )
        assert exc.value.status_code == 500

        mock_sb.table().select().eq().maybe_single().execute.side_effect = None
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        with pytest.raises(HTTPException) as exc:
            update_profile_details(
                req, bg, ProfileDetailsUpdate(name="Alex"), USER_1, None,
            )
        assert exc.value.status_code == 404

    # institute name < 3 letters
    valid_profile = {
        "id": USER_1,
        "name": "Current",
        "age": 22,
        "campus_name": "MIT",
        "campus_year": 2,
    }
    with (
        patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb,
        patch(
            "app.api.user.profile.details.user_module.decrypt_profile_record",
            return_value=valid_profile,
        ),
        patch("app.api.user.profile.details._assert_no_decryption_failures"),
    ):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=valid_profile,
        )
        p_invalid_campus = ProfileDetailsUpdate.model_construct(campus_name="AB")
        with pytest.raises(HTTPException) as exc:
            update_profile_details(req, bg, p_invalid_campus, USER_1, None)
        assert exc.value.status_code == 400

    # name rolling window ineligible
    with (
        patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb,
        patch(
            "app.api.user.profile.details.user_module.decrypt_profile_record",
            return_value=valid_profile,
        ),
        patch("app.api.user.profile.details._assert_no_decryption_failures"),
        patch("app.api.user.profile.details.validate_display_name"),
        patch(
            "app.api.user.profile.details._rolling_change_window_status",
            return_value=(2, False, None),
        ),
    ):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=valid_profile,
        )
        with pytest.raises(HTTPException) as exc:
            update_profile_details(
                req, bg, ProfileDetailsUpdate(name="BrandNew"), USER_1, None,
            )
        assert exc.value.status_code == 403

    # age > max_age for variant & age rolling window ineligible
    with (
        patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb,
        patch(
            "app.api.user.profile.details.user_module.decrypt_profile_record",
            return_value=valid_profile,
        ),
        patch("app.api.user.profile.details._assert_no_decryption_failures"),
        patch(
            "app.api.user.profile.details.fetch_public_user",
            return_value={"app_variant": "nexus_mec"},
        ),
    ):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=valid_profile,
        )
        with pytest.raises(HTTPException) as exc:
            update_profile_details(req, bg, ProfileDetailsUpdate(age=29), USER_1, None)
        assert exc.value.status_code == 400

    with (
        patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb,
        patch(
            "app.api.user.profile.details.user_module.decrypt_profile_record",
            return_value=valid_profile,
        ),
        patch("app.api.user.profile.details._assert_no_decryption_failures"),
        patch(
            "app.api.user.profile.details.fetch_public_user",
            return_value={"app_variant": "nexus"},
        ),
        patch(
            "app.api.user.profile.details._rolling_change_window_status",
            return_value=(2, False, None),
        ),
    ):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=valid_profile,
        )
        with pytest.raises(HTTPException) as exc:
            update_profile_details(req, bg, ProfileDetailsUpdate(age=25), USER_1, None)
        assert exc.value.status_code == 403

    # Tab activation: incomplete missing fields & tab deactivations
    incomplete_profile = {
        "id": USER_1,
        "name": "Current",
        "age": 22,
        "is_dating_active": False,
    }
    with (
        patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb,
        patch(
            "app.api.user.profile.details.user_module.decrypt_profile_record",
            return_value=incomplete_profile,
        ),
        patch("app.api.user.profile.details._assert_no_decryption_failures"),
        patch(
            "app.api.user.profile.details._validate_tab_activation",
            return_value=["dating_for"],
        ),
    ):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=incomplete_profile,
        )
        with pytest.raises(HTTPException) as exc:
            update_profile_details(
                req, bg, ProfileDetailsUpdate(is_dating_active=True), USER_1, None,
            )
        assert exc.value.status_code == 400

    # Deactivating tabs successfully
    with (
        patch("app.api.user.profile.details.user_module.supabase_client") as mock_sb,
        patch(
            "app.api.user.profile.details.user_module.decrypt_profile_record",
            return_value=valid_profile,
        ),
        patch("app.api.user.profile.details._assert_no_decryption_failures"),
    ):
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=valid_profile,
        )
        mock_sb.table().update().eq().execute.return_value = MagicMock(
            data=[{"id": USER_1}],
        )
        res_deact = update_profile_details(
            req,
            bg,
            ProfileDetailsUpdate(
                is_dating_active=False,
                is_friends_active=False,
                is_professional_active=False,
            ),
            USER_1,
            None,
        )
        assert res_deact["status"] == "success"


async def test_api_dependencies() -> None:
    # Bearer tokens
    creds_valid = HTTPAuthorizationCredentials(
        scheme="Bearer", credentials="jwt-token-xyz",
    )
    creds_invalid = HTTPAuthorizationCredentials(scheme="Basic", credentials="xyz")
    assert get_bearer_token(creds_valid) == "jwt-token-xyz"
    assert get_optional_bearer_token(creds_valid) == "jwt-token-xyz"
    assert get_optional_bearer_token(None) is None
    assert get_optional_bearer_token(creds_invalid) is None
    with pytest.raises(HTTPException):
        get_bearer_token(None)
    with pytest.raises(HTTPException):
        get_bearer_token(creds_invalid)

    # User identity & status checks
    assert await get_authenticated_user_id(payload={"sub": USER_1}) == USER_1
    assert await get_optional_authenticated_user_id(token=None) is None

    # assert_account_active
    active_u = {
        "id": USER_1,
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": None,
        "purged_at": None,
    }
    assert_account_active(active_u)

    with pytest.raises(HTTPException):
        assert_account_active({**active_u, "is_active": False})
    with pytest.raises(HTTPException):
        assert_account_active({**active_u, "is_suspended": True})
    with pytest.raises(HTTPException):
        assert_account_active(
            {**active_u, "deletion_requested_at": "2026-08-25T00:00:00Z"},
        )

    # Special category & safety consent
    now = datetime.now(timezone.utc)
    u_consent = {
        "id": USER_1,
        "special_category_consent_version": "2.0.0",
        "special_category_consent_at": now.isoformat(),
        "safety_data_consent_version": "2.0.0",
        "safety_data_consent_at": now.isoformat(),
    }
    with (
        patch("app.api.dependencies.settings.current_terms_version", "2.0.0"),
        patch(
            "app.api.dependencies.get_cached_public_user",
            AsyncMock(return_value=u_consent),
        ),
    ):
        assert_special_category_consent(u_consent)
        assert_safety_consent(u_consent)
        assert await require_safety_consent(user_id=USER_1) == USER_1


def test_api_profile_details_and_helpers() -> None:
    # Helper validators
    _assert_no_decryption_failures({"name": "Alice"})
    with pytest.raises(HTTPException):
        _assert_no_decryption_failures({"name": "__DECRYPTION_FAILED__"})

    assert (
        _sets_special_category_data(ProfileDetailsUpdate(religious_beliefs="Agnostic"))
        is True
    )
    assert _sets_special_category_data(ProfileDetailsUpdate(bio="Hello")) is False

    imgs = _build_ordered_images({"profile_pic": "p1.jpg", "normal_pics": ["p2.jpg"]})
    assert len(imgs) == 2

    # Activations
    valid_common = {
        "name": "Alice",
        "age": 22,
        "sub_interests": {"tech": ["python", "fastapi"]},
        "profile_pic": "p1.jpg",
        "normal_pics": ["p2.jpg"],
        "bio": "Hello",
    }
    missing_list: list[str] = []
    _validate_common_activation(valid_common, ProfileDetailsUpdate(), missing_list)
    assert len(missing_list) == 0

    _validate_dating_activation(
        {**valid_common, "dating_target_buckets": ["men"]},
        ProfileDetailsUpdate(),
        missing_list,
    )
    _validate_friends_activation(
        {**valid_common, "friends_target_buckets": ["all"]},
        ProfileDetailsUpdate(),
        missing_list,
    )
    _validate_professional_activation(
        {
            **valid_common,
            "professional_target_buckets": ["tech"],
            "role_at": "Nexus",
            "role_type": "Eng",
        },
        ProfileDetailsUpdate(),
        missing_list,
    )

    # GET profile details
    mock_table = _make_chaining_mock(
        {
            "id": USER_1,
            "name": encrypt_to_hex("Alice"),
            "age": 22,
            "is_dating_active": True,
        },
    )
    mock_request = MagicMock()
    with (
        patch(
            "app.api.user.profile.details.supabase_client.table",
            return_value=mock_table,
        ),
        patch(
            "app.api.user.profile.details._rolling_change_window_status",
            return_value=(0, True, None),
        ),
    ):
        det = get_profile_details(mock_request, _device=None, user_id=USER_1)
        assert det is not None

    # GET derived signals
    with patch(
        "app.api.user.profile.details.supabase_client.table", return_value=mock_table,
    ):
        sig = get_profile_derived_signals(mock_request, _device=None, user_id=USER_1)
        assert sig is not None

    # PATCH profile details
    patch_req = ProfileDetailsUpdate(bio="New bio", drinking="Socially")
    bg = MagicMock()
    with (
        patch(
            "app.api.user.profile.details.supabase_client.table",
            return_value=mock_table,
        ),
        patch(
            "app.api.user.profile.details.fetch_public_user",
            return_value={"id": USER_1, "is_active": True},
        ),
        patch("app.api.user.profile.details.sync_redis_client"),
    ):
        up_res = update_profile_details(
            request=mock_request,
            background_tasks=bg,
            payload=patch_req,
            user_id=USER_1,
            _device=None,
        )
        assert up_res is not None


async def test_api_user_auth_otp() -> None:
    mock_request = MagicMock()
    mock_table = _make_chaining_mock(
        [
            {
                "id": USER_1,
                "is_active": True,
                "accepted_terms_version": settings.current_terms_version,
            },
        ],
    )
    now = datetime.now(timezone.utc)

    # Auth bootstrap
    with (
        patch("app.api.user.auth_otp.supabase_client.table", return_value=mock_table),
        patch("app.api.user.auth_otp.redis_client", AsyncMock()),
        patch(
            "app.api.user.auth_otp.get_user_email_by_id",
            return_value="student@berkeley.edu",
        ),
        patch("app.api.user.auth_otp.is_allowed_email", return_value=True),
    ):
        boot = await auth_bootstrap(
            mock_request,
            _device=None,
            auth_user={"id": USER_1, "email": "student@berkeley.edu"},
        )
        assert boot is not None

    # Account phone OTP request & verify
    with (
        patch("app.api.user.auth_otp.redis_client", AsyncMock()),
        patch("app.api.user.auth_otp.is_phone_blocklisted", return_value=False),
        patch("app.api.user.auth_otp.find_user_id_by_phone", return_value=None),
        patch("app.api.user.auth_otp.send_sms", AsyncMock(return_value=True)),
    ):
        p_req = await request_account_phone_otp(
            mock_request,
            AccountPhoneOtpRequestRequest(phone="+14155552671"),
            _device=None,
            user_id=USER_1,
        )
        assert p_req.sent is True

        with (
            patch(
                "app.api.user.auth_otp.verify_and_consume_hashed_otp",
                AsyncMock(return_value=True),
            ),
            patch("app.api.user.auth_otp.set_verified_mobile"),
        ):
            p_ver = await verify_account_phone_otp(
                mock_request,
                AccountPhoneOtpVerifyRequest(phone="+14155552671", code="123456"),
                _device=None,
                user_id=USER_1,
            )
            assert p_ver.verified is True

    # Accept terms
    with (
        patch("app.api.user.auth_otp.supabase_client.table", return_value=mock_table),
        patch(
            "app.api.user.auth_otp.update_user_terms",
            return_value=(settings.current_terms_version, now),
        ),
        patch(
            "app.api.user.auth_otp.update_community_guidelines_consent",
            return_value=(settings.current_terms_version, now),
        ),
        patch(
            "app.api.user.auth_otp.update_special_category_consent",
            return_value=(settings.current_terms_version, now),
        ),
        patch(
            "app.api.user.auth_otp.update_safety_data_consent",
            return_value=(settings.current_terms_version, now),
        ),
        patch(
            "app.api.user.auth_otp.fetch_public_user",
            return_value={
                "id": USER_1,
                "is_active": True,
                "accepted_terms_version": settings.current_terms_version,
            },
        ),
    ):
        t_res = await accept_terms(
            mock_request,
            ConsentUpdateRequest(
                terms_version=settings.current_terms_version,
                general_accepted=True,
                community_guidelines_accepted=True,
                special_category_accepted=True,
                safety_data_accepted=True,
            ),
            _device=None,
            auth_user={"id": USER_1, "email": "student@berkeley.edu"},
        )
        assert t_res.user_id == USER_1
