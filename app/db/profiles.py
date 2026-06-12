import json
import logging
from collections.abc import Sequence
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import DiscoveryTab
from app.core.crypto import compute_blind_index, decrypt_pii
from app.db.client import DatabaseAccessError, ProfileDecodeError, supabase_client
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
        raise ProfileDecodeError(
            f"{field} decrypted to invalid JSON list payload",
        ) from e

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
        raise ProfileDecodeError(
            f"{field} decrypted to invalid JSON object payload",
        ) from e

    if not isinstance(parsed, dict):
        raise ProfileDecodeError(f"{field} must decrypt to a dict")

    row[field] = parsed


def decrypt_profile_record(row: dict[str, Any]) -> dict[str, Any]:
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
        "pronouns",
        "hometown",
        "current_place",
        "partner_values",
        "children_plans",
        "religious_beliefs",
        "lifestyle",
        "drinking",
        "smoking",
        "role",
        "profile_pic",
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
        "normal_pics",
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


def _fetch_and_decrypt_viewer(
    viewer_id: str,
    active_tab: DiscoveryTab,
) -> dict[str, Any] | None:
    """Helper to fetch and decrypt the discovery viewer profile record."""
    try:
        viewer_res = (
            supabase_client.table("profiles")
            .select("*")
            .eq("id", viewer_id)
            .limit(1)
            .execute()
        )
        viewer_rows = viewer_res.data
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
        return None

    return decrypt_profile_record(viewer)


def _build_candidate_query(
    viewer_id: str,
    active_tab: DiscoveryTab,
    filters: DiscoveryFilters,
    excluded_ids: set[str],
) -> Any:
    """Helper to assemble query constraints for candidate matching."""
    completion_flag_column = _get_completion_flag_column(active_tab)
    query = supabase_client.table("profiles").select("*")
    query = query.neq("id", viewer_id)
    query = query.eq(completion_flag_column, True)
    query = query.eq("is_deactivated", False)

    if filters.campus_years:
        query = query.in_("campus_year", filters.campus_years)
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
    if filters.campus_branches:
        query = query.in_(
            "campus_branch_blind_index",
            [compute_blind_index(b) for b in filters.campus_branches],
        )
    if filters.role:
        query = query.eq("role_blind_index", compute_blind_index(filters.role))

    query = query.gte("age", filters.min_age)
    query = query.lte("age", filters.max_age)

    if excluded_ids:
        excluded_filter = f"({','.join(str(x) for x in excluded_ids)})"
        query = query.not_.in_("id", excluded_filter)

    return query


def _get_expanded_viewer_buckets(
    viewer: dict[str, Any],
    active_tab: DiscoveryTab,
) -> tuple[list[str], list[str]]:
    """Helper to extract and expand target and search preference buckets from viewer."""
    target_bucket_column = _get_target_bucket_column(active_tab)
    viewer_targets_raw = viewer.get(target_bucket_column)
    viewer_search_raw = viewer.get("search_buckets")

    if not isinstance(viewer_targets_raw, list):
        logger.warning(
            "Viewer profile missing valid target bucket configuration",
            extra={"viewer_id": viewer["id"], "active_tab": active_tab},
        )
        return [], []

    if not isinstance(viewer_search_raw, list) or not viewer_search_raw:
        logger.warning(
            "Viewer profile missing valid search bucket configuration",
            extra={"viewer_id": viewer["id"], "active_tab": active_tab},
        )
        return [], []

    viewer_search_list = cast(list[Any], viewer_search_raw)
    viewer_targets_list = cast(list[Any], viewer_targets_raw)
    viewer_search_expanded = _expand_target_buckets(viewer_search_list)
    viewer_targets = _expand_target_buckets(viewer_targets_list)

    if not viewer_targets:
        logger.warning(
            "Viewer target buckets empty after expansion",
            extra={"viewer_id": viewer["id"], "active_tab": active_tab},
        )
        return [], []

    return viewer_search_expanded, viewer_targets


def _filter_candidate_matches(
    candidates_data: list[Any],
    viewer_search_expanded: list[str],
    target_bucket_column: str,
) -> list[dict[str, Any]]:
    """
    Helper to verify candidate mutual matching eligibility
    and decrypt matching rows.
    """
    candidates_to_enrich: list[dict[str, Any]] = []
    for candidate in candidates_data:
        if not isinstance(candidate, dict):
            continue

        cand_dict = cast(dict[str, Any], candidate)
        candidate_targets_raw = cand_dict.get(target_bucket_column)
        if not isinstance(candidate_targets_raw, list):
            continue

        candidate_targets_list = cast(list[Any], candidate_targets_raw)
        candidate_targets = _expand_target_buckets(candidate_targets_list)
        if not candidate_targets:
            continue

        if any(bucket in candidate_targets for bucket in viewer_search_expanded):
            candidates_to_enrich.append(decrypt_profile_record(cand_dict))
    return candidates_to_enrich


