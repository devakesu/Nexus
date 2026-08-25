#!/usr/bin/env python3
"""One-shot migration script to re-encrypt PII ciphertext under the new leading key.

Iterates through all database tables containing Fernet-encrypted PII columns,
decrypts each field using MultiFernet (which tries all configured keys in order),
re-encrypts with the primary (first) key in the key list, and updates the row in-place.

Row Atomicity:
If any encrypted field on a row fails to decrypt, the entire row is skipped (no partial writes).
Skipped row IDs are logged and reported to Sentry for investigation.

Usage:
    # Dry run across all tables
    infisical run --env=prod projectId=xxxx --path=/public --path=/runtime -- python3 scripts/rotate_pii_encryption.py --dry-run

    # Full re-encryption pass
    infisical run --env=prod projectId=xxxx --path=/public --path=/runtime -- python3 scripts/rotate_pii_encryption.py

    # Target specific table with custom batch size and starting offset
    infisical run --env=prod projectId=xxxx --path=/public --path=/runtime -- python3 scripts/rotate_pii_encryption.py --table profiles --batch-size 100 --offset 500
"""

import argparse
from dataclasses import dataclass
import logging
import os
import sys
from typing import Any, cast

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import sentry_sdk
from app.core.config import settings
from app.core.infra.sentry import scrub_event
from app.core.security.crypto import DecryptFailedError, decrypt_pii, encrypt_to_hex
from app.db.client import supabase_client
from app.db.profiles.encryption import ALL_ENCRYPTED_FIELDS

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


@dataclass
class TableConfig:
    table: str
    pk: str
    category: str
    fields: list[str]


@dataclass
class RotationResult:
    table: str
    total_scanned: int = 0
    total_updated: int = 0
    total_skipped: int = 0
    total_unchanged: int = 0
    errors: int = 0


PII_TABLE_CONFIGS: list[TableConfig] = [
    TableConfig(
        table="profiles",
        pk="id",
        category="profile",
        fields=sorted(list(ALL_ENCRYPTED_FIELDS)),
    ),
    TableConfig(
        table="users",
        pk="id",
        category="contact",
        fields=["mobile"],
    ),
    TableConfig(
        table="safety_contacts",
        pk="id",
        category="contact",
        fields=["name", "phone"],
    ),
    TableConfig(
        table="safety_sessions",
        pk="id",
        category="media_escrow",
        fields=["label", "event_context"],
    ),
    TableConfig(
        table="safety_alerts",
        pk="id",
        category="media_escrow",
        fields=["current_location"],
    ),
    TableConfig(
        table="safety_evidence",
        pk="id",
        category="media_escrow",
        fields=["media_key_base64"],
    ),
    TableConfig(
        table="spotify_connections",
        pk="user_id",
        category="oauth",
        fields=["refresh_token"],
    ),
    TableConfig(
        table="spotify_playlists",
        pk="id",
        category="oauth",
        fields=["name", "tracks"],
    ),
    TableConfig(
        table="feedback_reports",
        pk="id",
        category="contact",
        fields=["subject", "message"],
    ),
    TableConfig(
        table="chat_events",
        pk="id",
        category="chat",
        fields=["event_time", "location_lat", "location_lng", "location_label"],
    ),
]


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


