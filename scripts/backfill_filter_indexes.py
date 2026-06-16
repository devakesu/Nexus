#!/usr/bin/env python3
"""
Backfill blind index columns for children_plans and religious_beliefs.

Run once after the 20260614000000_filter_indexes.sql migration:
    python scripts/backfill_filter_indexes.py

Requires the app environment to be loaded (SUPABASE_URL, SUPABASE_KEY,
ENCRYPTION_KEY, BLIND_INDEX_KEY set via .env or environment).
"""
import os
import sys
from typing import Any, cast

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.core.crypto import compute_blind_index
from app.db.client import supabase_client
from app.db.profiles import decrypt_profile_record

BATCH = 50


def main() -> None:
    print("Starting blind index backfill...")
    offset = 0
    total_updated = 0
    total_skipped = 0

    while True:
        res = (
            supabase_client.table("profiles")
            .select("*")
            .range(offset, offset + BATCH - 1)
            .execute()
        )
        rows = res.data or []
        if not rows:
            break

        for _row in rows:
            row: dict[str, Any] = cast(dict[str, Any], _row)
            try:
                profile = decrypt_profile_record(row)
            except Exception as exc:
                print(f"  SKIP {row.get('id')}: decrypt error — {exc}")
                total_skipped += 1
                continue

            update: dict[str, Any] = {}

            if cp := profile.get("children_plans"):
                update["children_plans_blind_index"] = compute_blind_index(cp)
            if rb := profile.get("religious_beliefs"):
                update["religious_beliefs_blind_index"] = compute_blind_index(rb)

            if update:
                supabase_client.table("profiles").update(update).eq(
                    "id", profile["id"]
                ).execute()
                total_updated += 1

        print(f"  Processed batch offset={offset}, rows={len(rows)}")
        offset += BATCH

    print(
        f"Done. Updated: {total_updated}, Skipped (decrypt error): {total_skipped}"
    )


if __name__ == "__main__":
    main()