def _execute_and_filter_candidates(
    query: Any,
    viewer: dict[str, Any],
    active_tab: DiscoveryTab,
    candidate_limit: int,
) -> list[dict[str, Any]]:
    """Helper to query candidates overlapping target preferences and filter results."""
    viewer_search_expanded, viewer_targets = _get_expanded_viewer_buckets(
        viewer,
        active_tab,
    )
    if not viewer_targets:
        return []

    try:
        res = (
            query.overlaps("search_buckets", viewer_targets)
            .limit(candidate_limit)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Candidate query failed",
            extra={"viewer_id": viewer["id"], "active_tab": active_tab},
        )
        raise DatabaseAccessError("Failed to fetch candidate profiles") from e

    target_bucket_column = _get_target_bucket_column(active_tab)
    from app.core.crypto import DecryptFailedError

    try:
        return _filter_candidate_matches(
            res.data,
            viewer_search_expanded,
            target_bucket_column,
        )
    except (DecryptFailedError, ProfileDecodeError):
        logger.exception(
            "Candidate decryption or decode failure",
            extra={"viewer_id": viewer["id"], "active_tab": active_tab},
        )
        raise


def _map_vector_embeddings(
    vector_records: list[Any],
    viewer: dict[str, Any],
    candidate_map: dict[str, dict[str, Any]],
    viewer_id: str,
) -> None:
    """Helper to route query vector records into candidate map and viewer profiles."""
    for record in vector_records:
        if not isinstance(record, dict):
            continue

        rec_dict = cast(dict[str, Any], record)
        target_uid = cast(str | None, rec_dict.get("user_id"))
        v_profile = rec_dict.get("vector_profiles")

        if not isinstance(v_profile, dict) or not target_uid:
            continue

        v_dict = cast(dict[str, Any], v_profile)

        if target_uid == viewer_id:
            viewer["bio_embedding"] = v_dict.get("bio_embedding")
            viewer["career_embedding"] = v_dict.get("career_embedding")
            viewer["identity_embedding"] = v_dict.get("identity_embedding")
        elif target_uid in candidate_map:
            candidate_map[target_uid]["bio_embedding"] = v_dict.get(
                "bio_embedding",
            )
            candidate_map[target_uid]["career_embedding"] = v_dict.get(
                "career_embedding",
            )
            candidate_map[target_uid]["identity_embedding"] = v_dict.get(
                "identity_embedding",
            )


def _enrich_candidates_with_vectors(
    viewer: dict[str, Any],
    candidates: list[dict[str, Any]],
    viewer_id: str,
) -> None:
    """Helper to lookup and attach career/bio/identity embeddings for matched rows."""
    _attach_empty_embeddings(viewer)
    for candidate in candidates:
        _attach_empty_embeddings(candidate)

    candidate_map: dict[str, dict[str, Any]] = {}
    for c in candidates:
        cand_id = c.get("id")
        if cand_id:
            candidate_map[str(cand_id)] = c

    all_target_ids: list[str] = [*candidate_map.keys(), viewer_id]

    try:
        vector_res = (
            supabase_client.table("profile_pseudonym_map")
            .select(
                "user_id, vector_profiles(bio_embedding, "
                "career_embedding, identity_embedding)",
            )
            .in_("user_id", all_target_ids)
            .execute()
        )
        vector_records = vector_res.data
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

    _map_vector_embeddings(vector_records, viewer, candidate_map, viewer_id)


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

    viewer = _fetch_and_decrypt_viewer(viewer_id, active_tab)
    if not viewer:
        return None, []

    excluded_ids = fetch_active_discovery_excluded_ids(viewer_id, active_tab)
    query = _build_candidate_query(viewer_id, active_tab, filters, excluded_ids)
    candidates_to_enrich = _execute_and_filter_candidates(
        query=query,
        viewer=viewer,
        active_tab=active_tab,
        candidate_limit=candidate_limit,
    )

    if excluded_ids:
        candidates_to_enrich = [
            c for c in candidates_to_enrich if str(c.get("id")) not in excluded_ids
        ]

    if not candidates_to_enrich:
        logger.info(
            "No candidates matched stage 1 filters",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        _attach_empty_embeddings(viewer)
        return viewer, []

    candidate_map = {c["id"]: c for c in candidates_to_enrich if "id" in c}
    _enrich_candidates_with_vectors(viewer, list(candidate_map.values()), viewer_id)

    logger.info(
        "Stage 1 candidate fetch complete",
        extra={
            "viewer_id": viewer_id,
            "active_tab": active_tab,
            "candidate_count": len(candidate_map),
        },
    )

    return viewer, list(candidate_map.values())
