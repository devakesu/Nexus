import json
import logging
from collections.abc import Sequence
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import DiscoveryTab
from app.core.crypto import compute_blind_index, decrypt_pii, encrypt_to_hex
from app.db.client import DatabaseAccessError, ProfileDecodeError, supabase_client
from app.db.exclusions import fetch_active_discovery_excluded_ids
from app.models import DiscoveryFilters

logger = logging.getLogger(__name__)


def _get_completion_flag_column(active_tab: DiscoveryTab) -> str:
    if active_tab == "Dating":
        return "is_dating_active"
    if active_tab == "Friends":
        return "is_friends_active"
    if active_tab == "Professional":
        return "is_professional_active"
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

    IMPORTANT: profile_pic and normal_pics are decrypted as scalar/list fields.
    If the caller is constructing ordered_images lists, decrypt_profile_record
    MUST be called before accessing profile_pic or normal_pics, otherwise
    the returned lists will contain raw hex ciphertexts.

    Raises:
        DecryptFailedError: ciphertext cannot be decrypted
        ProfileDecodeError: decrypted content has an invalid shape
    """
    scalar_fields = [
        "display_gender",
        "display_sexuality",
        "pronouns",
        "bio",
        "campus_branch",
        "campus_name",
        "hometown",
        "current_place",
        "partner_values",
        "children_plans",
        "religious_beliefs",
        "lifestyle",
        "drinking",
        "smoking",
        "role_at",
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
        "role_type",
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
            # NOTE: We fetch all fields needed for decryption. If any expected
            # columns are omitted, decrypt_profile_record will receive None
            # and default them to empty.
            .select(
                "id, name, age, campus_year, campus_branch, campus_name, "
                "display_gender, display_sexuality, pronouns, bio, search_bucket, "
                "hometown, current_place, partner_values, children_plans, "
                "religious_beliefs, lifestyle, drinking, smoking, role_at, "
                "dating_target_buckets, dating_for, friends_target_buckets, "
                "professional_target_buckets, looking_for, activities, "
                "causes_supported, top_artists, tech_skills, languages, "
                "ai_vibe_tags, pets, interests, sub_interests, value_dimensions, "
                "role_type, normal_pics, profile_pic",
            )
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


def _apply_blind_index_filters(query: Any, filters: DiscoveryFilters) -> Any:
    """Apply all encrypted single-value IN filters using blind indexes."""
    blind_fields: list[tuple[list[str] | None, str]] = [
        (filters.drinking, "drinking_blind_index"),
        (filters.smoking, "smoking_blind_index"),
        (filters.campus_branches, "campus_branch_blind_index"),
        (filters.children_plans, "children_plans_blind_index"),
        (filters.religious_beliefs, "religious_beliefs_blind_index"),
    ]
    for values, column in blind_fields:
        if values:
            query = query.in_(column, [compute_blind_index(v) for v in values])
    return query


def _build_candidate_query(
    viewer_id: str,
    active_tab: DiscoveryTab,
    filters: DiscoveryFilters,
    excluded_ids: set[str],
) -> Any:
    """Helper to assemble query constraints for candidate matching."""
    completion_flag_column = _get_completion_flag_column(active_tab)
    explicit_columns = (
        "id, name, age, campus_year, campus_branch, campus_name, "
        "display_gender, display_sexuality, pronouns, bio, search_bucket, "
        "hometown, current_place, partner_values, children_plans, "
        "religious_beliefs, lifestyle, drinking, smoking, role_at, "
        "dating_target_buckets, dating_for, friends_target_buckets, "
        "professional_target_buckets, looking_for, activities, "
        "causes_supported, top_artists, tech_skills, languages, "
        "ai_vibe_tags, pets, interests, sub_interests, value_dimensions, "
        f"profile_pic, normal_pics, {completion_flag_column}"
    )
    query = supabase_client.table("profiles").select(explicit_columns)
    query = query.neq("id", viewer_id)
    query = query.eq(completion_flag_column, True)
    query = query.eq("is_deactivated", False)

    if filters.campus_years:
        query = query.in_("campus_year", filters.campus_years)
    query = _apply_blind_index_filters(query, filters)
    dealbreakers = filters.dealbreaker_fields or []
    if filters.dating_for and "dating_for" in dealbreakers:
        query = query.overlaps("dating_for", filters.dating_for)
    if filters.search_bucket_filter:
        query = query.in_("search_bucket", filters.search_bucket_filter)

    query = query.gte("age", filters.min_age)
    query = query.lte("age", filters.max_age)

    if excluded_ids:
        # NOTE: At scale, if excluded_ids has thousands of entries (e.g. from
        # user blocks/passes), converting it to a comma-separated filter in a
        # PostgREST GET request can exceed URL length limits.
        # Consider chunking or migrating this to a DB-side RPC function /
        # exclusion view if this list grows large.
        query = query.not_.in_("id", list(excluded_ids))

    return query


def _get_expanded_viewer_buckets(
    viewer: dict[str, Any],
    active_tab: DiscoveryTab,
) -> tuple[list[str], list[str]]:
    """Helper to extract and expand target and search preference buckets from viewer."""
    target_bucket_column = _get_target_bucket_column(active_tab)
    search_bucket_column = "search_bucket"
    viewer_targets_raw = viewer.get(target_bucket_column)
    viewer_search_raw = viewer.get(search_bucket_column)

    if not isinstance(viewer_targets_raw, list):
        logger.warning(
            "Viewer profile missing valid target bucket configuration",
            extra={"viewer_id": viewer["id"], "active_tab": active_tab},
        )
        return [], []

    if not viewer_search_raw:
        logger.warning(
            "Viewer profile missing valid search bucket configuration",
            extra={"viewer_id": viewer["id"], "active_tab": active_tab},
        )
        return [], []

    viewer_targets_list = cast(list[Any], viewer_targets_raw)
    viewer_search_expanded = [str(viewer_search_raw)]
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


_POST_FETCH_FIELDS: frozenset[str] = frozenset({
    "languages",
    "sub_interests",
    "role_type",
    "looking_for",
    "causes_supported",
    "tech_skills",
    "partner_values",
})


def _list_overlap(cand_list: list[str], allowed: list[str]) -> bool:
    return bool(set(cand_list) & set(allowed))


def _check_basic_overlap(c: dict[str, Any], filters: DiscoveryFilters) -> bool:
    if filters.languages and not _list_overlap(
        c.get("languages") or [],
        filters.languages,
    ):
        return False
    if filters.sub_interests:
        sub_raw = cast(dict[str, list[str]], c.get("sub_interests") or {})
        flat: list[str] = [v for vs in sub_raw.values() for v in vs]
        if not _list_overlap(flat, filters.sub_interests):
            return False
    return not (
        filters.role_type
        and not _list_overlap(c.get("role_type") or [], filters.role_type)
    )


def _check_candidate_match(
    c: dict[str, Any],
    filters: DiscoveryFilters,
    dealbreakers: set[str],
) -> bool:
    if not _check_basic_overlap(c, filters):
        return False

    if filters.looking_for and not _list_overlap(
        c.get("looking_for") or [],
        filters.looking_for,
    ):
        return False
    if filters.causes_supported and not _list_overlap(
        c.get("causes_supported") or [],
        filters.causes_supported,
    ):
        return False
    if filters.tech_skills and not _list_overlap(
        c.get("tech_skills") or [],
        filters.tech_skills,
    ):
        return False
    if filters.partner_values and "partner_values" in dealbreakers:
        pv_raw = c.get("partner_values") or ""
        pv_list = [v.strip().lower() for v in pv_raw.split(",") if v.strip()]
        lower_filters = [v.strip().lower() for v in filters.partner_values if v.strip()]
        if not _list_overlap(pv_list, lower_filters):
            return False
    return True


def _apply_post_fetch_filters(
    candidates: list[dict[str, Any]],
    filters: DiscoveryFilters,
) -> list[dict[str, Any]]:
    """In-memory filter pass for encrypted fields that have no blind indexes."""
    dealbreakers = set(filters.dealbreaker_fields or [])
    return [
        c
        for c in candidates
        if _check_candidate_match(c, filters, dealbreakers)
    ]


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

    search_bucket_column = "search_bucket"
    try:
        res = (
            query.in_(search_bucket_column, viewer_targets)
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

    active_post_fetch = sum(
        1 for f in _POST_FETCH_FIELDS if getattr(filters, f, None)
    )
    effective_limit = min(candidate_limit + active_post_fetch * 100, 600)

    candidates_to_enrich = _execute_and_filter_candidates(
        query=query,
        viewer=viewer,
        active_tab=active_tab,
        candidate_limit=effective_limit,
    )

    candidates_to_enrich = _apply_post_fetch_filters(candidates_to_enrich, filters)

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


async def update_profile_images_and_metadata(
    user_id: str,
    images: list[str],
    vibe_tags: list[str],
) -> None:
    """
    Encrypts and saves ordered images (profile pic & normal gallery)
    and locally computed vibe tags directly into Supabase BYTEA fields.
    """
    profile_pic = images[0] if images else ""
    normal_pics = images[1:] if len(images) > 1 else []

    db_mutation_payload = {
        "profile_pic": encrypt_to_hex(profile_pic),
        "normal_pics": encrypt_to_hex(json.dumps(normal_pics)),
        "ai_vibe_tags": encrypt_to_hex(json.dumps(vibe_tags)),
        "updated_at": "now()",
    }

    try:
        response = (
            supabase_client.table("profiles")
            .update(db_mutation_payload)
            .eq("id", user_id)
            .execute()
        )
        if not response.data:
            raise ValueError("Profile update returned no data")
    except Exception as e:
        logger.exception(
            "Failed to update profile images and metadata for user %s",
            user_id,
        )
        raise DatabaseAccessError("Failed to update profile images and metadata") from e


def fetch_peer_profile_by_id(target_id: str) -> dict[str, Any] | None:
    """
    Fetch and fully decrypt a profile record by ID for peer viewing
    (e.g., from the likes inbox). Returns None if the profile is not found
    or is inactive. Raises DatabaseAccessError on query failure.
    """
    try:
        res = (
            supabase_client.table("profiles")
            .select("*")
            .eq("id", target_id)
            .eq("is_deactivated", False)
            .limit(1)
            .execute()
        )
        rows = res.data
        if not rows:
            return None
        row = cast(dict[str, Any], rows[0])
        # Resolve the first image as profile_pic if a separate
        # ordered_images list exists.
        if not row.get("profile_pic") and row.get("ordered_images"):
            images = row["ordered_images"]
            if isinstance(images, list) and images:
                row["profile_pic"] = images[0]
        return decrypt_profile_record(row)
    except APIError as e:
        logger.exception(
            "Failed to fetch peer profile",
            extra={"target_id": target_id},
        )
        raise DatabaseAccessError(
            "Failed to fetch peer profile",
        ) from e
