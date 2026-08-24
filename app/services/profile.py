"""Profile vector compilation and background embedding synchronization service.

Fetches updated user profiles, triggers sentence transformer embedding calculations across intent-isolated contexts,
and upserts vector representations to the `vector_profiles` database table.
"""

import logging
from typing import Any, cast

from app.core.infra.cache import sync_redis_client
from app.db.client import supabase_client
from app.db.profiles import decrypt_profile_record, sanitize_decrypted_profile
from app.services.embeddings import generate_nexus_intent_embeddings

logger = logging.getLogger(__name__)


def recompile_and_push_vectors(user_id: str, plaintext_bio: str | None = None) -> None:
    """Background task to fetch full decrypted profile and upsert intent embeddings.

    Args:
        user_id: Unique user identifier string.
        plaintext_bio: Optional plaintext bio string if updated in current request.
    """
    cooldown_key = f"user:vector_recompile_cooldown:{user_id}"
    try:
        if not sync_redis_client.set(cooldown_key, "1", ex=60, nx=True):
            logger.info(
                "Vector recompile skipped: cooldown active",
                extra={"user_id": user_id},
            )
            return
    except Exception:
        # Non-fatal: if Redis is unavailable, continue with recompilation
        pass

    try:
        select_cols = (
            "id, bio, lifestyle, partner_values, religious_beliefs, "
            "children_plans, campus_branch, campus_year, role_at, "
            "display_gender, pronouns, looking_for, activities, "
            "causes_supported, ai_vibe_tags, tech_skills, sub_interests"
        )
        res = (
            supabase_client.table("profiles")
            .select(select_cols)
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        raw = getattr(res, "data", None)
        if not raw or not isinstance(raw, dict):
            logger.warning(
                "Vector recompile skipped: profile not found",
                extra={"user_id": user_id},
            )
            return

        profile = decrypt_profile_record(cast(dict[str, Any], raw))
        profile = sanitize_decrypted_profile(profile)

        # Use the caller-supplied plaintext bio if provided; otherwise use the persisted bio.
        effective_bio = (
            plaintext_bio
            if plaintext_bio is not None
            else (profile.get("bio") or "")
        )

        vectors = generate_nexus_intent_embeddings(profile, effective_bio)

        # Resolve (or create) the pseudonym firewall token for this user.
        # upsert with on_conflict="user_id" is a no-op for existing rows while
        # auto-generating a pseudonym_id for first-time users via the DB DEFAULT.
        map_res = (
            supabase_client.table("profile_pseudonym_map")
            .upsert({"user_id": user_id}, on_conflict="user_id", ignore_duplicates=True)
            .select("pseudonym_id")
            .execute()
        )
        map_rows = getattr(map_res, "data", None)
        if not map_rows:
            # upsert with ignore_duplicates returns no rows on conflict; fall back
            # to a plain select to retrieve the pre-existing pseudonym_id.
            map_res = (
                supabase_client.table("profile_pseudonym_map")
                .select("pseudonym_id")
                .eq("user_id", user_id)
                .maybe_single()
                .execute()
            )
            map_rows_fallback = getattr(map_res, "data", None)
            if not map_rows_fallback or not isinstance(map_rows_fallback, dict):
                logger.error(
                    "Vector recompile aborted: could not resolve pseudonym mapping",
                    extra={"user_id": user_id},
                )
                return
            pseudonym_id: str = str(
                cast(dict[str, Any], map_rows_fallback)["pseudonym_id"],
            )
        else:
            pseudonym_id = str(cast(list[Any], map_rows)[0]["pseudonym_id"])

        supabase_client.table("vector_profiles").upsert(
            {
                "pseudonym_id": pseudonym_id,
                "bio_embedding": vectors["bio_embedding"],
                "career_embedding": vectors["career_embedding"],
                "identity_embedding": vectors["identity_embedding"],
            },
            on_conflict="pseudonym_id",
        ).execute()

        logger.info(
            "Intent embeddings recompiled and committed",
            extra={"user_id": user_id},
        )
    except Exception:
        # Non-fatal: vector staleness is preferable to blocking the save response.
        logger.exception(
            "Vector recompile failed for user %s - skipping silently",
            user_id,
        )
