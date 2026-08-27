"""Test Suite for Test Auth Core.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
import json
from typing import Any, cast
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePublicKey
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.security.jwks import (
    _find_jwk_by_kid,
    _isolate_fallback_jwk,
    _parse_jwk_dict,
    clear_jwks_cache,
    get_fallback_public_key,
    get_live_supabase_public_key,
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


async def test_core_jwks_deep() -> None:
    clear_jwks_cache()

    # parse_jwk_dict
    parsed = _parse_jwk_dict(
        {"kid": "k1", "kty": "EC", "crv": "P-256", "x": "abc", "y": "def"},
    )
    assert parsed["kid"] == "k1"

    with pytest.raises(Exception):
        _parse_jwk_dict("{malformed-json")
    with pytest.raises(Exception):
        _parse_jwk_dict(123)

    # find_jwk_by_kid
    keys: list[dict[str, str]] = [{"kid": "k1"}, {"kid": "k2"}]
    assert _find_jwk_by_kid(cast(list[object], keys), "k1") == {"kid": "k1"}
    assert _find_jwk_by_kid(cast(list[object], keys), "missing") is None

    # isolate_fallback_jwk
    fallback_doc = {"keys": [{"kid": "f1", "kty": "EC"}, {"kid": "f2"}]}
    assert _isolate_fallback_jwk(fallback_doc, "f1") == {"kid": "f1", "kty": "EC"}
    assert _isolate_fallback_jwk(fallback_doc, None) == {"kid": "f1", "kty": "EC"}

    # get_fallback_public_key with real EC key
    private_key = ec.generate_private_key(ec.SECP256R1())
    real_public_key = private_key.public_key()

    mock_fb_jwk = {"kty": "EC", "crv": "P-256", "kid": "fallback-kid"}
    with (
        patch(
            "app.core.security.jwks.settings.supabase_jwt_secret",
            json.dumps({"keys": [mock_fb_jwk]}),
        ),
        patch("app.core.security.jwks.PyJWK") as mock_pyjwk,
    ):
        mock_pyjwk.return_value.key = real_public_key
        key = get_fallback_public_key("fallback-kid")
        assert isinstance(key, EllipticCurvePublicKey)

    # get_live_supabase_public_key
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {"keys": [mock_fb_jwk]}

    mock_client = AsyncMock()
    mock_client.get.return_value = mock_resp

    dummy_token = jwt.encode({"sub": USER_1}, "secret", headers={"kid": "fallback-kid"})
    with (
        patch("app.core.security.jwks._get_jwks_client", return_value=mock_client),
        patch(
            "app.core.security.jwks._resolve_key_from_cache",
            return_value=real_public_key,
        ),
    ):
        live_key = await get_live_supabase_public_key(dummy_token)
        assert isinstance(live_key, EllipticCurvePublicKey)
