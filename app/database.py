import hashlib
import json
import logging
import math
import random
from datetime import datetime, timedelta, timezone
from typing import Any, Sequence, cast

from postgrest.exceptions import APIError
from supabase import Client, create_client

from app.cache import get_cached_active_block_ids
from app.config import DiscoveryTab, settings
from app.crypto import DecryptFailedError, compute_blind_index, decrypt_pii
from app.models import DiscoveryFilters, OrbitNodeDetailDatingOut, OrbitNodeDetailFriendsOut, OrbitNodeDetailProfessionalOut

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
    return _coerce_float(value, 0.0)

def _coerce_float(value: Any, default: float = 0.0) -> float:
    if isinstance(value, bool):
        return default
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return default
    return default

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
    
    
def _collect_blocked_counterparty_ids(rows: object, viewer_id: str) -> set[str]:
    excluded: set[str] = set()

    if not isinstance(rows, list):
        return excluded

    for row in rows:
        if not isinstance(row, dict):
            continue

        actor_id = row.get("actor_id")
        target_id = row.get("target_id")

        if actor_id == viewer_id and target_id:
            excluded.add(str(target_id))
        elif target_id == viewer_id and actor_id:
            excluded.add(str(actor_id))

    return excluded

def build_tab_aware_orbit_node_detail(
    session_tab: DiscoveryTab,
    payload: dict[str, Any],
) -> OrbitNodeDetailDatingOut | OrbitNodeDetailFriendsOut | OrbitNodeDetailProfessionalOut:
    base = {
        "id": str(payload.get("id") or ""),
        "name": payload.get("name"),
        "age": payload.get("age"),
        "branch": payload.get("branch"),
        "year": payload.get("year"),
        "role": payload.get("role"),
        "score": _coerce_score(payload.get("score")),
        "x": _coerce_float(payload.get("x")),
        "y": _coerce_float(payload.get("y")),
        "orbit_tier": int(_coerce_float(payload.get("orbit_tier"), 3.0)),
    }

    if session_tab == "Dating":
        return OrbitNodeDetailDatingOut(
            **base,
            tab="Dating",
            display_gender=payload.get("display_gender"),
            display_sexuality=payload.get("display_sexuality"),
            drinking=payload.get("drinking"),
            smoking=payload.get("smoking"),
            hometown=payload.get("hometown"),
            partner_values=payload.get("partner_values"),
            children_plans=payload.get("children_plans"),
            religious_beliefs=payload.get("religious_beliefs"),
            lifestyle=payload.get("lifestyle"),
            activities=payload.get("activities") or [],
            looking_for=payload.get("looking_for") or [],
            causes_supported=payload.get("causes_supported") or [],
            top_artists=payload.get("top_artists") or [],
            tech_skills=payload.get("tech_skills") or [],
            languages=payload.get("languages") or [],
            ai_vibe_tags=payload.get("ai_vibe_tags") or [],
            pets=payload.get("pets") or [],
        )

    if session_tab == "Friends":
        return OrbitNodeDetailFriendsOut(
            **base,
            tab="Friends",
            hometown=payload.get("hometown"),
            lifestyle=payload.get("lifestyle"),
            activities=payload.get("activities") or [],
            causes_supported=payload.get("causes_supported") or [],
            top_artists=payload.get("top_artists") or [],
            languages=payload.get("languages") or [],
            ai_vibe_tags=payload.get("ai_vibe_tags") or [],
            pets=payload.get("pets") or [],
        )

    if session_tab == "Professional":
        return OrbitNodeDetailProfessionalOut(
            **base,
            tab="Professional",
            hometown=payload.get("hometown"),
            tech_skills=payload.get("tech_skills") or [],
            languages=payload.get("languages") or [],
            causes_supported=payload.get("causes_supported") or [],
        )

    raise ValueError(f"Unsupported session_tab: {session_tab}")


