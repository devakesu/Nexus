"""Unit tests for JWKS key retrieval, cache TTL, rotation, and force-refresh."""

import time
from collections.abc import Generator
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException
from starlette.requests import Request

from app.api.admin import flush_jwks_cache_endpoint, verify_internal_admin_token
from app.api.dependencies import (
    get_authenticated_user_payload,
    get_optional_authenticated_user_id,
)
from app.core.security import jwks
from app.core.security.jwks import (
    JWKS_CACHE_TTL_SECONDS,
    clear_jwks_cache,
    get_live_supabase_public_key,
)


def _generate_ec_key_pair() -> tuple[ec.EllipticCurvePrivateKey, ec.EllipticCurvePublicKey]:
    priv = ec.generate_private_key(ec.SECP256R1())
    return priv, priv.public_key()


@pytest.fixture(autouse=True)
def reset_jwks_state() -> Generator[None, None, None]:
    clear_jwks_cache()
    yield
    clear_jwks_cache()


def test_jwks_cache_ttl_constant() -> None:
    """Ensure JWKS cache TTL is set to 15 minutes (900 seconds)."""
    assert JWKS_CACHE_TTL_SECONDS == 900.0


@pytest.mark.anyio
async def test_get_live_supabase_public_key_fetches_and_caches() -> None:
    """Verify that remote JWKS is fetched and cached, not refetched on subsequent calls within TTL."""
    priv, pub = _generate_ec_key_pair()
    token = jwt.encode({"sub": "user-123"}, priv, algorithm="ES256", headers={"kid": "kid-1"})

    mock_jwk = MagicMock()
    mock_jwk.key_id = "kid-1"
    mock_jwk.key = pub

    mock_jwk_set = MagicMock()
    mock_jwk_set.keys = [mock_jwk]

    with patch("app.core.security.jwks.PyJWKSet.from_dict", return_value=mock_jwk_set), \
         patch("app.core.security.jwks._get_jwks_client") as mock_client_factory:
        mock_client = AsyncMock()
        mock_response = MagicMock(status_code=200)
        mock_response.json.return_value = {"keys": [{"kid": "kid-1"}]}
        mock_client.get.return_value = mock_response
        mock_client_factory.return_value = mock_client

        # First call fetches from remote
        key1 = await get_live_supabase_public_key(token)
        assert key1 == pub
        assert mock_client.get.call_count == 1

        # Second call within TTL with same kid uses cache (no additional HTTP GET)
        key2 = await get_live_supabase_public_key(token)
        assert key2 == pub
        assert mock_client.get.call_count == 1


@pytest.mark.anyio
async def test_get_live_supabase_public_key_expired_ttl_refetches() -> None:
    """Verify that cache expiration (> 3600s) triggers a refetch."""
    priv, pub = _generate_ec_key_pair()
    token = jwt.encode({"sub": "user-123"}, priv, algorithm="ES256", headers={"kid": "kid-1"})

    mock_jwk = MagicMock()
    mock_jwk.key_id = "kid-1"
    mock_jwk.key = pub

    mock_jwk_set = MagicMock()
    mock_jwk_set.keys = [mock_jwk]

    with patch("app.core.security.jwks.PyJWKSet.from_dict", return_value=mock_jwk_set), \
         patch("app.core.security.jwks._get_jwks_client") as mock_client_factory:
        mock_client = AsyncMock()
        mock_response = MagicMock(status_code=200)
        mock_response.json.return_value = {"keys": [{"kid": "kid-1"}]}
        mock_client.get.return_value = mock_response
        mock_client_factory.return_value = mock_client

        # Initial fetch
        await get_live_supabase_public_key(token)
        assert mock_client.get.call_count == 1

        # Simulate time passing beyond 900s
        jwks._last_fetch_time = time.time() - 901

        # Next call should trigger refetch
        await get_live_supabase_public_key(token)
        assert mock_client.get.call_count == 2


