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

# Global thread-safe memory cache primitives for zero-latency signature parsing
_cached_jwks: PyJWKSet | None = None
_last_fetch_time: float = 0.0
_jwks_lock = asyncio.Lock()


def _parse_jwk_dict(raw_data: Any) -> dict[str, Any]:
    """
    Defensively normalizes Union inputs (JSON strings or dictionaries) into a
    structured JWK/JWKS dictionary format.
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
    """Helper to isolate and type-cast the target JWK from the keys mapping list."""
    if "keys" not in jwk_dict:
        return jwk_dict

    keys_list = jwk_dict.get("keys")
    if not isinstance(keys_list, list) or not keys_list:
        raise jwt.InvalidTokenError(
            "Static backup JWKS keys mapping is invalid or empty.",
        )

    # Match incoming key identifier or default fallback to the primary array element
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
    """
    Parses and isolates an explicit EllipticCurvePublicKey from the static local
    Infisical configurations if remote endpoints are completely unreachable.
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
    """
    Safely determines if a specified Key ID exists inside
    the active cached key-set array.
    """
    return any(jwk.key_id == kid for jwk in jwk_set.keys)


async def _fetch_and_update_cached_jwks(current_time: float) -> None:
    """Helper to dynamically retrieve and update Supabase rotating public keys."""
    global _cached_jwks, _last_fetch_time
    try:
        jwks_url = f"{settings.supabase_url}/auth/v1/.well-known/jwks.json"
        async with httpx.AsyncClient() as client:
            response = await client.get(jwks_url, timeout=10.0)
        if response.status_code == 200:
            _cached_jwks = PyJWKSet.from_dict(response.json())
            _last_fetch_time = current_time
    except httpx.HTTPError as err:
        logger.warning("Supabase JWKS dynamic fetch failed: %r", err)


def _resolve_key_from_cache(token_kid: str) -> EllipticCurvePublicKey | None:
    """Helper to locate and parse key identifier from active cache memory."""
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


async def get_live_supabase_public_key(token: str) -> EllipticCurvePublicKey:
    """
    Dynamically tracks, fetches, and returns Supabase's rotating Elliptic Curve keys.
    Caches results in memory for up to 24 hours to prevent network call degradation,
    narrowing types strictly to clear broad Any definitions.
    """
    try:
        unverified_header = jwt.get_unverified_header(token)
        token_kid: str | None = unverified_header.get("kid")
    except (jwt.DecodeError, ValueError) as err:
        raise jwt.InvalidTokenError(
            "Malformed request payload token structure: Unreadable header parameters.",
        ) from err

    current_time = time.time()

    # Trigger cache re-fetch context if empty, older than 24 hours,
    # or tracking a new key ID (kid)
    cache_expired = (current_time - _last_fetch_time) > 86400
    missing_kid = token_kid is not None and (
        _cached_jwks is None
        or not syntax_has_kid(_cached_jwks, token_kid)
    )

    if not _cached_jwks or cache_expired or missing_kid:
        async with _jwks_lock:
            # Re-check inside lock to prevent dogpiling/multiple fetches
            current_time = time.time()
            cache_expired = (current_time - _last_fetch_time) > 86400
            missing_kid = token_kid is not None and (
                _cached_jwks is None
                or not syntax_has_kid(_cached_jwks, token_kid)
            )
            if not _cached_jwks or cache_expired or missing_kid:
                await _fetch_and_update_cached_jwks(current_time)

    if token_kid:
        resolved = _resolve_key_from_cache(token_kid)
        if resolved:
            return resolved

    # Safe execution fallback route if network operations drop
    # or key IDs miss target cached entities
    return get_fallback_public_key(token_kid)