def _collect_target_ids(rows: object) -> set[str]:
    target_ids: set[str] = set()

    if not isinstance(rows, list):
        return target_ids

    for row in rows:
        if isinstance(row, dict) and row.get("target_id"):
            target_ids.add(str(row["target_id"]))

    return target_ids


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
        block_res = (
            supabase_client.table("profile_discovery_actions")
            .select("actor_id, target_id")
            .eq("action", "block")
            .is_("revoked_at", "null")
            .or_(f"actor_id.eq.{viewer_id},target_id.eq.{viewer_id}")
            .execute()
        )
        excluded.update(_collect_blocked_counterparty_ids(block_res.data, viewer_id))

        hide_res = (
            supabase_client.table("profile_discovery_actions")
            .select("target_id")
            .eq("actor_id", viewer_id)
            .eq("tab", active_tab)
            .eq("action", "hide")
            .is_("revoked_at", "null")
            .execute()
        )
        excluded.update(_collect_target_ids(hide_res.data))

        engagement_res = (
            supabase_client.table("profile_discovery_actions")
            .select("target_id")
            .eq("actor_id", viewer_id)
            .eq("tab", active_tab)
            .in_("action", ["like", "superlike"])
            .is_("revoked_at", "null")
            .execute()
        )
        excluded.update(_collect_target_ids(engagement_res.data))

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
        excluded.update(_collect_target_ids(pass_res.data))

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
    try:
        res = (
            supabase_client.table("profile_discovery_actions")
            .select("actor_id, target_id")
            .eq("action", "block")
            .is_("revoked_at", "null")
            .or_(f"actor_id.eq.{viewer_id},target_id.eq.{viewer_id}")
            .execute()
        )

        return _collect_blocked_counterparty_ids(res.data, viewer_id)

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
    

def get_discovery_session_for_viewer(
    session_id: str,
    viewer_id: str,
) -> dict[str, Any] | None:
    try:
        res = (
            supabase_client.table("discovery_sessions")
            .select("*")
            .eq("id", session_id)
            .eq("viewer_id", viewer_id)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch discovery session for viewer",
            extra={"viewer_id": viewer_id, "session_id": session_id},
        )
        raise DatabaseAccessError("Failed to fetch discovery session for viewer") from e
    except Exception as e:
        logger.exception(
            "Unexpected discovery session-for-viewer lookup failure",
            extra={"viewer_id": viewer_id, "session_id": session_id},
        )
        raise DatabaseAccessError("Unexpected discovery session-for-viewer lookup failure") from e

    rows = res.data if isinstance(res.data, list) else []
    row = rows[0] if rows else None
    return row if isinstance(row, dict) else None


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

def _assign_orbit_positions(
    viewer_id: str,
    active_tab: DiscoveryTab,
    ranked_items: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    candidate_ids: list[str] = []
    for item in ranked_items:
        if not isinstance(item, dict):
            continue
        profile_raw = item.get("profile")
        profile = profile_raw if isinstance(profile_raw, dict) else {}
        candidate_id = profile.get("id")
        if candidate_id:
            candidate_ids.append(str(candidate_id))

    seed_input = f"{viewer_id}:{active_tab}:{'|'.join(sorted(candidate_ids))}"
    seed_value = int(hashlib.sha256(seed_input.encode("utf-8")).hexdigest()[:16], 16)
    rng = random.Random(seed_value)

    tier_buckets: dict[int, list[dict[str, Any]]] = {
        0: [],
        1: [],
        2: [],
        3: [],
    }

    for item in ranked_items:
        score = _coerce_score(item.get("score"))
        if score >= 85.0:
            tier_buckets[0].append(item)
        elif score >= 70.0:
            tier_buckets[1].append(item)
        elif score >= 50.0:
            tier_buckets[2].append(item)
        else:
            tier_buckets[3].append(item)

    tier_radii = {
        0: 120.0,
        1: 240.0,
        2: 380.0,
        3: 560.0,
    }

    positioned_items: list[dict[str, Any]] = []

    for tier, items in tier_buckets.items():
        if not items:
            continue

        radius = tier_radii[tier]
        count = len(items)
        base_angle_offset = rng.uniform(0.0, 2.0 * math.pi)

        for index, item in enumerate(items):
            angle = base_angle_offset + ((2.0 * math.pi * index) / count)
            radial_jitter = rng.uniform(-18.0, 18.0)
            angular_jitter = rng.uniform(-0.08, 0.08)

            final_radius = max(40.0, radius + radial_jitter)
            final_angle = angle + angular_jitter

            positioned_items.append(
                {
                    **item,
                    "_orbit_tier": tier,
                    "_x": round(final_radius * math.cos(final_angle), 2),
                    "_y": round(final_radius * math.sin(final_angle), 2),
                }
            )

    positioned_items.sort(
        key=lambda item: (
            -_coerce_score(item.get("score")),
            str(
                item.get("profile", {}).get("id")
                if isinstance(item.get("profile"), dict)
                else ""
            ),
        )
    )

    return positioned_items

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

    positioned_items = _assign_orbit_positions(
        viewer_id=viewer_id,
        active_tab=active_tab,
        ranked_items=ranked_items,
    )

    items_payload: list[dict[str, Any]] = []
    for position, item in enumerate(positioned_items):
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
                "x": _coerce_float(item.get("_x")),
                "y": _coerce_float(item.get("_y")),
                "orbit_tier": int(_coerce_float(item.get("_orbit_tier"), 3.0)),
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
) -> dict[str, Any] | None:
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
    
