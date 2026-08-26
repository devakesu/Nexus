"""Phase 26 Coverage Suite: Deep branch and error coverage for chat keys, presence, DB chat keys, auth discovery sessions, and email senders."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.email.senders import ProviderResult, SendEmailProps
from app.db.client import DatabaseAccessError, ProfileNotFoundError
from app.models import (
    BatchPresenceRequest,
    EstablishSessionRequest,
    OneTimePrekeyItem,
    PresenceHeartbeatRequest,
    UploadIdentityKeyRequest,
    UploadOneTimePrekeysRequest,
    UploadSignedPrekeyRequest,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
CONV_1 = "00000000-0000-0000-0000-000000000010"


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


def make_api_error(code: str = "P0001", message: str = "DB error") -> APIError:
    return APIError({"code": code, "message": message, "details": "details", "hint": "hint"})


# =============================================================================
# 1. API CHAT KEYS TESTS
# =============================================================================

async def test_api_chat_keys_deep():
    from app.api.chat.keys import (
        establish_session,
        get_key_bundle,
        get_one_time_prekey_count,
        upload_identity_key,
        upload_one_time_prekeys,
        upload_signed_prekey,
    )

    req = make_dummy_request()

    # upload_identity_key: ProfileNotFoundError & DatabaseAccessError
    id_req = UploadIdentityKeyRequest(identity_public_key=b"AAAA", registration_id=123)
    with patch("app.api.chat.keys.upsert_identity_key", side_effect=ProfileNotFoundError("No profile")):
        with pytest.raises(HTTPException) as exc:
            await upload_identity_key(req, id_req, None, USER_1)
        assert exc.value.status_code == 404

    with patch("app.api.chat.keys.upsert_identity_key", side_effect=DatabaseAccessError("DB fail")):
        with pytest.raises(HTTPException) as exc:
            await upload_identity_key(req, id_req, None, USER_1)
        assert exc.value.status_code == 503

    # upload_signed_prekey: ProfileNotFoundError & DatabaseAccessError
    sp_req = UploadSignedPrekeyRequest(key_id=1, public_key=b"AAAA", signature=b"BBBB")
    with patch("app.api.chat.keys.fetch_identity_key", return_value={"identity_public_key": b"ID"}), \
         patch("app.api.chat.keys.verify_signed_prekey_signature", return_value=True), \
         patch("app.api.chat.keys.upsert_signed_prekey", side_effect=ProfileNotFoundError("No profile")):
        with pytest.raises(HTTPException) as exc:
            await upload_signed_prekey(req, sp_req, None, USER_1)
        assert exc.value.status_code == 404

    with patch("app.api.chat.keys.fetch_identity_key", return_value={"identity_public_key": b"ID"}), \
         patch("app.api.chat.keys.verify_signed_prekey_signature", return_value=True), \
         patch("app.api.chat.keys.upsert_signed_prekey", side_effect=DatabaseAccessError("DB fail")):
        with pytest.raises(HTTPException) as exc:
            await upload_signed_prekey(req, sp_req, None, USER_1)
        assert exc.value.status_code == 503

    # upload_one_time_prekeys: ProfileNotFoundError & DatabaseAccessError
    ot_req = UploadOneTimePrekeysRequest(prekeys=[OneTimePrekeyItem(key_id=1, public_key=b"AAAA")])
    with patch("app.api.chat.keys.bulk_insert_one_time_prekeys", side_effect=ProfileNotFoundError("No profile")):
        with pytest.raises(HTTPException) as exc:
            await upload_one_time_prekeys(req, ot_req, None, USER_1)
        assert exc.value.status_code == 404

    with patch("app.api.chat.keys.bulk_insert_one_time_prekeys", side_effect=DatabaseAccessError("DB fail")):
        with pytest.raises(HTTPException) as exc:
            await upload_one_time_prekeys(req, ot_req, None, USER_1)
        assert exc.value.status_code == 503

    # get_one_time_prekey_count: DatabaseAccessError
    with patch("app.api.chat.keys.count_unused_one_time_prekeys", side_effect=DatabaseAccessError("DB fail")):
        with pytest.raises(HTTPException) as exc:
            await get_one_time_prekey_count(req, None, USER_1)
        assert exc.value.status_code == 503

    # get_key_bundle: NOT_MATCHED, None, DatabaseAccessError, low prekey replenishment
    with patch("app.api.chat.keys.redis_client") as mock_redis, \
         patch("app.api.chat.keys.fetch_x3dh_key_bundle_unified", return_value=(None, "NOT_MATCHED")):
        mock_redis.get = AsyncMock(return_value=None)
        with pytest.raises(HTTPException) as exc:
            await get_key_bundle(req, USER_2, None, USER_1)
        assert exc.value.status_code == 403

    with patch("app.api.chat.keys.redis_client") as mock_redis, \
         patch("app.api.chat.keys.fetch_x3dh_key_bundle_unified", side_effect=DatabaseAccessError("DB fail")):
        mock_redis.get = AsyncMock(side_effect=Exception("Redis fail"))
        with pytest.raises(HTTPException) as exc:
            await get_key_bundle(req, USER_2, None, USER_1)
        assert exc.value.status_code == 503

    bundle_dict = {
        "identity_public_key": b"\x01" * 32,
        "registration_id": 1234,
        "signed_prekey_id": 1,
        "signed_prekey_public": b"\x02" * 32,
        "signed_prekey_signature": b"\x03" * 64,
        "one_time_prekey_id": 10,
        "one_time_prekey_public": b"\x04" * 32,
        "one_time_prekey_used": True,
    }
    with patch("app.api.chat.keys.redis_client") as mock_redis, \
         patch("app.api.chat.keys.fetch_x3dh_key_bundle_unified", return_value=(bundle_dict, None)), \
         patch("app.api.chat.keys.count_unused_one_time_prekeys", return_value=5), \
         patch("app.api.chat.keys.send_prekey_replenishment_notification"):
        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.set = AsyncMock(return_value=True)
        res_bundle = await get_key_bundle(req, USER_2, None, USER_1)
        assert res_bundle.user_id == USER_2

    # establish_session: DatabaseAccessError
    est_req = EstablishSessionRequest(conversation_id=CONV_1)
    with patch("app.api.chat.keys.mark_session_established", side_effect=DatabaseAccessError("DB fail")):
        with pytest.raises(HTTPException) as exc:
            await establish_session(req, est_req, None, USER_1)
        assert exc.value.status_code == 503


# =============================================================================
# 2. API CHAT PRESENCE TESTS
# =============================================================================

async def test_api_chat_presence_deep():
    from app.api.chat.presence import (
        _coarsen_last_active_timestamp,
        _resolve_batch_presence,
        batch_get_presence,
        get_presence,
        send_presence_heartbeat,
    )

    req = make_dummy_request()

    # _coarsen_last_active_timestamp
    dt = datetime(2026, 8, 26, 14, 47, 33, 123456, tzinfo=timezone.utc)
    coarsened = _coarsen_last_active_timestamp(dt, 30)
    assert coarsened.minute == 30
    assert coarsened.second == 0

    # _resolve_batch_presence: empty, no match, blocked, privacy flag off, redis decode error fallback to db, invalid date
    assert await _resolve_batch_presence(USER_1, []) == {}

    with patch("app.api.chat.presence.fetch_active_matches_for_targets", return_value=set()):
        res_no_match = await _resolve_batch_presence(USER_1, [USER_2])
        assert not res_no_match[USER_2].is_online

    with patch("app.api.chat.presence.fetch_active_matches_for_targets", return_value={USER_2}), \
         patch("app.db.discovery.get_cached_active_block_ids", side_effect=[{USER_2}, set()]):
        res_blocked = await _resolve_batch_presence(USER_1, [USER_2])
        assert not res_blocked[USER_2].is_online

    with patch("app.api.chat.presence.fetch_active_matches_for_targets", return_value={USER_2}), \
         patch("app.db.discovery.get_cached_active_block_ids", side_effect=[set(), {USER_1}]):
        res_target_blocked = await _resolve_batch_presence(USER_1, [USER_2])
        assert not res_target_blocked[USER_2].is_online

    with patch("app.api.chat.presence.fetch_active_matches_for_targets", return_value={USER_2}), \
         patch("app.db.discovery.get_cached_active_block_ids", return_value=set()), \
         patch("app.api.chat.presence.batch_fetch_user_share_flags", return_value={USER_2: {"share_active_status": False}}):
        res_no_share = await _resolve_batch_presence(USER_1, [USER_2])
        assert not res_no_share[USER_2].is_online

    # Redis decode error -> DB fallback with invalid date
    now_iso = datetime.now(timezone.utc).isoformat()
    with patch("app.api.chat.presence.fetch_active_matches_for_targets", return_value={USER_2}), \
         patch("app.db.discovery.get_cached_active_block_ids", return_value=set()), \
         patch("app.api.chat.presence.batch_fetch_user_share_flags", return_value={USER_2: {"share_active_status": True}}), \
         patch("app.api.chat.presence.redis_client") as mock_redis, \
         patch("app.api.chat.presence.batch_fetch_presence_from_db", return_value={USER_2: {"is_online": True, "last_active_at": "invalid_date"}}):
        mock_redis.mget = AsyncMock(return_value=["malformed_json"])
        res_db_fallback = await _resolve_batch_presence(USER_1, [USER_2])
        assert not res_db_fallback[USER_2].is_online

    # Redis success with valid online presence
    with patch("app.api.chat.presence.fetch_active_matches_for_targets", return_value={USER_2}), \
         patch("app.db.discovery.get_cached_active_block_ids", return_value=set()), \
         patch("app.api.chat.presence.batch_fetch_user_share_flags", return_value={USER_2: {"share_active_status": True}}), \
         patch("app.api.chat.presence.redis_client") as mock_redis:
        mock_redis.mget = AsyncMock(return_value=[f'{{"is_online": true, "last_active_at": "{now_iso}"}}'])
        res_online = await _resolve_batch_presence(USER_1, [USER_2])
        assert res_online[USER_2].is_online is True

    # send_presence_heartbeat: DatabaseAccessError
    hb_req = PresenceHeartbeatRequest(is_online=True)
    with patch("app.api.chat.presence.upsert_presence_heartbeat", side_effect=DatabaseAccessError("DB fail")):
        with pytest.raises(HTTPException) as exc:
            await send_presence_heartbeat(req, hb_req, None, USER_1)
        assert exc.value.status_code == 503

    # batch_get_presence: too many IDs (> 50) & DatabaseAccessError
    too_many = BatchPresenceRequest.model_construct(user_ids=[f"00000000-0000-0000-0000-0000000000{i:02d}" for i in range(60)])
    with pytest.raises(HTTPException) as exc:
        await batch_get_presence(req, too_many, None, USER_1)
    assert exc.value.status_code == 400

    batch_ok = BatchPresenceRequest(user_ids=[USER_2])
    with patch("app.api.chat.presence._resolve_batch_presence", side_effect=DatabaseAccessError("DB fail")):
        with pytest.raises(HTTPException) as exc:
            await batch_get_presence(req, batch_ok, None, USER_1)
        assert exc.value.status_code == 503

    # get_presence: DatabaseAccessError
    with patch("app.api.chat.presence._resolve_single_presence", side_effect=DatabaseAccessError("DB fail")):
        with pytest.raises(HTTPException) as exc:
            await get_presence(req, USER_2, None, USER_1)
        assert exc.value.status_code == 503


# =============================================================================
# 3. DB CHAT KEYS TESTS
# =============================================================================

def test_db_chat_keys_deep():
    from app.db.chat.keys import (
        _from_bytea,
        bulk_insert_one_time_prekeys,
        count_unused_one_time_prekeys,
        fetch_active_matches_for_targets,
        fetch_identity_key,
        fetch_key_bundle,
        fetch_x3dh_key_bundle_unified,
        has_active_match,
        mark_session_established,
        upsert_identity_key,
        upsert_signed_prekey,
    )

    # _from_bytea representations
    assert _from_bytea(memoryview(b"abc")) == b"abc"
    assert _from_bytea(b"abc") == b"abc"
    assert _from_bytea("\\x616263") == b"abc"
    with pytest.raises(DatabaseAccessError):
        _from_bytea(12345)

    # upsert_identity_key: 23503 error, generic APIError, user_devices exception
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().upsert().execute.side_effect = make_api_error("23503")
        with pytest.raises(ProfileNotFoundError):
            upsert_identity_key(USER_1, b"key", 1)

        mock_sb.table().upsert().execute.side_effect = make_api_error("P0001")
        with pytest.raises(DatabaseAccessError):
            upsert_identity_key(USER_1, b"key", 1)

        mock_sb.table().upsert().execute.side_effect = None
        mock_sb.table().delete().eq().execute.return_value = MagicMock()
        mock_sb.table().update().eq().execute.side_effect = Exception("device fail")
        upsert_identity_key(USER_1, b"key", 1)

    # fetch_identity_key: None row, APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=None)
        assert fetch_identity_key(USER_1) is None

        mock_sb.table().select().eq().maybe_single().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            fetch_identity_key(USER_1)

    # upsert_signed_prekey: 23503, generic APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.rpc().execute.side_effect = make_api_error("23503")
        with pytest.raises(ProfileNotFoundError):
            upsert_signed_prekey(USER_1, 1, b"pub", b"sig")

        mock_sb.rpc().execute.side_effect = make_api_error("P0001")
        with pytest.raises(DatabaseAccessError):
            upsert_signed_prekey(USER_1, 1, b"pub", b"sig")

    # bulk_insert_one_time_prekeys: empty, 23503, generic APIError
    bulk_insert_one_time_prekeys(USER_1, [])
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().insert().execute.side_effect = make_api_error("23503")
        with pytest.raises(ProfileNotFoundError):
            bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"pub"}])

        mock_sb.table().insert().execute.side_effect = make_api_error("P0001")
        with pytest.raises(DatabaseAccessError):
            bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"pub"}])

    # count_unused_one_time_prekeys: APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().select().eq().is_().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            count_unused_one_time_prekeys(USER_1)

    # has_active_match: APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().select().or_().is_().limit().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            has_active_match(USER_1, USER_2)

    # fetch_active_matches_for_targets: empty, APIError
    assert fetch_active_matches_for_targets(USER_1, []) == set()
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().select().or_().is_().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            fetch_active_matches_for_targets(USER_1, [USER_2])

    # fetch_key_bundle: identity not found, signed prekey not found, APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=None)
        assert fetch_key_bundle(USER_1) is None

        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data={"identity_public_key": b"ID", "registration_id": 123})
        mock_sb.table().select().eq().is_().order().limit().maybe_single().execute.return_value = MagicMock(data=None)
        assert fetch_key_bundle(USER_1) is None

        mock_sb.table().select().eq().maybe_single().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            fetch_key_bundle(USER_1)

    # fetch_x3dh_key_bundle_unified: rpc error field, fallback not matched, fallback identity not found
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.rpc().execute.return_value = MagicMock(data={"error": "NOT_MATCHED"})
        b, err = fetch_x3dh_key_bundle_unified(USER_1, USER_2)
        assert b is None
        assert err == "NOT_MATCHED"

        mock_sb.rpc().execute.side_effect = Exception("RPC failed")
        with patch("app.db.chat.keys.has_active_match", return_value=False):
            b_fallback, err_fallback = fetch_x3dh_key_bundle_unified(USER_1, USER_2)
            assert b_fallback is None
            assert err_fallback == "NOT_MATCHED"

        with patch("app.db.chat.keys.has_active_match", return_value=True), \
             patch("app.db.chat.keys.fetch_key_bundle", return_value=None):
            b_none, err_none = fetch_x3dh_key_bundle_unified(USER_1, USER_2)
            assert b_none is None
            assert err_none == "IDENTITY_NOT_FOUND"

    # mark_session_established: APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().update().eq().or_().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            mark_session_established(USER_1, CONV_1)


# =============================================================================
# 4. DB SESSIONS AUTH SESSIONS TESTS
# =============================================================================

def test_db_sessions_auth_sessions_deep():
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

    # prune_excess_viewer_discovery_sessions: exception
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().gt().order().execute.side_effect = Exception("fail")
        prune_excess_viewer_discovery_sessions(USER_1)

    # create_discovery_session: empty session_id, APIError, Exception
    with patch("app.db.sessions.auth_sessions.assign_orbit_positions", return_value=[{"profile": {"id": USER_2}, "score": 85}]), \
         patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.rpc().execute.return_value = MagicMock(data="None")
        with pytest.raises(DatabaseAccessError):
            create_discovery_session(USER_1, "Dating", {}, [])

        mock_sb.rpc().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            create_discovery_session(USER_1, "Dating", {}, [])

        mock_sb.rpc().execute.side_effect = Exception("Unexpected")
        with pytest.raises(DatabaseAccessError):
            create_discovery_session(USER_1, "Dating", {}, [])

    # get_discovery_session: APIError, Exception, None response, non-dict row
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().eq().maybe_single().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            get_discovery_session("sess-1", USER_1, "Dating")

        mock_sb.table().select().eq().eq().eq().maybe_single().execute.side_effect = Exception("fail")
        with pytest.raises(DatabaseAccessError):
            get_discovery_session("sess-1", USER_1, "Dating")

        mock_sb.table().select().eq().eq().eq().maybe_single().execute.side_effect = None
        mock_sb.table().select().eq().eq().eq().maybe_single().execute.return_value = None
        assert get_discovery_session("sess-1", USER_1, "Dating") is None

        mock_sb.table().select().eq().eq().eq().maybe_single().execute.return_value = MagicMock(data="not-a-dict")
        with pytest.raises(DatabaseAccessError):
            get_discovery_session("sess-1", USER_1, "Dating")

    # get_discovery_session_by_id: APIError, Exception, None response, non-dict row
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().maybe_single().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            get_discovery_session_by_id("sess-1", USER_1)

        mock_sb.table().select().eq().eq().maybe_single().execute.side_effect = Exception("fail")
        with pytest.raises(DatabaseAccessError):
            get_discovery_session_by_id("sess-1", USER_1)

        mock_sb.table().select().eq().eq().maybe_single().execute.side_effect = None
        mock_sb.table().select().eq().eq().maybe_single().execute.return_value = None
        assert get_discovery_session_by_id("sess-1", USER_1) is None

        mock_sb.table().select().eq().eq().maybe_single().execute.return_value = MagicMock(data="not-a-dict")
        with pytest.raises(DatabaseAccessError):
            get_discovery_session_by_id("sess-1", USER_1)

    # delete_expired_discovery_sessions: APIError, Exception
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().delete().lte().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            delete_expired_discovery_sessions()

        mock_sb.table().delete().lte().execute.side_effect = Exception("fail")
        with pytest.raises(DatabaseAccessError):
            delete_expired_discovery_sessions()

    # invalidate_viewer_discovery_sessions: APIError, Exception
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().delete().eq().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            invalidate_viewer_discovery_sessions(USER_1)

        mock_sb.table().delete().eq().execute.side_effect = Exception("fail")
        with pytest.raises(DatabaseAccessError):
            invalidate_viewer_discovery_sessions(USER_1)

    # verify_session_not_expired
    assert verify_session_not_expired({}) is False
    assert verify_session_not_expired({"expires_at": "2020-01-01T00:00:00Z"}) is False
    assert verify_session_not_expired({"expires_at": (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()}) is True

    # is_candidate_in_active_session & get_candidate_session_details: exception
    with patch("app.db.sessions.auth_sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().gt().limit().execute.side_effect = Exception("fail")
        assert is_candidate_in_active_session(USER_1, USER_2) is False

        mock_sb.table().select().eq().eq().limit().execute.side_effect = Exception("fail")
        assert get_candidate_session_details(USER_1, USER_2, tab="orbit") is None


# =============================================================================
# 5. CORE EMAIL SENDERS TESTS
# =============================================================================

async def test_core_email_senders_deep():
    from app.core.email import senders

    # Reset globals
    senders._sendpulse_token = None
    senders._sendpulse_token_expires_at = 0.0

    props = SendEmailProps(
        to="user@example.com",
        subject="Test Email",
        html="<p>Hello User</p>",
        text="Hello User",
        from_name="Nexus",
        reply_to="reply@nexus.test",
    )

    # get_sendpulse_token: missing credentials & HTTP status error
    with patch.object(senders, "has_sendpulse", False):
        with pytest.raises(ValueError):
            await senders.get_sendpulse_token()

    mock_client = MagicMock()
    with patch.object(senders, "has_sendpulse", True), \
         patch.object(senders, "_get_email_client", return_value=mock_client):
        mock_res = MagicMock()
        mock_res.status_code = 401
        mock_client.post = AsyncMock(return_value=mock_res)
        with pytest.raises(RuntimeError):
            await senders.get_sendpulse_token()

    # send_via_sendpulse: unconfigured, HTTP error with message, success
    with patch.object(senders, "has_sendpulse", False):
        with pytest.raises(ValueError):
            await senders.send_via_sendpulse(props)

    with patch.object(senders, "has_sendpulse", True), \
         patch.object(senders, "get_sendpulse_token", return_value="tok-123"), \
         patch.object(senders, "_get_email_client", return_value=mock_client):
        err_res = MagicMock()
        err_res.status_code = 400
        err_res.json.return_value = {"message": "Invalid recipient"}
        mock_client.post = AsyncMock(return_value=err_res)
        with pytest.raises(RuntimeError):
            await senders.send_via_sendpulse(props)

        ok_res = MagicMock()
        ok_res.status_code = 200
        ok_res.json.return_value = {"id": "msg-sp-123"}
        mock_client.post = AsyncMock(return_value=ok_res)
        sp_result = await senders.send_via_sendpulse(props)
        assert sp_result.success is True
        assert sp_result.id == "msg-sp-123"

    # send_via_brevo: unconfigured, HTTP error with message, success
    with patch.object(senders, "has_brevo", False):
        with pytest.raises(ValueError):
            await senders.send_via_brevo(props)

    with patch.object(senders, "has_brevo", True), \
         patch.object(senders, "_get_email_client", return_value=mock_client):
        err_brevo = MagicMock()
        err_brevo.status_code = 500
        err_brevo.json.return_value = {"message": "Brevo down"}
        mock_client.post = AsyncMock(return_value=err_brevo)
        with pytest.raises(RuntimeError):
            await senders.send_via_brevo(props)

        ok_brevo = MagicMock()
        ok_brevo.status_code = 201
        ok_brevo.json.return_value = {"messageId": "msg-br-123"}
        mock_client.post = AsyncMock(return_value=ok_brevo)
        br_result = await senders.send_via_brevo(props)
        assert br_result.success is True
        assert br_result.id == "msg-br-123"

    # get_providers & execute_failover (both providers fail)
    p_config_sp = senders.get_providers(use_sp=True)
    assert p_config_sp.p_name == "SendPulse"

    p_config_br = senders.get_providers(use_sp=False)
    assert p_config_br.p_name == "Brevo"

    sec_fn = AsyncMock(side_effect=Exception("Secondary failed"))
    failover_res = await senders.execute_failover(sec_fn, props, "Brevo", Exception("Primary failed"))
    assert failover_res.success is False
    assert "All providers failed" in str(failover_res.error)

    # send_email: no providers configured, failover triggered with secondary
    with patch.object(senders, "has_brevo", False), \
         patch.object(senders, "has_sendpulse", False):
        with pytest.raises(RuntimeError):
            await senders.send_email(props)

    with patch.object(senders, "has_brevo", True), \
         patch.object(senders, "has_sendpulse", True), \
         patch.object(senders, "send_via_brevo", side_effect=Exception("Brevo fail")), \
         patch.object(senders, "send_via_sendpulse", return_value=ProviderResult(success=True, provider="SendPulse", id="msg-sp")):
        email_res = await senders.send_email(props)
        assert email_res.success is True
        assert email_res.provider == "SendPulse"
