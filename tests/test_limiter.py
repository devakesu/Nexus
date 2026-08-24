"""Tests for rate limiting key generation and security."""

from unittest.mock import MagicMock

from starlette.datastructures import Headers

from app.core.infra.limiter import get_user_or_ip


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
    from typing import Any, cast
    from app.core.config import settings
    from app.core.infra.limiter import limiter

    limiter_any = cast(Any, limiter)
    assert limiter_any._storage_uri == settings.redis_url
    storage_repr = repr(limiter_any._storage).lower()
    assert "redis" in storage_repr or "redis" in str(limiter_any._storage_uri).lower()


