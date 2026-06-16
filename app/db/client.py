import logging
from datetime import datetime, timezone

import httpx
from dateutil.parser import parse as parse_date
from supabase.lib.client_options import SyncClientOptions

from app.core.config import settings
from supabase import Client, create_client

logger = logging.getLogger(__name__)

# High-privilege backend client. Service role access must be treated as trusted
# backend-only code because it can bypass RLS depending on how requests are made.
supabase_client: Client = create_client(
    settings.supabase_url,
    settings.supabase_service_role_key,
    options=SyncClientOptions(
        httpx_client=httpx.Client(http2=False),
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
