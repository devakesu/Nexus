"""
Nexus intent-isolated embedding compiler.

Accepts a single plaintext bio string alongside the full decrypted profile
dictionary and partitions the data into three unpolluted text contexts
before encoding them with the local sentence-transformer model.

Track mapping
─────────────
  bio_embedding
      bio + lifestyle + partner_values + religious_beliefs + children_plans
  career_embedding
      campus_branch + campus_year + role + tech_skills + sub_interests
      + looking_for
  identity_embedding
      causes_supported + activities + display_gender + pronouns
"""

import logging
from typing import Any, cast

from sentence_transformers import SentenceTransformer

logger = logging.getLogger(__name__)

# Module-level singleton - loaded once on first call, reused on all subsequent calls.
_model: SentenceTransformer | None = None


def get_embedding_model() -> SentenceTransformer:
    """Return the shared sentence-transformer singleton, loading it on first call."""
    global _model
    if _model is None:
        logger.info("Loading sentence-transformer model (all-MiniLM-L6-v2)")
        _model = SentenceTransformer("all-MiniLM-L6-v2")
    return _model


def generate_nexus_intent_embeddings(
    profile: dict[str, Any],
    raw_plaintext_bio: str,
) -> dict[str, list[float]]:
    """
    Partition the V6 profile payload into three intent-isolated text contexts
    and encode each with the local sentence-transformer model.

    Args:
        profile:           Decrypted profile dictionary (all fields already plaintext).
        raw_plaintext_bio: The plaintext bio string submitted by the user in the
                           current request (before encryption).

    Returns:
        Dictionary with keys ``bio_embedding``, ``career_embedding``, and
        ``identity_embedding``, each containing a list[float] of length 384.
    """

    # ──────────────────────────────────────────────────────────────────
    # 1. EXTRACT FIELDS WITH SAFE FALLBACKS
    # ──────────────────────────────────────────────────────────────────
    lifestyle: str = (profile.get("lifestyle") or "").strip()
    partner_values_raw: Any = profile.get("partner_values") or []
    if isinstance(partner_values_raw, str):
        partner_values = partner_values_raw.strip()
    else:
        partner_values = ", ".join(str(v) for v in partner_values_raw).strip()
    religious_beliefs: str = (profile.get("religious_beliefs") or "").strip()
    children_plans: str = (profile.get("children_plans") or "").strip()

    campus_branch: str = (profile.get("campus_branch") or "B.Tech.").strip()
    campus_year: int | str = profile.get("campus_year") or 1
    role: str = (profile.get("role_at") or "").strip()

    display_gender: str = (profile.get("display_gender") or "").strip()
    pronouns: str = (profile.get("pronouns") or "").strip()

    # List fields - guard against None and non-list shapes.
    looking_for: list[str] = list(profile.get("looking_for") or [])
    activities: list[str] = list(profile.get("activities") or [])
    causes_supported: list[str] = list(profile.get("causes_supported") or [])
    tech_skills: list[str] = list(profile.get("tech_skills") or [])

    # sub_interests is a dict[str, list[str]] - flatten to a single list.
    sub_interests_raw: Any = profile.get("sub_interests") or {}
    sub_interests_flat: list[str] = []
    if isinstance(sub_interests_raw, dict):
        typed_sub: dict[str, Any] = cast(dict[str, Any], sub_interests_raw)
        for bucket in typed_sub.values():
            if isinstance(bucket, list):
                typed_bucket: list[Any] = cast(list[Any], bucket)
                sub_interests_flat.extend(str(item) for item in typed_bucket)

    # ──────────────────────────────────────────────────────────────────
    # 2. COMPILE THREE STRICTLY SEGREGATED TEXT CONTEXTS
    # ──────────────────────────────────────────────────────────────────

    # Track A - Platonic / Romantic vibe focus
    bio_text_context = (
        f"[BIO SPACE] Era: {raw_plaintext_bio} | "
        f"Lifestyle & Day Structure: {lifestyle} | "
        f"Intent/Values Checklist: {partner_values} | "
        f"Belief Structure: {religious_beliefs} | "
        f"Family Direction: {children_plans}"
    )

    # Track B - Technical / Professional focus
    career_text_context = (
        f"[CAREER SPACE] Academic Path: {campus_branch} (Year {campus_year}) | "
        f"Target Professional Focus: {role} | "
        f"Active Team Gaps: {', '.join(looking_for)} | "
        f"Technical Stack Keywords: {', '.join(tech_skills)} | "
        f"Granular Coding Dimensions: {', '.join(sub_interests_flat)}"
    )

    # Track C - Cultural identity & aesthetic alignment (shadow telemetry)
    identity_text_context = (
        f"[IDENTITY SPACE] Presentation Silhouette: {display_gender} ({pronouns}) | "
        f"Social Causes Supported: {', '.join(causes_supported)} | "
        f"Campus Context Engagements: {', '.join(activities)}"
    )

    # ──────────────────────────────────────────────────────────────────
    # 3. LOCAL INFERENCE - zero network latency
    # ──────────────────────────────────────────────────────────────────
    model = get_embedding_model()
    return {
        "bio_embedding": model.encode(bio_text_context).tolist(),  # type: ignore[misc]
        "career_embedding": model.encode(career_text_context).tolist(),  # type: ignore[misc]
        "identity_embedding": model.encode(identity_text_context).tolist(),  # type: ignore[misc]
    }
