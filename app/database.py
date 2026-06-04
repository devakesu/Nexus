import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Any, Optional, Sequence

from postgrest.exceptions import APIError
from supabase import Client, create_client

from app.config import DiscoveryTab, settings
from app.crypto import DecryptFailedError, compute_blind_index, decrypt_pii
from app.models import DiscoveryFilters

logger = logging.getLogger(__name__)

# High-privilege backend client. Service role access must be treated as trusted
# backend-only code because it can bypass RLS depending on how requests are made.
supabase_client: Client = create_client(
    settings.supabase_url,
    settings.supabase_service_role_key,
)


class ProfileDecodeError(Exception):
    """Raised when an encrypted profile field cannot be decoded into its expected shape."""


class DatabaseAccessError(Exception):
    """Raised when a database operation fails unexpectedly."""


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _coerce_score(value: Any) -> float:
    if isinstance(value, bool):
        return 1.0 if value else 0.0
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return 0.0
    return 0.0

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


def _expand_target_buckets(buckets: Sequence[str] | list[Any] | None) -> list[str]:
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


def fetch_active_discovery_excluded_ids(
    viewer_id: str,
    active_tab: DiscoveryTab,
) -> set[str]:
    """
    Return candidate ids that must be excluded from discovery for this viewer.

    Active exclusions:
    - block: both directions, global
    - hide: actor -> target for this tab
    - pass: actor -> target for this tab while not expired
    - optionally like/superlike depending on product policy
    """
    excluded: set[str] = set()
    now_iso = utcnow().isoformat()

    try:
        # Global blocks in either direction
        block_res = (
            supabase_client.table("profile_discovery_actions")
            .select("actor_id, target_id")
            .eq("action", "block")
            .is_("revoked_at", "null")
            .or_(f"actor_id.eq.{viewer_id},target_id.eq.{viewer_id}")
            .execute()
        )

        for row in block_res.data or []:
            if not isinstance(row, dict):
                continue
            actor_id = row.get("actor_id")
            target_id = row.get("target_id")

            if actor_id == viewer_id and target_id:
                excluded.add(str(target_id))
            elif target_id == viewer_id and actor_id:
                excluded.add(str(actor_id))

        # Tab-scoped hides
        hide_res = (
            supabase_client.table("profile_discovery_actions")
            .select("target_id")
            .eq("actor_id", viewer_id)
            .eq("tab", active_tab)
            .eq("action", "hide")
            .is_("revoked_at", "null")
            .execute()
        )

        for row in hide_res.data or []:
            if isinstance(row, dict) and row.get("target_id"):
                excluded.add(str(row["target_id"]))

        engagement_res = (
            supabase_client.table("profile_discovery_actions")
            .select("target_id")
            .eq("actor_id", viewer_id)
            .eq("tab", active_tab)
            .in_("action", ["like", "superlike"])
            .is_("revoked_at", "null")
            .execute()
        )

        for row in engagement_res.data or []:
            if isinstance(row, dict) and row.get("target_id"):
                excluded.add(str(row["target_id"]))
                
        # Active passes only
        pass_res = (
            supabase_client.table("profile_discovery_actions")
            .select("target_id")
            .eq("actor_id", viewer_id)
            .eq("tab", active_tab)
            .eq("action", "pass")
            .is_("revoked_at", "null")
            .gt("expires_at", now_iso)
            .execute()
        )

        for row in pass_res.data or []:
            if isinstance(row, dict) and row.get("target_id"):
                excluded.add(str(row["target_id"]))

        return excluded

    except APIError as e:
        logger.exception(
            "Failed to fetch active discovery exclusions",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError("Failed to fetch active discovery exclusions") from e
    except Exception as e:
        logger.exception(
            "Unexpected active discovery exclusion failure",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError("Unexpected active discovery exclusion failure") from e
    

def fetch_active_block_ids(viewer_id: str) -> set[str]:
    """
    Return ids of users with an active block in either direction.
    Used for lightweight re-check at snapshot page read time.
    """
    excluded: set[str] = set()

    try:
        res = (
            supabase_client.table("profile_discovery_actions")
            .select("actor_id, target_id")
            .eq("action", "block")
            .is_("revoked_at", "null")
            .or_(f"actor_id.eq.{viewer_id},target_id.eq.{viewer_id}")
            .execute()
        )

        for row in res.data or []:
            if not isinstance(row, dict):
                continue
            actor_id = row.get("actor_id")
            target_id = row.get("target_id")
            if actor_id == viewer_id and target_id:
                excluded.add(str(target_id))
            elif target_id == viewer_id and actor_id:
                excluded.add(str(actor_id))

        return excluded

    except APIError as e:
        logger.exception(
            "Failed to fetch active block ids",
            extra={"viewer_id": viewer_id},
        )
        raise DatabaseAccessError("Failed to fetch active block ids") from e
    except Exception as e:
        logger.exception(
            "Unexpected block id fetch failure",
            extra={"viewer_id": viewer_id},
        )
        raise DatabaseAccessError("Unexpected block id fetch failure") from e
    
    
def fetch_stage_1_candidates(
    viewer_id: str,
    active_tab: DiscoveryTab,
    filters: DiscoveryFilters,
    candidate_limit: int = 200,
) -> tuple[Optional[dict[str, Any]], list[dict[str, Any]]]:
    
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


def create_discovery_session(
    viewer_id: str,
    active_tab: DiscoveryTab,
    filters: dict[str, Any],
    ranked_items: list[dict[str, Any]],
    expires_in_minutes: int = 15,
) -> str:
    expires_at = utcnow() + timedelta(minutes=expires_in_minutes)

    try:
        session_res = (
            supabase_client.table("discovery_sessions")
            .insert(
                {
                    "viewer_id": viewer_id,
                    "tab": active_tab,
                    "filters": filters or {},
                    "expires_at": expires_at.isoformat(),
                    "last_cursor_position": 0,
                }
            )
            .select("id")
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to create discovery session",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError("Failed to create discovery session") from e
    except Exception as e:
        logger.exception(
            "Unexpected discovery session creation failure",
            extra={"viewer_id": viewer_id, "active_tab": active_tab},
        )
        raise DatabaseAccessError("Unexpected discovery session creation failure") from e

    session_rows = session_res.data if isinstance(session_res.data, list) else []
    session_row = session_rows[0] if session_rows else None

    if not isinstance(session_row, dict) or "id" not in session_row:
        raise DatabaseAccessError("Discovery session creation returned malformed data")

    session_id = str(session_row["id"])

    items_payload: list[dict[str, Any]] = []
    for position, item in enumerate(ranked_items):
        if not isinstance(item, dict):
            continue

        profile_raw = item.get("profile")
        profile = profile_raw if isinstance(profile_raw, dict) else {}
        candidate_id = profile.get("id")
        if not candidate_id:
            continue

        items_payload.append(
            {
                "session_id": session_id,
                "position": position,
                "candidate_id": str(candidate_id),
                "score": _coerce_score(item.get("score")),
            }
        )

    if not items_payload:
        return session_id

    try:
        (
            supabase_client.table("discovery_session_items")
            .insert(items_payload)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to insert discovery session items",
            extra={
                "viewer_id": viewer_id,
                "active_tab": active_tab,
                "session_id": session_id,
                "item_count": len(items_payload),
            },
        )
        raise DatabaseAccessError("Failed to insert discovery session items") from e
    except Exception as e:
        logger.exception(
            "Unexpected discovery session item insert failure",
            extra={
                "viewer_id": viewer_id,
                "active_tab": active_tab,
                "session_id": session_id,
                "item_count": len(items_payload),
            },
        )
        raise DatabaseAccessError("Unexpected discovery session item insert failure") from e

    return session_id


def get_discovery_session(
    session_id: str,
    viewer_id: str,
    active_tab: DiscoveryTab,
) -> Optional[dict[str, Any]]:
    try:
        res = (
            supabase_client.table("discovery_sessions")
            .select("*")
            .eq("id", session_id)
            .eq("viewer_id", viewer_id)
            .eq("tab", active_tab)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch discovery session",
            extra={"viewer_id": viewer_id, "active_tab": active_tab, "session_id": session_id},
        )
        raise DatabaseAccessError("Failed to fetch discovery session") from e
    except Exception as e:
        logger.exception(
            "Unexpected discovery session lookup failure",
            extra={"viewer_id": viewer_id, "active_tab": active_tab, "session_id": session_id},
        )
        raise DatabaseAccessError("Unexpected discovery session lookup failure") from e

    rows = res.data if isinstance(res.data, list) else []
    row = rows[0] if rows else None
    return row if isinstance(row, dict) else None
    
    
def fetch_discovery_session_page(
    session_id: str,
    viewer_id: str,
    start_position: int,
    limit: int,
) -> tuple[list[dict[str, Any]], int]:
    try:
        count_res = (
            supabase_client.table("discovery_session_items")
            .select("position")
            .eq("session_id", session_id)
            .order("position", desc=False)
            .execute()
        )
        count_rows = count_res.data if isinstance(count_res.data, list) else []
        total_count = len(count_rows)
    except APIError as e:
        logger.exception(
            "Failed to count discovery session items",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to count discovery session items") from e
    except Exception as e:
        logger.exception(
            "Unexpected discovery session count failure",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Unexpected discovery session count failure") from e

    page_rows: list[dict[str, Any]] = []
    hard_excluded_ids = fetch_active_block_ids(viewer_id)

    next_position = start_position
    chunk_size = max(limit * 2, 20)

    while len(page_rows) < limit and next_position < total_count:
        try:
            res = (
                supabase_client.table("discovery_session_items")
                .select(
                    """
                    position,
                    score,
                    profiles:candidate_id (
                        id,
                        name,
                        branch,
                        year,
                        display_gender,
                        display_sexuality,
                        role,
                        is_deactivated
                    )
                    """
                )
                .eq("session_id", session_id)
                .gte("position", next_position)
                .order("position", desc=False)
                .limit(chunk_size)
                .execute()
            )
        except APIError as e:
            logger.exception(
                "Failed to fetch discovery session page chunk",
                extra={
                    "session_id": session_id,
                    "start_position": start_position,
                    "next_position": next_position,
                    "limit": limit,
                    "chunk_size": chunk_size,
                },
            )
            raise DatabaseAccessError("Failed to fetch discovery session page") from e
        except Exception as e:
            logger.exception(
                "Unexpected discovery session page chunk fetch failure",
                extra={
                    "session_id": session_id,
                    "start_position": start_position,
                    "next_position": next_position,
                    "limit": limit,
                    "chunk_size": chunk_size,
                },
            )
            raise DatabaseAccessError("Unexpected discovery session page fetch failure") from e

        rows = res.data if isinstance(res.data, list) else []
        if not rows:
            break

        max_position_seen: Optional[int] = None

        for row in rows:
            if not isinstance(row, dict):
                continue

            row_position = row.get("position")
            if isinstance(row_position, int):
                max_position_seen = row_position if max_position_seen is None else max(max_position_seen, row_position)

            profile_raw = row.get("profiles")
            profile = profile_raw if isinstance(profile_raw, dict) else None
            if profile is None:
                continue

            try:
                hydrated_profile = _decrypt_profile_record(profile)
                candidate_id = hydrated_profile.get("id")

                if hydrated_profile.get("is_deactivated") is True:
                    continue
                if not candidate_id:
                    continue
                if str(candidate_id) in hard_excluded_ids:
                    continue
            except (DecryptFailedError, ProfileDecodeError):
                logger.exception(
                    "Failed to decrypt profile within discovery session page",
                    extra={"session_id": session_id, "candidate_id": profile.get("id")},
                )
                raise

            page_rows.append(
                {
                    "position": row.get("position"),
                    "score": _coerce_score(row.get("score")),
                    "id": hydrated_profile.get("id"),
                    "name": hydrated_profile.get("name"),
                    "branch": hydrated_profile.get("branch"),
                    "year": hydrated_profile.get("year"),
                    "display_gender": hydrated_profile.get("display_gender"),
                    "display_sexuality": hydrated_profile.get("display_sexuality"),
                    "role": hydrated_profile.get("role"),
                }
            )

            if len(page_rows) >= limit:
                break

        if len(page_rows) >= limit:
            break

        if max_position_seen is None:
            break

        next_position = max_position_seen + 1

    return page_rows, total_count


def touch_discovery_session_cursor(
    session_id: str,
    viewer_id: str,
    next_position: int,
) -> None:
    """
    Persist the latest emitted cursor position for observability or resumability.
    """
    try:
        (
            supabase_client.table("discovery_sessions")
            .update({"last_cursor_position": next_position})
            .eq("id", session_id)
            .eq("viewer_id", viewer_id)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to update discovery session cursor",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "next_position": next_position,
            },
        )
        raise DatabaseAccessError("Failed to update discovery session cursor") from e
    except Exception as e:
        logger.exception(
            "Unexpected discovery session cursor update failure",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "next_position": next_position,
            },
        )
        raise DatabaseAccessError("Unexpected discovery session cursor update failure") from e


def delete_expired_discovery_sessions() -> int:
    """
    Delete expired discovery sessions. Session items cascade automatically.
    """
    try:
        res = (
            supabase_client.table("discovery_sessions")
            .delete()
            .lte("expires_at", utcnow().isoformat())
            .execute()
        )
        deleted_rows = res.data if isinstance(res.data, list) else []
        return len(deleted_rows)
    except APIError as e:
        logger.exception("Failed to delete expired discovery sessions")
        raise DatabaseAccessError("Failed to delete expired discovery sessions") from e
    except Exception as e:
        logger.exception("Unexpected expired discovery session cleanup failure")
        raise DatabaseAccessError("Unexpected expired discovery session cleanup failure") from e