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
os.environ.setdefault("PII_ENCRYPTION_KEY", "test-pii-encryption-key")
os.environ.setdefault("BLIND_INDEX_KEY", "test-blind-index-key")
os.environ.setdefault("APP_DOMAIN", "localhost")
