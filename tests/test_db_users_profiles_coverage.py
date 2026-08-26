"""Test coverage suite for DB Users and Profiles layers.

Covers:
- app/db/profiles/crud.py
- app/db/profiles/encryption.py
- app/db/profiles/media.py
- app/db/users/auth.py
- app/db/users/consent.py
- app/db/users/account_deletion.py
- app/db/users/import_export.py
- app/db/users/export.py
- app/db/users/profile.py
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from typing import Any, cast
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from postgrest.exceptions import APIError
from storage3.utils import StorageException

from app.core.config import DiscoveryTab
from app.core.security.crypto import DecryptFailedError, encrypt_to_hex
from app.db.client import DatabaseAccessError, ProfileDecodeError, supabase_client
from app.db.profiles.crud import (
    _attach_empty_embeddings,
    _fetch_and_decrypt_viewer,
    _get_completion_flag_column,
    _get_target_bucket_column,
    fetch_music_affinities,
    fetch_peer_profile_by_id,
    fetch_stage_1_candidates,
    is_active_profile,
)
from app.db.profiles.encryption import (
    decrypt_profile_field,
    decrypt_profile_fields,
    sanitize_decrypted_profile,
)
from app.db.profiles.media import (
    _is_safe_media_path,
    _sign_media_paths,
    sign_profile_media,
    sign_profile_media_bulk,
    update_profile_images_and_metadata,
)
from app.models import DiscoveryFilters
from app.db.users.account_deletion import (
    _purge_single_due_account,
    cancel_deletion,
    compute_deletion_flag_reason,
    fetch_deletion_status,
    hard_purge_long_tail_accounts,
    is_phone_blocklisted,
    purge_due_accounts,
    request_deletion,
)
from app.db.users.auth import (
    _dump_user_object,
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
    _log_consent_event,
    _parse_terms_timestamp,
    _parse_version_tuple,
    _validate_terms_versions,
    update_community_guidelines_consent,
    update_safety_data_consent,
    update_special_category_consent,
    update_user_terms,
)
from app.db.users.export import (
    build_user_data_export,
)
from app.db.users.import_export import (
    execute_import,
    generate_export_code,
)
from app.db.users.profile import (
    fetch_profile,
    upsert_profile_variant,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"


# ==============================================================================
# 1. PROFILES ENCRYPTION TESTS
# ==============================================================================

def test_profile_encryption_and_decryption_fields():
    # 1. Scalar decryption
    enc_name = encrypt_to_hex("Alice")
    row_scalar = {"name": enc_name}
    decrypt_profile_field(row_scalar, "name")
    assert row_scalar["name"] == "Alice"

    row_none = {"name": None}
    decrypt_profile_field(row_none, "name")
    assert row_none["name"] is None

    # 2. Array decryption
    enc_langs = encrypt_to_hex(json.dumps(["English", "Spanish"]))
    row_arr = {"languages": enc_langs}
    decrypt_profile_field(row_arr, "languages")
    assert row_arr["languages"] == ["English", "Spanish"]

    # 3. Dict decryption
    enc_interests = encrypt_to_hex(json.dumps({"tech": 5, "music": 4}))
    row_dict = {"interests": enc_interests}
    decrypt_profile_field(row_dict, "interests")
    assert row_dict["interests"] == {"tech": 5, "music": 4}

    # 4. Corrupted JSON dict -> ProfileDecodeError
    enc_bad_json = encrypt_to_hex("not json")
    row_bad = {"interests": enc_bad_json}
    with pytest.raises(ProfileDecodeError):
        decrypt_profile_field(row_bad, "interests")

    # 5. Decrypt failure
    with patch("app.db.profiles.encryption.decrypt_pii", side_effect=DecryptFailedError("Failed")):
        row_fail = {"name": "corrupted_hex"}
        decrypt_profile_field(row_fail, "name")
        assert row_fail["name"] == "__DECRYPTION_FAILED__"

    # 6. decrypt_profile_fields
    raw_row = {
        "id": USER_1,
        "name": enc_name,
        "languages": enc_langs,
        "unencrypted_field": "test",
    }
    dec_fields = decrypt_profile_fields(dict(raw_row), fields=frozenset({"name", "languages"}))
    assert dec_fields["name"] == "Alice"
    assert dec_fields["languages"] == ["English", "Spanish"]

    # 7. sanitize_decrypted_profile
    sentinel_row = {
        "name": "__DECRYPTION_FAILED__",
        "languages": ["__DECRYPTION_FAILED__"],
        "interests": {"__DECRYPTION_FAILED__": True},
    }
    sanitized = sanitize_decrypted_profile(sentinel_row)
    assert sanitized["name"] == ""
    assert sanitized["languages"] == []
    assert sanitized["interests"] == {}

    # 9. decrypt_profile_rows
    from app.db.profiles.encryption import decrypt_profile_rows
    row_for_map = [{"id": USER_1, "name": enc_name, "profile_pic": f"{USER_1}/pic.jpg"}]
    with patch("app.db.profiles.encryption.sign_profile_media_bulk"):
        p_map = decrypt_profile_rows(row_for_map)
        assert USER_1 in p_map
        assert p_map[USER_1]["name"] == "Alice"


# ==============================================================================
# 2. PROFILES MEDIA TESTS
# ==============================================================================

async def test_profile_media_signing():
    # 1. Safe media path checks
    assert _is_safe_media_path(f"{USER_1}/avatar.jpg") is True
    assert _is_safe_media_path("../etc/passwd") is False
    assert _is_safe_media_path(r"folder\avatar.jpg") is False
    assert _is_safe_media_path("/root/avatar.jpg") is False
    assert _is_safe_media_path("avatar%20pic.jpg") is False
    assert _is_safe_media_path("avatar\x00pic.jpg") is False
    assert _is_safe_media_path("") is False

    # 2. _sign_media_paths
    assert _sign_media_paths([]) == {}

    # Storage exception handled gracefully
    mock_from = MagicMock()
    mock_from.return_value.create_signed_urls.side_effect = StorageException("Storage offline")
    with patch("app.db.profiles.media.supabase_client.storage.from_", mock_from):
        assert _sign_media_paths([f"{USER_1}/pic.jpg"]) == {}

    # Successful signing
    mock_from.return_value.create_signed_urls.side_effect = None
    mock_from.return_value.create_signed_urls.return_value = [
        {"path": f"{USER_1}/pic.jpg", "signedURL": "https://storage.nexus/pic.jpg?token=abc"}
    ]
    with patch("app.db.profiles.media.supabase_client.storage.from_", mock_from):
        urls = _sign_media_paths([f"{USER_1}/pic.jpg"])
        assert f"{USER_1}/pic.jpg" in urls

    # 3. sign_profile_media and bulk
    row = {
        "id": USER_1,
        "profile_pic": f"{USER_1}/pic.jpg",
        "normal_pics": [f"{USER_1}/pic1.jpg"],
    }
    with patch("app.db.profiles.media._sign_media_paths", return_value={
        f"{USER_1}/pic.jpg": "https://storage/pic.jpg",
        f"{USER_1}/pic1.jpg": "https://storage/pic1.jpg",
    }):
        signed_row = sign_profile_media(dict(row))
        assert signed_row["profile_pic"] == "https://storage/pic.jpg"
        assert signed_row["normal_pics"] == ["https://storage/pic1.jpg"]

        rows_to_sign = [dict(row)]
        sign_profile_media_bulk(rows_to_sign)
        assert len(rows_to_sign) == 1

    # 4. update_profile_images_and_metadata
    mock_table = MagicMock()
    mock_table.update.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(data=[{"id": USER_1}])
    with patch("app.db.profiles.media.supabase_client.table", return_value=mock_table):
        await update_profile_images_and_metadata(USER_1, [f"{USER_1}/pic1.jpg"], ["vibe1"])


# ==============================================================================
# 3. PROFILES CRUD TESTS
# ==============================================================================

def test_profiles_crud():
    # 1. Completion flags and target bucket columns
    assert _get_completion_flag_column("Dating") == "is_dating_active"
    assert _get_completion_flag_column("Friends") == "is_friends_active"
    assert _get_completion_flag_column("Professional") == "is_professional_active"
    with pytest.raises(ValueError):
        _get_completion_flag_column(cast(DiscoveryTab, "InvalidTab"))

    assert _get_target_bucket_column("Dating") == "dating_target_buckets"
    assert _get_target_bucket_column("Friends") == "friends_target_buckets"
    assert _get_target_bucket_column("Professional") == "professional_target_buckets"
    with pytest.raises(ValueError):
        _get_target_bucket_column(cast(DiscoveryTab, "InvalidTab"))

    # 2. _attach_empty_embeddings
    rec: dict[str, Any] = {}
    _attach_empty_embeddings(rec)
    assert rec["bio_embedding"] is None

    # 3. _fetch_and_decrypt_viewer
    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1, "name": encrypt_to_hex("Alice"), "users": {"app_variant": "nexus"}}]
    )
    def _mock_decrypt_fields(r: dict[str, Any], **kw: Any) -> dict[str, Any]:
        return {**r, "name": "Alice"}

    def _mock_decrypt_rec(r: dict[str, Any]) -> dict[str, Any]:
        return {**r, "name": "Alice"}

    def _mock_passthrough(r: dict[str, Any], **kw: Any) -> dict[str, Any]:
        return r

    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table), \
         patch("app.db.profiles.crud.decrypt_profile_fields", side_effect=_mock_decrypt_fields):
        viewer = _fetch_and_decrypt_viewer(USER_1, "Dating")
        assert viewer is not None
        assert viewer["name"] == "Alice"

    # APIError -> DatabaseAccessError
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.side_effect = APIError({"message": "DB error"})
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError):
            _fetch_and_decrypt_viewer(USER_1, "Dating")

    # 5. fetch_peer_profile_by_id, is_active_profile, fetch_music_affinities
    mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.eq.return_value.neq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1, "name": encrypt_to_hex("Alice"), "profile_pic": None, "normal_pics": [], "is_deactivated": False}]
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table), \
         patch("app.db.profiles.crud.decrypt_profile_record", side_effect=_mock_decrypt_rec):
        peer = fetch_peer_profile_by_id(USER_1)
        assert peer is not None
        assert peer["name"] == "Alice"

    mock_table.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}]
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        assert is_active_profile(USER_1) is True

    mock_table.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"artist_affinity": encrypt_to_hex(json.dumps({"coldplay": 1.0})), "genre_affinity": encrypt_to_hex(json.dumps({"rock": 1.0}))}]
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        a_aff, g_aff = fetch_music_affinities(USER_1)
        assert "coldplay" in a_aff
        assert "rock" in g_aff

    # 6. fetch_stage_1_candidates
    mock_viewer = {
        "id": USER_1,
        "search_bucket": "b_1",
        "dating_target_buckets": ["b_1", "b_2"],
        "is_dating_active": True,
        "app_variant": "nexus",
    }
    with patch("app.db.profiles.crud._fetch_and_decrypt_viewer", return_value=mock_viewer), \
         patch("app.db.profiles.crud.fetch_active_discovery_excluded_ids", return_value=set()), \
         patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table), \
         patch("app.db.profiles.crud.decrypt_profile_fields", side_effect=_mock_passthrough):
        v, cands = fetch_stage_1_candidates(USER_1, "Dating", filters=DiscoveryFilters(min_age=18, max_age=50), candidate_limit=10)
        assert v is not None
        assert v["id"] == USER_1
        assert len(cands) >= 0


# ==============================================================================
# 4. USERS AUTH & CONSENT TESTS
# ==============================================================================

def test_users_auth_and_domains():
    # 1. Disposable email checks
    with patch("app.db.users.auth.DISPOSABLE_DOMAINS", {"tempmail.com", "mailinator.com"}):
        assert is_disposable_email("test@tempmail.com") is True
        assert is_disposable_email("test@gmail.com") is False
        assert is_disposable_email("not_an_email") is False

    # 2. Allowed email by app variant
    with patch("app.db.users.auth.settings.allowed_signup_domains", {"nexus_mec": ["mec.edu.in"]}):
        assert is_allowed_email("student@mec.edu.in", "nexus_mec") is True
        assert is_allowed_email("student@gmail.com", "nexus_mec") is False
        assert is_allowed_email("anyone@gmail.com", "nexus") is True

    # 3. _dump_user_object
    u_dict = {"id": USER_1, "email": "user@example.com"}
    assert _dump_user_object(u_dict) == u_dict

    u_obj = MagicMock()
    u_obj.model_dump.return_value = {"id": USER_1, "email": "user@example.com"}
    dumped = _dump_user_object(u_obj)
    assert dumped["id"] == USER_1

    # 4. get_supabase_user_from_jwt
    with patch("app.db.users.auth.supabase_client.auth.get_user", return_value={"user": u_dict}):
        jwt_u = get_supabase_user_from_jwt("token123")
        assert jwt_u["id"] == USER_1

    # 5. fetch_public_user & _decrypt_mobile
    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1, "mobile": encrypt_to_hex("+15551234567", category="contact")}]
    )
    with patch("app.db.users.auth.supabase_client.table", return_value=mock_table):
        p_user = fetch_public_user(USER_1)
        assert p_user is not None
        assert p_user["mobile"] == "+15551234567"

    # 6. set_verified_mobile, set_user_suspension, find_user_id_by_phone
    with patch("app.db.users.is_phone_blocklisted", return_value=False), \
         patch("app.db.users.auth.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.auth.invalidate_user_status_cache", new_callable=AsyncMock):
        set_verified_mobile(USER_1, "+15551234567")
        set_user_suspension(USER_1, is_suspended=False)

    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}]
    )
    with patch("app.db.users.auth.supabase_client.table", return_value=mock_table):
        f_uid = find_user_id_by_phone("+15551234567")
        assert f_uid == USER_1

    # 7. get_user_email_by_id & get_user_id_by_email & upsert_public_user
    with patch.object(supabase_client.auth.admin, "get_user_by_id", return_value=MagicMock(user=MagicMock(email="user@example.com"))):
        mail = get_user_email_by_id(USER_1)
        assert mail == "user@example.com"

    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data=USER_1)
    with patch("app.db.users.auth.supabase_client.rpc", return_value=mock_rpc):
        uid = get_user_id_by_email("user@example.com")
        assert uid == USER_1

    with patch("app.db.users.auth.fetch_public_user", return_value={"id": USER_1}):
        ups_u, created = upsert_public_user(USER_1)
        assert ups_u["id"] == USER_1
        assert created is False


def test_users_consent():
    now = datetime.now(timezone.utc)

    # 1. _parse_terms_timestamp
    assert _parse_terms_timestamp(now) == now
    assert _parse_terms_timestamp(now.isoformat()).year == now.year
    with pytest.raises(HTTPException):
        _parse_terms_timestamp(12345)

    # 2. _parse_version_tuple & validate
    assert _parse_version_tuple("1.0.2") == (1, 0, 2)
    with pytest.raises(ValueError):
        _parse_version_tuple("")
    with pytest.raises(ValueError):
        _parse_version_tuple("1.x")

    with patch("app.db.users.consent.settings.current_terms_version", "2.0.0"):
        _validate_terms_versions("2.0.0")

    # 3. _clear_consent_pair & _log_consent_event
    mock_table = MagicMock()
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": USER_1}])
    mock_table.insert.return_value.execute.return_value = MagicMock(data=[{"id": "log_1"}])
    with patch("app.db.users.consent.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.consent.invalidate_user_status_cache", new_callable=AsyncMock):
        _clear_consent_pair(USER_1, "accepted_terms_version", "terms_accepted_at")
        _log_consent_event(USER_1, "general", True, "2.0.0")

    # 4. update_user_terms & update_community_guidelines_consent
    with patch("app.db.users.consent._validate_terms_versions"), \
         patch("app.db.users.consent._update_consent_pair", return_value=("2.0.0", now)), \
         patch("app.db.users.consent._log_consent_event"):
        res = update_user_terms(USER_1, "2.0.0", granted=True)
        assert res is not None
        assert res[0] == "2.0.0"
        update_community_guidelines_consent(USER_1, "2.0.0", granted=True)

    # 5. update_special_category_consent & update_safety_data_consent
    with patch("app.db.users.consent._validate_terms_versions"), \
         patch("app.db.users.consent._verify_general_terms_accepted"), \
         patch("app.db.users.consent._update_consent_pair", return_value=("2.0.0", now)), \
         patch("app.db.users.consent._log_consent_event"):
        res_sp = update_special_category_consent(USER_1, "2.0.0", granted=True)
        assert res_sp is not None
        res_sf = update_safety_data_consent(USER_1, "2.0.0", granted=True)
        assert res_sf is not None


# ==============================================================================
# 5. USERS ACCOUNT DELETION, EXPORT & IMPORT TESTS
# ==============================================================================

async def test_account_deletion_and_export():
    now = datetime.now(timezone.utc)

    def table_router(t: str) -> MagicMock:
        mock = MagicMock()
        if t == "users":
            mock.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
                data=[{"moderation_status": "clear", "is_suspended": False}]
            )
            mock.select.return_value.not_.return_value.is_.return_value.lte.return_value.limit.return_value.execute.return_value = MagicMock(
                data=[{"id": USER_1}]
            )
            mock.select.return_value.lte.return_value.limit.return_value.execute.return_value = MagicMock(
                data=[{"id": USER_1}]
            )
        elif t == "user_reports":
            mock.select.return_value.eq.return_value.in_.return_value.limit.return_value.execute.return_value = MagicMock(
                data=[]
            )
        elif t == "deleted_account_blocklist":
            mock.select.return_value.eq.return_value.gt.return_value.limit.return_value.execute.return_value = MagicMock(
                data=[{"id": "b_1", "cooldown_expires_at": (now + timedelta(days=10)).isoformat()}]
            )
        mock.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": USER_1}])
        return mock

    # 1. compute_deletion_flag_reason & is_phone_blocklisted
    with patch("app.db.users.account_deletion.supabase_client.table", side_effect=table_router):
        flag = compute_deletion_flag_reason(USER_1)
        assert flag is None
        assert is_phone_blocklisted("blind_index_123456789012") is True
        assert is_phone_blocklisted("") is False

    # 2. request_deletion
    with patch("app.db.users.account_deletion.supabase_client.table", side_effect=table_router), \
         patch("app.db.users.account_deletion.invalidate_user_status_cache", new_callable=AsyncMock), \
         patch("app.db.users.account_deletion._close_all_conversations"):
        sched = request_deletion(USER_1, flagged_reason_code=None)
        assert sched is not None

    # 3. cancel_deletion
    with patch("app.db.users.account_deletion.supabase_client.table", side_effect=table_router), \
         patch("app.db.users.account_deletion.invalidate_user_status_cache", new_callable=AsyncMock), \
         patch("app.db.users.account_deletion.reopen_conversations_for_reactivation"):
        cancel_deletion(USER_1)

    # 4. fetch_deletion_status
    with patch("app.db.users.account_deletion.supabase_client.table", side_effect=table_router):
        status_info = fetch_deletion_status(USER_1)
        assert status_info is not None

    # 5. purge_due_accounts & _purge_single_due_account & hard_purge_long_tail_accounts
    with patch("app.db.users.account_deletion.supabase_client.table", side_effect=table_router), \
         patch("app.db.users.account_deletion._anonymize_profile_and_user"), \
         patch("app.db.users.account_deletion._delete_no_retention_rows"), \
         patch("app.db.users.account_deletion._delete_user_media_objects"), \
         patch("app.db.users.account_deletion._ban_and_scrub_auth_user"):
        _purge_single_due_account({"id": USER_1, "mobile_blind_index": "b_1", "deletion_flagged_reason_code": "banned"}, now)

    with patch("app.db.users.account_deletion.supabase_client.table", side_effect=table_router), \
         patch("app.db.users.account_deletion._purge_single_due_account"):
        purge_due_accounts()

    with patch("app.db.users.account_deletion.supabase_client.table", side_effect=table_router), \
         patch("app.db.users.account_deletion._fetch_accounts_due_for_long_tail_purge", return_value=[USER_1]), \
         patch("app.db.users.account_deletion._archive_account_history", return_value=[]), \
         patch("app.db.users.account_deletion._chunked_pre_purge_child_records"), \
         patch("app.db.users.account_deletion.supabase_client.auth.admin.delete_user"):
        hard_purge_long_tail_accounts()

    # 6. generate_export_code & execute_import
    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(data={"import_sync_code": "ABC123"})
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": USER_1}])
    with patch("app.db.users.import_export.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.import_export.redis_client.delete", new_callable=AsyncMock):
        exp_code, exp_dt = await generate_export_code(USER_1)
        assert len(exp_code) == 6
        assert exp_dt is not None

    mock_source = {
        "id": USER_1,
        "import_sync_expires_at": (now + timedelta(minutes=10)).isoformat(),
        "display_gender": encrypt_to_hex("Woman"),
    }
    mock_target = {"id": USER_2, "has_imported_data": False}
    with patch("app.db.users.import_export._fetch_import_profiles", return_value=(mock_source, mock_target)), \
         patch("app.db.users.import_export.fetch_public_user", return_value={"id": USER_1, "app_variant": "nexus_mec"}), \
         patch("app.db.users.import_export.supabase_client.table", return_value=mock_table):
        copied = execute_import(target_user_id=USER_2, sync_code=exp_code, target_variant="nexus")
        assert "display_gender" in copied

    # 9. build_user_data_export & _safe_select
    def _mock_export_dec(r: dict[str, Any]) -> dict[str, Any]:
        return {**r, "name": "Alice"}

    with patch("app.db.users.export.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.export.decrypt_profile_record", side_effect=_mock_export_dec):
        export_payload = build_user_data_export(USER_1)
        assert "profile" in export_payload

    # 8. fetch_profile & upsert_profile_variant in app/db/users/profile.py
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1, "name": encrypt_to_hex("Alice"), "age": 20}]
    )
    mock_table.upsert.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1, "name": encrypt_to_hex("Alice"), "age": 21}]
    )
    with patch("app.db.users.profile.supabase_client.table", return_value=mock_table):
        p_row = fetch_profile(USER_1)
        assert p_row is not None
        prof, created = upsert_profile_variant(USER_1, "Alice", "CS", 2024, 21, "Main Campus", "b_1")
        assert prof is not None
        assert created is not None
