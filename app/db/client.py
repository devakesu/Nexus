import logging
from datetime import datetime, timezone

import httpx
from dateutil.parser import parse as parse_date
from supabase.lib.client_options import SyncClientOptions

from app.core.config import settings
from supabase import Client, create_client

logger = logging.getLogger(__name__)

# Service role client — bypasses all RLS by design.
# Authorization is enforced at the FastAPI layer:
#   1. ES256 JWT verification (get_authenticated_user_id in dependencies.py)
#   2. user_id scoping: every write is filtered to the verified caller's user_id
#   3. Account-status checks (suspension, deactivation) before any mutation
#   4. Firebase App Check device attestation on sensitive routes
# DB-level backstops: guard_service_fields() trigger (server-owned columns),
# deny-all RLS on vector_profiles and profile_pseudonym_map.
supabase_client: Client = create_client(
    settings.supabase_url,
    settings.supabase_service_role_key,
    options=SyncClientOptions(
        httpx_client=httpx.Client(
            http1=True,
            http2=True,
            timeout=httpx.Timeout(30.0, read=20.0, connect=10.0),
            limits=httpx.Limits(keepalive_expiry=30.0),
        ),
    ),
)


class ProfileDecodeError(Exception):
    """Raised when an encrypted profile field cannot be decoded.

    It must decode into its expected shape.
    """


class DatabaseAccessError(Exception):
    """Raised when a database operation fails unexpectedly."""


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def parse_utc_datetime(raw: "str | datetime") -> datetime:
    """Parse an ISO 8601 string (with optional Z suffix) into a UTC-aware datetime."""
    if isinstance(raw, datetime):
        return raw if raw.tzinfo is not None else raw.replace(tzinfo=timezone.utc)
    dt = parse_date(raw)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt
