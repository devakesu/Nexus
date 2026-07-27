"""Database user authentication, profile creation, and account status persistence layer.

Provides database interaction functions for user registration, encrypted PII management,
disposable email domain checks, account status verification, and deletion handling.

All symbols are re-exported from their sub-modules for full backward compatibility.
"""

from app.db.users.auth import (
    DISPOSABLE_DOMAINS,
    fetch_public_user,
    find_user_id_by_phone,
    get_supabase_user_from_jwt,
    get_user_email_by_id,
    get_user_id_by_email,
    is_allowed_email,
    is_disposable_email,
    set_verified_mobile,
    upsert_public_user,
)
from app.db.users.consent import (
    update_safety_data_consent,
    update_special_category_consent,
    update_user_terms,
)
from app.db.users.import_export import execute_import, generate_export_code
from app.db.users.profile import fetch_profile, upsert_profile_variant

__all__ = [
    # auth
    "DISPOSABLE_DOMAINS",
    # migration
    "execute_import",
    # profile
    "fetch_profile",
    "fetch_public_user",
    "find_user_id_by_phone",
    "generate_export_code",
    "get_supabase_user_from_jwt",
    "get_user_email_by_id",
    "get_user_id_by_email",
    "is_allowed_email",
    "is_disposable_email",
    "set_verified_mobile",
    # consent
    "update_safety_data_consent",
    "update_special_category_consent",
    "update_user_terms",
    "upsert_profile_variant",
    "upsert_public_user",
]
