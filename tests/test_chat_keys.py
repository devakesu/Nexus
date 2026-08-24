from unittest.mock import MagicMock, patch

import pytest
from starlette.requests import Request

from app.api.chat.keys import get_key_bundle
from app.models import KeyBundleResponse


@pytest.mark.anyio
@patch("app.db.chat.keys.has_active_match")
@patch("app.db.chat.keys.fetch_key_bundle")
async def test_get_key_bundle_success(
    mock_fetch_key_bundle: MagicMock,
    mock_has_active_match: MagicMock,
) -> None:
    mock_has_active_match.return_value = True
    mock_fetch_key_bundle.return_value = {
        "identity_public_key": b"\x05.AqK9s \x0c\xd2&\xe7",
        "registration_id": 12345,
        "signed_prekey_id": 1,
        "signed_prekey_public": b"\x05\x1b\xbd\nU\xaf\xa1",
        "signed_prekey_signature": b"m#:\x9f\x8f\xa3\xa8\x07",
        "one_time_prekey_id": 99,
        "one_time_prekey_public": b"\x05\xfb\xd1\x1c\xd1\x0b",
        "one_time_prekey_used": True,
    }

    mock_request = Request(
        scope={
            "type": "http",
            "client": ("127.0.0.1", 1234),
            "headers": [],
            "path": "/api/v1/chat/keys/bundle/22222222-2222-2222-2222-222222222222",
        },
    )

    res = await get_key_bundle(
        request=mock_request,
        target_user_id="22222222-2222-2222-2222-222222222222",
        _device=None,
        user_id="11111111-1111-1111-1111-111111111111",
    )

    assert isinstance(res, KeyBundleResponse)
    assert res.user_id == "22222222-2222-2222-2222-222222222222"
    assert res.identity_public_key == b"\x05.AqK9s \x0c\xd2&\xe7"
    assert res.signed_prekey_public == b"\x05\x1b\xbd\nU\xaf\xa1"
    assert res.signed_prekey_signature == b"m#:\x9f\x8f\xa3\xa8\x07"
    assert res.one_time_prekey_id == 99
    assert res.one_time_prekey_public == b"\x05\xfb\xd1\x1c\xd1\x0b"
    assert res.one_time_prekey_used is True


@pytest.mark.anyio
@patch("app.api.chat.keys.upsert_signed_prekey")
@patch("app.api.chat.keys.fetch_identity_key")
async def test_upload_signed_prekey_success(
    mock_fetch_identity_key: MagicMock,
    mock_upsert_signed_prekey: MagicMock,
) -> None:
    import base64
    from app.api.chat.keys import upload_signed_prekey
    from app.models import UploadSignedPrekeyRequest

    ik_b64 = "BR8E73u1SCcDUAPQ60LRQwVY4OCtbqenWTbMl6ivUuVV"
    spk_b64 = "BUHa0WwzYMms6/U8Deadyw20dmaQ9HwN0p1dBuv45JAn"
    sig_b64 = (
        "wV3OLnTNNC7IGSrRCDuQqY+tSxF+Sn5Dyrl6Lx/kgid2kio8v2FQzcU2Ug18swxcQuYAD3snFDYc7n44e7W8CQ=="
    )

    ik_pub = base64.b64decode(ik_b64)
    spk_pub = base64.b64decode(spk_b64)
    sig = base64.b64decode(sig_b64)

    mock_fetch_identity_key.return_value = {
        "identity_public_key": ik_pub,
        "registration_id": 1234,
    }

    mock_request = Request(
        scope={
            "type": "http",
            "client": ("127.0.0.1", 1234),
            "headers": [],
            "path": "/api/v1/chat/keys/signed-prekey",
        },
    )

    payload = UploadSignedPrekeyRequest.model_validate(
        {
            "key_id": 1,
            "public_key": spk_b64,
            "signature": sig_b64,
        }
    )

    res = await upload_signed_prekey(
        request=mock_request,
        payload=payload,
        _device=None,
        user_id="test-user-id",
    )

    assert res == {"success": True}
    mock_upsert_signed_prekey.assert_called_once_with(
        "test-user-id", 1, spk_pub, sig,
    )


@pytest.mark.anyio
@patch("app.api.chat.keys.fetch_identity_key")
async def test_upload_signed_prekey_no_identity(
    mock_fetch_identity_key: MagicMock,
) -> None:
    import base64
    from fastapi import HTTPException
    from app.api.chat.keys import upload_signed_prekey
    from app.models import UploadSignedPrekeyRequest

    mock_fetch_identity_key.return_value = None

    mock_request = Request(
        scope={
            "type": "http",
            "client": ("127.0.0.1", 1234),
            "headers": [],
            "path": "/api/v1/chat/keys/signed-prekey",
        },
    )

    payload = UploadSignedPrekeyRequest.model_validate(
        {
            "key_id": 1,
            "public_key": base64.b64encode(b"\x05" + b"\x01" * 32).decode(),
            "signature": base64.b64encode(b"\x00" * 64).decode(),
        }
    )

    with pytest.raises(HTTPException) as exc:
        await upload_signed_prekey(
            request=mock_request,
            payload=payload,
            _device=None,
            user_id="test-user-id",
        )

    assert exc.value.status_code == 400
    assert "Identity key not registered" in exc.value.detail


