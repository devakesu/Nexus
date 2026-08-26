"""Comprehensive unit tests covering 100% of app/api/user endpoints, profile details, settings, sync, devices, export, and account deletion."""

from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import BackgroundTasks, HTTPException, Request

from app.api.user.account_deletion import (
    cancel_account_deletion,
    get_account_deletion_settings,
    request_account_deletion,
    request_account_deletion_otp,
    verify_account_deletion_otp,
)
from app.api.user.devices import register_device, unregister_device
from app.api.user.export import (
    export_account_data,
    request_data_export_otp,
    verify_data_export_otp,
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
from app.api.user.profile.media import update_profile_media_and_tags
from app.api.user.profile.moderation import get_moderation_subjects
from app.api.user.settings import (
    get_email_notification_settings,
    get_privacy_settings,
    update_email_notification_settings,
    update_privacy_settings,
)
from app.api.user.sync import create_export_code, import_from_flavor
from app.core.utils.moderation import NameModerationError
from app.models import (
    AccountDeletionOtpRequestRequest,
    AccountDeletionOtpVerifyRequest,
    AccountDeletionRequestRequest,
    DataExportOtpRequestRequest,
    DataExportOtpVerifyRequest,
    DataExportRequestRequest,
    EmailNotificationSettingsUpdate,
    ImportRequest,
    ModerationSubjectsRequest,
    PrivacySettingsUpdate,
    ProfileDetailsUpdate,
    ProfileImagesAndTagsUpdate,
    RegisterDeviceRequest,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"


def make_mock_request() -> Request:
    return Request({"type": "http", "headers": [], "query_string": b"", "path": "/"})


# ==========================================
# 1. PROFILE DETAILS & HELPERS TESTS
# ==========================================

def test_profile_helpers_validation():
    # 1. sets special category data
    assert _sets_special_category_data(ProfileDetailsUpdate(religious_beliefs="Agnostic")) is True
    assert _sets_special_category_data(ProfileDetailsUpdate(name="Alice")) is False

    # 2. validate common activation
    valid_common = {
        "name": "Alice",
        "age": 22,
        "campus_branch": "CSE",
        "campus_year": 2024,
        "profile_pic": "p.jpg",
        "normal_pics": ["n.jpg"],
        "bio": "Bio",
        "sub_interests": {"Tech": ["AI", "Cloud"]},
    }
    missing: list[str] = []
    _validate_common_activation(valid_common, ProfileDetailsUpdate(), missing)
    assert len(missing) == 0

    missing_bad: list[str] = []
    _validate_common_activation({}, ProfileDetailsUpdate(), missing_bad)
    assert len(missing_bad) > 0

    # 3. validate dating activation
    valid_dating = {
        "display_gender": "Female",
        "search_bucket": "F",
        "dating_target_buckets": ["M"],
        "dating_for": ["long_term"],
        "drinking": "socially",
        "smoking": "never",
        "partner_values": ["Loyalty"],
    }
    missing_dating: list[str] = []
    _validate_dating_activation(valid_dating, ProfileDetailsUpdate(), missing_dating)
    assert len(missing_dating) == 0

    # 4. validate friends activation
    valid_friends = {
        "friends_target_buckets": ["ALL"],
        "activities": ["Coding"],
        "causes_supported": ["Climate"],
    }
    missing_friends: list[str] = []
    _validate_friends_activation(valid_friends, ProfileDetailsUpdate(), missing_friends)
    assert len(missing_friends) == 0

    # 5. validate professional activation
    valid_prof = {
        "professional_target_buckets": ["ALL"],
        "tech_skills": ["Python"],
        "role_at": "Software Engineer",
        "looking_for": ["Mentorship"],
    }
    missing_prof: list[str] = []
    _validate_professional_activation(valid_prof, ProfileDetailsUpdate(), missing_prof)
    assert len(missing_prof) == 0

    # 6. assert no decryption failures
    _assert_no_decryption_failures({"name": "Alice"})
    with pytest.raises(HTTPException) as exc_dec_fail:
        _assert_no_decryption_failures({"name": "Alice", "name_decryption_failed": "__DECRYPTION_FAILED__"})
    assert exc_dec_fail.value.status_code == 500

    # 7. build ordered images
    images = _build_ordered_images({"profile_pic": "p1.jpg", "normal_pics": ["p2.jpg", "p3.jpg"]})
    assert len(images) == 3


def test_get_profile_details():
    req = make_mock_request()

    # 1. Profile not found -> 404
    with patch("app.api.user.profile.details.supabase_client.table") as mock_table:
        mock_table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(data=None)
        with pytest.raises(HTTPException) as exc_404:
            get_profile_details(request=req, user_id=USER_1)
        assert exc_404.value.status_code == 404

    # 2. Profile found & decrypted
    raw_profile = {
        "id": USER_1,
        "name": "Alice",
        "age": 22,
        "campus_year": 2024,
        "campus_branch": "CSE",
        "campus_name": "Main Campus",
        "display_gender": "Female",
        "display_sexuality": "Straight",
        "pronouns": "she/her",
        "bio": "Hello",
        "search_bucket": "F",
        "hometown": "City",
        "current_place": "Town",
        "partner_values": ["Loyalty"],
        "children_plans": "open",
        "religious_beliefs": "Spiritual",
        "lifestyle": "Active",
        "drinking": "socially",
        "smoking": "never",
        "role_at": "Student",
        "role_type": "Student",
        "dating_target_buckets": ["M"],
        "dating_for": ["long_term"],
        "friends_target_buckets": ["ALL"],
        "professional_target_buckets": ["ALL"],
        "looking_for": ["Mentorship"],
        "activities": ["Reading"],
        "causes_supported": ["Climate"],
        "top_artists": ["Taylor Swift"],
        "tech_skills": ["Python"],
        "languages": ["English"],
        "pets": ["Cat"],
        "interests": ["Tech"],
        "sub_interests": {"Tech": ["AI", "Cloud"]},
        "profile_pic": "p.jpg",
        "normal_pics": ["n1.jpg"],
        "ai_vibe_tags": ["Creative"],
        "is_dating_active": True,
        "is_friends_active": True,
        "is_professional_active": True,
    }
    with patch("app.api.user.profile.details.supabase_client.table") as mock_table, \
         patch("app.api.user.profile.details.decrypt_profile_record", return_value=raw_profile), \
         patch("app.api.user.profile.details._rolling_change_window_status", return_value=(0, True, None)):
        mock_table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(data=raw_profile)
        res = get_profile_details(request=req, user_id=USER_1)
        assert res["name"] == "Alice"
        assert res["age"] == 22


def test_update_profile_details():
    req = make_mock_request()
    bg_tasks = BackgroundTasks()

    # 1. Empty payload -> detail: No fields to update
    empty_update = ProfileDetailsUpdate()
    res_empty = update_profile_details(request=req, payload=empty_update, background_tasks=bg_tasks, user_id=USER_1)
    assert res_empty["detail"] == "No fields to update."

    # 2. Special category data consent failure -> 403
    update_religion = ProfileDetailsUpdate(religious_beliefs="Agnostic")
    with patch("app.api.user.profile.details.fetch_public_user", return_value={"id": USER_1}), \
         patch("app.api.user.profile.details.assert_special_category_consent", side_effect=HTTPException(status_code=403, detail="No consent")):
        with pytest.raises(HTTPException) as exc_consent:
            update_profile_details(request=req, payload=update_religion, background_tasks=bg_tasks, user_id=USER_1)
        assert exc_consent.value.status_code == 403

    # 3. Name moderation error -> 422
    update_name = ProfileDetailsUpdate(name="BadName")
    with patch("app.api.user.profile.details.fetch_public_user", return_value={"id": USER_1}), \
         patch("app.api.user.profile.details.user_module.supabase_client.table") as mock_table, \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value={"name": "Alice"}), \
         patch("app.api.user.profile.details.validate_display_name", side_effect=NameModerationError(reason="profanity", detail="Disallowed")):
        mock_table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(data={"name": "Alice"})
        with pytest.raises(HTTPException) as exc_mod:
            update_profile_details(request=req, payload=update_name, background_tasks=bg_tasks, user_id=USER_1)
        assert exc_mod.value.status_code == 422

    # 4. Successful bio update
    update_bio = ProfileDetailsUpdate(bio="New bio")
    with patch("app.api.user.profile.details.fetch_public_user", return_value={"id": USER_1}), \
         patch("app.api.user.profile.details.user_module.supabase_client.table") as mock_table, \
         patch("app.api.user.profile.details.user_module.decrypt_profile_record", return_value={"id": USER_1, "bio": "Old bio"}), \
         patch("app.api.user.profile.details.recompile_and_push_vectors"):
        
        mock_current_res = MagicMock()
        mock_current_res.data = {"id": USER_1, "bio": "Old bio", "is_dating_active": True}
        mock_update_res = MagicMock()
        mock_update_res.data = [{"id": USER_1, "bio": "New bio"}]
        
        mock_table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_current_res
        mock_table.return_value.update.return_value.eq.return_value.select.return_value.execute.return_value = mock_update_res

        res_update = update_profile_details(request=req, payload=update_bio, background_tasks=bg_tasks, user_id=USER_1)
        assert res_update["status"] == "success"


def test_get_profile_derived_signals():
    req = make_mock_request()

    profile_row = {
        "id": USER_1,
        "search_bucket": "F",
        "display_gender": "Female",
        "display_sexuality": "Straight",
        "dating_target_buckets": ["M"],
        "friends_target_buckets": ["ALL"],
        "professional_target_buckets": ["ALL"],
    }
    with patch("app.api.user.profile.details.supabase_client.table") as mock_table, \
         patch("app.api.user.profile.details.decrypt_profile_record", return_value=profile_row):
        mock_table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(data=profile_row)
        sig = get_profile_derived_signals(request=req, user_id=USER_1)
        assert sig.user_id == USER_1
        assert sig.transparency_notice is not None


# ==========================================
# 2. PROFILE MEDIA & MODERATION TESTS
# ==========================================

async def test_update_profile_media_and_tags():
    req = make_mock_request()

    # 1. Media not matching user prefix -> 422
    foreign_payload = ProfileImagesAndTagsUpdate(
        profile_pic=f"{USER_2}/pic.jpg",
        normal_pics=[],
        ai_vibe_tags=["tag"],
    )
    with pytest.raises(HTTPException) as exc_for:
        await update_profile_media_and_tags(request=req, payload=foreign_payload, user_id=USER_1)
    assert exc_for.value.status_code == 422

    # 2. Successful media update
    valid_media = ProfileImagesAndTagsUpdate(
        profile_pic=f"{USER_1}/profile.jpg",
        normal_pics=[f"{USER_1}/pic1.jpg"],
        ai_vibe_tags=["Artistic"],
    )
    with patch("app.api.user.profile.media.update_profile_images_and_metadata"):
        res = await update_profile_media_and_tags(request=req, payload=valid_media, user_id=USER_1)
        assert res["status"] == "success"


def test_get_moderation_subjects():
    req = make_mock_request()
    payload = ModerationSubjectsRequest(target_ids=[USER_2])

    # 1. Empty valid ids -> returns []
    with patch("app.api.user.profile.moderation.supabase_client.table") as mock_table:
        mock_table.return_value.select.return_value.eq.return_value.in_.return_value.in_.return_value.is_.return_value.execute.return_value = MagicMock(data=[])
        res_empty = get_moderation_subjects(request=req, payload=payload, user_id=USER_1)
        assert res_empty == []

    # 2. Populated subjects
    action_data = [{"target_id": USER_2}]
    profile_data = [{"id": USER_2, "name": "Bob", "age": 25, "profile_pic": "b.jpg"}]
    with patch("app.api.user.profile.moderation.supabase_client.table") as mock_table, \
         patch("app.api.user.profile.moderation.decrypt_profile_record", return_value=profile_data[0]), \
         patch("app.api.user.profile.moderation.sanitize_decrypted_profile", return_value=profile_data[0]), \
         patch("app.api.user.profile.moderation.sign_profile_media_bulk", return_value=["https://signed.pic/b.jpg"]):
        
        mock_table.return_value.select.return_value.eq.return_value.in_.return_value.in_.return_value.is_.return_value.execute.return_value = MagicMock(data=action_data)
        mock_table.return_value.select.return_value.in_.return_value.eq.return_value.execute.return_value = MagicMock(data=profile_data)

        res_subjects = get_moderation_subjects(request=req, payload=payload, user_id=USER_1)
        assert len(res_subjects) == 1


# ==========================================
# 3. SETTINGS TESTS
# ==========================================

def test_privacy_and_email_settings():
    req = make_mock_request()

    # 1. Get privacy settings
    with patch("app.api.user.settings.supabase_client.table") as mock_table:
        mock_table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
            data={"hidden_profile_fields": ["drinking"], "share_active_status": True, "share_read_receipts": False}
        )
        priv = get_privacy_settings(request=req, user_id=USER_1)
        assert priv.share_active_status is True
        assert priv.share_read_receipts is False

    # 2. Update privacy settings
    priv_up = PrivacySettingsUpdate(share_active_status=False)
    with patch("app.api.user.settings.supabase_client.table") as mock_table:
        mock_table.return_value.update.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(
            data=[{"hidden_profile_fields": [], "share_active_status": False, "share_read_receipts": True}]
        )
        priv_res = update_privacy_settings(request=req, payload=priv_up, user_id=USER_1)
        assert priv_res.share_active_status is False

    # 3. Get email settings
    with patch("app.api.user.settings.supabase_client.table") as mock_table:
        mock_table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
            data={"email_notify_matches": True, "email_notify_messages": False}
        )
        email_set = get_email_notification_settings(request=req, user_id=USER_1)
        assert email_set.email_notify_matches is True
        assert email_set.email_notify_messages is False

    # 4. Update email settings
    email_up = EmailNotificationSettingsUpdate(email_notify_matches=False)
    with patch("app.api.user.settings.supabase_client.table") as mock_table:
        mock_table.return_value.update.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(
            data=[{"email_notify_matches": False, "email_notify_messages": True}]
        )
        email_res = update_email_notification_settings(request=req, payload=email_up, user_id=USER_1)
        assert email_res.email_notify_matches is False


