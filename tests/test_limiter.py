from typing import Any, cast
from unittest.mock import MagicMock

import pytest
from starlette.datastructures import Headers
from starlette.requests import Request
from uvicorn.middleware.proxy_headers import ProxyHeadersMiddleware

from app.core.config import settings
from app.core.infra.limiter import get_user_or_ip, limiter


def test_get_user_or_ip_with_verified_user_id():
    """Verified user_id on request.state takes priority."""
    request = MagicMock()
    request.state.user_id = "user-12345"
    request.state.authenticated_user_payload = None

    key = get_user_or_ip(request)
    assert key == "user:user-12345"


def test_get_user_or_ip_with_authenticated_payload():
    """Authenticated payload on request.state is used when user_id is missing."""
    request = MagicMock()
    request.state.user_id = None
    request.state.authenticated_user_payload = {"sub": "user-67890", "email": "test@example.com"}

    key = get_user_or_ip(request)
    assert key == "user:user-67890"

    request.state.authenticated_user_payload = {"id": "user-abcde"}
    key = get_user_or_ip(request)
    assert key == "user:user-abcde"


def test_get_user_or_ip_ignores_unverified_bearer_token():
    """Unverified Authorization Bearer header must NOT be parsed for quota attribution.

    Prevents attacker from forging JWT sub to burn a victim's rate limit.
    """
    request = MagicMock()
    request.state.user_id = None
    request.state.authenticated_user_payload = None
    # Forged token containing victim's sub
    request.headers = Headers({
        "authorization": "Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ2aWN0aW0tdXVpZCJ9.invalidsignature",
    })
    request.client.host = "192.168.1.100"

    key = get_user_or_ip(request)
    assert key == "192.168.1.100"
    assert "victim-uuid" not in key


def test_get_user_or_ip_fallback_to_ip_anonymous():
    """Anonymous request without auth falls back to client IP."""
    request = MagicMock()
    request.state.user_id = None
    request.state.authenticated_user_payload = None
    request.headers = Headers({})
    request.client.host = "203.0.113.42"

    key = get_user_or_ip(request)
    assert key == "203.0.113.42"


def test_limiter_redis_storage_backend():
    """Verify SlowAPI Limiter is configured with Redis storage backend using settings.redis_url."""
    limiter_any = cast(Any, limiter)
    assert limiter_any._storage_uri == settings.redis_url
    storage_repr = repr(limiter_any._storage).lower()
    assert "redis" in storage_repr or "redis" in str(limiter_any._storage_uri).lower()


@pytest.mark.anyio
async def test_proxy_headers_middleware_extracts_client_ip():
    """Verify ProxyHeadersMiddleware correctly unwraps X-Forwarded-For to derive client IP."""
    received_client_host = None

    async def dummy_app(scope: Any, receive: Any, send: Any) -> None:
        nonlocal received_client_host
        req = Request(scope)
        received_client_host = get_user_or_ip(req)
        await send({"type": "http.response.start", "status": 200, "headers": []})
        await send({"type": "http.response.body", "body": b"ok"})

    middleware = ProxyHeadersMiddleware(dummy_app, trusted_hosts="*")

    scope: dict[str, Any] = {
        "type": "http",
        "method": "GET",
        "path": "/api/v1/test",
        "headers": [
            (b"host", b"nexus.internal"),
            (b"x-forwarded-for", b"198.51.100.75, 10.0.0.1"),
            (b"x-forwarded-proto", b"https"),
        ],
        "client": ("10.0.0.1", 54321),
    }

    async def dummy_receive() -> dict[str, Any]:
        return {"type": "http.request"}

    async def dummy_send(msg: Any) -> None:
        pass

    await middleware(cast(Any, scope), cast(Any, dummy_receive), cast(Any, dummy_send))

    # ProxyHeadersMiddleware should unwrap to the original untrusted client IP
    assert received_client_host == "198.51.100.75"
    assert scope["client"][0] == "198.51.100.75"
    assert scope["scheme"] == "https"