@pytest.mark.anyio
@patch("app.api.chat.keys.fetch_identity_key")
async def test_upload_signed_prekey_invalid_signature(
    mock_fetch_identity_key: MagicMock,
) -> None:
    import base64
    from fastapi import HTTPException
    from app.api.chat.keys import upload_signed_prekey
    from app.models import UploadSignedPrekeyRequest

    ik_pub = base64.b64decode("BR8E73u1SCcDUAPQ60LRQwVY4OCtbqenWTbMl6ivUuVV")
    spk_b64 = "BUHa0WwzYMms6/U8Deadyw20dmaQ9HwN0p1dBuv45JAn"

    mock_fetch_identity_key.return_value = {
        "identity_public_key": ik_pub,
        "registration_id": 1234,
    }

    mock_request = Request(
        scope={
            "type": "http",
            "client": ("127.0.0.1", 1234),
            "headers": [],
            "path": "/api/v1/chat/keys/signed-prekey",
        },
    )

    payload = UploadSignedPrekeyRequest.model_validate(
        {
            "key_id": 1,
            "public_key": spk_b64,
            "signature": base64.b64encode(b"\x00" * 64).decode(),  # Invalid signature
        }
    )

    with pytest.raises(HTTPException) as exc:
        await upload_signed_prekey(
            request=mock_request,
            payload=payload,
            _device=None,
            user_id="test-user-id",
        )

    assert exc.value.status_code == 400
    assert exc.value.detail == "Signed prekey signature invalid"


@pytest.mark.anyio
@patch("app.db.chat.keys.has_active_match")
@patch("app.db.chat.keys.fetch_key_bundle")
@patch("app.api.chat.keys.redis_client")
@patch("app.api.chat.keys.count_unused_one_time_prekeys")
async def test_key_bundle_rate_limiting_per_peer(
    mock_count_unused: MagicMock,
    mock_redis: MagicMock,
    mock_fetch_key_bundle: MagicMock,
    mock_has_active_match: MagicMock,
) -> None:
    from unittest.mock import AsyncMock
    mock_has_active_match.return_value = True
    mock_count_unused.return_value = 50  # healthy pool

    bundle_data = {
        "identity_public_key": b"\x05.AqK9s \x0c\xd2&\xe7",
        "registration_id": 12345,
        "signed_prekey_id": 1,
        "signed_prekey_public": b"\x05\x1b\xbd\nU\xaf\xa1",
        "signed_prekey_signature": b"m#:\x9f\x8f\xa3\xa8\x07",
        "one_time_prekey_id": 99,
        "one_time_prekey_public": b"\x05\xfb\xd1\x1c\xd1\x0b",
        "one_time_prekey_used": True,
    }
    mock_fetch_key_bundle.return_value = bundle_data

    # First call: cache miss
    cached_store: dict[str, str] = {}
    async def mock_get(key: str):
        return cached_store.get(key)
    async def mock_set(key: str, val: str, ex: int | None = None):
        cached_store[key] = val
        return True

    mock_redis.get = AsyncMock(side_effect=mock_get)
    mock_redis.set = AsyncMock(side_effect=mock_set)

    mock_request = Request(
        scope={
            "type": "http",
            "client": ("127.0.0.1", 1234),
            "headers": [],
            "path": "/api/v1/chat/keys/bundle/22222222-2222-2222-2222-222222222222",
        },
    )

    # 1st request -> fetches from DB and populates cache
    res1 = await get_key_bundle(
        request=mock_request,
        target_user_id="22222222-2222-2222-2222-222222222222",
        _device=None,
        user_id="11111111-1111-1111-1111-111111111111",
    )
    assert res1.one_time_prekey_id == 99
    assert mock_fetch_key_bundle.call_count == 1

    # 2nd request from same caller -> served from Redis cache without hitting DB
    res2 = await get_key_bundle(
        request=mock_request,
        target_user_id="22222222-2222-2222-2222-222222222222",
        _device=None,
        user_id="11111111-1111-1111-1111-111111111111",
    )
    assert res2.one_time_prekey_id == 99
    assert res2.signed_prekey_id == res1.signed_prekey_id
    assert mock_fetch_key_bundle.call_count == 1  # Still 1, did not consume another OTPK!


