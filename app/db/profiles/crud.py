"""Profile retrieval, stage 1 candidate search queries, and peer profile lookup methods."""

import logging
from collections.abc import Sequence
from typing import Any, cast

from postgrest.exceptions import APIError

import app.db.profiles as profiles_module
from app.core.config import DiscoveryTab
from app.core.security.crypto import DecryptFailedError, compute_blind_index
from app.db.client import DatabaseAccessError, ProfileDecodeError, normalize_uuid, supabase_client
from app.db.discovery import fetch_active_discovery_excluded_ids
from app.db.profiles.encryption import decrypt_profile_record
from app.db.profiles.media import sign_profile_media
from app.models import DiscoveryFilters

logger = logging.getLogger(__name__)

_PROFILE_SELECT_COLUMNS = (
    "id, name, age, campus_year, campus_branch, campus_name, "
    "display_gender, display_sexuality, pronouns, bio, search_bucket, "
    "hometown, current_place, partner_values, children_plans, "
    "religious_beliefs, lifestyle, drinking, smoking, role_at, "
    "dating_target_buckets, dating_for, friends_target_buckets, "
    "professional_target_buckets, looking_for, activities, "
    "causes_supported, top_artists, artist_affinity, genre_affinity, "
    "tech_skills, languages, "
    "ai_vibe_tags, pets, interests, sub_interests, value_dimensions, "
    "role_type, normal_pics, profile_pic, updated_at"
)

_POST_FETCH_FIELDS: frozenset[str] = frozenset(
    {
        "languages",
        "sub_interests",
        "role_type",
        "looking_for",
        "causes_supported",
        "tech_skills",
        "partner_values",
    },
)


def _get_completion_flag_column(active_tab: DiscoveryTab) -> str:
    """Get completion flag column name."""
    if active_tab == "Dating":
        return "is_dating_active"
    if active_tab == "Friends":
        return "is_friends_active"
    if active_tab == "Professional":
        return "is_professional_active"
    raise ValueError(f"Unsupported active_tab: {active_tab}")


def _get_target_bucket_column(active_tab: DiscoveryTab) -> str:
    """Get target bucket column name."""
    if active_tab == "Dating":
        return "dating_target_buckets"
    if active_tab == "Friends":
        return "friends_target_buckets"
    if active_tab == "Professional":
        return "professional_target_buckets"
    raise ValueError(f"Unsupported active_tab: {active_tab}")


def _expand_target_buckets(buckets: Sequence[Any] | None) -> list[str]:
    """Expand target buckets."""
    if not buckets:
        return []
    str_buckets = [str(b) for b in buckets]
    if "Open" in str_buckets:
        return ["M", "F", "NB"]
    return str_buckets


def _attach_empty_embeddings(record: dict[str, Any]) -> None:
    """Attach empty embedding keys."""
    record["bio_embedding"] = None
    record["career_embedding"] = None
    record["identity_embedding"] = None


def _fetch_and_decrypt_viewer(
    viewer_id: str,
    active_tab: DiscoveryTab,
) -> dict[str, Any] | None:
    """Fetch and decrypt viewer profile."""
    try:
        viewer_res = (
            supabase_client.table("profiles")
            .select(f"{_PROFILE_SELECT_COLUMNS}, users!inner(app_variant)")
            .eq("id", viewer_id)
            .limit(1)
            .execute()
        )
        viewer_rows = viewer_res.data
        if viewer_rows and isinstance(viewer_rows[0], dict):
            viewer = cast(dict[str, Any], viewer_rows[0])
            users_info = viewer.pop("users", None)
            users_dict = (
                cast(dict[str, Any], users_info)
                if isinstance(users_info, dict)
                else {}
            )
            viewer["app_variant"] = users_dict.get("app_variant", "nexus")
        else:
            viewer = None
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

    if not viewer:
        logger.warning(
            "Viewer profile response was empty or malformed",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        return None

    return decrypt_profile_record(viewer)


def _apply_blind_index_filters(query: Any, filters: DiscoveryFilters) -> Any:
    """Apply blind index filter constraints."""
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
    app_variant: str,
) -> Any:
    """Build candidate discovery PostgREST query."""
    completion_flag_column = _get_completion_flag_column(active_tab)
    explicit_columns = (
        f"{_PROFILE_SELECT_COLUMNS}, {completion_flag_column}, "
        "chat_presence(last_active_at), "
        "users!inner(app_variant, is_active, is_suspended, moderation_status)"
    )
    query = profiles_module.supabase_client.table("profiles").select(explicit_columns)
    query = query.neq("id", viewer_id)
    query = query.eq(completion_flag_column, True)
    query = query.eq("is_deactivated", False)
    query = query.eq("users.app_variant", app_variant)
    query = query.eq("users.is_active", True)
    query = query.eq("users.is_suspended", False)
    query = query.neq("users.moderation_status", "banned")

    if filters.campus_years:
        query = query.in_("campus_year", filters.campus_years)
    query = _apply_blind_index_filters(query, filters)
    dealbreakers = filters.dealbreaker_fields or []
    if filters.dating_for and "dating_for" in dealbreakers:
        query = query.overlaps("dating_for", filters.dating_for)
    if filters.search_bucket_filter:
        expanded_buckets = _expand_target_buckets(filters.search_bucket_filter)
        query = query.in_("search_bucket", expanded_buckets)

    query = query.gte("age", filters.min_age)
    query = query.lte("age", filters.max_age)

    if excluded_ids:
        query = query.not_.in_("id", list(excluded_ids)[:1000])

    return query