def rotate_table_records(
    config: TableConfig,
    batch_size: int = 50,
    dry_run: bool = False,
    start_offset: int = 0,
) -> RotationResult:
    """Re-encrypts all encrypted records in a specific database table.

    Args:
        config: Table configuration specifying table name, primary key, category, and fields.
        batch_size: Number of records to fetch per batch.
        dry_run: If True, simulates decryption and encryption without DB updates.
        start_offset: Row offset to start from.

    Returns:
        RotationResult: Summary statistics for the table rotation.
    """
    result = RotationResult(table=config.table)
    offset = start_offset
    columns_to_select = f"{config.pk}, {', '.join(config.fields)}"

    logger.info(
        "Starting PII rotation for table '%s' (fields: %s, batch_size: %d, offset: %d, dry_run: %s)...",
        config.table,
        config.fields,
        batch_size,
        offset,
        dry_run,
    )

    while True:
        try:
            res = (
                supabase_client.table(config.table)
                .select(columns_to_select)
                .range(offset, offset + batch_size - 1)
                .execute()
            )
            rows = cast(list[dict[str, Any]], res.data or [])
        except Exception as e:
            logger.exception(
                "Database error fetching batch for table '%s' at offset %d: %s",
                config.table,
                offset,
                e,
            )
            result.errors += 1
            if settings.sentry_backend_dsn:
                sentry_sdk.capture_exception(e)
            break

        if not rows:
            break

        for row in rows:
            result.total_scanned += 1
            pk_val = row.get(config.pk)

            # Step 1: Attempt decryption for all encrypted fields on the row
            decrypted_values: dict[str, str | None] = {}
            row_failed = False
            failed_field = None

            for field in config.fields:
                raw_val = row.get(field)
                if raw_val is None or raw_val == "" or raw_val == b"":
                    decrypted_values[field] = None
                    continue

                try:
                    decrypted = decrypt_pii(raw_val, category=config.category)
                    decrypted_values[field] = decrypted
                except DecryptFailedError as e:
                    row_failed = True
                    failed_field = field
                    logger.error(
                        "Decryption failed for table '%s' PK '%s' field '%s': %s",
                        config.table,
                        pk_val,
                        field,
                        e,
                    )
                    if settings.sentry_backend_dsn:
                        sentry_sdk.capture_message(
                            f"PII re-encryption decryption failure on {config.table}.{field} for PK {pk_val}",
                            level="error",
                        )
                    break
                except Exception as e:
                    row_failed = True
                    failed_field = field
                    logger.exception(
                        "Unexpected error decrypting table '%s' PK '%s' field '%s': %s",
                        config.table,
                        pk_val,
                        field,
                        e,
                    )
                    if settings.sentry_backend_dsn:
                        sentry_sdk.capture_exception(e)
                    break

            # Step 2: Enforce row-level atomicity - skip entire row if any field failed
            if row_failed:
                result.total_skipped += 1
                logger.warning(
                    "Skipping entire row in '%s' (PK: %s) due to failure on field '%s'.",
                    config.table,
                    pk_val,
                    failed_field,
                )
                continue

            # Step 3: Build update payload with newly encrypted tokens
            update_payload: dict[str, Any] = {}
            has_encrypted_content = False

            for field, plaintext in decrypted_values.items():
                if plaintext is not None:
                    has_encrypted_content = True
                    update_payload[field] = encrypt_to_hex(
                        plaintext, category=config.category,
                    )

            if not has_encrypted_content:
                result.total_unchanged += 1
                continue

            # Step 4: Write back atomically if not dry run
            if dry_run:
                result.total_updated += 1
            else:
                try:
                    supabase_client.table(config.table).update(update_payload).eq(
                        config.pk, pk_val,
                    ).execute()
                    result.total_updated += 1
                except Exception as e:
                    result.errors += 1
                    logger.exception(
                        "Failed to update row in '%s' (PK: %s): %s",
                        config.table,
                        pk_val,
                        e,
                    )
                    if settings.sentry_backend_dsn:
                        sentry_sdk.capture_exception(e)

        offset += batch_size

    logger.info(
        "Finished table '%s': %d scanned, %d updated, %d skipped, %d unchanged, %d errors.",
        config.table,
        result.total_scanned,
        result.total_updated,
        result.total_skipped,
        result.total_unchanged,
        result.errors,
    )
    return result


def main() -> int:
    """Main entrypoint for PII rotation CLI script."""
    parser = argparse.ArgumentParser(
        description="Re-encrypt PII ciphertext under the primary key across all tables.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=50,
        help="Number of rows per batch fetch (default: 50).",
    )
    parser.add_argument(
        "--table",
        type=str,
        default=None,
        help="Limit rotation to a single table (e.g. 'profiles').",
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
        help="Simulate decryption and re-encryption without modifying database rows.",
    )
    args = parser.parse_args()

    init_sentry_if_configured()

    configs = PII_TABLE_CONFIGS
    if args.table:
        configs = [c for c in configs if c.table == args.table]
        if not configs:
            logger.error("Unknown table '%s'. Available tables: %s", args.table, [c.table for c in PII_TABLE_CONFIGS])
            return 1

    total_scanned = 0
    total_updated = 0
    total_skipped = 0
    total_errors = 0

    print("=" * 70)
    print(f"  NEXUS PII KEY ROTATION & RE-ENCRYPTION TOOL  {'[DRY-RUN]' if args.dry_run else ''}")
    print("=" * 70)

    for config in configs:
        res = rotate_table_records(
            config=config,
            batch_size=args.batch_size,
            dry_run=args.dry_run,
            start_offset=args.offset if (args.table and args.table == config.table) else 0,
        )
        total_scanned += res.total_scanned
        total_updated += res.total_updated
        total_skipped += res.total_skipped
        total_errors += res.errors

    print("\n" + "=" * 70)
    print("  ROTATION SUMMARY")
    print("=" * 70)
    print(f"  Total Rows Scanned:   {total_scanned}")
    print(f"  Total Rows Updated:   {total_updated}")
    print(f"  Total Rows Skipped:   {total_skipped}")
    print(f"  Total DB Errors:      {total_errors}")
    print("=" * 70)

    if total_skipped > 0 or total_errors > 0:
        logger.error(
            "PII rotation completed with %d skipped rows and %d database errors. "
            "DO NOT remove the old key until all rows are successfully migrated.",
            total_skipped,
            total_errors,
        )
        return 1

    logger.info("PII rotation completed successfully with zero errors.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
