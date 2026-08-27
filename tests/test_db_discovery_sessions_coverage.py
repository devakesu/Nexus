"""Test coverage suite for DB Discovery and Sessions layers.

Covers:
- app/db/discovery/exclusions.py
- app/db/discovery/matches.py
- app/db/discovery/orbit.py
- app/db/sessions/auth_sessions.py
- app/db/sessions/node_details.py
- app/db/sessions/viewport.py
"""

from __future__ import annotations

import json
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.core.security.crypto import encrypt_to_hex
from app.db.discovery.exclusions import (
    fetch_active_block_ids,
    fetch_active_discovery_excluded_ids,
    fetch_expired_pass_candidates,
    fetch_likes_for_user,
    get_cached_active_block_ids,
    has_active_discovery_action,
    invalidate_block_cache,
    mark_likes_seen,
    record_discovery_action,
    record_user_report,
)
from app.db.discovery.matches import (
    fetch_matches_for_user,
    record_match,
    record_mutual_pass,
    set_match_unmatched,
)
from app.db.discovery.orbit import (
    DeterministicRNG,
    assign_orbit_positions,
    build_tab_aware_orbit_node_detail,
    coerce_float,
    coerce_score,
    quantize_music_match_grade,
    quantize_score,
)
from app.db.sessions.auth_sessions import (
    create_discovery_session,
    delete_expired_discovery_sessions,
    get_candidate_session_details,
    get_discovery_session,
    get_discovery_session_by_id,
    invalidate_viewer_discovery_sessions,
    is_candidate_in_active_session,
    prune_excess_viewer_discovery_sessions,
)
from app.db.sessions.node_details import fetch_discovery_node_detail
from app.db.sessions.viewport import fetch_spatial_viewport

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
SESS_1 = "00000000-0000-0000-0000-000000000099"
MATCH_1 = "00000000-0000-0000-0000-000000000022"


# ==============================================================================
# 1. DISCOVERY EXCLUSIONS & ACTIONS TESTS
# ==============================================================================

