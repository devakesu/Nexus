#!/usr/bin/env python3
"""One-shot migration script to re-compute deterministic HMAC blind indexes under the new key.

Iterates through all database tables containing blind-index columns:
- users.mobile_blind_index (domain='mobile', source=users.mobile)
- profiles.campus_branch_blind_index (domain='campus_branch', source=profiles.campus_branch)
- safety_contact_notices.phone_blind_index (domain='safety_contact_phone', source=safety_contacts.phone)

For each row:
1. Decrypts the source encrypted PII field using MultiFernet.
2. Re-computes the HMAC-SHA256 blind index digest using the primary (first) key in BLIND_INDEX_KEY.
3. Updates the target blind index column.

Usage:
    # Dry run across all blind index domains
    infisical run --env=prod projectId=xxxx --path=/public --path=/runtime -- python3 scripts/rotate_blind_indexes.py --dry-run

    # Full blind index rotation pass
    infisical run --env=prod projectId=xxxx --path=/public --path=/runtime -- python3 scripts/rotate_blind_indexes.py

    # Target specific domain
    infisical run --env=prod projectId=xxxx --path=/public --path=/runtime -- python3 scripts/rotate_blind_indexes.py --domain mobile --batch-size 100
"""

import argparse
from dataclasses import dataclass
import logging
import os
import sys
from typing import Any, cast

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import sentry_sdk
from app.core.auth.phone_otp import normalize_phone
from app.core.config import settings
from app.core.infra.sentry import scrub_event
from app.core.security.crypto import (
    DecryptFailedError,
    _get_blind_index_keys,
    compute_blind_index,
    compute_blind_index_with_key,
    decrypt_pii,
)
from app.db.client import supabase_client

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


@dataclass
class BlindIndexResult:
    domain: str
    total_scanned: int = 0
    total_updated: int = 0
    total_skipped: int = 0
    total_unchanged: int = 0
    errors: int = 0


def init_sentry_if_configured() -> None:
    """Initializes Sentry SDK if DSN is configured in settings."""
    if settings.sentry_backend_dsn:
        sentry_sdk.init(
            dsn=settings.sentry_backend_dsn,
            environment=settings.sentry_environment,
            traces_sample_rate=settings.sentry_traces_sample_rate,
            send_default_pii=False,
            before_send=scrub_event,
        )


def rotate_users_mobile_blind_index(
    batch_size: int = 50,
    dry_run: bool = False,
    start_offset: int = 0,
) -> BlindIndexResult:
    """Re-computes users.mobile_blind_index using primary blind index key."""
    result = BlindIndexResult(domain="mobile")
    offset = start_offset

    logger.info(
        "Rotating users.mobile_blind_index (batch_size: %d, offset: %d, dry_run: %s)...",
        batch_size,
        offset,
        dry_run,
    )

    while True:
        try:
            res = (
                supabase_client.table("users")
                .select("id, mobile, mobile_blind_index")
                .range(offset, offset + batch_size - 1)
                .execute()
            )
            rows = cast(list[dict[str, Any]], res.data or [])
        except Exception as e:
            logger.exception("Database error fetching users at offset %d: %s", offset, e)
            result.errors += 1
            if settings.sentry_backend_dsn:
                sentry_sdk.capture_exception(e)
            break

        if not rows:
            break

        for row in rows:
            result.total_scanned += 1
            user_id = row.get("id")
            raw_mobile = row.get("mobile")

            if not raw_mobile:
                result.total_unchanged += 1
                continue

            try:
                decrypted_mobile = decrypt_pii(raw_mobile, category="contact")
            except DecryptFailedError as e:
                result.total_skipped += 1
                logger.error(
                    "Decryption failed for users PK '%s' mobile: %s",
                    user_id,
                    e,
                )
                if settings.sentry_backend_dsn:
                    sentry_sdk.capture_message(
                        f"Blind index rotation decryption failure on users.mobile for PK {user_id}",
                        level="error",
                    )
                continue
            except Exception as e:
                result.total_skipped += 1
                logger.exception("Unexpected error decrypting mobile for user %s: %s", user_id, e)
                if settings.sentry_backend_dsn:
                    sentry_sdk.capture_exception(e)
                continue

            if not decrypted_mobile:
                result.total_unchanged += 1
                continue

            try:
                norm_phone = normalize_phone(decrypted_mobile)
            except Exception:
                norm_phone = decrypted_mobile.strip().lower()

            new_blind_index = compute_blind_index(norm_phone, domain="mobile")
            current_blind_index = row.get("mobile_blind_index")

            if current_blind_index == new_blind_index:
                result.total_unchanged += 1
                continue

            if dry_run:
                result.total_updated += 1
            else:
                try:
                    supabase_client.table("users").update(
                        {"mobile_blind_index": new_blind_index},
                    ).eq("id", user_id).execute()
                    result.total_updated += 1
                except Exception as e:
                    result.errors += 1
                    logger.exception(
                        "Failed to update mobile_blind_index for user %s: %s",
                        user_id,
                        e,
                    )
                    if settings.sentry_backend_dsn:
                        sentry_sdk.capture_exception(e)

        offset += batch_size

    logger.info(
        "Finished users.mobile_blind_index: %d scanned, %d updated, %d skipped, %d unchanged, %d errors.",
        result.total_scanned,
        result.total_updated,
        result.total_skipped,
        result.total_unchanged,
        result.errors,
    )
    return result


