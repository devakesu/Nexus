import json
import time
from typing import Optional, Dict, Any
import httpx
import jwt
from jwt import PyJWKSet, PyJWK
from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePublicKey

from app.config import settings

# Global thread-safe memory cache primitives for zero-latency signature parsing
_cached_jwks: Optional[PyJWKSet] = None
_last_fetch_time: float = 0.0

def _parse_jwk_dict(raw_data: Any) -> Dict[str, Any]:
    """
    Defensively normalizes Union inputs (JSON strings or dictionaries) into a 
    structured JWK/JWKS dictionary format.
    """
    if isinstance(raw_data, str):
        try:
            parsed = json.loads(raw_data)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            raise RuntimeError("CRITICAL: Configured SUPABASE_JWT_SECRET string is not valid JSON.")
            
    if isinstance(raw_data, dict):
        return raw_data
        
    raise RuntimeError("CRITICAL: Invalid key format configuration container detected.")


def get_fallback_public_key(kid: Optional[str]) -> EllipticCurvePublicKey:
    """
    Parses and isolates an explicit EllipticCurvePublicKey from the static local 
    Infisical configurations if remote endpoints are completely unreachable.
    """
    jwk_dict = _parse_jwk_dict(settings.supabase_jwt_secret)
    
    # Isolate key block if wrapped in standard outer JWKS layout
    if "keys" in jwk_dict:
        keys_list = jwk_dict.get("keys", [])
        if not keys_list:
            raise jwt.InvalidTokenError("Static backup JWKS contains an empty key mapping list.")
            
        # Match incoming key identifier or default fallback to the primary array element
        target_jwk = keys_list[0]
        if kid:
            for k in keys_list:
                if isinstance(k, dict) and k.get("kid") == kid:
                    target_jwk = k
                    break
        jwk_dict = target_jwk

    try:
        key_object = PyJWK(jwk_dict).key
        if not isinstance(key_object, EllipticCurvePublicKey):
            raise TypeError("Calculated signature key material is not an Elliptic Curve instance.")
        return key_object
    except Exception as e:
        raise RuntimeError(f"CRITICAL: Failed to unpack local static fallback public key footprint: {e}")


def syntax_has_kid(jwk_set: PyJWKSet, kid: str) -> bool:
    """Safely determines if a specified Key ID exists inside the active cached key-set array."""
    for jwk in jwk_set.keys:
        if jwk.key_id == kid:
            return True
    return False


def get_live_supabase_public_key(token: str) -> EllipticCurvePublicKey:
    """
    Dynamically tracks, fetches, and returns Supabase's rotating Elliptic Curve keys.
    Caches results in memory for up to 24 hours to prevent network call degradation, 
    narrowing types strictly to clear broad Any definitions.
    """
    global _cached_jwks, _last_fetch_time
    
    try:
        unverified_header = jwt.get_unverified_header(token)
        token_kid: Optional[str] = unverified_header.get("kid")
    except Exception:
        raise jwt.InvalidTokenError("Malformed request payload token structure: Unreadable header parameters.")

    current_time = time.time()
    
    # Trigger cache re-fetch context if empty, older than 24 hours, or tracking a new key ID (kid)
    cache_expired = (current_time - _last_fetch_time) > 86400
    missing_kid = token_kid is not None and (_cached_jwks is None or not syntax_has_kid(_cached_jwks, token_kid))
    
    if not _cached_jwks or cache_expired or missing_kid:
        try:
            jwks_url = f"{settings.supabase_url}/auth/v1/.well-known/jwks.json"
            response = httpx.get(jwks_url, timeout=5.0)
            if response.status_code == 200:
                _cached_jwks = PyJWKSet.from_dict(response.json())
                _last_fetch_time = current_time
        except Exception:
            # Silently pass through and allow execution to route towards the static fallback key matrix
            pass

    if _cached_jwks and token_kid:
        for jwk in _cached_jwks.keys:
            if jwk.key_id == token_kid:
                try:
                    resolved_key = jwk.key
                    if isinstance(resolved_key, EllipticCurvePublicKey):
                        return resolved_key
                except Exception:
                    pass

    # Safe execution fallback route if network operations drop or key IDs miss target cached entities
    return get_fallback_with_type_narrowing(token_kid)


def get_fallback_with_type_narrowing(kid: Optional[str]) -> EllipticCurvePublicKey:
    """Helper extraction routine ensuring explicit typing guarantees are held."""
    fallback_key = get_fallback_public_key(kid)
    if not isinstance(fallback_key, EllipticCurvePublicKey):
        raise jwt.InvalidTokenError("Resolved backup public verification context failed type validation boundaries.")
    return fallback_key