async def test_discovery_exclusions_and_blocks():
    now = datetime.now(timezone.utc)
    mock_table = MagicMock()

    # 1. get_cached_active_block_ids
    with patch("app.db.discovery.exclusions.redis_client.get", new_callable=AsyncMock, return_value=json.dumps([USER_2])):
        blocks = await get_cached_active_block_ids(USER_1)
        assert USER_2 in blocks

    # cache miss -> fetch from DB
    with patch("app.db.discovery.exclusions.redis_client.get", new_callable=AsyncMock, return_value=None), \
         patch("app.db.discovery.exclusions.redis_client.set", new_callable=AsyncMock), \
         patch("app.db.discovery.exclusions.fetch_active_block_ids", return_value={USER_3}):
        blocks2 = await get_cached_active_block_ids(USER_1)
        assert USER_3 in blocks2

    # 2. fetch_active_block_ids
    mock_table.select.return_value.eq.return_value.is_.return_value.or_.return_value.execute.return_value = MagicMock(
        data=[{"actor_id": USER_1, "target_id": USER_2}, {"actor_id": USER_3, "target_id": USER_1}],
    )
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_table):
        b_ids = fetch_active_block_ids(USER_1)
        assert USER_2 in b_ids
        assert USER_3 in b_ids

    # 3. fetch_active_discovery_excluded_ids
    mock_table.select.return_value.is_.return_value.or_.return_value.execute.return_value = MagicMock(
        data=[
            {"actor_id": USER_1, "target_id": USER_2, "action": "block", "tab": "Dating"},
            {"actor_id": USER_1, "target_id": USER_3, "action": "like", "tab": "Dating"},
            {"actor_id": USER_1, "target_id": "other_4", "action": "pass", "tab": "Dating", "expires_at": (now + timedelta(days=5)).isoformat()},
        ],
    )
    mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(
        data=[{"liker_id": USER_1, "liked_back_id": "matched_user"}],
    )
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_table):
        excluded = fetch_active_discovery_excluded_ids(USER_1, "Dating")
        assert USER_2 in excluded
        assert USER_3 in excluded
        assert "other_4" in excluded
        assert "matched_user" in excluded

    # 4. has_active_discovery_action & record_discovery_action
    mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.is_.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": "act1"}],
    )
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_table):
        assert has_active_discovery_action(USER_1, USER_2, "like", "Dating") is True

    mock_table.insert.return_value.execute.return_value = MagicMock(data=[{"id": "act1"}])
    mock_table.update.return_value.eq.return_value.eq.return_value.eq.return_value.is_.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": "act1"}])
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_table):
        record_discovery_action(USER_1, USER_2, "pass", "Dating")
        record_discovery_action(USER_1, USER_2, "unlike", "Dating")

    # 5. record_user_report & invalidate_block_cache
    mock_table.insert.return_value.select.return_value.execute.return_value = MagicMock(data=[{"id": "rep1"}])
    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[{"id": "blk1"}])
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_table):
        record_user_report(USER_1, USER_2, reason="spam", reason_detail="bot behavior", tab="Dating")

    with patch("app.db.discovery.exclusions.redis_client.delete", new_callable=AsyncMock), \
         patch("app.db.sessions.auth_sessions.invalidate_viewer_discovery_sessions"):
        await invalidate_block_cache(USER_1, USER_2)

    # 6. fetch_expired_pass_candidates & fetch_likes_for_user & mark_likes_seen
    mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.is_.return_value.not_.is_.return_value.execute.return_value = MagicMock(
        data=[{"target_id": USER_2, "expires_at": (now - timedelta(days=2)).isoformat()}],
    )
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_table):
        expired = fetch_expired_pass_candidates(USER_1, "Dating")
        assert USER_2 in expired

    mock_table.select.return_value.eq.return_value.eq.return_value.in_.return_value.is_.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"actor_id": USER_2, "action": "like", "created_at": now.isoformat()}],
    )
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_table):
        likes = fetch_likes_for_user(USER_1, "Dating")
        assert len(likes) == 1

    mock_table.update.return_value.eq.return_value.in_.return_value.in_.return_value.is_.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.discovery.exclusions.supabase_client.table", return_value=mock_table):
        mark_likes_seen(USER_1, [USER_2], "Dating")


# ==============================================================================
# 2. DISCOVERY MATCHES TESTS
# ==============================================================================

def test_discovery_matches_crud():
    now = datetime.now(timezone.utc)
    mock_table = MagicMock()

    # 1. record_match
    # existing match
    mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": MATCH_1}],
    )
    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table):
        m_id = record_match(USER_1, USER_2, "Dating")
        assert m_id == MATCH_1

    # new match
    mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.limit.return_value.execute.return_value = MagicMock(data=[])
    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[{"id": MATCH_1}])
    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table):
        m_id2 = record_match(USER_1, USER_2, "Dating")
        assert m_id2 == MATCH_1

    # 2. fetch_matches_for_user
    mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.order.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[
            {"id": MATCH_1, "liker_id": USER_1, "liked_back_id": USER_2, "created_at": now.isoformat()},
            {"id": "match2", "liker_id": USER_3, "liked_back_id": USER_1, "created_at": now.isoformat()},
        ],
    )
    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table):
        user_matches = fetch_matches_for_user(USER_1, "Dating")
        assert len(user_matches) == 2
        assert user_matches[0]["matched_user_id"] == USER_2
        assert user_matches[1]["matched_user_id"] == USER_3

    # 3. record_mutual_pass & set_match_unmatched & fetch_active_match_between
    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[{"id": "mp1"}])
    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table):
        record_mutual_pass(USER_1, USER_2, "Dating")

    mock_table.update.return_value.or_.return_value.is_.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": MATCH_1}])
    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table):
        set_match_unmatched(USER_1, USER_2, tab="Dating")

    mock_table.select.return_value.or_.return_value.is_.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": MATCH_1, "tab": "Dating", "liker_id": USER_1, "liked_back_id": USER_2}],
    )
    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table):
        from app.db.discovery.matches import fetch_active_match_between
        am = fetch_active_match_between(USER_1, USER_2)
        assert am is not None
        assert am["id"] == MATCH_1


