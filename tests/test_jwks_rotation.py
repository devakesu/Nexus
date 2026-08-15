"""Unit tests for JWKS key retrieval, cache TTL, rotation, and force-refresh."""

import time
from collections.abc import Generator
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from starlette.requests import Request

from app.api.dependencies import get_authenticated_user_payload, get_optional_authenticated_user_id
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
    """Ensure JWKS cache TTL is set to 1 hour (3600 seconds)."""
    assert JWKS_CACHE_TTL_SECONDS == 3600.0


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

        # Simulate time passing beyond 3600s
        jwks._last_fetch_time = time.time() - 3601

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

    with patch("app.core.config.Settings.is_jwks", new_callable=lambda: property(lambda self: True)), \
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

    with patch("app.core.config.Settings.is_jwks", new_callable=lambda: property(lambda self: True)), \
         patch("app.api.dependencies.get_live_supabase_public_key", mock_get_key):
        user_id = await get_optional_authenticated_user_id(token)
        assert user_id == "user-123"
        assert mock_get_key.call_count == 2
        mock_get_key.assert_any_call(token)
        mock_get_key.assert_any_call(token, force_refresh=True)
