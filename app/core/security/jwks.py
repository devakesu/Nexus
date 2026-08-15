"""JSON Web Key Set (JWKS) key retrieval and caching for Supabase JWT verification.

Provides dynamic remote public key fetching with 1-hour in-memory caching and lock protection,
along with static fallback resolution for offline or local execution modes.
"""

import asyncio
import json
import logging
import time
from typing import Any, cast

import httpx
import jwt
from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePublicKey
from jwt import PyJWK, PyJWKSet

from app.core.config import settings

logger = logging.getLogger(__name__)

# Cache TTL: 1 hour (3600s) to minimize exposure window on key rotation/revocation
JWKS_CACHE_TTL_SECONDS: float = 3600.0

# Shared memory cache primitives for zero-latency signature parsing
_cached_jwks: PyJWKSet | None = None
_last_fetch_time: float = 0.0
_jwks_lock = asyncio.Lock()
_http_client: httpx.AsyncClient | None = None


def clear_jwks_cache() -> None:
    """Clears the cached JWKS and resets the last fetch timestamp."""
    global _cached_jwks, _last_fetch_time
    _cached_jwks = None
    _last_fetch_time = 0.0


def _get_jwks_client() -> httpx.AsyncClient:
    """Returns or initializes the shared module-level httpx.AsyncClient instance."""
    global _http_client
    if _http_client is None or _http_client.is_closed:
        _http_client = httpx.AsyncClient(timeout=10.0)
    return _http_client


def _parse_jwk_dict(raw_data: Any) -> dict[str, Any]:
    """Defensively normalizes input strings or dictionaries into a JWK/JWKS dictionary format.

    Args:
        raw_data: Input JSON string or dictionary key container.

    Returns:
        dict[str, Any]: Parsed JWK dictionary representation.

    Raises:
        RuntimeError: If data is malformed or invalid JSON.
    """
    if isinstance(raw_data, str):
        try:
            parsed = json.loads(raw_data)
            if isinstance(parsed, dict):
                parsed_dict = cast(dict[object, object], parsed)
                return {str(k): v for k, v in parsed_dict.items()}
        except json.JSONDecodeError as err:
            raise RuntimeError(
                "CRITICAL: Configured SUPABASE_JWT_SECRET string is not valid JSON.",
            ) from err

    if isinstance(raw_data, dict):
        raw_dict = cast(dict[object, object], raw_data)
        return {str(k): v for k, v in raw_dict.items()}

    raise RuntimeError("CRITICAL: Invalid key format configuration container detected.")


def _find_jwk_by_kid(keys_list: list[object], kid: str) -> dict[str, Any] | None:
    """Finds a matching JWK dictionary in a list by key ID (`kid`).

    Args:
        keys_list: List of candidate key objects/dictionaries.
        kid: Key identifier string to match.

    Returns:
        dict[str, Any] | None: Matching JWK dictionary or None.
    """
    for item in keys_list:
        if isinstance(item, dict):
            item_dict = cast(dict[str, Any], item)
            if item_dict.get("kid") == kid:
                return item_dict
    return None


def _isolate_fallback_jwk(
    jwk_dict: dict[str, Any],
    kid: str | None,
) -> dict[str, Any]:
    """Isolates the target JWK dictionary from a JWKS wrapper map.

    Args:
        jwk_dict: JWKS or JWK dictionary mapping.
        kid: Target key identifier string.

    Returns:
        dict[str, Any]: Isolated JWK dictionary.
    """
    if "keys" not in jwk_dict:
        return jwk_dict

    keys_list = jwk_dict.get("keys")
    if not isinstance(keys_list, list) or not keys_list:
        raise jwt.InvalidTokenError(
            "Static backup JWKS keys mapping is invalid or empty.",
        )

    keys_list_obj = cast(list[object], keys_list)
    if kid:
        matched = _find_jwk_by_kid(keys_list_obj, kid)
        if matched is not None:
            return matched

    first_key = keys_list_obj[0]
    if isinstance(first_key, dict):
        return cast(dict[str, Any], first_key)

    return {}


