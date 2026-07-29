"""API rate limiting configuration and key generation utilities.

Integrates SlowAPI rate limiting with dynamic key derivation based on authenticated user ID
(via verified JWT payload decoding) or client IP address fallback.
"""

import contextlib
from typing import Any, cast

import jwt
from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import settings


def get_user_or_ip(request: Request) -> str:
    """Derives the rate-limiting identifier key for an incoming HTTP request.

    Checks request.state for cached user_id or decoded JWT payload from authentication,
    otherwise parses the Bearer JWT token header using non-blocking decoding before
    falling back to client IP address.

    Args:
        request: FastAPI/Starlette request instance.

    Returns:
        str: Rate-limiting bucket identifier string.
    """
    user_id = getattr(request.state, "user_id", None)
    if user_id:
        return f"user:{user_id}"

    user_payload = cast(dict[str, Any] | None, getattr(request.state, "authenticated_user_payload", None))
    if isinstance(user_payload, dict):
        user_id_val = user_payload.get("sub") or user_payload.get("id")
        if user_id_val:
            return f"user:{user_id_val}"

    auth_header = request.headers.get("authorization")
    if auth_header and auth_header.lower().startswith("bearer "):
        token = auth_header.split(" ", 1)[1]
        with contextlib.suppress(Exception):
            secret = settings.supabase_jwt_secret
            is_jwks = settings.is_jwks
            if is_jwks:
                payload = jwt.decode(token, options={"verify_signature": False})
            else:
                payload = jwt.decode(
                    token,
                    cast(str, secret),
                    algorithms=["HS256"],
                    audience="authenticated",
                )

            user_id = payload.get("sub")
            if user_id:
                return f"user:{user_id}"

    return get_remote_address(request)


limiter = Limiter(
    key_func=get_user_or_ip,
    enabled=settings.enable_rate_limiting,
)

