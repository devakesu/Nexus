"""
Value dimension scorer - fully local, zero network latency.

Mitigates Semantic Dilution by dynamically compiling intent-segregated text
blocks per dimension before running sentence transformer dot-product matches.
"""

import json
import logging
from typing import Any, cast

import numpy as np
from numpy.typing import NDArray

from app.core.crypto import encrypt_to_hex
from app.db.client import supabase_client
from app.db.profiles import decrypt_profile_record
from app.services.embeddings import get_embedding_model

logger = logging.getLogger(__name__)

_DEFAULT_DIMENSIONS: dict[str, int] = {
    "civil_liberties": 5,
    "environmentalism": 5,
    "technology_optimism": 5,
}

# 🛡️ 1. SEMANTIC SIGNAL ROUTING DICTIONARIES
# Ensures that unrelated parameters (like coffee or baking) leave the evaluation tracks
_SIGNAL_ROUTING_MATRIX: dict[str, set[str]] = {
    "civil_liberties": {
        "lgbtq+ rights",
        "mental health advocacy",
        "human rights",
        "gender equality",
        "tech ethics",
        "digital rights",
        "privacy",
        "philosophy",
        "politics",
        "autonomy",
    },
    "environmentalism": {
        "nature & gardening",
        "hiking",
        "gardening",
        "renewable energy",
        "climate action",
        "reforestation",
        "ecology",
        "solarpunk",
        "permaculture",
        "vegetable gardening",
        "bonsai trees",
        "houseplants",
        "bird watching",
        "outdoors",
        "sustainability",
    },
    "technology_optimism": {
        "coding",
        "crypto",
        "ai",
        "tech & skills",
        "collaborative projects",
        "startup",
        "design",
        "cryptocurrency & web3",
        "tech ethics",
        "systems",
        "decentralization",
        "cyberpunk",
        "python",
        "flutter & dart",
        "web development",
        "cybersecurity",
        "cloud & devops",
        "mobile apps",
        "digital illustration",
        "ui/ux design",
        "video editing",
    },
}

# 🎨 2. COMPACT NATURAL LANGUAGE ANCHORS
_DIMENSION_ANCHORS: dict[str, list[str]] = {
    "civil_liberties": [
        (
            "I advocate for digital rights, social justice, inclusion, "
            "equality, individual liberties, and freedom."
        ),
        (
            "I stand for a progressive, inclusive future with privacy "
            "safeguards, civil liberties, and personal autonomy."
        ),
    ],
    "environmentalism": [
        (
            "I care about environmental sustainability, eco-friendly green "
            "energy, conservation, and nature."
        ),
        (
            "I support solarpunk ecology, renewable resource preservation, "
            "planting trees, and organic living."
        ),
    ],
    "technology_optimism": [
        (
            "I love software engineering, advanced computing systems, "
            "technical automation, and technology progress."
        ),
        (
            "I am an acceleration tech optimist passionate about "
            "programming, software development, and AI innovation."
        ),
    ],
}

# ⚙️ 3. OPTIMIZED ACCURATE CALIBRATION WINDOW
_SIM_FLOOR: float = 0.15
_SIM_CEIL: float = 0.55

_anchor_vecs: dict[str, NDArray[np.float32]] | None = None


def _get_anchor_vecs() -> dict[str, NDArray[np.float32]]:
    global _anchor_vecs
    if _anchor_vecs is None:
        model = get_embedding_model()
        _anchor_vecs = {}
        for dim, phrases in _DIMENSION_ANCHORS.items():
            encoded: NDArray[np.float32] = model.encode(  # type: ignore[misc]
                phrases,
                normalize_embeddings=True,
                convert_to_numpy=True,
            )
            mean_vec: NDArray[np.float32] = encoded.mean(axis=0)
            norm = float(np.linalg.norm(mean_vec))
            _anchor_vecs[dim] = mean_vec / norm if norm > 0 else mean_vec
        logger.info("Intent-isolated anchor coordinates cached successfully")
    return _anchor_vecs


def _sim_to_score(sim: float) -> int:
    clamped = max(_SIM_FLOOR, min(_SIM_CEIL, sim))
    return round((clamped - _SIM_FLOOR) / (_SIM_CEIL - _SIM_FLOOR) * 9)