@pytest.mark.anyio
@patch("app.db.chat.keys.has_active_match")
@patch("app.db.chat.keys.fetch_key_bundle")
@patch("app.api.chat.keys.redis_client")
@patch("app.api.chat.keys.count_unused_one_time_prekeys")
@patch("app.api.chat.keys.send_prekey_replenishment_notification")
async def test_prekey_exhaustion_low_pool_alert(
    mock_send_push: MagicMock,
    mock_count_unused: MagicMock,
    mock_redis: MagicMock,
    mock_fetch_key_bundle: MagicMock,
    mock_has_active_match: MagicMock,
) -> None:
    from unittest.mock import AsyncMock
    mock_has_active_match.return_value = True
    mock_count_unused.return_value = 5  # Low pool (< 15)

    mock_fetch_key_bundle.return_value = {
        "identity_public_key": b"\x05.AqK9s \x0c\xd2&\xe7",
        "registration_id": 12345,
        "signed_prekey_id": 1,
        "signed_prekey_public": b"\x05\x1b\xbd\nU\xaf\xa1",
        "signed_prekey_signature": b"m#:\x9f\x8f\xa3\xa8\x07",
        "one_time_prekey_id": 10,
        "one_time_prekey_public": b"\x05\xfb\xd1\x1c\xd1\x0b",
        "one_time_prekey_used": True,
    }

    mock_redis.get = AsyncMock(return_value=None)
    mock_redis.set = AsyncMock(return_value=True)

    mock_request = Request(
        scope={
            "type": "http",
            "client": ("127.0.0.1", 1234),
            "headers": [],
            "path": "/api/v1/chat/keys/bundle/22222222-2222-2222-2222-222222222222",
        },
    )

    await get_key_bundle(
        request=mock_request,
        target_user_id="22222222-2222-2222-2222-222222222222",
        _device=None,
        user_id="11111111-1111-1111-1111-111111111111",
    )

    # Allow spawned task to execute
    import asyncio
    await asyncio.sleep(0.01)
    mock_send_push.assert_called_once_with("22222222-2222-2222-2222-222222222222")


@pytest.mark.anyio
@patch("app.services.fcm_sender._is_firebase_initialized", return_value=True)
@patch("app.services.fcm_sender._fetch_user_fcm_tokens", return_value=["token-123"])
@patch("app.services.fcm_sender._send_to_tokens")
async def test_send_prekey_replenishment_notification(
    mock_send: MagicMock,
    _mock_tokens: MagicMock,
    _mock_init: MagicMock,
) -> None:
    from app.services.fcm_sender import send_prekey_replenishment_notification
    mock_send.return_value = 1

    await send_prekey_replenishment_notification("target-user-id")

    mock_send.assert_called_once_with(
        ["token-123"],
        None,
        None,
        {"type": "replenish_prekeys"},
        "chat_messages",
    )


@patch("app.db.chat.keys.supabase_client.table")
def test_upsert_identity_key_deactivates_prior_user_devices(mock_table: MagicMock) -> None:
    from app.db.chat.keys import upsert_identity_key

    builder = MagicMock()
    builder.upsert.return_value = builder
    builder.delete.return_value = builder
    builder.update.return_value = builder
    builder.eq.return_value = builder
    builder.execute.return_value = MagicMock(data=[])
    mock_table.return_value = builder

    upsert_identity_key(
        user_id="user-xyz-123",
        identity_public_key=b"\x05" + b"\x02" * 32,
        registration_id=9999,
    )

    # Verify user_devices update was executed to deactivate prior tokens
    mock_table.assert_any_call("user_devices")
    builder.update.assert_called_with({"is_active": False})
    builder.eq.assert_any_call("user_id", "user-xyz-123")


@patch("app.db.chat.keys.supabase_client.rpc")
def test_fetch_x3dh_key_bundle_unified_rpc(mock_rpc: MagicMock) -> None:
    from app.db.chat.keys import fetch_x3dh_key_bundle_unified

    mock_rpc_builder = MagicMock()
    mock_rpc_builder.execute.return_value = MagicMock(
        data={
            "identity_public_key": "\\x052e41714b3973200cd226e7",
            "registration_id": 12345,
            "signed_prekey_id": 1,
            "signed_prekey_public": "\\x051bbd0a55afa1",
            "signed_prekey_signature": "\\x6d233a9f8fa3a807",
            "one_time_prekey_id": 99,
            "one_time_prekey_public": "\\x05fbd11cd10b",
            "one_time_prekey_used": True,
        }
    )
    mock_rpc.return_value = mock_rpc_builder

    bundle, error_code = fetch_x3dh_key_bundle_unified(
        "11111111-1111-1111-1111-111111111111",
        "22222222-2222-2222-2222-222222222222",
    )

    assert error_code is None
    assert bundle is not None
    assert bundle["registration_id"] == 12345
    assert bundle["signed_prekey_id"] == 1
    assert bundle["one_time_prekey_id"] == 99
    assert bundle["one_time_prekey_used"] is True
    # Single RPC call dispatched with normalized UUIDs
    mock_rpc.assert_called_once_with(
        "get_x3dh_key_bundle",
        {
            "p_requester_id": "11111111-1111-1111-1111-111111111111",
            "p_target_id": "22222222-2222-2222-2222-222222222222",
        },
    )