def _get_expanded_viewer_buckets(
    viewer: dict[str, Any],
    active_tab: DiscoveryTab,
) -> tuple[list[str], list[str]]:
    """Extract and expand viewer target and search buckets."""
    target_bucket_column = _get_target_bucket_column(active_tab)
    search_bucket_column = "search_bucket"
    viewer_targets_raw = viewer.get(target_bucket_column)
    viewer_search_raw = viewer.get(search_bucket_column)

    if not isinstance(viewer_targets_raw, list) or not viewer_search_raw:
        return [], []

    viewer_targets_list = cast(list[Any], viewer_targets_raw)
    viewer_search_expanded = [str(viewer_search_raw)]
    viewer_targets = _expand_target_buckets(viewer_targets_list)

    if not viewer_targets:
        return [], []

    return viewer_search_expanded, viewer_targets


def _unpack_chat_presence(cand_dict: dict[str, Any]) -> None:
    """Extract last_active_at from chat_presence relationship."""
    presence = cand_dict.get("chat_presence")
    if isinstance(presence, dict):
        presence_dict = cast(dict[str, Any], presence)
        last_active = presence_dict.get("last_active_at")
        if last_active is not None:
            cand_dict["last_active_at"] = last_active
    elif isinstance(presence, list) and presence:
        presence_list = cast(list[Any], presence)
        first_presence = presence_list[0]
        if isinstance(first_presence, dict):
            first_presence_dict = cast(dict[str, Any], first_presence)
            last_active = first_presence_dict.get("last_active_at")
            if last_active is not None:
                cand_dict["last_active_at"] = last_active


def _filter_candidate_matches(
    candidates_data: list[Any],
    viewer_search_expanded: list[str],
    target_bucket_column: str,
) -> list[dict[str, Any]]:
    """Filter candidate matches by target bucket eligibility."""
    candidates_to_enrich: list[dict[str, Any]] = []
    for candidate in candidates_data:
        if not isinstance(candidate, dict):
            continue

        cand_dict = cast(dict[str, Any], candidate)
        cand_dict.pop("users", None)
        candidate_targets_raw = cand_dict.get(target_bucket_column)
        if not isinstance(candidate_targets_raw, list):
            continue

        candidate_targets_list = cast(list[Any], candidate_targets_raw)
        candidate_targets = _expand_target_buckets(candidate_targets_list)
        if not candidate_targets:
            continue

        if any(bucket in candidate_targets for bucket in viewer_search_expanded):
            _unpack_chat_presence(cand_dict)
            candidates_to_enrich.append(decrypt_profile_record(cand_dict))
    return candidates_to_enrich


def _list_overlap(cand_list: list[str], allowed: list[str]) -> bool:
    """Check list overlap."""
    return bool(set(cand_list) & set(allowed))


def _check_basic_overlap(c: dict[str, Any], filters: DiscoveryFilters) -> bool:
    """Check basic field overlap against filters."""
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
    """Check candidate match against post-fetch filter criteria."""
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
        pv_raw: Any = c.get("partner_values") or []
        if isinstance(pv_raw, str):
            pv_list: list[str] = [
                v.strip().lower() for v in pv_raw.split(",") if v.strip()
            ]
        else:
            pv_list: list[str] = [
                str(v).strip().lower() for v in pv_raw if str(v).strip()
            ]
        lower_filters = [v.strip().lower() for v in filters.partner_values if v.strip()]
        if not _list_overlap(pv_list, lower_filters):
            return False
    return True


def _apply_post_fetch_filters(
    candidates: list[dict[str, Any]],
    filters: DiscoveryFilters,
) -> list[dict[str, Any]]:
    """In-memory filter pass for encrypted fields."""
    dealbreakers = set(filters.dealbreaker_fields or [])
    return [c for c in candidates if _check_candidate_match(c, filters, dealbreakers)]