def _compile_filtered_text_for_dimension(
    dimension: str,
    interests: dict[str, int],
    sub_interests: dict[str, list[str]],
    causes_supported: list[str],
    tech_skills: list[str],
    activities: list[str],
    lifestyle: str,
    bio: str,
) -> str:
    """
    Surgically compiles profile tokens relevant ONLY to the evaluated dimension.
    Prevents unrelated visual/lifestyle noise from diluting transformer focus.
    """
    valid_signals = _SIGNAL_ROUTING_MATRIX[dimension]
    sentences: list[str] = []

    # Filter & inject Primary Interests matching domain signals
    filtered_interests = [inst for inst in interests if inst.lower() in valid_signals]
    if filtered_interests:
        sentences.append(
            f"Passionate profile interests include: {', '.join(filtered_interests)}.",
        )

    # Filter & inject Granular Sub-Interests matching domain signals
    flattened_subs = [sub for bucket in sub_interests.values() for sub in bucket]
    filtered_subs = [sub for sub in flattened_subs if sub.lower() in valid_signals]
    if filtered_subs:
        sentences.append(f"Specific focus tracks cover: {', '.join(filtered_subs)}.")

    # Filter & inject explicit arrays
    filtered_causes = [c for c in causes_supported if c.lower() in valid_signals]
    if filtered_causes:
        sentences.append(f"Dedicated advocate for: {', '.join(filtered_causes)}.")

    filtered_skills = [s for s in tech_skills if s.lower() in valid_signals]
    if filtered_skills:
        sentences.append(
            "Possesses technical engineering capabilities in: "
            f"{', '.join(filtered_skills)}.",
        )

    filtered_activities = [a for a in activities if a.lower() in valid_signals]
    if filtered_activities:
        sentences.append(
            "Participates in related campus spaces like: "
            f"{', '.join(filtered_activities)}.",
        )

    # Context check: if lifestyle/bio has matching keywords, append to capture intent
    lowered_lifestyle = lifestyle.lower()
    lowered_bio = bio.lower()

    if any(word in lowered_lifestyle for word in valid_signals):
        sentences.append(f"Lifestyle context markers: {lifestyle}")
    if any(word in lowered_bio for word in valid_signals):
        sentences.append(f"Stated profile overview statement: {bio}")

    return " ".join(sentences)


def derive_value_dimensions(
    interests: dict[str, int],
    sub_interests: dict[str, list[str]],
    causes_supported: list[str],
    tech_skills: list[str],
    activities: list[str],
    lifestyle: str,
    bio: str = "",
) -> dict[str, int]:
    """
    Calculates 3 unpolluted metric coordinates by checking
    isolated dimensional text blocks independently.
    """
    has_signal = any(
        (
            interests,
            sub_interests,
            causes_supported,
            tech_skills,
            activities,
            lifestyle,
            bio,
        ),
    )
    if not has_signal:
        return _DEFAULT_DIMENSIONS.copy()

    try:
        model = get_embedding_model()
        anchors = _get_anchor_vecs()
        computed_output_matrix: dict[str, int] = {}

        # Evaluate each psychometric coordinate inside its own unpolluted space
        for dim, anchor_vec in anchors.items():
            targeted_text = _compile_filtered_text_for_dimension(
                dimension=dim,
                interests=interests,
                sub_interests=sub_interests,
                causes_supported=causes_supported,
                tech_skills=tech_skills,
                activities=activities,
                lifestyle=lifestyle,
                bio=bio,
            )

            if not targeted_text.strip():
                computed_output_matrix[dim] = (
                    5  # Default to neutral midpoint if no signals found
                )
                continue

            # Generate local inference embedding track over clean targeted text
            profile_vec: NDArray[np.float32] = model.encode(  # type: ignore[misc]
                targeted_text,
                normalize_embeddings=True,
                convert_to_numpy=True,
            )

            # Compute similarity distance map cleanly
            similarity = float(np.dot(profile_vec, anchor_vec))
            computed_output_matrix[dim] = _sim_to_score(similarity)

        return computed_output_matrix

    except Exception:
        logger.exception(
            "Value dimension derivation failed - using defaults fallback space",
        )
        return _DEFAULT_DIMENSIONS.copy()


def recompile_value_dimensions(user_id: str) -> None:
    try:
        res = (
            supabase_client.table("profiles")
            .select(
                "interests, sub_interests, causes_supported, "
                "tech_skills, activities, lifestyle, bio",
            )
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        raw = getattr(res, "data", None)
        if not raw or not isinstance(raw, dict):
            logger.warning(
                "Value dimension recompile skipped: profile not found",
                extra={"user_id": user_id},
            )
            return

        row = decrypt_profile_record(cast(dict[str, Any], raw))

        dimensions = derive_value_dimensions(
            interests=row.get("interests") or {},
            sub_interests=row.get("sub_interests") or {},
            causes_supported=row.get("causes_supported") or [],
            tech_skills=row.get("tech_skills") or [],
            activities=row.get("activities") or [],
            lifestyle=row.get("lifestyle") or "",
            bio=row.get("bio") or "",
        )

        supabase_client.table("profiles").update(
            {"value_dimensions": encrypt_to_hex(json.dumps(dimensions))},
        ).eq("id", user_id).execute()

        logger.info(
            "Value dimensions recompiled cleanly",
            extra={"user_id": user_id, "dimensions": dimensions},
        )
    except Exception:
        logger.exception("Value dimension recompile failed for user %s", user_id)
