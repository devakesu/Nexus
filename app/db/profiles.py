"""Database profile CRUD, encrypted PII decoding, media storage, and discovery candidate query layer.

Manages user profile data persistence, media bucket signed URL generation,
field-level PII encryption/decryption, and discovery query filtering.
"""

import json
import logging
from collections.abc import Sequence
from typing import Any, cast

from postgrest.exceptions import APIError
from storage3.utils import StorageException

from app.core.config import DiscoveryTab
from app.core.crypto import (
    DecryptFailedError,
    compute_blind_index,
    decrypt_pii,
    encrypt_to_hex,
)
from app.db.client import DatabaseAccessError, ProfileDecodeError, supabase_client
from app.db.exclusions import fetch_active_discovery_excluded_ids
from app.models import DiscoveryFilters

logger = logging.getLogger(__name__)

_MEDIA_BUCKET = "user_media"
_MEDIA_URL_TTL_SECONDS = 3600



def _sign_media_paths(paths: Sequence[str]) -> dict[str, str]:
    """Batch-exchanges user_media storage paths for short-lived signed URLs.

    Uses the service-role client, which bypasses the bucket's owner-only RLS
    (see 20260726000000_user_media_owner_scoped.sql) - callers here have
    already decided, via their own query/authorization, that the requester
    may see this path. One network call regardless of how many paths are
    passed in, so callers should gather everything they need signed first
    rather than looping.
    """
    unique_paths = list(dict.fromkeys(p for p in paths if p))
    if not unique_paths:
        return {}
    try:
        signed = supabase_client.storage.from_(_MEDIA_BUCKET).create_signed_urls(
            unique_paths,
            _MEDIA_URL_TTL_SECONDS,
        )
    except StorageException:
        logger.exception("Failed to batch-sign user_media paths")
        return {}
    result: dict[str, str] = {}
    for item in signed:
        path = item["path"]
        signed_url = item["signedURL"]
        if path and signed_url:
            result[path] = signed_url
    return result


def sign_profile_media(row: dict[str, Any]) -> dict[str, Any]:
    """Replaces a single decrypted profile row's profile_pic/normal_pics
    storage paths with signed URLs, in place (one batched call for that
    row's own paths). Missing/unsigned paths resolve to None rather than
    leaking the raw storage path to the client.
    """
    pic = row.get("profile_pic")
    raw_normal_pics = row.get("normal_pics")
    normal_pics_list = (
        cast(list[Any], raw_normal_pics) if isinstance(raw_normal_pics, list) else []
    )
    normal_pics: list[str] = [p for p in normal_pics_list if isinstance(p, str) and p]
    all_paths = cast(list[str], [pic, *normal_pics]) if pic else normal_pics
    signed = _sign_media_paths(all_paths)
    if pic:
        row["profile_pic"] = signed.get(pic)
    if normal_pics:
        row["normal_pics"] = [signed[p] for p in normal_pics if p in signed]
    return row


def sign_profile_media_bulk(
    rows: list[dict[str, Any]],
    pic_field: str = "profile_pic",
) -> None:
    """Batch signed-URL equivalent of sign_profile_media for a list of rows
    that each carry a single thumbnail field (e.g. chat/likes/moderation-
    subject list rows) - one network call for the whole list, regardless of
    its size.
    """
    paths = [row[pic_field] for row in rows if row.get(pic_field)]
    signed = _sign_media_paths(paths)
    for row in rows:
        pic = row.get(pic_field)
        if pic:
            row[pic_field] = signed.get(pic)


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
# artist_affinity and genre_affinity are matching-engine-only signals - they
# are selected here (the scoring hot path, feeding viewer + candidate dicts
# into Nexus_Engine.engine.calculate_directional_match) but must NEVER be
# added to fetch_peer_profile_by_id's column list below, nor to
# app/db/sessions.py's fetch_discovery_node_detail - those two back every
# peer-facing profile view and only ever expose the bounded public
# top_artists list.


def decrypt_profile_rows(profiles_data: list[Any]) -> dict[str, dict[str, Any]]:
    """Decrypt profile_pic on a list of raw profile rows, keyed by profile id."""
    profile_map: dict[str, dict[str, Any]] = {}
    for p in profiles_data:
        if not isinstance(p, dict):
            continue
        p_dict = cast(dict[str, Any], p)
        pid = str(p_dict.get("id") or "")
        raw_pic = p_dict.get("profile_pic")
        if raw_pic:
            try:
                p_dict["profile_pic"] = decrypt_pii(raw_pic)
            except DecryptFailedError:
                p_dict["profile_pic"] = None
        profile_map[pid] = p_dict
    sign_profile_media_bulk(list(profile_map.values()))
    return profile_map


def _get_completion_flag_column(active_tab: DiscoveryTab) -> str:
    """Get completion flag column.

        Args:
            active_tab: Active discovery tab category ('Dating', 'BFF', or 'Networking').

        Returns:
            str: Response payload or result."""
    if active_tab == "Dating":
        return "is_dating_active"
    if active_tab == "Friends":
        return "is_friends_active"
    if active_tab == "Professional":
        return "is_professional_active"
    raise ValueError(f"Unsupported active_tab: {active_tab}")


def _get_target_bucket_column(active_tab: DiscoveryTab) -> str:
    """Get target bucket column.

        Args:
            active_tab: Active discovery tab category ('Dating', 'BFF', or 'Networking').

        Returns:
            str: Response payload or result."""
    if active_tab == "Dating":
        return "dating_target_buckets"
    if active_tab == "Friends":
        return "friends_target_buckets"
    if active_tab == "Professional":
        return "professional_target_buckets"
    raise ValueError(f"Unsupported active_tab: {active_tab}")