def _execute_and_filter_candidates(
    query: Any,
    viewer: dict[str, Any],
    active_tab: DiscoveryTab,
    candidate_limit: int,
) -> list[dict[str, Any]]:
    """Execute candidate query and filter matching results."""
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
    """Route query vector records into candidate map and viewer profile."""
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
    """Attach career/bio/identity embeddings to viewer and matched candidates."""
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
    """Execute the Stage 1 database filtering pass."""
    logger.info(
        "Fetching stage 1 candidates",
        extra={"viewer_id": viewer_id, "active_tab": active_tab},
    )

    viewer = _fetch_and_decrypt_viewer(viewer_id, active_tab)
    if not viewer:
        return None, []

    app_variant = viewer.get("app_variant", "nexus")

    excluded_ids = fetch_active_discovery_excluded_ids(viewer_id, active_tab)
    query = _build_candidate_query(
        viewer_id=viewer_id,
        active_tab=active_tab,
        filters=filters,
        excluded_ids=excluded_ids,
        app_variant=app_variant,
    )

    dealbreakers = set(filters.dealbreaker_fields or [])
    active_post_fetch = sum(
        1
        for f in _POST_FETCH_FIELDS
        if getattr(filters, f, None)
        and (f != "partner_values" or "partner_values" in dealbreakers)
    )
    effective_limit = min(candidate_limit + active_post_fetch * 50, 400)

    candidates_to_enrich = _execute_and_filter_candidates(
        query=query,
        viewer=viewer,
        active_tab=active_tab,
        candidate_limit=effective_limit,
    )

    if excluded_ids:
        candidates_to_enrich = [
            c for c in candidates_to_enrich if str(c.get("id") or "") not in excluded_ids
        ]

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


def fetch_peer_profile_by_id(target_id: str) -> dict[str, Any] | None:
    """Fetch and fully decrypt a profile record by ID for peer viewing."""
    try:
        res = (
            supabase_client.table("profiles")
            .select(
                "id, name, age, campus_year, display_gender, display_sexuality, "
                "pronouns, bio, campus_branch, campus_name, hometown, current_place, "
                "children_plans, religious_beliefs, lifestyle, drinking, smoking, "
                "role_at, profile_pic, looking_for, activities, causes_supported, "
                "top_artists, tech_skills, role_type, languages, ai_vibe_tags, "
                "pets, normal_pics, partner_values, interests, sub_interests, "
                "value_dimensions, created_at, updated_at, "
                "is_deactivated",
            )
            .eq("id", target_id)
            .eq("is_deactivated", False)
            .limit(1)
            .execute()
        )
        rows = res.data
        if not rows:
            return None
        row = cast(dict[str, Any], rows[0])
        if not row.get("profile_pic") and row.get("ordered_images"):
            images = row["ordered_images"]
            if isinstance(images, list) and images:
                row["profile_pic"] = images[0]
        return sign_profile_media(decrypt_profile_record(row))
    except APIError as e:
        logger.exception(
            "Failed to fetch peer profile",
            extra={"target_id": target_id},
        )
        raise DatabaseAccessError(
            "Failed to fetch peer profile",
        ) from e


def is_active_profile(user_id: str) -> bool:
    """Check if a profile exists and is active (not deactivated)."""
    try:
        valid_id = normalize_uuid(user_id)
    except (ValueError, TypeError):
        return False

    try:
        res = (
            supabase_client.table("profiles")
            .select("id")
            .eq("id", valid_id)
            .eq("is_deactivated", False)
            .limit(1)
            .execute()
        )
        rows = cast(list[dict[str, Any]], getattr(res, "data", None) or [])
        return len(rows) > 0
    except APIError as e:
        logger.exception(
            "Failed to check if profile is active",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to verify user profile status") from e


def fetch_music_affinities(user_id: str) -> tuple[dict[str, float], dict[str, float]]:
    """Fetch and decrypt only artist_affinity and genre_affinity for music match grading.

    Avoids fetching, decrypting, or signing the entire peer profile payload.
    """
    try:
        valid_id = normalize_uuid(user_id)
    except (ValueError, TypeError):
        return {}, {}

    try:
        res = (
            supabase_client.table("profiles")
            .select("artist_affinity, genre_affinity")
            .eq("id", valid_id)
            .eq("is_deactivated", False)
            .limit(1)
            .execute()
        )
        rows = cast(list[dict[str, Any]], getattr(res, "data", None) or [])
        if not rows:
            return {}, {}
        row = dict(rows[0])
        from app.db.profiles.encryption import _parse_encrypted_dict

        _parse_encrypted_dict(row, "artist_affinity")
        _parse_encrypted_dict(row, "genre_affinity")
        raw_artist = row.get("artist_affinity")
        raw_genre = row.get("genre_affinity")
        artist_affinity: dict[str, float] = (
            cast(dict[str, float], raw_artist)
            if isinstance(raw_artist, dict) and "__DECRYPTION_FAILED__" not in raw_artist
            else {}
        )
        genre_affinity: dict[str, float] = (
            cast(dict[str, float], raw_genre)
            if isinstance(raw_genre, dict) and "__DECRYPTION_FAILED__" not in raw_genre
            else {}
        )
        return artist_affinity, genre_affinity
    except APIError:
        logger.exception("Failed to fetch music affinities", extra={"user_id": user_id})
        return {}, {}
    except Exception:
        logger.exception("Unexpected error fetching music affinities", extra={"user_id": user_id})
        return {}, {}
