import logging
from datetime import datetime, timezone

from app.core.config import settings
from supabase import Client, create_client

logger = logging.getLogger(__name__)

# High-privilege backend client. Service role access must be treated as trusted
# backend-only code because it can bypass RLS depending on how requests are made.
supabase_client: Client = create_client(
    settings.supabase_url,
    settings.supabase_service_role_key,
)


class ProfileDecodeError(Exception):
    """Raised when an encrypted profile field cannot be decoded.

    It must decode into its expected shape.
    """


class DatabaseAccessError(Exception):
    """Raised when a database operation fails unexpectedly."""


def utcnow() -> datetime:
    return datetime.now(timezone.utc)
