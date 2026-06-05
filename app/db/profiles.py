import json
import logging
from typing import Any, Sequence

from postgrest.exceptions import APIError

from app.core.config import DiscoveryTab
from app.core.crypto import decrypt_pii, compute_blind_index
from app.db.client import supabase_client, DatabaseAccessError, ProfileDecodeError
from app.db.exclusions import fetch_active_discovery_excluded_ids
from app.models import DiscoveryFilters

logger = logging.getLogger(__name__)


def _get_completion_flag_column(active_tab: DiscoveryTab) -> str:
    if active_tab == "Dating":
        return "is_dating_complete"
    if active_tab == "Friends":
        return "is_friends_complete"
    if active_tab == "Professional":
        return "is_professional_complete"
    raise ValueError(f"Unsupported active_tab: {active_tab}")


def _get_target_bucket_column(active_tab: DiscoveryTab) -> str:
    if active_tab == "Dating":
        return "dating_target_buckets"
    if active_tab == "Friends":
        return "friends_target_buckets"
    if active_tab == "Professional":
        return "professional_target_buckets"
    raise ValueError(f"Unsupported active_tab: {active_tab}")


def _expand_target_buckets(buckets: Sequence[Any] | None) -> list[str]:
    if not buckets:
        return []
    # Normalize to list[str]
    str_buckets = [str(b) for b in buckets]
    if "Open" in str_buckets:
        return ["M", "F", "NB", "Q"]
    return str_buckets


def _parse_encrypted_scalar(row: dict[str, Any], field: str) -> None:
    raw = row.get(field)
    if raw is None:
        row[field] = ""
        return

    row[field] = decrypt_pii(raw)


def _parse_encrypted_list(row: dict[str, Any], field: str) -> None:
    raw = row.get(field)
    if raw is None:
        row[field] = []
        return

    decrypted = decrypt_pii(raw)

    if decrypted == "":
        row[field] = []
        return

    try:
        parsed = json.loads(decrypted)
    except json.JSONDecodeError as e:
        raise ProfileDecodeError(f"{field} decrypted to invalid JSON list payload") from e

    if not isinstance(parsed, list):
        raise ProfileDecodeError(f"{field} must decrypt to a list")

    row[field] = parsed


def _parse_encrypted_dict(row: dict[str, Any], field: str) -> None:
    raw = row.get(field)
    if raw is None:
        row[field] = {}
        return

    decrypted = decrypt_pii(raw)

    if decrypted == "":
        row[field] = {}
        return

    try:
        parsed = json.loads(decrypted)
    except json.JSONDecodeError as e:
        raise ProfileDecodeError(f"{field} decrypted to invalid JSON object payload") from e

    if not isinstance(parsed, dict):
        raise ProfileDecodeError(f"{field} must decrypt to a dict")

    row[field] = parsed


def _decrypt_profile_record(row: dict[str, Any]) -> dict[str, Any]:
    """
    Decrypt and normalize a single profile record in memory.

    Scalar encrypted fields decrypt to strings.
    Encrypted list payloads must decrypt to JSON arrays.
    Encrypted structured payloads must decrypt to JSON objects.

    Raises:
        DecryptFailedError: ciphertext cannot be decrypted
        ProfileDecodeError: decrypted content has an invalid shape
    """
    scalar_fields = [
        "display_gender",
        "display_sexuality",
        "hometown",
        "partner_values",
        "children_plans",
        "religious_beliefs",
        "lifestyle",
        "drinking",
        "smoking",
        "role",
    ]
    for field in scalar_fields:
        _parse_encrypted_scalar(row, field)

    array_fields = [
        "looking_for",
        "activities",
        "causes_supported",
        "top_artists",
        "tech_skills",
        "languages",
        "ai_vibe_tags",
        "pets",
    ]
    for field in array_fields:
        _parse_encrypted_list(row, field)

    json_fields = ["interests", "sub_interests", "value_dimensions"]
    for field in json_fields:
        _parse_encrypted_dict(row, field)

    return row