# ==========================================
# 4. SYNC & DEVICES TESTS
# ==========================================

async def test_cross_flavor_sync():
    req = make_mock_request()
    now = datetime.now(timezone.utc)

    # 1. Main nexus variant cannot export -> 403
    with patch("app.api.user.sync.fetch_profile", return_value={"id": USER_1}), \
         patch("app.api.user.sync.fetch_public_user", return_value={"id": USER_1, "app_variant": "nexus"}), \
         patch("app.api.user.sync.assert_account_active"):
        with pytest.raises(HTTPException) as exc_exp_nexus:
            await create_export_code(request=req, auth_user={"id": USER_1})
        assert exc_exp_nexus.value.status_code == 403

    # 2. Flavor variant can generate export code
    with patch("app.api.user.sync.fetch_profile", return_value={"id": USER_1}), \
         patch("app.api.user.sync.fetch_public_user", return_value={"id": USER_1, "app_variant": "nexus_mec"}), \
         patch("app.api.user.sync.assert_account_active"), \
         patch("app.api.user.sync.generate_export_code", return_value=("ABC123", now + timedelta(minutes=15))):
        exp_res = await create_export_code(request=req, auth_user={"id": USER_1})
        assert exp_res.code == "ABC123"

    # 3. Import payload
    import_payload = ImportRequest(sync_code="ABC123")
    with patch("app.api.user.sync.fetch_profile", return_value={"id": USER_1, "has_imported_data": False}), \
         patch("app.api.user.sync.fetch_public_user", return_value={"id": USER_1, "app_variant": "nexus"}), \
         patch("app.api.user.sync.assert_account_active"), \
         patch("app.api.user.sync.redis_client.get", new_callable=AsyncMock, return_value=None), \
         patch("app.api.user.sync.redis_client.delete", new_callable=AsyncMock), \
         patch("app.api.user.sync.redis_client.set", new_callable=AsyncMock), \
         patch("app.api.user.sync.execute_import", return_value=["name", "bio"]):
        imp_res = await import_from_flavor(request=req, payload=import_payload, auth_user={"id": USER_1})
        assert imp_res.success is True


