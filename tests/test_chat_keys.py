from unittest.mock import MagicMock, patch

import pytest
from starlette.requests import Request

from app.api.chat.keys import get_key_bundle
from app.models import KeyBundleResponse


@pytest.mark.anyio
@patch("app.api.chat.keys.has_active_match")
@patch("app.api.chat.keys.fetch_key_bundle")
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
            "path": "/api/v1/chat/keys/bundle/target-user-id",
        },
    )

    res = await get_key_bundle(
        request=mock_request,
        target_user_id="target-user-id",
        _device=None,
        user_id="current-user-id",
    )

    assert isinstance(res, KeyBundleResponse)
    assert res.user_id == "target-user-id"
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