def rotate_profiles_campus_branch_blind_index(
    batch_size: int = 50,
    dry_run: bool = False,
    start_offset: int = 0,
) -> BlindIndexResult:
    """Re-computes profiles.campus_branch_blind_index using primary blind index key."""
    result = BlindIndexResult(domain="campus_branch")
    offset = start_offset

    logger.info(
        "Rotating profiles.campus_branch_blind_index (batch_size: %d, offset: %d, dry_run: %s)...",
        batch_size,
        offset,
        dry_run,
    )

    while True:
        try:
            res = (
                supabase_client.table("profiles")
                .select("id, campus_branch, campus_branch_blind_index")
                .range(offset, offset + batch_size - 1)
                .execute()
            )
            rows = cast(list[dict[str, Any]], res.data or [])
        except Exception as e:
            logger.exception("Database error fetching profiles at offset %d: %s", offset, e)
            result.errors += 1
            if settings.sentry_backend_dsn:
                sentry_sdk.capture_exception(e)
            break

        if not rows:
            break

        for row in rows:
            result.total_scanned += 1
            profile_id = row.get("id")
            raw_branch = row.get("campus_branch")

            if not raw_branch:
                result.total_unchanged += 1
                continue

            try:
                decrypted_branch = decrypt_pii(raw_branch, category="profile")
            except DecryptFailedError as e:
                result.total_skipped += 1
                logger.error(
                    "Decryption failed for profiles PK '%s' campus_branch: %s",
                    profile_id,
                    e,
                )
                if settings.sentry_backend_dsn:
                    sentry_sdk.capture_message(
                        f"Blind index rotation decryption failure on profiles.campus_branch for PK {profile_id}",
                        level="error",
                    )
                continue
            except Exception as e:
                result.total_skipped += 1
                logger.exception("Unexpected error decrypting campus_branch for profile %s: %s", profile_id, e)
                if settings.sentry_backend_dsn:
                    sentry_sdk.capture_exception(e)
                continue

            if not decrypted_branch:
                result.total_unchanged += 1
                continue

            new_blind_index = compute_blind_index(decrypted_branch, domain="campus_branch")
            current_blind_index = row.get("campus_branch_blind_index")

            if current_blind_index == new_blind_index:
                result.total_unchanged += 1
                continue

            if dry_run:
                result.total_updated += 1
            else:
                try:
                    supabase_client.table("profiles").update(
                        {"campus_branch_blind_index": new_blind_index},
                    ).eq("id", profile_id).execute()
                    result.total_updated += 1
                except Exception as e:
                    result.errors += 1
                    logger.exception(
                        "Failed to update campus_branch_blind_index for profile %s: %s",
                        profile_id,
                        e,
                    )
                    if settings.sentry_backend_dsn:
                        sentry_sdk.capture_exception(e)

        offset += batch_size

    logger.info(
        "Finished profiles.campus_branch_blind_index: %d scanned, %d updated, %d skipped, %d unchanged, %d errors.",
        result.total_scanned,
        result.total_updated,
        result.total_skipped,
        result.total_unchanged,
        result.errors,
    )
    return result