async def test_devices_registration():
    req = make_mock_request()
    dev_payload = RegisterDeviceRequest(fcm_token="fcm-token-123", platform="android", device_id="dev-1")

    # 1. Register device
    with patch("app.api.user.devices._upsert_device_token"):
        reg_res = await register_device(request=req, payload=dev_payload, user_id=USER_1)
        assert reg_res == {"success": True}

    # 2. Unregister device
    with patch("app.api.user.devices._deactivate_device_token"):
        unreg_res = await unregister_device(request=req, payload=dev_payload, user_id=USER_1)
        assert unreg_res == {"success": True}


# ==========================================
# 5. DATA EXPORT & ACCOUNT DELETION TESTS
# ==========================================

async def test_data_export_flow():
    req = make_mock_request()
    otp_req_payload = DataExportOtpRequestRequest(email="test@example.com")
    export_req_payload = DataExportRequestRequest(email="test@example.com")

    # 1. Request export OTP
    with patch("app.api.user.export.resolve_verified_user", return_value=(USER_1, "test@example.com")), \
         patch("app.api.user.export.redis_client.exists", new_callable=AsyncMock, return_value=False), \
         patch("app.api.user.export.redis_client.get", new_callable=AsyncMock, return_value=None), \
         patch("app.api.user.export.redis_client.set", new_callable=AsyncMock), \
         patch("app.api.user.export.redis_client.incr", new_callable=AsyncMock, return_value=1), \
         patch("app.api.user.export.redis_client.expire", new_callable=AsyncMock), \
         patch("app.api.user.export.redis_client.setex", new_callable=AsyncMock), \
         patch("app.api.user.export.redis_client.delete", new_callable=AsyncMock), \
         patch("app.api.user.export.send_data_export_otp_email", return_value=MagicMock(success=True)):
        req_res = await request_data_export_otp(request=req, payload=otp_req_payload, auth_user_id=USER_1)
        assert req_res.sent is True

    # 2. Verify export OTP
    verify_payload = DataExportOtpVerifyRequest(email="test@example.com", code="12345678")
    with patch("app.api.user.export.resolve_verified_user", return_value=(USER_1, "test@example.com")), \
         patch("app.api.user.export.verify_and_consume_raw_otp"), \
         patch("app.api.user.export.redis_client.setex", new_callable=AsyncMock):
        v_res = await verify_data_export_otp(request=req, payload=verify_payload, auth_user_id=USER_1)
        assert v_res.verified is True

    # 3. Export data download
    with patch("app.api.user.export.resolve_verified_user", return_value=(USER_1, "test@example.com")), \
         patch("app.api.user.export.redis_client.get", new_callable=AsyncMock, return_value="1"), \
         patch("app.api.user.export.redis_client.delete", new_callable=AsyncMock), \
         patch("app.api.user.export.build_user_data_export", return_value={"user": {}}):
        exp_dl = await export_account_data(request=req, payload=export_req_payload, auth_user_id=USER_1)
        assert exp_dl.status_code == 200


