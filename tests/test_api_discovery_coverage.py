"""Comprehensive unit tests covering 100% of discovery endpoints, likes, status, well_known, legal, and dev_temp."""

from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request

from app.api.dev_temp import dev_decrypt_profile, verify_dev_user
from app.api.discovery._shared import _validate_conversation_membership
from app.api.discovery.endpoints import (
    _coarsen_total_nodes,
    _node_to_out,
    _validate_discovery_action,
    _validate_forward_session,
    get_discovery_node_detail,
    get_discovery_orbit,
    get_discovery_viewport,
    handle_discovery_action,
)
from app.api.discovery.likes import (
    _parse_matched_at,
    _verify_peer_access_and_infer_tab,
    get_likes_inbox,
    get_matches,
    get_peer_profile,
    mark_likes_as_seen,
    record_like_back_action,
    record_match_action,
)
from app.api.legal import (
    _field_or,
    _placeholder_banner,
    legal_privacy_page,
    legal_terms_page,
    render_legal_page,
)
from app.api.status import health_check
from app.api.well_known import apple_app_site_association, assetlinks
from app.core.security.crypto import DecryptFailedError
from app.db.client import DatabaseAccessError, ProfileDecodeError
from app.models import (
    DiscoveryActionRequest,
    DiscoveryRequest,
    DiscoveryViewportRequest,
    LikeActionRequest,
    MarkLikesSeenRequest,
    MatchActionRequest,
    OrbitNodeDetailRequest,
    PeerProfileRequest,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
SESSION_ID = "11111111-1111-1111-1111-111111111111"
MATCH_ID = "22222222-2222-2222-2222-222222222222"
CONV_ID = "33333333-3333-3333-3333-333333333333"


def make_mock_request() -> Request:
    return Request({"type": "http", "headers": [], "query_string": b"", "path": "/"})


# ==========================================
# 1. DISCOVERY SHARED & VALIDATION TESTS
# ==========================================

async def test_validate_conversation_membership():
    # 1. No conversation_id -> no-op
    await _validate_conversation_membership(USER_1, USER_2, None)

    # 2. Conversation not found -> 404
    with patch("app.db.chat.fetch_conversation_participants", return_value=None):
        with pytest.raises(HTTPException) as exc_404:
            await _validate_conversation_membership(USER_1, USER_2, CONV_ID)
        assert exc_404.value.status_code == 404

    # 3. Caller not participant -> 403
    with patch("app.db.chat.fetch_conversation_participants", return_value={"user_a_id": USER_2, "user_b_id": USER_3}):
        with pytest.raises(HTTPException) as exc_403:
            await _validate_conversation_membership(USER_1, USER_2, CONV_ID)
        assert exc_403.value.status_code == 403

    # 4. Target not participant -> 400
    with patch("app.db.chat.fetch_conversation_participants", return_value={"user_a_id": USER_1, "user_b_id": USER_3}):
        with pytest.raises(HTTPException) as exc_400:
            await _validate_conversation_membership(USER_1, USER_2, CONV_ID)
        assert exc_400.value.status_code == 400

    # 5. Success
    with patch("app.db.chat.fetch_conversation_participants", return_value={"user_a_id": USER_1, "user_b_id": USER_2}):
        await _validate_conversation_membership(USER_1, USER_2, CONV_ID)


async def test_validate_forward_session():
    now = datetime.now(timezone.utc)
    # 1. Active session details found
    with patch("app.db.sessions.get_candidate_session_details", return_value={"expires_at": now + timedelta(hours=1)}):
        await _validate_forward_session(USER_1, USER_2, "Dating")

    # 2. No session details found -> 400
    with patch("app.db.sessions.get_candidate_session_details", return_value=None):
        with pytest.raises(HTTPException) as exc_no_sess:
            await _validate_forward_session(USER_1, USER_2, "Dating")
        assert exc_no_sess.value.status_code == 400

    # 3. Expired session -> 410
    with patch("app.db.sessions.get_candidate_session_details", return_value={"expires_at": now - timedelta(hours=1)}):
        with pytest.raises(HTTPException) as exc_exp:
            await _validate_forward_session(USER_1, USER_2, "Dating")
        assert exc_exp.value.status_code == 410


async def test_validate_discovery_action():
    # 1. Action on self -> 400
    self_payload = DiscoveryActionRequest(target_id=USER_1, action="like", tab="Dating")
    with pytest.raises(HTTPException) as exc_self:
        await _validate_discovery_action(USER_1, self_payload)
    assert exc_self.value.status_code == 400

    # 2. Unsupported reversal -> 400
    # Note: DiscoveryActionRequest validator restricts Literal, test via bypass
    mock_payload = MagicMock(target_id=USER_2, action="uninvalid", conversation_id=None, tab="Dating")
    with patch("app.api.discovery.endpoints._validate_conversation_membership"):
        with pytest.raises(HTTPException) as exc_rev:
            await _validate_discovery_action(USER_1, mock_payload)
        assert exc_rev.value.status_code == 400

    # 3. Reversal without active action -> 400
    unpass_payload = DiscoveryActionRequest(target_id=USER_2, action="unpass", tab="Dating")
    with patch("app.api.discovery.endpoints._validate_conversation_membership"), \
         patch("app.db.discovery.has_active_discovery_action", return_value=False):
        with pytest.raises(HTTPException) as exc_no_act:
            await _validate_discovery_action(USER_1, unpass_payload)
        assert exc_no_act.value.status_code == 400

    # 4. Reversal with active action -> success
    with patch("app.api.discovery.endpoints._validate_conversation_membership"), \
         patch("app.db.discovery.has_active_discovery_action", return_value=True):
        await _validate_discovery_action(USER_1, unpass_payload)

    # 5. Block action with inactive profile -> 400
    block_payload = DiscoveryActionRequest(target_id=USER_2, action="block")
    with patch("app.api.discovery.endpoints._validate_conversation_membership"), \
         patch("app.db.profiles.is_active_profile", return_value=False):
        with pytest.raises(HTTPException) as exc_inact:
            await _validate_discovery_action(USER_1, block_payload)
        assert exc_inact.value.status_code == 400

    # 6. Block action with active profile -> success
    with patch("app.api.discovery.endpoints._validate_conversation_membership"), \
         patch("app.db.profiles.is_active_profile", return_value=True):
        await _validate_discovery_action(USER_1, block_payload)


# ==========================================
# 2. DISCOVERY ENDPOINTS TESTS
# ==========================================

def test_coarsen_total_nodes_and_node_to_out():
    assert _coarsen_total_nodes(0) == 0
    assert _coarsen_total_nodes(5) == 0
    assert _coarsen_total_nodes(8) == 10
    assert _coarsen_total_nodes(20) == 25
    assert _coarsen_total_nodes(45) == 50
    assert _coarsen_total_nodes(80) == 100
    assert _coarsen_total_nodes(200) == 250
    assert _coarsen_total_nodes(400) == 500
    assert _coarsen_total_nodes(650) == 600

    node = {"id": USER_1, "name": "Alice", "profile_pic": "a.jpg", "x": 1.5, "y": -2.0, "orbit_tier": 1}
    out = _node_to_out(node)
    assert out.id == USER_1
    assert out.name == "Alice"
    assert out.x == 1.5
    assert out.y == -2.0


async def test_get_discovery_orbit_and_viewport():
    req = make_mock_request()
    now = datetime.now(timezone.utc)
    disc_payload = DiscoveryRequest(tab="Dating")

    # 1. New discovery session
    with patch("app.api.discovery.endpoints.get_or_validate_session", return_value=(SESSION_ID, now)), \
         patch("app.api.discovery.endpoints.create_new_discovery_session", return_value=(SESSION_ID, now)), \
         patch("app.api.discovery.endpoints.fetch_spatial_viewport", return_value=(
             [{"id": USER_2, "name": "Bob", "profile_pic": "b.jpg", "x": 0.5, "y": 0.5, "orbit_tier": 1}],
             15,
         )):
        res = await get_discovery_orbit(request=req, payload=disc_payload, user_id=USER_1)
        assert res.session_id == SESSION_ID
        assert len(res.nodes) == 1
        assert res.total_nodes == 25

    # 2. Existing session ID supplied
    disc_payload_with_session = DiscoveryRequest(tab="Dating", session_id=SESSION_ID)
    with patch("app.api.discovery.endpoints.get_or_validate_session", return_value=(SESSION_ID, now)), \
         patch("app.api.discovery.endpoints.fetch_spatial_viewport", return_value=([], 0)):
        res_existing = await get_discovery_orbit(request=req, payload=disc_payload_with_session, user_id=USER_1)
        assert res_existing.session_id == SESSION_ID

    # 3. Discovery orbit errors
    with patch("app.api.discovery.endpoints.create_new_discovery_session", side_effect=ProfileDecodeError("bad")):
        with pytest.raises(HTTPException) as exc_pde:
            await get_discovery_orbit(request=req, payload=disc_payload, user_id=USER_1)
        assert exc_pde.value.status_code == 500

    with patch("app.api.discovery.endpoints.create_new_discovery_session", side_effect=DatabaseAccessError("db fail")):
        with pytest.raises(HTTPException) as exc_db:
            await get_discovery_orbit(request=req, payload=disc_payload, user_id=USER_1)
        assert exc_db.value.status_code == 503

    with patch("app.api.discovery.endpoints.create_new_discovery_session", side_effect=RuntimeError("unexpected")):
        with pytest.raises(HTTPException) as exc_unexp:
            await get_discovery_orbit(request=req, payload=disc_payload, user_id=USER_1)
        assert exc_unexp.value.status_code == 500

    # 4. Viewport query success
    vp_payload = DiscoveryViewportRequest(session_id=SESSION_ID, center_x=0.0, center_y=0.0, radius=100.0, tab="Dating")
    with patch("app.api.discovery.endpoints.get_or_validate_session", return_value=(SESSION_ID, now)), \
         patch("app.api.discovery.endpoints.fetch_spatial_viewport", return_value=(
             [{"id": USER_2, "name": "Bob", "profile_pic": "b.jpg", "x": 0.5, "y": 0.5, "orbit_tier": 1}],
             1,
         )):
        res_vp = await get_discovery_viewport(request=req, payload=vp_payload, user_id=USER_1)
        assert len(res_vp.nodes) == 1

    # 5. Viewport query errors
    with patch("app.api.discovery.endpoints.get_or_validate_session", side_effect=ProfileDecodeError("bad")):
        with pytest.raises(HTTPException) as exc_vp_pde:
            await get_discovery_viewport(request=req, payload=vp_payload, user_id=USER_1)
        assert exc_vp_pde.value.status_code == 500

    with patch("app.api.discovery.endpoints.get_or_validate_session", side_effect=DatabaseAccessError("db fail")):
        with pytest.raises(HTTPException) as exc_vp_db:
            await get_discovery_viewport(request=req, payload=vp_payload, user_id=USER_1)
        assert exc_vp_db.value.status_code == 503

    with patch("app.api.discovery.endpoints.get_or_validate_session", side_effect=RuntimeError("fail")):
        with pytest.raises(HTTPException) as exc_vp_err:
            await get_discovery_viewport(request=req, payload=vp_payload, user_id=USER_1)
        assert exc_vp_err.value.status_code == 500


async def test_get_orbit_node_detail_and_actions():
    req = make_mock_request()
    detail_payload = OrbitNodeDetailRequest(
        session_id=SESSION_ID,
        candidate_id=USER_2,
    )

    # 1. Node detail success
    dating_detail = {
        "id": USER_2,
        "name": "Bob",
        "age": 25,
        "profile_pic": "bob.jpg",
        "bio": "Hello world",
        "height_cm": 180,
    }
    with patch("app.api.discovery.endpoints.fetch_discovery_node_detail", return_value=("Dating", dating_detail)):
        res_det = await get_discovery_node_detail(request=req, payload=detail_payload, user_id=USER_1)
        assert res_det.name == "Bob"

    # 2. Node detail not found -> 404
    with patch("app.api.discovery.endpoints.fetch_discovery_node_detail", return_value=None):
        with pytest.raises(HTTPException) as exc_404:
            await get_discovery_node_detail(request=req, payload=detail_payload, user_id=USER_1)
        assert exc_404.value.status_code == 404

    # 3. Node detail errors
    with patch("app.api.discovery.endpoints.fetch_discovery_node_detail", side_effect=ProfileDecodeError("bad json")):
        with pytest.raises(HTTPException) as exc_pde:
            await get_discovery_node_detail(request=req, payload=detail_payload, user_id=USER_1)
        assert exc_pde.value.status_code == 500

    with patch("app.api.discovery.endpoints.fetch_discovery_node_detail", side_effect=DecryptFailedError("bad key")):
        with pytest.raises(HTTPException) as exc_dfe:
            await get_discovery_node_detail(request=req, payload=detail_payload, user_id=USER_1)
        assert exc_dfe.value.status_code == 500

    with patch("app.api.discovery.endpoints.fetch_discovery_node_detail", side_effect=DatabaseAccessError("db fail")):
        with pytest.raises(HTTPException) as exc_db:
            await get_discovery_node_detail(request=req, payload=detail_payload, user_id=USER_1)
        assert exc_db.value.status_code == 503

    with patch("app.api.discovery.endpoints.fetch_discovery_node_detail", side_effect=RuntimeError("err")):
        with pytest.raises(HTTPException) as exc_err:
            await get_discovery_node_detail(request=req, payload=detail_payload, user_id=USER_1)
        assert exc_err.value.status_code == 500

    # 4. Discovery action: superlike
    action_superlike = DiscoveryActionRequest(target_id=USER_2, action="superlike", tab="Dating")
    with patch("app.api.discovery.endpoints._validate_discovery_action"), \
         patch("app.api.discovery.endpoints.record_discovery_action"), \
         patch("app.api.discovery.endpoints.send_like_notification"):
        res_super = await handle_discovery_action(request=req, payload=action_superlike, user_id=USER_1)
        assert res_super.success is True

    # 5. Discovery action: pass
    action_pass = DiscoveryActionRequest(target_id=USER_2, action="pass", tab="Dating")
    with patch("app.api.discovery.endpoints._validate_discovery_action"), \
         patch("app.api.discovery.endpoints.record_discovery_action"):
        res_p = await handle_discovery_action(request=req, payload=action_pass, user_id=USER_1)
        assert res_p.success is True

    # 6. Discovery action: block
    action_block = DiscoveryActionRequest(target_id=USER_2, action="block")
    with patch("app.api.discovery.endpoints._validate_discovery_action"), \
         patch("app.api.discovery.endpoints.record_discovery_action"), \
         patch("app.api.discovery.endpoints.invalidate_block_cache", new_callable=AsyncMock), \
         patch("app.api.discovery.endpoints.set_match_unmatched"), \
         patch("app.api.discovery.endpoints.close_conversation_for_match_action"):
        res_blk = await handle_discovery_action(request=req, payload=action_block, user_id=USER_1)
        assert res_blk.success is True

    # 7. Discovery action: unblock
    action_unblock = DiscoveryActionRequest(target_id=USER_2, action="unblock")
    with patch("app.api.discovery.endpoints._validate_discovery_action"), \
         patch("app.api.discovery.endpoints.record_discovery_action"), \
         patch("app.api.discovery.endpoints.invalidate_block_cache", new_callable=AsyncMock):
        res_unblk = await handle_discovery_action(request=req, payload=action_unblock, user_id=USER_1)
        assert res_unblk.success is True

    # 8. Discovery action errors
    with patch("app.api.discovery.endpoints._validate_discovery_action", side_effect=DatabaseAccessError("db fail")):
        with pytest.raises(HTTPException) as exc_act_db:
            await handle_discovery_action(request=req, payload=action_pass, user_id=USER_1)
        assert exc_act_db.value.status_code == 503

    with patch("app.api.discovery.endpoints._validate_discovery_action", side_effect=RuntimeError("err")):
        with pytest.raises(HTTPException) as exc_act_err:
            await handle_discovery_action(request=req, payload=action_pass, user_id=USER_1)
        assert exc_act_err.value.status_code == 500


# ==========================================
# 3. LIKES & MATCHES TESTS
# ==========================================

def test_parse_matched_at():
    now = datetime.now(timezone.utc)
    assert _parse_matched_at(now) == now
    assert isinstance(_parse_matched_at("2026-08-25T20:00:00Z"), datetime)


async def test_verify_peer_access_and_infer_tab():
    # 1. target == user_id -> 403
    with pytest.raises(HTTPException) as exc_self:
        await _verify_peer_access_and_infer_tab(USER_1, USER_1, "Dating")
    assert exc_self.value.status_code == 403

    # 2. Blocked by viewer or target -> 403
    with patch("app.api.discovery.likes.get_cached_active_block_ids", new_callable=AsyncMock, side_effect=[{USER_2}, set()]):
        with pytest.raises(HTTPException) as exc_blk:
            await _verify_peer_access_and_infer_tab(USER_2, USER_1, "Dating")
        assert exc_blk.value.status_code == 403

    # 3. Peer match found
    with patch("app.api.discovery.likes.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.discovery.likes._find_peer_like", new_callable=AsyncMock, return_value=None), \
         patch("app.api.discovery.likes._find_peer_match", new_callable=AsyncMock, return_value={"tab": "Friends"}):
        tab = await _verify_peer_access_and_infer_tab(USER_2, USER_1, "Dating")
        assert tab == "Friends"

    # 4. No like or match found -> 403
    with patch("app.api.discovery.likes.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.discovery.likes._find_peer_like", new_callable=AsyncMock, return_value=None), \
         patch("app.api.discovery.likes._find_peer_match", new_callable=AsyncMock, return_value=None):
        with pytest.raises(HTTPException) as exc_no_access:
            await _verify_peer_access_and_infer_tab(USER_2, USER_1, "Dating")
        assert exc_no_access.value.status_code == 403


async def test_likes_and_matches_endpoints():
    req = make_mock_request()
    now = datetime.now(timezone.utc)

    # 1. Get likes empty
    with patch("app.api.discovery.likes.fetch_likes_for_user", return_value=[]):
        res_empty = await get_likes_inbox(request=req, tab="Dating", user_id=USER_1)
        assert res_empty.likes == []
        assert res_empty.unseen_count == 0

    # 2. Get likes populated
    with patch("app.api.discovery.likes.fetch_likes_for_user", return_value=[
        {"actor_id": USER_2, "action": "superlike", "created_at": now, "seen_at": None}
    ]), patch("app.api.discovery.likes.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
       patch("app.api.discovery.likes.supabase_client.table") as mock_table:
        
        mock_profile_res = MagicMock()
        mock_profile_res.data = [{"id": USER_2, "name": "Bob", "age": 25, "profile_pic": "b.jpg"}]
        mock_query = MagicMock()
        mock_query.select.return_value.in_.return_value.eq.return_value.execute.return_value = mock_profile_res
        mock_table.return_value = mock_query

        res_likes = await get_likes_inbox(request=req, tab="Dating", user_id=USER_1)
        assert len(res_likes.likes) == 1
        assert res_likes.unseen_count == 1

    # 3. Get likes DatabaseAccessError -> 503
    with patch("app.api.discovery.likes.fetch_likes_for_user", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc_likes_db:
            await get_likes_inbox(request=req, tab="Dating", user_id=USER_1)
        assert exc_likes_db.value.status_code == 503

    # 4. Mark likes seen DatabaseAccessError -> 503
    seen_payload = MarkLikesSeenRequest(tab="Dating", mark_all=True)
    with patch("app.api.discovery.likes.mark_likes_seen", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc_seen_db:
            await mark_likes_as_seen(request=req, payload=seen_payload, user_id=USER_1)
        assert exc_seen_db.value.status_code == 503

    # 5. Record like back: revoke fails -> 400
    like_act = LikeActionRequest(target_id=USER_2, action="like", tab="Dating")
    with patch("app.api.discovery.likes._validate_conversation_membership"), \
         patch("app.api.discovery.likes.revoke_incoming_like", return_value=False):
        with pytest.raises(HTTPException) as exc_no_like:
            await record_like_back_action(request=req, payload=like_act, user_id=USER_1)
        assert exc_no_like.value.status_code == 400

    # 6. Record like back: action == block
    block_act = LikeActionRequest(target_id=USER_2, action="block")
    with patch("app.api.discovery.likes._validate_conversation_membership"), \
         patch("app.api.discovery.likes.revoke_incoming_like", return_value=True), \
         patch("app.api.discovery.likes.record_discovery_action"), \
         patch("app.api.discovery.likes.invalidate_block_cache", new_callable=AsyncMock), \
         patch("app.api.discovery.likes.set_match_unmatched"), \
         patch("app.api.discovery.likes.close_conversation_for_match_action"):
        res_blk = await record_like_back_action(request=req, payload=block_act, user_id=USER_1)
        assert res_blk.success is True

    # 7. Record like back: action == report
    report_act = LikeActionRequest(target_id=USER_2, action="report", reason="harassment")
    with patch("app.api.discovery.likes._validate_conversation_membership"), \
         patch("app.api.discovery.likes.record_user_report"), \
         patch("app.api.discovery.likes.invalidate_block_cache", new_callable=AsyncMock), \
         patch("app.api.discovery.likes.set_match_unmatched"), \
         patch("app.api.discovery.likes.close_conversation_for_match_action"):
        res_rep = await record_like_back_action(request=req, payload=report_act, user_id=USER_1)
        assert res_rep.success is True

    # 8. Record like back: exception triggers unrevoke
    with patch("app.api.discovery.likes._validate_conversation_membership"), \
         patch("app.api.discovery.likes.revoke_incoming_like", return_value=True), \
         patch("app.api.discovery.likes.record_discovery_action", side_effect=RuntimeError("boom")), \
         patch("app.api.discovery.likes.unrevoke_incoming_like") as mock_unrevoke:
        with pytest.raises(RuntimeError):
            await record_like_back_action(request=req, payload=like_act, user_id=USER_1)
        assert mock_unrevoke.called

    # 9. Get matches empty
    with patch("app.api.discovery.likes.fetch_matches_for_user", return_value=[]):
        res_matches_empty = await get_matches(request=req, tab="Dating", user_id=USER_1)
        assert res_matches_empty.matches == []

    # 10. Get matches DatabaseAccessError -> 503
    with patch("app.api.discovery.likes.fetch_matches_for_user", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc_m_db:
            await get_matches(request=req, tab="Dating", user_id=USER_1)
        assert exc_m_db.value.status_code == 503

    # 11. Record match action: report
    m_report_act = MatchActionRequest(target_id=USER_2, action="report", reason="harassment", conversation_id=CONV_ID)
    with patch("app.api.discovery.likes._validate_conversation_membership"), \
         patch("app.api.discovery.likes.set_match_unmatched"), \
         patch("app.api.discovery.likes.close_conversation_for_match_action"), \
         patch("app.api.discovery.likes.record_user_report"), \
         patch("app.api.discovery.likes.invalidate_block_cache", new_callable=AsyncMock):
        res_m_rep = await record_match_action(request=req, payload=m_report_act, user_id=USER_1)
        assert res_m_rep.success is True

    # 12. Record match action: block
    m_block_act = MatchActionRequest(target_id=USER_2, action="block")
    with patch("app.api.discovery.likes._validate_conversation_membership"), \
         patch("app.api.discovery.likes.set_match_unmatched"), \
         patch("app.api.discovery.likes.close_conversation_for_match_action"), \
         patch("app.api.discovery.likes.record_discovery_action"), \
         patch("app.api.discovery.likes.invalidate_block_cache", new_callable=AsyncMock):
        res_m_blk = await record_match_action(request=req, payload=m_block_act, user_id=USER_1)
        assert res_m_blk.success is True

    # 13. Record match action: DatabaseAccessError -> 503
    with patch("app.api.discovery.likes._validate_conversation_membership", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc_ma_db:
            await record_match_action(request=req, payload=m_block_act, user_id=USER_1)
        assert exc_ma_db.value.status_code == 503

    # 14. Get peer profile: Spotify connected on both sides -> music affinities
    peer_payload = PeerProfileRequest(target_id=USER_2, tab="Dating")
    dating_detail = {
        "id": USER_2,
        "name": "Bob",
        "age": 25,
        "profile_pic": "bob.jpg",
        "bio": "Hello",
        "height_cm": 180,
    }
    with patch("app.api.discovery.likes.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.discovery.likes.fetch_active_like_action", return_value={"tab": "Dating"}), \
         patch("app.api.discovery.likes.fetch_peer_profile_by_id", return_value=dating_detail), \
         patch("app.db.spotify.get_connection", return_value={"id": "spot-conn", "disconnected_at": None}), \
         patch("app.db.profiles.fetch_music_affinities", return_value=(["Radiohead"], ["rock"])), \
         patch("Nexus_Engine.engine.calculate_playlist_match_grade", return_value=88):
        res_spotify_peer = await get_peer_profile(request=req, payload=peer_payload, user_id=USER_1)
        assert res_spotify_peer.music_match_grade is not None
        assert res_spotify_peer.music_match_grade > 0

    # 15. Get peer profile: not found -> 404
    with patch("app.api.discovery.likes.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.discovery.likes.fetch_active_like_action", return_value={"tab": "Dating"}), \
         patch("app.api.discovery.likes.fetch_peer_profile_by_id", return_value=None):
        with pytest.raises(HTTPException) as exc_peer_404:
            await get_peer_profile(request=req, payload=peer_payload, user_id=USER_1)
        assert exc_peer_404.value.status_code == 404

    # 16. Get peer profile: ProfileDecodeError -> 500
    with patch("app.api.discovery.likes.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.discovery.likes.fetch_active_like_action", return_value={"tab": "Dating"}), \
         patch("app.api.discovery.likes.fetch_peer_profile_by_id", side_effect=ProfileDecodeError("bad")):
        with pytest.raises(HTTPException) as exc_peer_pde:
            await get_peer_profile(request=req, payload=peer_payload, user_id=USER_1)
        assert exc_peer_pde.value.status_code == 500

    # 17. Get peer profile: DatabaseAccessError -> 503
    with patch("app.api.discovery.likes.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set()), \
         patch("app.api.discovery.likes.fetch_active_like_action", return_value={"tab": "Dating"}), \
         patch("app.api.discovery.likes.fetch_peer_profile_by_id", side_effect=DatabaseAccessError("fail")):
        with pytest.raises(HTTPException) as exc_peer_db:
            await get_peer_profile(request=req, payload=peer_payload, user_id=USER_1)
        assert exc_peer_db.value.status_code == 503


# ==========================================
# 4. STATUS & WELL-KNOWN & LEGAL TESTS
# ==========================================

def test_status_and_well_known():
    req = make_mock_request()

    # Health check
    assert health_check(req) == {"status": "healthy"}

    # Apple App Site Association
    with patch("app.api.well_known.settings.apple_team_id", "ABC123XYZ"):
        resp = apple_app_site_association(req)
        assert resp.status_code == 200
        assert b"com.devakesu.apps.nexus" in resp.body

    with patch("app.api.well_known.settings.apple_team_id", ""):
        resp_empty = apple_app_site_association(req)
        assert resp_empty.status_code == 200

    # Android Assetlinks
    with patch("app.api.well_known.settings.android_sha256_fingerprint", "AA:BB:CC:DD"):
        resp_al = assetlinks(req)
        assert resp_al.status_code == 200
        assert b"AA:BB:CC:DD" in resp_al.body

    with patch("app.api.well_known.settings.android_sha256_fingerprint", ""):
        resp_al_empty = assetlinks(req)
        assert resp_al_empty.status_code == 200


def test_legal_templates_and_pages():
    req = make_mock_request()

    assert _field_or("Mumbai", "default") == "Mumbai"
    assert "placeholder" in _field_or(None, "placeholder")

    assert _placeholder_banner([]) == ""
    assert "Before publish" in _placeholder_banner(["missing field"])

    html = render_legal_page(is_embed=True)
    assert len(html) > 0

    resp_terms = legal_terms_page(req, embed=False)
    assert resp_terms.status_code == 200

    resp_priv = legal_privacy_page(req)
    assert resp_priv.status_code == 302
    assert resp_priv.headers["location"] == "/legal#privacy"


# ==========================================
# 5. DEV TEMP INSPECTION TESTS
# ==========================================

def test_dev_temp_endpoints():
    # 1. verify_dev_user with dev_allowed_email unset
    with patch("app.api.dev_temp.settings.dev_allowed_email", ""):
        with pytest.raises(HTTPException) as exc_403:
            verify_dev_user("Bearer test-token")
        assert exc_403.value.status_code == 403

    # 2. verify_dev_user unauthorized
    with patch("app.api.dev_temp.settings.dev_allowed_email", "dev@example.com"):
        with pytest.raises(HTTPException) as exc_401:
            verify_dev_user(None)
        assert exc_401.value.status_code == 401

    # 3. verify_dev_user mismatch
    with patch("app.api.dev_temp.settings.dev_allowed_email", "dev@example.com"), \
         patch("app.db.users.get_supabase_user_from_jwt", return_value={"id": USER_1, "email": "other@example.com"}):
        with pytest.raises(HTTPException) as exc_mismatch:
            verify_dev_user("Bearer test-token")
        assert exc_mismatch.value.status_code == 403

    # 4. verify_dev_user success
    with patch("app.api.dev_temp.settings.dev_allowed_email", "dev@example.com"), \
         patch("app.db.users.get_supabase_user_from_jwt", return_value={"id": USER_1, "email": "dev@example.com"}):
        uid = verify_dev_user("Bearer test-token")
        assert uid == USER_1

    # 5. dev_decrypt_profile not found
    with patch("app.api.dev_temp.supabase_client.table") as mock_tbl:
        mock_res = MagicMock()
        mock_res.data = None
        mock_tbl.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_res
        with pytest.raises(HTTPException) as exc_nf:
            dev_decrypt_profile("00000000-0000-0000-0000-000000000404")
        assert exc_nf.value.status_code == 404

    # 6. dev_decrypt_profile success
    with patch("app.api.dev_temp.supabase_client.table") as mock_tbl, \
         patch("app.api.dev_temp.decrypt_profile_record", return_value={"id": USER_1, "name": "Alice"}):
        mock_res = MagicMock()
        mock_res.data = {"id": USER_1, "name_enc": "b64"}
        mock_tbl.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_res
        prof = dev_decrypt_profile(USER_1)
        assert prof["name"] == "Alice"