def _expand_target_buckets(buckets: Sequence[Any] | None) -> list[str]:
    """Expand target buckets.

        Args:
            buckets: Input buckets parameter.

        Returns:
            list[str]: Response payload or result."""
    if not buckets:
        return []
    # Normalize to list[str]
    str_buckets = [str(b) for b in buckets]
    if "Open" in str_buckets:
        return ["M", "F", "NB"]
    return str_buckets


def _parse_encrypted_scalar(row: dict[str, Any], field: str) -> None:
    """Parse encrypted scalar.

        Args:
            row: Input row parameter.
            field: Input field parameter."""
    raw = row.get(field)
    if raw is None:
        row[field] = None
        return

    try:
        row[field] = decrypt_pii(raw)
    except DecryptFailedError:
        row[field] = "__DECRYPTION_FAILED__"


def _parse_encrypted_list(row: dict[str, Any], field: str) -> None:
    """Parse encrypted list.

        Args:
            row: Input row parameter.
            field: Input field parameter."""
    raw = row.get(field)
    if raw is None:
        row[field] = []
        return

    try:
        decrypted = decrypt_pii(raw)
    except DecryptFailedError:
        row[field] = ["__DECRYPTION_FAILED__"]
        return

    if decrypted == "":
        row[field] = []
        return

    try:
        parsed = json.loads(decrypted)
    except json.JSONDecodeError:
        # Fallback: if it was stored as a comma-separated string, split it!
        parsed = [v.strip() for v in decrypted.split(",") if v.strip()]

    if not isinstance(parsed, list):
        parsed = [str(parsed)]

    row[field] = parsed


def _parse_encrypted_dict(row: dict[str, Any], field: str) -> None:
    """Parse encrypted dict.

        Args:
            row: Input row parameter.
            field: Input field parameter."""
    raw = row.get(field)
    if raw is None:
        row[field] = {}
        return

    try:
        decrypted = decrypt_pii(raw)
    except DecryptFailedError:
        row[field] = {"__DECRYPTION_FAILED__": True}
        return

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
        "partner_values",
    ]
    for field in array_fields:
        _parse_encrypted_list(row, field)

    json_fields = [
        "interests", "sub_interests", "value_dimensions",
        "artist_affinity", "genre_affinity",
    ]
    for field in json_fields:
        _parse_encrypted_dict(row, field)

    return row


def sanitize_decrypted_profile(row: dict[str, Any]) -> dict[str, Any]:
    """
    Replaces decryption failure sentinels with empty/safe equivalents in-place.
    """
    for k, v in list(row.items()):
        if v == "__DECRYPTION_FAILED__":
            row[k] = ""
        elif v == ["__DECRYPTION_FAILED__"]:
            row[k] = []
        elif v == {"__DECRYPTION_FAILED__": True}:
            row[k] = {}
    return row


def _attach_empty_embeddings(record: dict[str, Any]) -> None:
    """Attach empty embeddings.

        Args:
            record: Input record parameter."""
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
    app_variant: str,
) -> Any:
    """Helper to assemble query constraints for candidate matching."""
    completion_flag_column = _get_completion_flag_column(active_tab)
    explicit_columns = (
        f"{_PROFILE_SELECT_COLUMNS}, {completion_flag_column}, "
        "chat_presence(last_active_at), "
        "users!inner(app_variant, is_active, is_suspended, moderation_status)"
    )
    query = supabase_client.table("profiles").select(explicit_columns)
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
        # NOTE: At scale, if excluded_ids has thousands of entries (e.g. from
        # user blocks/passes), converting it to a comma-separated filter in a
        # PostgREST GET request can exceed URL length limits.
        # Consider chunking or migrating this to a DB-side RPC function /
        # exclusion view if this list grows large.
        query = query.not_.in_("id", list(excluded_ids)[:1000])

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


def _unpack_chat_presence(cand_dict: dict[str, Any]) -> None:
    """Helper to extract last_active_at from chat_presence relationship."""
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
    """
    Helper to verify candidate mutual matching eligibility
    and decrypt matching rows.
    """
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


def _list_overlap(cand_list: list[str], allowed: list[str]) -> bool:
    """Executes list overlap operation.

        Args:
            cand_list: Input cand list parameter.
            allowed: Input allowed parameter.

        Returns:
            bool: Response payload or result."""
    return bool(set(cand_list) & set(allowed))


def _check_basic_overlap(c: dict[str, Any], filters: DiscoveryFilters) -> bool:
    """Check basic overlap.

        Args:
            c: Input c parameter.
            filters: Input filters parameter.

        Returns:
            bool: Response payload or result."""
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
    """Check candidate match.

        Args:
            c: Input c parameter.
            filters: Input filters parameter.
            dealbreakers: Input dealbreakers parameter.

        Returns:
            bool: Response payload or result."""
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
    """In-memory filter pass for encrypted fields that have no blind indexes."""
    dealbreakers = set(filters.dealbreaker_fields or [])
    return [c for c in candidates if _check_candidate_match(c, filters, dealbreakers)]


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
    normal_pics = [pic for pic in images[1:] if pic] if len(images) > 1 else []

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
            .select("id")
            .execute()
        )
        if not response.data:
            raise ValueError("Profile not found")
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
        # Resolve the first image as profile_pic if a separate
        # ordered_images list exists.
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