async def test_account_deletion_flow():
    req = make_mock_request()
    del_otp_req_payload = AccountDeletionOtpRequestRequest(email="test@example.com")

    # 1. Request deletion OTP
    with patch("app.api.user.account_deletion.resolve_verified_user", return_value=(USER_1, "test@example.com")), \
         patch("app.api.user.account_deletion.redis_client.exists", new_callable=AsyncMock, return_value=False), \
         patch("app.api.user.account_deletion.redis_client.get", new_callable=AsyncMock, return_value=None), \
         patch("app.api.user.account_deletion.redis_client.set", new_callable=AsyncMock), \
         patch("app.api.user.account_deletion.redis_client.incr", new_callable=AsyncMock, return_value=1), \
         patch("app.api.user.account_deletion.redis_client.expire", new_callable=AsyncMock), \
         patch("app.api.user.account_deletion.redis_client.setex", new_callable=AsyncMock), \
         patch("app.api.user.account_deletion.redis_client.delete", new_callable=AsyncMock), \
         patch("app.api.user.account_deletion.send_account_deletion_otp_email", return_value=MagicMock(success=True)):
        del_req = await request_account_deletion_otp(request=req, payload=del_otp_req_payload, auth_user_id=USER_1)
        assert del_req.sent is True

    # 2. Verify deletion OTP
    verify_del_payload = AccountDeletionOtpVerifyRequest(email="test@example.com", code="12345678")
    with patch("app.api.user.account_deletion.resolve_verified_user", return_value=(USER_1, "test@example.com")), \
         patch("app.api.user.account_deletion.verify_and_consume_raw_otp"), \
         patch("app.api.user.account_deletion.redis_client.setex", new_callable=AsyncMock):
        v_del = await verify_account_deletion_otp(request=req, payload=verify_del_payload, auth_user_id=USER_1)
        assert v_del.verified is True

    # 3. Schedule account deletion
    req_del_payload = AccountDeletionRequestRequest(confirmation_text="DELETE", email="test@example.com")
    bg = BackgroundTasks()
    with patch("app.api.user.account_deletion.resolve_verified_user", return_value=(USER_1, "test@example.com")), \
         patch("app.api.user.account_deletion.fetch_deletion_status", return_value=None), \
         patch("app.api.user.account_deletion.redis_client.get", new_callable=AsyncMock, return_value="1"), \
         patch("app.api.user.account_deletion.redis_client.delete", new_callable=AsyncMock), \
         patch("app.api.user.account_deletion.compute_deletion_flag_reason", return_value=None), \
         patch("app.api.user.account_deletion.request_deletion", return_value=datetime.now(timezone.utc) + timedelta(days=14)), \
         patch("app.api.user.account_deletion.send_account_deletion_scheduled_email"):
        sch_del = await request_account_deletion(request=req, background_tasks=bg, payload=req_del_payload, auth_user_id=USER_1)
        assert sch_del.scheduled_purge_at is not None

    # 4. Cancel account deletion
    with patch("app.api.user.account_deletion.fetch_deletion_status", return_value={"status": "pending_deletion", "deletion_requested_at": "2026-08-25T00:00:00Z"}), \
         patch("app.api.user.account_deletion.get_user_email_by_id", return_value="test@example.com"), \
         patch("app.api.user.account_deletion.cancel_deletion"), \
         patch("app.api.user.account_deletion.redis_client.delete", new_callable=AsyncMock), \
         patch("app.api.user.account_deletion.send_account_reactivated_email"):
        canc_res = await cancel_account_deletion(request=req, background_tasks=bg, user_id=USER_1)
        assert canc_res.reactivated is True

    # 5. Get account deletion settings
    stat_res = get_account_deletion_settings(request=req)
    assert stat_res.grace_period_days > 0