# ==============================================================================
# 3. DISCOVERY ORBIT ALGORITHMS & POSITIONING TESTS
# ==============================================================================

def test_orbit_algorithms_and_positioning():
    # 1. DeterministicRNG
    rng = DeterministicRNG(12345)
    f1 = rng._next()
    f2 = rng.uniform(5.0, 10.0)
    assert 0.0 <= f1 < 1.0
    assert 5.0 <= f2 < 10.0

    # 2. Score coercions & quantization
    assert coerce_score(True) == 1.0
    assert coerce_score(False) == 0.0
    assert coerce_score("0.75") == 0.75
    assert coerce_float("12.34", 0.0) == 12.34
    assert coerce_float(None, 5.0) == 5.0

    assert quantize_score(0.0) == 0.0
    assert 0.0 <= quantize_score(0.85, session_id="sess1", candidate_id=USER_1) <= 1.0
    assert 10.0 <= quantize_score(85.0, session_id="sess1", candidate_id=USER_1) <= 100.0

    assert quantize_music_match_grade(None) is None
    assert quantize_music_match_grade("bad") is None
    assert quantize_music_match_grade(1) == 0
    assert quantize_music_match_grade(4) == 3
    assert quantize_music_match_grade(7) == 7
    assert quantize_music_match_grade(10) == 10

    # 3. assign_orbit_positions
    ranked = [
        {"profile": {"id": USER_2}, "score": 0.95},
        {"profile": {"id": USER_3}, "score": 0.50},
        {"profile": {"id": "c4"}, "score": 0.20},
    ]
    pos = assign_orbit_positions(USER_1, "Dating", ranked)
    assert len(pos) == 3
    assert "_x" in pos[0]
    assert "_y" in pos[0]
    assert "_orbit_tier" in pos[0]

    # 4. build_tab_aware_orbit_node_detail
    profile_data = {
        "id": USER_2,
        "name": "Bob",
        "age": 22,
        "bio": "Hello",
        "campus_branch": "CS",
        "campus_year": 4,
        "campus_name": "MIT",
        "dating_for": ["relationship"],
        "activities": ["coding"],
        "looking_for": ["friends"],
        "tech_skills": ["python"],
    }
    detail_dating = build_tab_aware_orbit_node_detail("Dating", profile_data)
    detail_friends = build_tab_aware_orbit_node_detail("Friends", profile_data)
    detail_prof = build_tab_aware_orbit_node_detail("Professional", profile_data)
    assert detail_dating is not None
    assert detail_friends is not None
    assert detail_prof is not None


# ==============================================================================
# 4. DISCOVERY SESSIONS & VIEWPORT TESTS
# ==============================================================================