@pytest.mark.anyio
async def test_get_live_supabase_public_key_force_refresh() -> None:
    """Verify that force_refresh=True forces an immediate refetch regardless of cache age."""
    priv, pub = _generate_ec_key_pair()
    token = jwt.encode({"sub": "user-123"}, priv, algorithm="ES256", headers={"kid": "kid-1"})

    mock_jwk = MagicMock()
    mock_jwk.key_id = "kid-1"
    mock_jwk.key = pub

    mock_jwk_set = MagicMock()
    mock_jwk_set.keys = [mock_jwk]

    with patch("app.core.security.jwks.PyJWKSet.from_dict", return_value=mock_jwk_set), \
         patch("app.core.security.jwks._get_jwks_client") as mock_client_factory:
        mock_client = AsyncMock()
        mock_response = MagicMock(status_code=200)
        mock_response.json.return_value = {"keys": [{"kid": "kid-1"}]}
        mock_client.get.return_value = mock_response
        mock_client_factory.return_value = mock_client

        # First call
        await get_live_supabase_public_key(token)
        assert mock_client.get.call_count == 1

        # Force refresh call
        await get_live_supabase_public_key(token, force_refresh=True)
        assert mock_client.get.call_count == 2


@pytest.mark.anyio
async def test_get_live_supabase_public_key_rejects_revoked_kid_when_cache_active() -> None:
    """Verify that when JWKS cache is active, an unrecognized/revoked kid raises InvalidTokenError."""
    priv, pub = _generate_ec_key_pair()
    token = jwt.encode({"sub": "user-123"}, priv, algorithm="ES256", headers={"kid": "revoked-kid"})

    mock_jwk = MagicMock()
    mock_jwk.key_id = "active-kid"
    mock_jwk.key = pub

    mock_jwk_set = MagicMock()
    mock_jwk_set.keys = [mock_jwk]

    with patch("app.core.security.jwks.PyJWKSet.from_dict", return_value=mock_jwk_set), \
         patch("app.core.security.jwks._get_jwks_client") as mock_client_factory:
        mock_client = AsyncMock()
        mock_response = MagicMock(status_code=200)
        mock_response.json.return_value = {"keys": [{"kid": "active-kid"}]}
        mock_client.get.return_value = mock_response
        mock_client_factory.return_value = mock_client

        with pytest.raises(jwt.InvalidTokenError, match="revoked"):
            await get_live_supabase_public_key(token)


@pytest.mark.anyio
async def test_auth_dependency_retries_on_signature_error() -> None:
    """Verify that get_authenticated_user_payload retries with force_refresh on InvalidSignatureError."""
    _, pub_old = _generate_ec_key_pair()
    priv_new, pub_new = _generate_ec_key_pair()

    token = jwt.encode(
        {"sub": "user-123", "aud": "authenticated"},
        priv_new,
        algorithm="ES256",
        headers={"kid": "key-id"},
    )

    scope: dict[str, Any] = {"type": "http", "headers": [], "query_string": b"", "path": "/"}
    request = Request(scope)

    # First call returns old key (signature mismatch), second call returns new key
    mock_get_key = AsyncMock(side_effect=[pub_old, pub_new])

    with patch("app.core.config.Settings.is_jwks", new_callable=lambda: property(lambda _self: True)), \
         patch("app.api.dependencies.get_live_supabase_public_key", mock_get_key):
        payload = await get_authenticated_user_payload(request, token)
        assert payload["sub"] == "user-123"
        assert mock_get_key.call_count == 2
        mock_get_key.assert_any_call(token)
        mock_get_key.assert_any_call(token, force_refresh=True)


