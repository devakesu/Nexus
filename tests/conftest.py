"""Pytest test configuration and environment setup fixture module.

Sets up default fallback environment variables for offline test discovery and execution.
"""

import os

# app.core.config.Settings validates required secrets at import time (it's
# designed to run inside `infisical run`). These unit tests only exercise
# pure layout math in app.db.orbit and never touch Supabase/Redis/etc., so we
# set harmless placeholder values (only if unset) purely to satisfy that
# import-time validation.
os.environ.setdefault("SUPABASE_URL", "http://localhost:54321")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key")
os.environ.setdefault("SUPABASE_JWT_SECRET", "test-jwt-secret")
os.environ.setdefault("SPOTIFY_REDIRECT_URI", "http://localhost:8000/callback")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/0")
os.environ.setdefault(
    "PII_ENCRYPTION_KEY",
    "YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE=",
)
os.environ.setdefault("BLIND_INDEX_KEY", "test-blind-index-key")
os.environ.setdefault("HMAC_SIGNING_KEY", "test-hmac-signing-key")
os.environ.setdefault("DEBUG", "true")
os.environ.setdefault("BACKEND_PUBLIC_URL", "http://localhost:8000")
os.environ.setdefault("ENFORCE_APP_CHECK", "false")
os.environ.setdefault("ENABLE_RATE_LIMITING", "false")

import pytest

from app.core.infra.limiter import limiter


@pytest.fixture(autouse=True)
def disable_limiter_in_tests():
    setattr(limiter, "_enabled", False)  # noqa: B010
    yield
    setattr(limiter, "_enabled", False)  # noqa: B010
