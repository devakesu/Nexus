"""Test Suite for Test Chat Api.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from postgrest.exceptions import APIError
from starlette.requests import Request

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


async def test_api_chat_presence_spotify_likes():
    from app.api.chat.keys import (
        get_key_bundle,
        get_one_time_prekey_count,
        upload_identity_key,
        upload_one_time_prekeys,
    )
    from app.api.chat.presence import (
        get_presence,
        send_presence_heartbeat,
    )
    from app.api.discovery.likes import (
        get_likes_inbox,
        mark_likes_as_seen,
        record_like_back_action,
    )
    from app.api.spotify.auth import spotify_connect
    from app.models import (
        LikeActionRequest,
        MarkLikesSeenRequest,
        OneTimePrekeyItem,
        PresenceHeartbeatRequest,
        UploadIdentityKeyRequest,
        UploadOneTimePrekeysRequest,
    )

    req = _make_mock_request()

    # 1. chat keys
    dummy_bundle = {
        "user_id": USER_2,
        "identity_public_key": b"\x00" * 32,
        "registration_id": 1234,
        "signed_prekey_id": 1,
        "signed_prekey_public": b"\x11" * 32,
        "signed_prekey_signature": b"\x22" * 64,
        "one_time_prekey_id": None,
        "one_time_prekey_public": None,
        "one_time_prekey_used": False,
    }
    with patch(
        "app.api.chat.keys.fetch_x3dh_key_bundle_unified",
        return_value=(dummy_bundle, None),
    ):
        bundle = await get_key_bundle(
            req, target_user_id=USER_2, _device=None, user_id=USER_1,
        )
        assert bundle is not None

    with patch("app.api.chat.keys.count_unused_one_time_prekeys", return_value=42):
        cnt = await get_one_time_prekey_count(req, _device=None, user_id=USER_1)
        assert cnt.count == 42

    with patch("app.api.chat.keys.upsert_identity_key"):
        up_id = UploadIdentityKeyRequest(
            identity_public_key=b"\x00" * 32,
            registration_id=100,
        )
        res_id = await upload_identity_key(req, up_id, _device=None, user_id=USER_1)
        assert res_id["success"] is True

    with patch("app.api.chat.keys.bulk_insert_one_time_prekeys"):
        otk = UploadOneTimePrekeysRequest(
            prekeys=[OneTimePrekeyItem(key_id=1, public_key=b"\x33" * 32)],
        )
        res_otk = await upload_one_time_prekeys(req, otk, _device=None, user_id=USER_1)
        assert res_otk["success"] is True

    # 2. presence
    with patch("app.api.chat.presence.upsert_presence_heartbeat"):
        await send_presence_heartbeat(
            req, PresenceHeartbeatRequest(is_online=True), _device=None, user_id=USER_1,
        )

    with patch(
        "app.api.chat.presence._resolve_single_presence",
        return_value=MagicMock(is_online=True),
    ):
        pres = await get_presence(
            req, target_user_id=USER_2, _device=None, user_id=USER_1,
        )
        assert pres.is_online is True

    # 3. spotify auth
    with (
        patch("app.api.spotify.auth._store_state", AsyncMock()),
        patch("app.api.spotify.auth.settings.spotify_client_id", "client_123"),
        patch(
            "app.api.spotify.auth.settings.spotify_redirect_uri",
            "https://app.nexus.com/callback",
        ),
    ):
        url_res = await spotify_connect(req, _device=None, user_id=USER_1)
        assert "auth_url" in url_res

    # 4. discovery likes inbox & actions
    with patch("app.api.discovery.likes.fetch_likes_for_user", return_value=[]):
        inbox = await get_likes_inbox(req, tab="Dating", _device=None, user_id=USER_1)
        assert inbox.likes == []

    with patch("app.api.discovery.likes.mark_likes_seen"):
        seen_res = await mark_likes_as_seen(
            req,
            MarkLikesSeenRequest(mark_all=True, tab="Dating"),
            _device=None,
            user_id=USER_1,
        )
        assert seen_res["success"] is True

    act_payload = LikeActionRequest(target_id=USER_2, action="pass", tab="Dating")
    with (
        patch("app.api.discovery.likes._validate_conversation_membership", AsyncMock()),
        patch("app.api.discovery.likes.revoke_incoming_like", return_value=True),
        patch("app.api.discovery.likes.record_discovery_action"),
    ):
        act_res = await record_like_back_action(
            req, act_payload, _device=None, user_id=USER_1,
        )
        assert act_res is not None


async def test_api_chat_keys_and_presence_deep():
    from app.api.chat.keys import (
        get_key_bundle,
        get_one_time_prekey_count,
        upload_identity_key,
        upload_one_time_prekeys,
        upload_signed_prekey,
    )
    from app.api.chat.presence import (
        batch_get_presence,
        get_presence,
        send_presence_heartbeat,
    )
    from app.models import (
        BatchPresenceRequest,
        OneTimePrekeyItem,
        PresenceHeartbeatRequest,
        UploadIdentityKeyRequest,
        UploadOneTimePrekeysRequest,
        UploadSignedPrekeyRequest,
    )

    mock_req = MagicMock()

    with (
        patch("app.api.chat.keys.upsert_identity_key"),
        patch(
            "app.api.chat.keys.fetch_identity_key",
            return_value={"identity_public_key": b"x" * 32},
        ),
        patch("app.api.chat.keys.verify_signed_prekey_signature", return_value=True),
        patch("app.api.chat.keys.upsert_signed_prekey"),
        patch("app.api.chat.keys.bulk_insert_one_time_prekeys"),
        patch("app.api.chat.keys.count_unused_one_time_prekeys", return_value=50),
        patch(
            "app.api.chat.keys.fetch_x3dh_key_bundle_unified",
            return_value=(
                {
                    "identity_public_key": b"x" * 32,
                    "registration_id": 1,
                    "signed_prekey_id": 1,
                    "signed_prekey_public": b"y" * 32,
                    "signed_prekey_signature": b"s" * 64,
                    "one_time_prekey_id": None,
                    "one_time_prekey_public": None,
                    "one_time_prekey_used": False,
                },
                None,
            ),
        ),
    ):
        # Keys
        id_req = UploadIdentityKeyRequest(
            identity_public_key=b"x" * 32,
            registration_id=12345,
        )
        await upload_identity_key(mock_req, id_req, _device=None, user_id=USER_1)

        spk_req = UploadSignedPrekeyRequest(
            key_id=1,
            public_key=b"x" * 32,
            signature=b"s" * 64,
        )
        await upload_signed_prekey(mock_req, spk_req, _device=None, user_id=USER_1)

        otpk_req = UploadOneTimePrekeysRequest(
            prekeys=[OneTimePrekeyItem(key_id=1, public_key=b"x" * 32)],
        )
        await upload_one_time_prekeys(mock_req, otpk_req, _device=None, user_id=USER_1)

        cnt_res = await get_one_time_prekey_count(
            mock_req, _device=None, user_id=USER_1,
        )
        assert cnt_res.count == 50

        kb_res = await get_key_bundle(mock_req, USER_2, _device=None, user_id=USER_1)
        assert kb_res.identity_public_key is not None

    with (
        patch("app.api.chat.presence.upsert_presence_heartbeat"),
        patch(
            "app.api.chat.presence.fetch_active_matches_for_targets",
            return_value={USER_2},
        ),
        patch(
            "app.api.chat.presence.batch_fetch_presence_from_db",
            return_value={
                USER_2: {
                    "is_online": True,
                    "last_active_at": datetime.now(timezone.utc).isoformat(),
                },
            },
        ),
        patch(
            "app.api.chat.presence.batch_fetch_user_share_flags",
            return_value={
                USER_2: {"share_active_status": True, "share_read_receipts": True},
            },
        ),
        patch(
            "app.api.chat.presence._resolve_batch_presence",
            AsyncMock(return_value={USER_2: MagicMock(is_online=True)}),
        ),
        patch(
            "app.api.chat.presence._resolve_single_presence",
            AsyncMock(return_value=MagicMock(is_online=True)),
        ),
    ):
        hb = await send_presence_heartbeat(
            mock_req,
            PresenceHeartbeatRequest(is_online=True),
            _device=None,
            user_id=USER_1,
        )
        assert hb["success"] is True

        batch_p = await batch_get_presence(
            mock_req,
            BatchPresenceRequest(user_ids=[USER_2]),
            _device=None,
            user_id=USER_1,
        )
        assert len(batch_p) > 0

        single_p = await get_presence(mock_req, USER_2, _device=None, user_id=USER_1)
        assert single_p is not None


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
    with patch(
        "app.api.chat.keys.upsert_identity_key",
        side_effect=ProfileNotFoundError("No profile"),
    ):
        with pytest.raises(HTTPException) as exc:
            await upload_identity_key(req, id_req, None, USER_1)
        assert exc.value.status_code == 404

    with patch(
        "app.api.chat.keys.upsert_identity_key",
        side_effect=DatabaseAccessError("DB fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await upload_identity_key(req, id_req, None, USER_1)
        assert exc.value.status_code == 503

    # upload_signed_prekey: ProfileNotFoundError & DatabaseAccessError
    sp_req = UploadSignedPrekeyRequest(key_id=1, public_key=b"AAAA", signature=b"BBBB")
    with (
        patch(
            "app.api.chat.keys.fetch_identity_key",
            return_value={"identity_public_key": b"ID"},
        ),
        patch("app.api.chat.keys.verify_signed_prekey_signature", return_value=True),
        patch(
            "app.api.chat.keys.upsert_signed_prekey",
            side_effect=ProfileNotFoundError("No profile"),
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await upload_signed_prekey(req, sp_req, None, USER_1)
        assert exc.value.status_code == 404

    with (
        patch(
            "app.api.chat.keys.fetch_identity_key",
            return_value={"identity_public_key": b"ID"},
        ),
        patch("app.api.chat.keys.verify_signed_prekey_signature", return_value=True),
        patch(
            "app.api.chat.keys.upsert_signed_prekey",
            side_effect=DatabaseAccessError("DB fail"),
        ),
    ):
        with pytest.raises(HTTPException) as exc:
            await upload_signed_prekey(req, sp_req, None, USER_1)
        assert exc.value.status_code == 503

    # upload_one_time_prekeys: ProfileNotFoundError & DatabaseAccessError
    ot_req = UploadOneTimePrekeysRequest(
        prekeys=[OneTimePrekeyItem(key_id=1, public_key=b"AAAA")],
    )
    with patch(
        "app.api.chat.keys.bulk_insert_one_time_prekeys",
        side_effect=ProfileNotFoundError("No profile"),
    ):
        with pytest.raises(HTTPException) as exc:
            await upload_one_time_prekeys(req, ot_req, None, USER_1)
        assert exc.value.status_code == 404

    with patch(
        "app.api.chat.keys.bulk_insert_one_time_prekeys",
        side_effect=DatabaseAccessError("DB fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await upload_one_time_prekeys(req, ot_req, None, USER_1)
        assert exc.value.status_code == 503

    # get_one_time_prekey_count: DatabaseAccessError
    with patch(
        "app.api.chat.keys.count_unused_one_time_prekeys",
        side_effect=DatabaseAccessError("DB fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await get_one_time_prekey_count(req, None, USER_1)
        assert exc.value.status_code == 503

    # get_key_bundle: NOT_MATCHED, None, DatabaseAccessError, low prekey replenishment
    with (
        patch("app.api.chat.keys.redis_client") as mock_redis,
        patch(
            "app.api.chat.keys.fetch_x3dh_key_bundle_unified",
            return_value=(None, "NOT_MATCHED"),
        ),
    ):
        mock_redis.get = AsyncMock(return_value=None)
        with pytest.raises(HTTPException) as exc:
            await get_key_bundle(req, USER_2, None, USER_1)
        assert exc.value.status_code == 403

    with (
        patch("app.api.chat.keys.redis_client") as mock_redis,
        patch(
            "app.api.chat.keys.fetch_x3dh_key_bundle_unified",
            side_effect=DatabaseAccessError("DB fail"),
        ),
    ):
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
    with (
        patch("app.api.chat.keys.redis_client") as mock_redis,
        patch(
            "app.api.chat.keys.fetch_x3dh_key_bundle_unified",
            return_value=(bundle_dict, None),
        ),
        patch("app.api.chat.keys.count_unused_one_time_prekeys", return_value=5),
        patch("app.api.chat.keys.send_prekey_replenishment_notification"),
    ):
        mock_redis.get = AsyncMock(return_value=None)
        mock_redis.set = AsyncMock(return_value=True)
        res_bundle = await get_key_bundle(req, USER_2, None, USER_1)
        assert res_bundle.user_id == USER_2

    # establish_session: DatabaseAccessError
    est_req = EstablishSessionRequest(conversation_id=CONV_1)
    with patch(
        "app.api.chat.keys.mark_session_established",
        side_effect=DatabaseAccessError("DB fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await establish_session(req, est_req, None, USER_1)
        assert exc.value.status_code == 503


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

    with patch(
        "app.api.chat.presence.fetch_active_matches_for_targets", return_value=set(),
    ):
        res_no_match = await _resolve_batch_presence(USER_1, [USER_2])
        assert not res_no_match[USER_2].is_online

    with (
        patch(
            "app.api.chat.presence.fetch_active_matches_for_targets",
            return_value={USER_2},
        ),
        patch(
            "app.db.discovery.get_cached_active_block_ids",
            side_effect=[{USER_2}, set()],
        ),
    ):
        res_blocked = await _resolve_batch_presence(USER_1, [USER_2])
        assert not res_blocked[USER_2].is_online

    with (
        patch(
            "app.api.chat.presence.fetch_active_matches_for_targets",
            return_value={USER_2},
        ),
        patch(
            "app.db.discovery.get_cached_active_block_ids",
            side_effect=[set(), {USER_1}],
        ),
    ):
        res_target_blocked = await _resolve_batch_presence(USER_1, [USER_2])
        assert not res_target_blocked[USER_2].is_online

    with (
        patch(
            "app.api.chat.presence.fetch_active_matches_for_targets",
            return_value={USER_2},
        ),
        patch("app.db.discovery.get_cached_active_block_ids", return_value=set()),
        patch(
            "app.api.chat.presence.batch_fetch_user_share_flags",
            return_value={USER_2: {"share_active_status": False}},
        ),
    ):
        res_no_share = await _resolve_batch_presence(USER_1, [USER_2])
        assert not res_no_share[USER_2].is_online

    # Redis decode error -> DB fallback with invalid date
    now_iso = datetime.now(timezone.utc).isoformat()
    with (
        patch(
            "app.api.chat.presence.fetch_active_matches_for_targets",
            return_value={USER_2},
        ),
        patch("app.db.discovery.get_cached_active_block_ids", return_value=set()),
        patch(
            "app.api.chat.presence.batch_fetch_user_share_flags",
            return_value={USER_2: {"share_active_status": True}},
        ),
        patch("app.api.chat.presence.redis_client") as mock_redis,
        patch(
            "app.api.chat.presence.batch_fetch_presence_from_db",
            return_value={
                USER_2: {"is_online": True, "last_active_at": "invalid_date"},
            },
        ),
    ):
        mock_redis.mget = AsyncMock(return_value=["malformed_json"])
        res_db_fallback = await _resolve_batch_presence(USER_1, [USER_2])
        assert not res_db_fallback[USER_2].is_online

    # Redis success with valid online presence
    with (
        patch(
            "app.api.chat.presence.fetch_active_matches_for_targets",
            return_value={USER_2},
        ),
        patch("app.db.discovery.get_cached_active_block_ids", return_value=set()),
        patch(
            "app.api.chat.presence.batch_fetch_user_share_flags",
            return_value={USER_2: {"share_active_status": True}},
        ),
        patch("app.api.chat.presence.redis_client") as mock_redis,
    ):
        mock_redis.mget = AsyncMock(
            return_value=[f'{{"is_online": true, "last_active_at": "{now_iso}"}}'],
        )
        res_online = await _resolve_batch_presence(USER_1, [USER_2])
        assert res_online[USER_2].is_online is True

    # send_presence_heartbeat: DatabaseAccessError
    hb_req = PresenceHeartbeatRequest(is_online=True)
    with patch(
        "app.api.chat.presence.upsert_presence_heartbeat",
        side_effect=DatabaseAccessError("DB fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await send_presence_heartbeat(req, hb_req, None, USER_1)
        assert exc.value.status_code == 503

    # batch_get_presence: too many IDs (> 50) & DatabaseAccessError
    too_many = BatchPresenceRequest.model_construct(
        user_ids=[f"00000000-0000-0000-0000-0000000000{i:02d}" for i in range(60)],
    )
    with pytest.raises(HTTPException) as exc:
        await batch_get_presence(req, too_many, None, USER_1)
    assert exc.value.status_code == 400

    batch_ok = BatchPresenceRequest(user_ids=[USER_2])
    with patch(
        "app.api.chat.presence._resolve_batch_presence",
        side_effect=DatabaseAccessError("DB fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await batch_get_presence(req, batch_ok, None, USER_1)
        assert exc.value.status_code == 503

    # get_presence: DatabaseAccessError
    with patch(
        "app.api.chat.presence._resolve_single_presence",
        side_effect=DatabaseAccessError("DB fail"),
    ):
        with pytest.raises(HTTPException) as exc:
            await get_presence(req, USER_2, None, USER_1)
        assert exc.value.status_code == 503
