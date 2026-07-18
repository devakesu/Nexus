from unittest.mock import MagicMock, patch
import pytest
from starlette.requests import Request
from app.api.chat_keys import get_key_bundle
from app.models import KeyBundleResponse

@pytest.mark.anyio
@patch("app.api.chat_keys.has_active_match")
@patch("app.api.chat_keys.fetch_key_bundle")
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
    }
    
    mock_request = Request(scope={
        "type": "http",
        "client": ("127.0.0.1", 1234),
        "headers": [],
        "path": "/api/v1/chat/keys/bundle/target-user-id"
    })
    
    res = await get_key_bundle(
        request=mock_request,
        target_user_id="target-user-id",
        _device=None,
        user_id="current-user-id"
    )
    
    assert isinstance(res, KeyBundleResponse)
    assert res.user_id == "target-user-id"
    assert res.identity_public_key == b"\x05.AqK9s \x0c\xd2&\xe7"
    assert res.signed_prekey_public == b"\x05\x1b\xbd\nU\xaf\xa1"
    assert res.signed_prekey_signature == b"m#:\x9f\x8f\xa3\xa8\x07"
    assert res.one_time_prekey_id == 99
    assert res.one_time_prekey_public == b"\x05\xfb\xd1\x1c\xd1\x0b"
