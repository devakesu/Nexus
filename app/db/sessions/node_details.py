"""Discovery node detail fetching, payload construction, and privacy boundaries."""

import asyncio
import logging
from typing import Any, cast

from postgrest.exceptions import APIError

from app.core.config import DiscoveryTab
from app.core.security.crypto import DecryptFailedError
from app.db.client import DatabaseAccessError, ProfileDecodeError, supabase_client
from app.db.discovery import coerce_float, coerce_score, get_cached_active_block_ids
from app.db.profiles import (
    decrypt_profile_record,
    sanitize_decrypted_profile,
    sign_profile_media,
)
from app.db.sessions.auth_sessions import _verify_session_not_expired

logger = logging.getLogger(__name__)


def _build_node_detail_payload(
    row: dict[str, Any],
    profile: dict[str, Any],
    cid: str,
    session_id: str,
    viewer_id: str,
    candidate_id: str,
    connection: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Build hydrated orbit node detail payload with media signatures."""
    try:
        hydrated_profile = decrypt_profile_record(profile)
        hydrated_profile = sanitize_decrypted_profile(hydrated_profile)
        hydrated_profile = sign_profile_media(hydrated_profile)
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

    grade_val = row.get("music_match_grade")
    music_match_grade = int(grade_val) if grade_val is not None else None

    if connection is None:
        from app.db.spotify import get_connection

        connection = get_connection(viewer_id)
    viewer_spotify_connected = (
        connection is not None and not connection.get("disconnected_at")
    )
    candidate_spotify_connected = bool(row.get("candidate_spotify_connected", False))

    payload: dict[str, Any] = {
        "id": str(hydrated_profile.get("id") or cid),
        "name": hydrated_profile.get("name"),
        "age": hydrated_profile.get("age"),
        "bio": hydrated_profile.get("bio"),
        "campus_branch": hydrated_profile.get("campus_branch"),
        "campus_year": hydrated_profile.get("campus_year"),
        "campus_name": hydrated_profile.get("campus_name"),
        "role_at": hydrated_profile.get("role_at"),
        "profile_pic": hydrated_profile.get("profile_pic"),
        "normal_pics": hydrated_profile.get("normal_pics") or [],
        "display_gender": hydrated_profile.get("display_gender"),
        "display_sexuality": hydrated_profile.get("display_sexuality"),
        "drinking": hydrated_profile.get("drinking"),
        "smoking": hydrated_profile.get("smoking"),
        "hometown": hydrated_profile.get("hometown"),
        "current_place": hydrated_profile.get("current_place"),
        "pronouns": hydrated_profile.get("pronouns"),
        "partner_values": hydrated_profile.get("partner_values"),
        "children_plans": hydrated_profile.get("children_plans"),
        "religious_beliefs": hydrated_profile.get("religious_beliefs"),
        "lifestyle": hydrated_profile.get("lifestyle"),
        "activities": hydrated_profile.get("activities") or [],
        "looking_for": hydrated_profile.get("looking_for") or [],
        "dating_for": hydrated_profile.get("dating_for") or [],
        "causes_supported": hydrated_profile.get("causes_supported") or [],
        "top_artists": hydrated_profile.get("top_artists") or [],
        "tech_skills": hydrated_profile.get("tech_skills") or [],
        "languages": hydrated_profile.get("languages") or [],
        "interests": hydrated_profile.get("interests") or {},
        "sub_interests": hydrated_profile.get("sub_interests") or {},
        "ai_vibe_tags": hydrated_profile.get("ai_vibe_tags") or [],
        "pets": hydrated_profile.get("pets") or [],
        "hidden_profile_fields": hydrated_profile.get("hidden_profile_fields") or [],
        "score": coerce_score(row.get("score")),
        "x": coerce_float(row.get("x")),
        "y": coerce_float(row.get("y")),
        "orbit_tier": int(coerce_float(row.get("orbit_tier"), 3.0)),
        "music_match_grade": music_match_grade,
        "viewer_spotify_connected": viewer_spotify_connected,
        "candidate_spotify_connected": candidate_spotify_connected,
    }
    return payload


async def _validate_discovery_node_data(
    row: dict[str, Any],
    viewer_id: str,
) -> tuple[DiscoveryTab, dict[str, Any], str] | None:
    """Validate node data against session expiry, deactivation, and block lists."""
    session_raw = row.get("discovery_sessions")
    session = (
        cast(dict[str, Any], session_raw) if isinstance(session_raw, dict) else None
    )
    if session is None:
        return None

    session_tab_raw = session.get("tab")
    if session_tab_raw not in {"Dating", "Friends", "Professional"}:
        return None

    if not _verify_session_not_expired(session):
        return None

    profile_raw = row.get("profiles")
    profile = (
        cast(dict[str, Any], profile_raw) if isinstance(profile_raw, dict) else None
    )
    if profile is None:
        return None

    if profile.get("is_deactivated") is True:
        return None

    hard_excluded = await get_cached_active_block_ids(viewer_id)
    cid = str(cast(object, profile.get("id") or row.get("candidate_id") or ""))
    if not cid or cid in hard_excluded:
        return None

    return cast(DiscoveryTab, session_tab_raw), profile, cid


def _query_discovery_node_detail(
    session_id: str,
    viewer_id: str,
    candidate_id: str,
) -> Any:
    """Synchronous helper to execute discovery node detail PostgREST query."""
    try:
        return (
            supabase_client.table("discovery_session_items")
            .select(
                """
                candidate_id,
                score,
                x,
                y,
                orbit_tier,
                music_match_grade,
                candidate_spotify_connected,
                profiles:candidate_id (
                    id,
                    name,
                    age,
                    bio,
                    campus_branch,
                    campus_year,
                    campus_name,
                    role_at,
                    profile_pic,
                    normal_pics,
                    display_gender,
                    display_sexuality,
                    drinking,
                    smoking,
                    hometown,
                    current_place,
                    pronouns,
                    partner_values,
                    children_plans,
                    religious_beliefs,
                    lifestyle,
                    activities,
                    looking_for,
                    dating_for,
                    causes_supported,
                    top_artists,
                    tech_skills,
                    languages,
                    interests,
                    sub_interests,
                    ai_vibe_tags,
                    pets,
                    hidden_profile_fields,
                    is_deactivated
                ),
                discovery_sessions!inner (
                    id,
                    viewer_id,
                    tab,
                    expires_at,
                    viewer_spotify_connected
                )
                """,
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


async def fetch_discovery_node_detail(
    session_id: str,
    viewer_id: str,
    candidate_id: str,
) -> tuple[DiscoveryTab, dict[str, Any]] | None:
    """Return (session_tab, hydrated_profile_payload) for a clicked discovery node."""
    res = await asyncio.to_thread(
        _query_discovery_node_detail,
        session_id=session_id,
        viewer_id=viewer_id,
        candidate_id=candidate_id,
    )

    rows = cast(list[Any], res.data or [])
    row_raw = rows[0] if rows else None
    if not isinstance(row_raw, dict):
        return None
    row = cast(dict[str, Any], row_raw)

    validated = await _validate_discovery_node_data(row, viewer_id)
    if not validated:
        return None

    session_tab, profile, cid = validated

    from app.db.spotify import get_connection

    connection = await asyncio.to_thread(get_connection, viewer_id)

    payload = _build_node_detail_payload(
        row=row,
        profile=profile,
        cid=cid,
        session_id=session_id,
        viewer_id=viewer_id,
        candidate_id=candidate_id,
        connection=connection,
    )

    return session_tab, payload
