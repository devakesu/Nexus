#!/usr/bin/env python3
"""
Backfill public.users.mobile/mobile_verified_at from auth.users for users who
already verified a phone number via Supabase's (now-disabled) native Phone
provider, so they aren't forced to re-verify under the new account-phone-otp
flow (app/core/account_phone_otp.py).

Run once after the 20260731000000_account_phone_verification.sql migration:
    python scripts/backfill_verified_mobile.py

Requires the app environment to be loaded (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
ENCRYPTION_KEY set via .env or environment). Uses the admin API (not
supabase_client.table("auth.users"), which PostgREST doesn't expose) to read
phone/phone_confirmed_at, since auth.users data isn't purged by disabling the
provider - only future API behavior changes.
"""
import logging
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.crypto import encrypt_to_hex
from app.db.client import supabase_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

PER_PAGE = 200


def main() -> None:
    """Main.

        Returns:
            None: Result value.
        """
    page = 1
    total_updated = 0
    total_skipped = 0

    while True:
        users = supabase_client.auth.admin.list_users(page=page, per_page=PER_PAGE)
        if not users:
            break

        for user in users:
            phone = getattr(user, "phone", None)
            phone_confirmed_at = getattr(user, "phone_confirmed_at", None)

            if not phone or not phone_confirmed_at:
                total_skipped += 1
                continue

            supabase_client.table("users").update(
                {
                    "mobile": encrypt_to_hex(phone),
                    "mobile_verified_at": phone_confirmed_at.isoformat()
                    if hasattr(phone_confirmed_at, "isoformat")
                    else phone_confirmed_at,
                },
            ).eq("id", str(user.id)).execute()
            total_updated += 1

        page += 1

    logger.info(
        "Backfilled %d users, skipped %d without a verified phone.",
        total_updated,
        total_skipped,
    )


if __name__ == "__main__":
    main()