async def fetch_spatial_viewport(
    session_id: str,
    viewer_id: str,
    center_x: float,
    center_y: float,
    radius: float,
) -> tuple[list[dict[str, Any]], int]:
    """
    Fetch session items within a circular viewport using bounding box
    pre-filter then distance check.
    """
    x_min, x_max = center_x - radius, center_x + radius
    y_min, y_max = center_y - radius, center_y + radius

    try:
        res = (
            supabase_client.table("discovery_session_items")
            .select(
                """
                candidate_id,
                score,
                x,
                y,
                orbit_tier,
                profiles:candidate_id (
                    id,
                    name,
                    is_deactivated
                )
                """
            )
            .eq("session_id", session_id)
            .gte("x", x_min).lte("x", x_max)
            .gte("y", y_min).lte("y", y_max)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch spatial viewport",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "center_x": center_x,
                "center_y": center_y,
                "radius": radius,
            },
        )
        raise DatabaseAccessError("Failed to fetch spatial viewport") from e
    except Exception as e:
        logger.exception(
            "Unexpected spatial viewport fetch failure",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "center_x": center_x,
                "center_y": center_y,
                "radius": radius,
            },
        )
        raise DatabaseAccessError("Unexpected spatial viewport fetch failure") from e

    rows = res.data if isinstance(res.data, list) else []
    result: list[dict[str, Any]] = []

    hard_excluded = await get_cached_active_block_ids(viewer_id)
    radius_sq = radius ** 2

    for row in rows:
        if not isinstance(row, dict):
            continue
        
        profile_raw = row.get("profiles")
        profile = profile_raw if isinstance(profile_raw, dict) else None
        if profile is None:
            continue

        cid = str(profile.get("id") or row.get("candidate_id") or "")
        if not cid or cid in hard_excluded:
            continue
        
        if profile.get("is_deactivated") is True:
            continue

        x = _coerce_float(row.get("x"))
        y = _coerce_float(row.get("y"))
        dx = x - center_x
        dy = y - center_y

        if dx * dx + dy * dy <= radius_sq:
            result.append(
                {
                    "id": cid,
                    "name": profile.get("name"),
                    "score": _coerce_score(row.get("score")),
                    "orbit_tier": int(_coerce_float(row.get("orbit_tier"), 3.0)),
                    "x": x,
                    "y": y,
                }
            )
            
    result.sort(
        key=lambda row: (
            row.get("orbit_tier", 99),
            -_coerce_score(row.get("score")),
            str(row.get("id") or ""),
        )
    )
    
    try:
        count_res = (
            supabase_client.table("discovery_session_items")
            .select("candidate_id", count="exact")  # type: ignore[arg-type]
            .eq("session_id", session_id)
            .limit(1)
            .execute()
        )
        total_count = int(count_res.count or 0)
    except APIError as e:
        logger.exception(
            "Failed to count spatial session items",
            extra={"session_id": session_id, "viewer_id": viewer_id},
        )
        raise DatabaseAccessError("Failed to count spatial session items") from e
    except Exception as e:
        logger.exception(
            "Unexpected spatial session count failure",
            extra={"session_id": session_id, "viewer_id": viewer_id},
        )
        raise DatabaseAccessError("Unexpected spatial session count failure") from e

    return result, total_count

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
    
    
async def fetch_discovery_node_detail(
    session_id: str,
    viewer_id: str,
    candidate_id: str,
) -> tuple[DiscoveryTab, dict[str, Any]] | None:
    """
    Return (session_tab, hydrated_profile_payload) for a clicked discovery node.
    Returns None when the session/item/profile is not available to the viewer.
    """
    try:
        res = (
            supabase_client.table("discovery_session_items")
            .select(
                """
                candidate_id,
                score,
                x,
                y,
                orbit_tier,
                profiles:candidate_id (
                    id,
                    name,
                    age,
                    branch,
                    year,
                    role,
                    display_gender,
                    display_sexuality,
                    drinking,
                    smoking,
                    hometown,
                    partner_values,
                    children_plans,
                    religious_beliefs,
                    lifestyle,
                    activities,
                    looking_for,
                    causes_supported,
                    top_artists,
                    tech_skills,
                    languages,
                    ai_vibe_tags,
                    pets,
                    is_deactivated
                ),
                discovery_sessions!inner (
                    id,
                    viewer_id,
                    tab,
                    expires_at
                )
                """
            )
            .eq("session_id", session_id)
            .eq("candidate_id", candidate_id)
            .eq("discovery_sessions.viewer_id", viewer_id)
            .limit(1)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch discovery node detail",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "candidate_id": candidate_id,
            },
        )
        raise DatabaseAccessError("Failed to fetch discovery node detail") from e
    except Exception as e:
        logger.exception(
            "Unexpected discovery node detail failure",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "candidate_id": candidate_id,
            },
        )
        raise DatabaseAccessError("Unexpected discovery node detail failure") from e

    rows = res.data if isinstance(res.data, list) else []
    row = rows[0] if rows else None
    if not isinstance(row, dict):
        return None

    session_raw = row.get("discovery_sessions")
    session = session_raw if isinstance(session_raw, dict) else None
    if session is None:
        return None

    session_tab_raw = session.get("tab")
    if session_tab_raw not in {"Dating", "Friends", "Professional"}:
        return None

    session_tab = cast(DiscoveryTab, session_tab_raw)

    expires_at_raw = session.get("expires_at")
    if isinstance(expires_at_raw, str):
        expires_at = datetime.fromisoformat(expires_at_raw.replace("Z", "+00:00"))
    elif isinstance(expires_at_raw, datetime):
        expires_at = expires_at_raw
    else:
        return None

    if expires_at <= utcnow():
        return None

    profile_raw = row.get("profiles")
    profile = profile_raw if isinstance(profile_raw, dict) else None
    if profile is None:
        return None

    if profile.get("is_deactivated") is True:
        return None

    hard_excluded = await get_cached_active_block_ids(viewer_id)
    cid = str(profile.get("id") or row.get("candidate_id") or "")
    if not cid or cid in hard_excluded:
        return None

    try:
        hydrated_profile = _decrypt_profile_record(profile)
    except (DecryptFailedError, ProfileDecodeError):
        logger.exception(
            "Failed to decrypt orbit node detail profile",
            extra={
                "session_id": session_id,
                "viewer_id": viewer_id,
                "candidate_id": candidate_id,
            },
        )
        raise

    payload = {
        "id": str(hydrated_profile.get("id") or cid),
        "name": hydrated_profile.get("name"),
        "age": hydrated_profile.get("age"),
        "branch": hydrated_profile.get("branch"),
        "year": hydrated_profile.get("year"),
        "role": hydrated_profile.get("role"),
        "display_gender": hydrated_profile.get("display_gender"),
        "display_sexuality": hydrated_profile.get("display_sexuality"),
        "drinking": hydrated_profile.get("drinking"),
        "smoking": hydrated_profile.get("smoking"),
        "hometown": hydrated_profile.get("hometown"),
        "partner_values": hydrated_profile.get("partner_values"),
        "children_plans": hydrated_profile.get("children_plans"),
        "religious_beliefs": hydrated_profile.get("religious_beliefs"),
        "lifestyle": hydrated_profile.get("lifestyle"),
        "activities": hydrated_profile.get("activities") or [],
        "looking_for": hydrated_profile.get("looking_for") or [],
        "causes_supported": hydrated_profile.get("causes_supported") or [],
        "top_artists": hydrated_profile.get("top_artists") or [],
        "tech_skills": hydrated_profile.get("tech_skills") or [],
        "languages": hydrated_profile.get("languages") or [],
        "ai_vibe_tags": hydrated_profile.get("ai_vibe_tags") or [],
        "pets": hydrated_profile.get("pets") or [],
        "score": _coerce_score(row.get("score")),
        "x": _coerce_float(row.get("x")),
        "y": _coerce_float(row.get("y")),
        "orbit_tier": int(_coerce_float(row.get("orbit_tier"), 3.0)),
    }

    return session_tab, payload