def _attach_empty_embeddings(record: dict[str, Any]) -> None:
    record["bio_embedding"] = None
    record["career_embedding"] = None
    record["identity_embedding"] = None


def fetch_stage_1_candidates(
    viewer_id: str,
    active_tab: DiscoveryTab,
    filters: DiscoveryFilters,
    candidate_limit: int = 200,
) -> tuple[dict[str, Any] | None, list[dict[str, Any]]]:
    """
    Execute the Stage 1 database filtering pass.

    Returns:
        tuple[viewer_profile_or_none, candidate_profiles]

    Raises:
        DatabaseAccessError: unexpected database failures
        DecryptFailedError: encrypted fields could not be decrypted
        ProfileDecodeError: decrypted payload shape was invalid
    """
    logger.info(
        "Fetching stage 1 candidates",
        extra={"viewer_id": viewer_id, "active_tab": active_tab},
    )

    try:
        viewer_res = (
            supabase_client.table("profiles")
            .select("*")
            .eq("id", viewer_id)
            .limit(1)
            .execute()
        )
        viewer_rows = viewer_res.data if isinstance(viewer_res.data, list) else []
        viewer = viewer_rows[0] if viewer_rows else None
    except APIError as e:
        logger.exception(
            "Failed to fetch viewer profile",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError("Failed to fetch viewer profile") from e
    except Exception as e:
        logger.exception(
            "Unexpected error fetching viewer profile",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError("Unexpected error fetching viewer profile") from e

    if not viewer or not isinstance(viewer, dict):
        logger.warning(
            "Viewer profile response was empty or malformed",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        return None, []

    from app.core.crypto import DecryptFailedError
    viewer = _decrypt_profile_record(viewer)

    completion_flag_column = _get_completion_flag_column(active_tab)
    target_bucket_column = _get_target_bucket_column(active_tab)
    excluded_ids = fetch_active_discovery_excluded_ids(viewer_id, active_tab)
    
    query = supabase_client.table("profiles").select("*")
    query = query.neq("id", viewer_id)
    query = query.eq(completion_flag_column, True)
    query = query.eq("is_deactivated", False)

    if filters.years:
        query = query.in_("year", filters.years)
    if filters.drinking:
        query = query.in_(
            "drinking_blind_index",
            [compute_blind_index(d) for d in filters.drinking],
        )
    if filters.smoking:
        query = query.in_(
            "smoking_blind_index",
            [compute_blind_index(s) for s in filters.smoking],
        )
    if filters.branches:
        query = query.in_(
            "branch_blind_index",
            [compute_blind_index(b) for b in filters.branches],
        )
    if filters.role:
        query = query.eq("role_blind_index", compute_blind_index(filters.role))

    query = query.gte("age", filters.min_age)
    query = query.lte("age", filters.max_age)

    candidates_to_enrich: list[dict[str, Any]] = []
    
    if excluded_ids:
        excluded_filter = f"({','.join(str(x) for x in excluded_ids)})"
        query = query.not_.in_("id", excluded_filter)

    try:
        viewer_targets_raw = viewer.get(target_bucket_column)
        viewer_search_raw = viewer.get("search_buckets")

        if not isinstance(viewer_targets_raw, list):
            logger.warning(
                "Viewer profile missing valid target bucket configuration",
                extra={"viewer_id": viewer_id, "active_tab": active_tab},
            )
            _attach_empty_embeddings(viewer)
            return viewer, []
        
        if not isinstance(viewer_search_raw, list) or not viewer_search_raw:
            logger.warning(
                "Viewer profile missing valid search bucket configuration",
                extra={"viewer_id": viewer_id, "active_tab": active_tab},
            )
            _attach_empty_embeddings(viewer)
            return viewer, []

        viewer_search_expanded = _expand_target_buckets(viewer_search_raw)
        viewer_targets = _expand_target_buckets(viewer_targets_raw)

        if not viewer_targets:
            logger.warning(
                "Viewer target buckets empty after expansion",
                extra={"viewer_id": viewer_id, "active_tab": active_tab},
            )
            _attach_empty_embeddings(viewer)
            return viewer, []

        res = query.overlaps("search_buckets", viewer_targets).limit(candidate_limit).execute()

        if not isinstance(res.data, list):
            logger.warning(
                "Candidate result payload malformed for bucketed query",
                extra={"viewer_id": viewer_id, "active_tab": active_tab},
            )
            _attach_empty_embeddings(viewer)
            return viewer, []

        for candidate in res.data:
            if not isinstance(candidate, dict):
                continue

            candidate_targets_raw = candidate.get(target_bucket_column)
            if not isinstance(candidate_targets_raw, list):
                continue

            candidate_targets = _expand_target_buckets(candidate_targets_raw)
            if not candidate_targets:
                continue

            if any(bucket in candidate_targets for bucket in viewer_search_expanded):
                candidates_to_enrich.append(_decrypt_profile_record(candidate))

    except (DecryptFailedError, ProfileDecodeError):
        logger.exception(
            "Candidate decryption or decode failure",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise
    except APIError as e:
        logger.exception(
            "Candidate query failed",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError("Failed to fetch candidate profiles") from e
    except Exception as e:
        logger.exception(
            "Unexpected error during candidate fetch",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError("Unexpected error during candidate fetch") from e

    _attach_empty_embeddings(viewer)
    
    if excluded_ids:
        candidates_to_enrich = [
            c for c in candidates_to_enrich
            if str(c.get("id")) not in excluded_ids
        ]

    if not candidates_to_enrich:
        logger.info(
            "No candidates matched stage 1 filters",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        return viewer, []

    for candidate in candidates_to_enrich:
        _attach_empty_embeddings(candidate)

    candidate_map = {c["id"]: c for c in candidates_to_enrich if "id" in c}
    all_target_ids = list(candidate_map.keys()) + [viewer_id]

    try:
        vector_res = (
            supabase_client.table("profile_pseudonym_map")
            .select("user_id, vector_profiles(bio_embedding, career_embedding, identity_embedding)")
            .in_("user_id", all_target_ids)
            .execute()
        )
        vector_records = vector_res.data if isinstance(vector_res.data, list) else []
    except APIError as e:
        logger.exception(
            "Vector lookup failed",
            extra={"viewer_id": viewer_id, "candidate_count": len(candidate_map)},
        )
        raise DatabaseAccessError("Failed to fetch vector profiles") from e
    except Exception as e:
        logger.exception(
            "Unexpected vector lookup failure",
            extra={"viewer_id": viewer_id, "candidate_count": len(candidate_map)},
        )
        raise DatabaseAccessError("Unexpected error fetching vector profiles") from e

    for record in vector_records:
        if not isinstance(record, dict):
            continue

        target_uid = record.get("user_id")
        v_profile = record.get("vector_profiles")

        if not isinstance(v_profile, dict) or not target_uid:
            continue

        if target_uid == viewer_id:
            viewer["bio_embedding"] = v_profile.get("bio_embedding")
            viewer["career_embedding"] = v_profile.get("career_embedding")
            viewer["identity_embedding"] = v_profile.get("identity_embedding")
        elif target_uid in candidate_map:
            candidate_map[target_uid]["bio_embedding"] = v_profile.get("bio_embedding")
            candidate_map[target_uid]["career_embedding"] = v_profile.get("career_embedding")
            candidate_map[target_uid]["identity_embedding"] = v_profile.get("identity_embedding")

    logger.info(
        "Stage 1 candidate fetch complete",
        extra={
            "viewer_id": viewer_id,
            "active_tab": active_tab,
            "candidate_count": len(candidate_map)
        },
    )

    return viewer, list(candidate_map.values())