@pytest.mark.anyio
async def test_optional_auth_dependency_retries_on_signature_error() -> None:
    """Verify that get_optional_authenticated_user_id retries with force_refresh on InvalidSignatureError."""
    _, pub_old = _generate_ec_key_pair()
    priv_new, pub_new = _generate_ec_key_pair()

    token = jwt.encode(
        {"sub": "user-123", "aud": "authenticated"},
        priv_new,
        algorithm="ES256",
        headers={"kid": "key-id"},
    )

    mock_get_key = AsyncMock(side_effect=[pub_old, pub_new])

    with patch("app.core.config.Settings.is_jwks", new_callable=lambda: property(lambda _self: True)), \
         patch("app.api.dependencies.get_live_supabase_public_key", mock_get_key):
        user_id = await get_optional_authenticated_user_id(token)
        assert user_id == "user-123"
        assert mock_get_key.call_count == 2
        mock_get_key.assert_any_call(token)
        mock_get_key.assert_any_call(token, force_refresh=True)


@pytest.mark.anyio
@patch("app.core.security.jwks.sentry_sdk.capture_message")
@patch("app.core.security.jwks._get_jwks_client")
async def test_jwks_fetch_non_200_logs_and_alerts_sentry(
    mock_client_factory: MagicMock,
    mock_capture_message: MagicMock,
) -> None:
    """Verify that unexpected non-200 HTTP response from JWKS endpoint alerts Sentry."""
    mock_client = AsyncMock()
    mock_response = MagicMock(status_code=302, text="Redirected")
    mock_client.get.return_value = mock_response
    mock_client_factory.return_value = mock_client

    await jwks._fetch_and_update_cached_jwks(time.time())

    mock_capture_message.assert_called_once()
    assert "302" in mock_capture_message.call_args[0][0]


@pytest.mark.anyio
@patch("app.core.security.jwks.sentry_sdk.capture_exception")
@patch("app.core.security.jwks._get_jwks_client")
async def test_jwks_fetch_network_error_alerts_sentry(
    mock_client_factory: MagicMock,
    mock_capture_exception: MagicMock,
) -> None:
    """Verify that httpx network errors during JWKS fetch alert Sentry."""
    import httpx

    mock_client = AsyncMock()
    mock_client.get.side_effect = httpx.ConnectError("Connection refused")
    mock_client_factory.return_value = mock_client

    await jwks._fetch_and_update_cached_jwks(time.time())

    mock_capture_exception.assert_called_once()


@pytest.mark.anyio
async def test_admin_flush_jwks_cache_endpoint() -> None:
    """Verify that POST /admin/jwks/flush clears the JWKS cache when authenticated with admin_api_key."""
    # Pre-populate cache
    jwks._cached_jwks = MagicMock()
    jwks._last_fetch_time = time.time()

    with patch("app.api.admin.settings.admin_api_key", "secret-admin-key"), \
         patch("app.api.admin.settings.supabase_service_role_key", "secret-service-role-key"), \
         patch("app.api.admin.settings.hmac_signing_key", "secret-hmac-key"):

        # 1. Unauthorized calls should fail
        with pytest.raises(HTTPException) as exc_info:
            verify_internal_admin_token(authorization="Bearer wrong-key")
        assert exc_info.value.status_code == 401

        # Missing auth header
        with pytest.raises(HTTPException) as exc_info:
            verify_internal_admin_token(authorization=None, x_admin_key=None)
        assert exc_info.value.status_code == 401

        # 2. Supabase and HMAC keys must NOT be accepted for admin operations
        with pytest.raises(HTTPException) as exc_info:
            verify_internal_admin_token(authorization="Bearer secret-service-role-key")
        assert exc_info.value.status_code == 401

        with pytest.raises(HTTPException) as exc_info:
            verify_internal_admin_token(authorization=None, x_admin_key="secret-hmac-key")
        assert exc_info.value.status_code == 401

        # 3. Authorized call via Bearer token with dedicated admin_api_key
        verify_internal_admin_token(authorization="Bearer secret-admin-key")

        # 4. Authorized call via X-Admin-Key with dedicated admin_api_key
        verify_internal_admin_token(authorization=None, x_admin_key="secret-admin-key")

        # 5. Invoke flush endpoint
        request = MagicMock()
        res = await flush_jwks_cache_endpoint(request=request, _auth=None)
        assert res["flushed"] is True
        assert jwks._cached_jwks is None
        assert jwks._last_fetch_time == 0.0

