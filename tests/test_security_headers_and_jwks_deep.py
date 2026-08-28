"""Unit tests for security headers, streaming request size limits, and deep JWKS fallback mechanics."""

from typing import Any, cast
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from starlette.requests import Request
from starlette.responses import PlainTextResponse, Response

from app.core.security.jwks import (
    _fetch_and_update_cached_jwks,
    _resolve_key_from_cache,
    get_fallback_public_key,
    syntax_has_kid,
)
from app.core.security.security import (
    RequestSizeLimitMiddleware,
    SecurityHeadersMiddleware,
)


@pytest.mark.anyio
async def test_request_size_limit_middleware_streaming_and_invalid_header():
    """Test RequestSizeLimitMiddleware streaming cutoff at 10MB and invalid Content-Length handling."""
    middleware = RequestSizeLimitMiddleware(app=MagicMock())

    # 1. Invalid non-numeric Content-Length header is ignored
    async def dummy_receive_small() -> dict[str, Any]:
        return {"type": "http.request", "body": b"hello"}

    req_invalid_cl = Request(
        scope={
            "type": "http",
            "method": "POST",
            "path": "/test",
            "headers": [(b"content-length", b"not-a-number")],
        },
        receive=dummy_receive_small,
    )

    async def call_next_success(_req: Request) -> Response:
        receive_func = cast(Any, _req)._receive
        await receive_func()
        return PlainTextResponse("ok")

    resp = await middleware.dispatch(req_invalid_cl, call_next_success)
    assert resp.status_code == 200

    # 2. Streaming chunks exceeding MAX_REQUEST_BODY_SIZE triggers 413
    chunks = [
        {"type": "http.request", "body": b"A" * (6 * 1024 * 1024)},
        {"type": "http.request", "body": b"B" * (5 * 1024 * 1024)},
    ]

    async def dummy_receive_large() -> dict[str, Any]:
        if chunks:
            return chunks.pop(0)
        return {"type": "http.request", "body": b""}

    req_streaming_large = Request(
        scope={
            "type": "http",
            "method": "POST",
            "path": "/upload",
            "headers": [],
        },
        receive=dummy_receive_large,
    )

    async def call_next_consume(_req: Request) -> Response:
        receive_func = cast(Any, _req)._receive
        while True:
            msg = cast(dict[str, Any], await receive_func())
            if not msg.get("body"):
                break
        return PlainTextResponse("ok")

    resp_large = await middleware.dispatch(req_streaming_large, call_next_consume)
    assert resp_large.status_code == 413


@pytest.mark.anyio
async def test_security_headers_middleware_static_and_dynamic():
    """Test SecurityHeadersMiddleware sets proper CSP, HSTS, and cache controls."""
    middleware = SecurityHeadersMiddleware(app=MagicMock())

    async def dummy_static_handler(_req: Request) -> Response:
        return PlainTextResponse("image")

    async def dummy_api_handler(_req: Request) -> Response:
        return PlainTextResponse("api")

    # 1. Static asset
    req_static = Request(scope={"type": "http", "method": "GET", "path": "/static/test.png", "headers": []})
    resp_static = await middleware.dispatch(req_static, dummy_static_handler)
    assert resp_static.headers["Cross-Origin-Resource-Policy"] == "cross-origin"
    assert "public" in resp_static.headers["Cache-Control"]

    # 2. API route
    req_api = Request(scope={"type": "http", "method": "GET", "path": "/api/v1/users", "headers": []})
    resp_api = await middleware.dispatch(req_api, dummy_api_handler)
    assert resp_api.headers["Cross-Origin-Resource-Policy"] == "same-origin"
    assert resp_api.headers["Cache-Control"] == "no-store, max-age=0"
    assert "Strict-Transport-Security" in resp_api.headers


@pytest.mark.anyio
async def test_fetch_and_update_cached_jwks_errors():
    """Test JWKS fetch handling non-200 status, HTTP errors, and general exceptions."""
    import app.core.security.jwks as jwks_mod

    # 1. Non-200 status
    mock_client = AsyncMock()
    mock_resp = MagicMock(status_code=500, text="Internal Error")
    mock_client.get.return_value = mock_resp

    with patch("app.core.security.jwks._get_jwks_client", return_value=mock_client):
        with patch("app.core.security.jwks.sentry_sdk.capture_message") as mock_sentry_msg:
            await _fetch_and_update_cached_jwks(1000.0)
            assert jwks_mod._last_fetch_failure_time == 1000.0
            mock_sentry_msg.assert_called_once()

    # 2. HTTPError
    mock_client.get.side_effect = httpx.ConnectError("Connection failed")
    with patch("app.core.security.jwks._get_jwks_client", return_value=mock_client):
        with patch("app.core.security.jwks.sentry_sdk.capture_exception") as mock_sentry_exc:
            await _fetch_and_update_cached_jwks(2000.0)
            assert jwks_mod._last_fetch_failure_time == 2000.0
            mock_sentry_exc.assert_called_once()

    # 3. General Exception
    mock_client.get.side_effect = RuntimeError("Fatal client explosion")
    with patch("app.core.security.jwks._get_jwks_client", return_value=mock_client):
        with patch("app.core.security.jwks.sentry_sdk.capture_exception") as mock_sentry_exc:
            await _fetch_and_update_cached_jwks(3000.0)
            assert jwks_mod._last_fetch_failure_time == 3000.0
            mock_sentry_exc.assert_called_once()


def test_resolve_key_and_syntax_has_kid_linear_fallbacks():
    """Test JWKS key resolution and syntax check when dictionary cache is empty."""
    import app.core.security.jwks as jwks_mod

    jwks_mod._cached_keys_by_kid = {}
    jwks_mod._cached_jwks = None

    # Both empty -> returns None
    assert _resolve_key_from_cache("kid-1") is None

    # syntax_has_kid fallback to jwk_set linear search
    mock_jwk1 = MagicMock(key_id="kid-1")
    mock_jwk2 = MagicMock(key_id="kid-2")
    mock_set = MagicMock(keys=[mock_jwk1, mock_jwk2])

    assert syntax_has_kid(mock_set, "kid-1") is True
    assert syntax_has_kid(mock_set, "kid-3") is False


def test_get_fallback_public_key_type_error():
    """Test get_fallback_public_key raising RuntimeError on parsing failure."""
    with patch("app.core.security.jwks._parse_jwk_dict", return_value={"kty": "RSA"}):
        with patch("app.core.security.jwks._isolate_fallback_jwk", return_value={"kty": "RSA"}):
            with patch("app.core.security.jwks.PyJWK") as mock_pyjwk:
                mock_pyjwk.return_value.key = "not-an-ec-key"
                with pytest.raises(RuntimeError, match="CRITICAL: Failed to unpack local static fallback public key"):
                    get_fallback_public_key("test-kid")
