import logging
from typing import Any, cast

from app.db.client import supabase_client
from app.db.profiles import decrypt_profile_record
from app.services.embeddings import generate_nexus_intent_embeddings

logger = logging.getLogger(__name__)


def recompile_and_push_vectors(user_id: str, plaintext_bio: str) -> None:
    """
    Background task: fetch the full decrypted profile, compile three
    intent-isolated embeddings, then upsert to vector_profiles.
    Runs after the profile write commits so all fields are current.
    """
    try:
        res = (
            supabase_client.table("profiles")
            .select("*")
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

        # Use the caller-supplied plaintext bio so the freshly written value
        # is encoded even before the next full profile fetch would see it.
        effective_bio = plaintext_bio or profile.get("bio") or ""

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
                cast(dict[str, Any], map_rows_fallback)["pseudonym_id"]
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
        ).execute()

        logger.info(
            "Intent embeddings recompiled and committed",
            extra={"user_id": user_id},
        )
    except Exception:
        # Non-fatal: vector staleness is preferable to blocking the save response.
        logger.exception(
            "Vector recompile failed for user %s — skipping silently",
            user_id,
        )
