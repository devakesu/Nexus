"""Database client initialization and common helper functions.

Manages the singleton Supabase service role client instance, custom database exception types,
and date/UUID normalization helper utilities.
"""

import logging
from datetime import datetime, timezone

import httpx
from dateutil.parser import parse as parse_date
from supabase.lib.client_options import SyncClientOptions

from app.core.config import settings
from supabase import Client, create_client

logger = logging.getLogger(__name__)

# Service role client - bypasses RLS; authorization enforced at FastAPI layer.
supabase_client: Client = create_client(
    settings.supabase_url,
    settings.supabase_service_role_key,
    options=SyncClientOptions(
        httpx_client=httpx.Client(
            http1=True,
            http2=False,
            timeout=httpx.Timeout(30.0, read=20.0, connect=10.0),
            limits=httpx.Limits(keepalive_expiry=30.0),
        ),
    ),
)


class ProfileDecodeError(Exception):
    """Raised when an encrypted profile field cannot be decrypted or decoded."""


class ProfileNotFoundError(Exception):
    """Raised when a user profile does not exist in the database."""


class DatabaseAccessError(Exception):
    """Raised when a database query operation fails unexpectedly."""


def utcnow() -> datetime:
    """Returns the current timezone-aware UTC datetime.

    Returns:
        datetime: UTC datetime instance.
    """
    return datetime.now(timezone.utc)


def parse_utc_datetime(raw: str | datetime) -> datetime:
    """Parses an ISO 8601 string or naive datetime into a UTC-aware datetime instance.

    Args:
        raw: Datetime instance or ISO string to parse.

    Returns:
        datetime: UTC-aware datetime instance.
    """
    if isinstance(raw, datetime):
        return raw if raw.tzinfo is not None else raw.replace(tzinfo=timezone.utc)
    dt = parse_date(raw)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def normalize_uuid(val: str | None) -> str:
    """Validates and formats a string as a standard UUID string representation.

    Args:
        val: Input UUID string.

    Returns:
        str: Normalized UUID string.

    Raises:
        ValueError: If input string is empty, None, or invalid UUID format.
    """
    import uuid

    if not val:
        raise ValueError("Invalid UUID: value is empty or None")
    return str(uuid.UUID(str(val).strip()))