def rotate_safety_contacts_blind_index(
    batch_size: int = 50,
    dry_run: bool = False,
    start_offset: int = 0,
) -> BlindIndexResult:
    """Re-computes safety_contact_notices.phone_blind_index from decrypted safety_contacts.phone."""
    result = BlindIndexResult(domain="safety_contact_phone")
    offset = start_offset
    keys = _get_blind_index_keys()
    old_keys = keys[1:] if len(keys) > 1 else []

    logger.info(
        "Rotating safety_contact_notices (batch_size: %d, offset: %d, dry_run: %s)...",
        batch_size,
        offset,
        dry_run,
    )

    while True:
        try:
            res = (
                supabase_client.table("safety_contacts")
                .select("id, user_id, phone")
                .range(offset, offset + batch_size - 1)
                .execute()
            )
            rows = cast(list[dict[str, Any]], res.data or [])
        except Exception as e:
            logger.exception("Database error fetching safety_contacts at offset %d: %s", offset, e)
            result.errors += 1
            if settings.sentry_backend_dsn:
                sentry_sdk.capture_exception(e)
            break

        if not rows:
            break

        for row in rows:
            result.total_scanned += 1
            contact_id = row.get("id")
            user_id = row.get("user_id")
            raw_phone = row.get("phone")

            if not raw_phone or not user_id:
                result.total_unchanged += 1
                continue

            try:
                decrypted_phone = decrypt_pii(raw_phone, category="contact")
            except DecryptFailedError as e:
                result.total_skipped += 1
                logger.error(
                    "Decryption failed for safety_contacts PK '%s' phone: %s",
                    contact_id,
                    e,
                )
                if settings.sentry_backend_dsn:
                    sentry_sdk.capture_message(
                        f"Blind index rotation decryption failure on safety_contacts.phone for PK {contact_id}",
                        level="error",
                    )
                continue
            except Exception as e:
                result.total_skipped += 1
                logger.exception("Unexpected error decrypting phone for contact %s: %s", contact_id, e)
                if settings.sentry_backend_dsn:
                    sentry_sdk.capture_exception(e)
                continue

            if not decrypted_phone:
                result.total_unchanged += 1
                continue

            try:
                norm_phone = normalize_phone(decrypted_phone)
            except Exception:
                norm_phone = decrypted_phone.strip().lower()

            new_blind_index = compute_blind_index(norm_phone, domain="safety_contact_phone")

            # Collect possible old digests
            old_digests: list[str] = [
                compute_blind_index_with_key(norm_phone, domain="safety_contact_phone", key=k)
                for k in old_keys
            ]

            if dry_run:
                result.total_updated += 1
            else:
                try:
                    for old_digest in old_digests:
                        if old_digest != new_blind_index:
                            supabase_client.table("safety_contact_notices").update(
                                {"phone_blind_index": new_blind_index},
                            ).eq("user_id", user_id).eq("phone_blind_index", old_digest).execute()
                    result.total_updated += 1
                except Exception as e:
                    result.errors += 1
                    logger.exception(
                        "Failed to update safety_contact_notices for contact %s (user %s): %s",
                        contact_id,
                        user_id,
                        e,
                    )
                    if settings.sentry_backend_dsn:
                        sentry_sdk.capture_exception(e)

        offset += batch_size

    logger.info(
        "Finished safety_contact_notices: %d scanned, %d updated, %d skipped, %d unchanged, %d errors.",
        result.total_scanned,
        result.total_updated,
        result.total_skipped,
        result.total_unchanged,
        result.errors,
    )
    return result


def main() -> int:
    """Main entrypoint for blind index rotation CLI script."""
    parser = argparse.ArgumentParser(
        description="Re-compute deterministic blind indexes under the primary key across all active domains.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=50,
        help="Number of rows per batch fetch (default: 50).",
    )
    parser.add_argument(
        "--domain",
        type=str,
        default=None,
        choices=["mobile", "campus_branch", "safety_contact_phone"],
        help="Limit rotation to a specific domain.",
    )
    parser.add_argument(
        "--offset",
        type=int,
        default=0,
        help="Starting row offset (default: 0).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Simulate index re-computation without modifying database rows.",
    )
    args = parser.parse_args()

    init_sentry_if_configured()

    total_scanned = 0
    total_updated = 0
    total_skipped = 0
    total_errors = 0

    print("=" * 70)
    print(f"  NEXUS BLIND INDEX ROTATION TOOL  {'[DRY-RUN]' if args.dry_run else ''}")
    print("=" * 70)

    domain_runners = {
        "mobile": rotate_users_mobile_blind_index,
        "campus_branch": rotate_profiles_campus_branch_blind_index,
        "safety_contact_phone": rotate_safety_contacts_blind_index,
    }

    selected_domains = [args.domain] if args.domain else list(domain_runners.keys())

    for domain in selected_domains:
        runner = domain_runners[domain]
        res = runner(
            batch_size=args.batch_size,
            dry_run=args.dry_run,
            start_offset=args.offset if (args.domain and args.domain == domain) else 0,
        )
        total_scanned += res.total_scanned
        total_updated += res.total_updated
        total_skipped += res.total_skipped
        total_errors += res.errors

    print("\n" + "=" * 70)
    print("  BLIND INDEX ROTATION SUMMARY")
    print("=" * 70)
    print(f"  Total Records Scanned: {total_scanned}")
    print(f"  Total Records Updated: {total_updated}")
    print(f"  Total Records Skipped: {total_skipped}")
    print(f"  Total DB Errors:       {total_errors}")
    print("=" * 70)

    if total_skipped > 0 or total_errors > 0:
        logger.error(
            "Blind index rotation completed with %d skipped records and %d database errors. "
            "DO NOT remove the old blind index key until all rows are successfully migrated.",
            total_skipped,
            total_errors,
        )
        return 1

    logger.info("Blind index rotation completed successfully with zero errors.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
