import asyncio
import contextlib
from typing import Any, cast

import jwt
from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import settings


def get_user_or_ip(request: Request) -> str:
    """
    Derives the rate-limiting key. Returns the authenticated user ID if
    available via Bearer token (verified signature check),
    falling back to the client IP address.
    """
    auth_header = request.headers.get("authorization")
    if auth_header and auth_header.lower().startswith("bearer "):
        token = auth_header.split(" ", 1)[1]
        with contextlib.suppress(Exception):
            secret = settings.supabase_jwt_secret
            is_jwks = settings.is_jwks
            public_key = None
            if is_jwks:
                from app.core.jwks import get_live_supabase_public_key
                with contextlib.suppress(Exception):
                    loop = asyncio.get_event_loop()
                    if loop.is_running():
                        future = asyncio.run_coroutine_threadsafe(
                            get_live_supabase_public_key(token),
                            loop,
                        )
                        public_key = future.result(timeout=2.0)
                    else:
                        public_key = loop.run_until_complete(
                            get_live_supabase_public_key(token),
                        )

            # If JWKS configuration but public key resolution failed, fallback to IP
            if is_jwks and not public_key:
                return get_remote_address(request)

            # Perform the cryptographic decode directly
            if is_jwks:
                payload = jwt.decode(
                    token,
                    cast(Any, public_key),
                    algorithms=["ES256"],
                    audience="authenticated",
                )
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
