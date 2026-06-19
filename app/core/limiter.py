import jwt
from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.core.config import settings


def get_user_or_ip(request: Request) -> str:
    """
    Derives the rate-limiting key. Returns the authenticated user ID if
    available via Bearer token (unverified signature check for keying only),
    falling back to the client IP address.
    """
    auth_header = request.headers.get("authorization")
    if auth_header and auth_header.lower().startswith("bearer "):
        import contextlib
        token = auth_header.split(" ", 1)[1]
        with contextlib.suppress(jwt.PyJWTError):
            payload = jwt.decode(token, options={"verify_signature": False})
            user_id = payload.get("sub")
            if user_id:
                return f"user:{user_id}"
    return get_remote_address(request)


limiter = Limiter(
    key_func=get_user_or_ip,
    enabled=settings.enable_rate_limiting,
)