def get_fallback_public_key(kid: str | None) -> EllipticCurvePublicKey:
    """Parses an EllipticCurvePublicKey from local static configuration as fallback.

    Args:
        kid: Optional Key ID string.

    Returns:
        EllipticCurvePublicKey: Resolved public key object.

    Raises:
        RuntimeError: If local key parsing fails or type mismatch occurs.
    """
    jwk_dict = _parse_jwk_dict(settings.supabase_jwt_secret)
    isolated_jwk = _isolate_fallback_jwk(jwk_dict, kid)

    try:
        key_object = PyJWK(isolated_jwk).key
        if not isinstance(key_object, EllipticCurvePublicKey):
            raise TypeError(
                "Calculated signature key material is not an Elliptic Curve instance.",
            )
        return key_object
    except (ValueError, KeyError, AttributeError, TypeError) as err:
        raise RuntimeError(
            "CRITICAL: Failed to unpack local static fallback public key "
            f"footprint: {err}",
        ) from err


def syntax_has_kid(jwk_set: PyJWKSet, kid: str) -> bool:
    """Checks whether a Key ID exists in a PyJWKSet.

    Args:
        jwk_set: Active cached PyJWKSet instance.
        kid: Key ID string to verify.

    Returns:
        bool: True if key present, False otherwise.
    """
    return any(jwk.key_id == kid for jwk in jwk_set.keys)


async def _fetch_and_update_cached_jwks(current_time: float) -> None:
    """Fetches rotating public key set from Supabase and updates in-memory cache.

    Args:
        current_time: Epoch timestamp of fetch attempt.
    """
    global _cached_jwks, _last_fetch_time
    try:
        jwks_url = f"{settings.supabase_url}/auth/v1/.well-known/jwks.json"
        client = _get_jwks_client()
        response = await client.get(jwks_url)
        if response.status_code == 200:
            _cached_jwks = PyJWKSet.from_dict(response.json())
            _last_fetch_time = current_time
    except httpx.HTTPError as err:
        logger.warning("Supabase JWKS dynamic fetch failed: %r", err)


def _resolve_key_from_cache(token_kid: str) -> EllipticCurvePublicKey | None:
    """Resolves an EllipticCurvePublicKey from the active memory cache by Key ID.

    Args:
        token_kid: Target key identifier string.

    Returns:
        EllipticCurvePublicKey | None: Matching key object or None.
    """
    if not _cached_jwks:
        return None
    for jwk in _cached_jwks.keys:
        if jwk.key_id == token_kid:
            try:
                resolved_key = jwk.key
                if isinstance(resolved_key, EllipticCurvePublicKey):
                    return resolved_key
            except (ValueError, KeyError, AttributeError, TypeError) as err:
                logger.warning("Failed to resolve public key from cache: %s", err)
    return None


async def get_live_supabase_public_key(
    token: str,
    force_refresh: bool = False,
) -> EllipticCurvePublicKey:
    """Retrieves the active Supabase Elliptic Curve public key for JWT verification.

    Args:
        token: Incoming JWT Bearer token string.
        force_refresh: If True, forces a refresh of the JWKS cache from Supabase.

    Returns:
        EllipticCurvePublicKey: Active public key instance.

    Raises:
        jwt.InvalidTokenError: If token header is malformed or key ID is revoked/invalid.
    """
    try:
        unverified_header = jwt.get_unverified_header(token)
        token_kid: str | None = unverified_header.get("kid")
    except (jwt.DecodeError, ValueError) as err:
        raise jwt.InvalidTokenError(
            "Malformed request payload token structure: Unreadable header parameters.",
        ) from err

    current_time = time.time()

    cache_expired = (current_time - _last_fetch_time) > JWKS_CACHE_TTL_SECONDS
    missing_kid = token_kid is not None and (
        _cached_jwks is None
        or not syntax_has_kid(_cached_jwks, token_kid)
    )

    if not _cached_jwks or cache_expired or missing_kid or force_refresh:
        async with _jwks_lock:
            current_time = time.time()
            cache_expired = (current_time - _last_fetch_time) > JWKS_CACHE_TTL_SECONDS
            missing_kid = token_kid is not None and (
                _cached_jwks is None
                or not syntax_has_kid(_cached_jwks, token_kid)
            )
            if not _cached_jwks or cache_expired or missing_kid or force_refresh:
                await _fetch_and_update_cached_jwks(current_time)

    if token_kid:
        resolved = _resolve_key_from_cache(token_kid)
        if resolved:
            return resolved
        if _cached_jwks is not None:
            raise jwt.InvalidTokenError(
                f"Specified key ID '{token_kid}' is not recognized or has been revoked.",
            )

    return get_fallback_public_key(token_kid)