async def test_auth_sessions_and_viewport():
    now = datetime.now(timezone.utc)
    mock_table = MagicMock()

    # 1. prune_excess_viewer_discovery_sessions & delete_expired_discovery_sessions
    mock_table.select.return_value.eq.return_value.gt.return_value.order.return_value.execute.return_value = MagicMock(
        data=[{"id": f"s{i}"} for i in range(10)],
    )
    mock_table.delete.return_value.in_.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table):
        prune_excess_viewer_discovery_sessions(USER_1, max_active=5)

    mock_table.delete.return_value.lt.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table):
        delete_expired_discovery_sessions()

    # 2. create_discovery_session
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data=SESS_1)
    with patch("app.db.sessions.auth_sessions.supabase_client.rpc", return_value=mock_rpc), \
         patch("app.db.sessions.auth_sessions.prune_excess_viewer_discovery_sessions"):
        sess_id, exp = create_discovery_session(
            viewer_id=USER_1,
            active_tab="Dating",
            filters={},
            ranked_items=[{"profile": {"id": USER_2}, "score": 0.9}],
            expires_in_minutes=60,
        )
        assert sess_id == SESS_1
        assert exp is not None

    # 3. get_discovery_session & get_discovery_session_by_id & is_candidate_in_active_session
    mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": SESS_1, "viewer_id": USER_1, "tab": "Dating", "expires_at": (now + timedelta(hours=1)).isoformat()},
    )
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table):
        ds = get_discovery_session(SESS_1, USER_1, "Dating")
        assert ds is not None
        assert ds["id"] == SESS_1

    mock_table.select.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": SESS_1, "viewer_id": USER_1, "active_tab": "Dating", "expires_at": (now + timedelta(hours=1)).isoformat()},
    )
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table):
        ds_id = get_discovery_session_by_id(SESS_1, USER_1)
        assert ds_id is not None

    mock_table.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": "item1"}],
    )
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table):
        assert is_candidate_in_active_session(SESS_1, USER_2) is True

    # 4. get_candidate_session_details & invalidate_viewer_discovery_sessions
    mock_table.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"session_id": SESS_1, "discovery_sessions": {"tab": "Dating", "expires_at": (now + timedelta(hours=1)).isoformat()}}],
    )
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table):
        cd = get_candidate_session_details(USER_1, USER_2)
        assert cd is not None
        assert cd["session_id"] == SESS_1

    mock_table.delete.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table):
        invalidate_viewer_discovery_sessions(USER_1)

    # 5. fetch_discovery_node_detail (app/db/sessions/node_details.py)
    mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[
            {
                "session_id": SESS_1,
                "candidate_id": USER_2,
                "score": 0.9,
                "orbit_tier": 1,
                "profiles": {
                    "id": USER_2,
                    "name": encrypt_to_hex("Bob"),
                    "is_deactivated": False,
                },
                "discovery_sessions": {
                    "viewer_id": USER_1,
                    "tab": "Dating",
                    "expires_at": (now + timedelta(hours=1)).isoformat(),
                },
            },
        ],
    )
    with patch("app.db.sessions.node_details.supabase_client.table", return_value=mock_table), \
         patch("app.db.sessions.node_details.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.db.spotify.get_connection", return_value=None):
        node_res = await fetch_discovery_node_detail(SESS_1, USER_1, USER_2)
        assert node_res is not None
        s_tab, node_detail = node_res
        assert s_tab == "Dating"
        assert node_detail["id"] == USER_2
        assert node_detail["id"] == USER_2

    # 6. fetch_spatial_viewport (app/db/sessions/viewport.py)
    mock_vp_row = {
        "candidate_id": USER_2,
        "score": 0.9,
        "orbit_tier": 1,
        "x": 0.1,
        "y": 0.2,
        "profiles": {
            "id": USER_2,
            "name": encrypt_to_hex("Bob"),
            "profile_pic": f"{USER_2}/pic.jpg",
            "is_deactivated": False,
        },
    }
    with patch("app.db.sessions.viewport._query_spatial_viewport", return_value=MagicMock(data=[mock_vp_row])), \
         patch("app.db.sessions.viewport.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.db.sessions.viewport._fetch_total_session_items_count", return_value=1), \
         patch("app.db.profiles.media.supabase_client.storage.from_"):
        vp_items, total_count = await fetch_spatial_viewport(
            session_id=SESS_1,
            viewer_id=USER_1,
            center_x=0.0,
            center_y=0.0,
            radius=1.0,
            include_total_count=True,
        )
        assert len(vp_items) == 1
        assert total_count == 1
        assert vp_items[0]["id"] == USER_2
