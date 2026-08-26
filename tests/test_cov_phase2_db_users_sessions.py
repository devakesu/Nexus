"""Phase 2 DB Coverage Expansion.

Targets:
- app/db/sessions/auth_sessions.py
- app/db/sessions/viewport.py
- app/db/sessions/node_details.py
- app/db/profiles/crud.py
- app/db/profiles/encryption.py
- app/db/profiles/media.py
- app/db/users/auth.py
- app/db/users/consent.py
- app/db/users/import_export.py
- app/db/users/profile.py
- app/db/feedback/feedback.py
- app/db/spotify.py
"""

from __future__ import annotations

import json
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.core.security.crypto import encrypt_to_hex

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
SESS_1 = "00000000-0000-0000-0000-000000000011"


# -----------------------------------------------------------------------------
# 1. DB SESSIONS: AUTH_SESSIONS, VIEWPORT, NODE_DETAILS
# -----------------------------------------------------------------------------
async def test_db_sessions_all_modules():
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

    mock_table = MagicMock()
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data=SESS_1)

    # 1. auth_sessions.py
    mock_table.insert.return_value.execute.return_value = MagicMock(data=[{"id": SESS_1, "viewer_id": USER_1}])
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table), \
         patch("app.db.sessions.auth_sessions.supabase_client.rpc", return_value=mock_rpc), \
         patch("app.db.sessions.auth_sessions.assign_orbit_positions", return_value=[{"profile": {"id": USER_2}, "score": 0.9}]):
        s_id, exp = create_discovery_session(USER_1, "Dating", {}, [{"candidate_id": USER_2}])
        assert s_id is not None
        assert exp is not None

    mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": SESS_1, "viewer_id": USER_1, "tab": "Dating"}
    )
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table):
        sess = get_discovery_session(SESS_1, USER_1, "Dating")
        assert sess is not None
        assert sess["id"] == SESS_1

    mock_table.select.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": SESS_1, "viewer_id": USER_1}
    )
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table):
        s_by_id = get_discovery_session_by_id(SESS_1, USER_1)
        assert s_by_id is not None

    cand_select_mock = MagicMock()
    exec_mock = MagicMock()
    exec_mock.data = [{"session_id": SESS_1, "discovery_sessions": {"tab": "Dating", "expires_at": "2026-08-26T18:00:00Z"}}]
    cand_select_mock.select.return_value.eq.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = exec_mock
    cand_select_mock.select.return_value.eq.return_value.eq.return_value.execute.return_value = exec_mock
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=cand_select_mock):
        assert is_candidate_in_active_session(USER_1, USER_2) is True
        details = get_candidate_session_details(USER_1, USER_2, "Dating")
        assert details is not None
        assert details["session_id"] == SESS_1

    mock_table.delete.return_value.lt.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_table):
        delete_expired_discovery_sessions()
        invalidate_viewer_discovery_sessions(USER_1)
        prune_excess_viewer_discovery_sessions(USER_1, max_active=5)

    # 2. node_details.py
    node_res = MagicMock()
    node_res.data = [{
        "candidate_id": USER_2,
        "score": 0.85,
        "x": 1.0,
        "y": 2.0,
        "orbit_tier": 1,
        "music_match_grade": 1,
        "candidate_spotify_connected": False,
        "discovery_sessions": {
            "id": SESS_1,
            "viewer_id": USER_1,
            "tab": "Dating",
            "expires_at": "2099-01-01T00:00:00Z",
            "viewer_spotify_connected": False,
        },
        "profiles": {
            "id": USER_2,
            "name": encrypt_to_hex("Bob", category="profile"),
            "bio": encrypt_to_hex("Hello", category="profile"),
            "normal_pics": encrypt_to_hex(json.dumps(["pic.jpg"]), category="profile"),
            "profile_pic": "pic.jpg",
            "interests": encrypt_to_hex(json.dumps({"tech": ["Python"]}), category="profile"),
            "is_deactivated": False,
        },
    }]
    mock_node_table = MagicMock()
    mock_node_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = node_res
    with patch("app.db.sessions.node_details.supabase_client.table", return_value=mock_node_table), \
         patch("app.db.sessions.node_details.get_cached_active_block_ids", AsyncMock(return_value=set())), \
         patch("app.db.sessions.node_details.sign_profile_media", return_value={"name": "Bob", "profile_pic": "https://signed.url"}):
        node_res_tuple = await fetch_discovery_node_detail(SESS_1, USER_1, USER_2)
        assert node_res_tuple is not None
        tab, node_dict = node_res_tuple
        assert tab == "Dating"
        assert node_dict["name"] == "Bob"

    # 3. viewport.py
    vp_res = MagicMock()
    vp_res.data = [{
        "candidate_id": USER_2,
        "score": 0.85,
        "x": 1.0,
        "y": 2.0,
        "orbit_tier": 1,
        "music_match_grade": 1,
        "candidate_spotify_connected": False,
        "profiles": {
            "id": USER_2,
            "name": encrypt_to_hex("Bob", category="profile"),
            "profile_pic": "pic.jpg",
        },
    }]
    mock_vp_table = MagicMock()
    mock_vp_table.select.return_value.eq.return_value.eq.return_value.gte.return_value.lte.return_value.gte.return_value.lte.return_value.execute.return_value = vp_res
    with patch("app.db.sessions.viewport.supabase_client.table", return_value=mock_vp_table), \
         patch("app.db.sessions.viewport.get_cached_active_block_ids", AsyncMock(return_value=set())), \
         patch("app.db.sessions.viewport.decrypt_profile_rows", return_value={USER_2: {"name": "Bob", "profile_pic": "https://signed.url"}}):
        vp_items, _ = await fetch_spatial_viewport(SESS_1, USER_1, 10.0, 10.0, 50.0, include_total_count=False)
        assert len(vp_items) == 1
        assert vp_items[0]["name"] == "Bob"


# -----------------------------------------------------------------------------
# 2. DB PROFILES: CRUD, ENCRYPTION, MEDIA
# -----------------------------------------------------------------------------
async def test_db_profiles_all_modules():
    from app.db.profiles.crud import (
        fetch_music_affinities,
        fetch_peer_profile_by_id,
        is_active_profile,
    )
    from app.db.profiles.encryption import (
        decrypt_profile_field,
        decrypt_profile_record,
        decrypt_profile_rows,
        sanitize_decrypted_profile,
    )
    from app.db.profiles.media import (
        sign_profile_media,
        sign_profile_media_bulk,
        update_profile_images_and_metadata,
    )

    mock_table = MagicMock()

    # 1. crud.py
    mock_table.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}]
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        assert is_active_profile(USER_1) is True

    mock_table.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"artist_affinity": encrypt_to_hex(json.dumps({"Queen": 0.9})), "genre_affinity": None}]
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        aff, _ = fetch_music_affinities(USER_1)
        assert aff is not None

    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={
            "id": USER_2,
            "name": encrypt_to_hex("Bob", category="profile"),
            "profile_pic": "pic.jpg",
            "is_deactivated": False,
        }
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table), \
         patch("app.db.profiles.crud.sign_profile_media", return_value={"id": USER_2, "name": "Bob"}):
        peer = fetch_peer_profile_by_id(USER_2)
        assert peer is not None

    # 2. encryption.py
    enc_val = encrypt_to_hex("Secret bio")
    row_dict = {"bio": enc_val, "age": 25}
    decrypt_profile_field(row_dict, "bio")
    assert row_dict["bio"] == "Secret bio"

    rec = {"bio": enc_val, "age": 25}
    dec_rec = decrypt_profile_record(rec)
    assert dec_rec["bio"] == "Secret bio"

    san = sanitize_decrypted_profile(dec_rec)
    assert san["bio"] == "Secret bio"

    dec_rows = decrypt_profile_rows([{"id": USER_1, "bio": enc_val}])
    assert USER_1 in dec_rows

    # 3. media.py
    mock_storage = MagicMock()
    mock_storage.create_signed_url.return_value = {"signedURL": "https://signed.url/pic.jpg"}
    mock_storage.create_signed_urls.return_value = [{"path": f"{USER_1}/pic.jpg", "signedURL": "https://signed.url/pic.jpg"}]
    with patch("app.db.profiles.media.supabase_client.storage.from_", return_value=mock_storage):
        signed_profile = sign_profile_media({"id": USER_1, "profile_pic": f"{USER_1}/pic.jpg", "normal_pics": []})
        assert signed_profile["profile_pic"] == "https://signed.url/pic.jpg"

        rows_to_sign = [{"id": USER_1, "profile_pic": f"{USER_1}/pic.jpg"}]
        sign_profile_media_bulk(rows_to_sign)
        assert rows_to_sign[0]["profile_pic"] == "https://signed.url/pic.jpg"

    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": USER_1}])
    with patch("app.db.profiles.media.supabase_client.table", return_value=mock_table):
        await update_profile_images_and_metadata(USER_1, [f"{USER_1}/pic.jpg"], ["tech", "music"])


# -----------------------------------------------------------------------------
# 3. DB USERS: AUTH, CONSENT, IMPORT/EXPORT, PROFILE
# -----------------------------------------------------------------------------
async def test_db_users_submodules():
    from app.db.users.auth import (
        fetch_public_user,
        find_user_id_by_phone,
        is_allowed_email,
        is_disposable_email,
        set_user_suspension,
        set_verified_mobile,
        upsert_public_user,
    )
    from app.db.users.consent import (
        update_community_guidelines_consent,
        update_safety_data_consent,
        update_special_category_consent,
        update_user_terms,
    )
    from app.db.users.import_export import (
        execute_import,
        generate_export_code,
    )
    from app.db.users.profile import (
        fetch_profile,
        upsert_profile_variant,
    )

    mock_table = MagicMock()

    # 1. auth.py
    assert is_disposable_email("user@0-mail.com") is True
    assert is_disposable_email("user@gmail.com") is False
    assert is_allowed_email("user@gmail.com") is True

    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1, "is_active": True}]
    )
    with patch("app.db.users.auth.supabase_client.table", return_value=mock_table):
        pub_u = fetch_public_user(USER_1)
        assert pub_u is not None
        assert pub_u["id"] == USER_1

    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}]
    )
    with patch("app.db.users.auth.supabase_client.table", return_value=mock_table):
        uid = find_user_id_by_phone("+1234567890")
        assert uid == USER_1

    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": USER_1}])
    with patch("app.db.users.auth.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.auth.invalidate_user_status_cache"):
        set_user_suspension(USER_1, True)
        set_verified_mobile(USER_1, "+1234567890")

    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[{"id": USER_1}])
    with patch("app.db.users.auth.supabase_client.table", return_value=mock_table):
        upsert_public_user(USER_1, "nexus")

    # 2. consent.py
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"accepted_terms_version": "1", "terms_accepted_at": "2026-01-01T00:00:00Z"}
    )
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"id": USER_1}])
    mock_table.insert.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.users.consent.supabase_client.table", return_value=mock_table):
        update_user_terms(USER_1, "1")
        update_special_category_consent(USER_1, "1", True)
        update_safety_data_consent(USER_1, "1", True)
        update_community_guidelines_consent(USER_1, "1", True)

    # 3. import_export.py
    mock_redis = AsyncMock()
    mock_redis.delete.return_value = True
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"import_sync_code": "ABC123"}
    )
    with patch("app.db.users.import_export.redis_client", mock_redis), \
         patch("app.db.users.import_export.supabase_client.table", return_value=mock_table):
        code, exp = await generate_export_code(USER_1)
        assert len(code) == 6
        assert exp is not None

    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{
            "id": USER_2,
            "import_sync_expires_at": "2026-09-01T00:00:00Z",
            "has_imported_data": False,
            "display_gender": encrypt_to_hex("Non-binary", category="profile"),
        }]
    )
    with patch("app.db.users.import_export.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.import_export.fetch_public_user", return_value={"id": USER_2, "app_variant": "campus"}):
        copied = execute_import(USER_1, "ABC123", "nexus")
        assert copied is not None

    # 4. profile.py
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": USER_1, "name": encrypt_to_hex("Alice", category="profile")}
    )
    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[{"id": USER_1}])
    with patch("app.db.users.profile.supabase_client.table", return_value=mock_table):
        prof = fetch_profile(USER_1)
        assert prof is not None
        prof_res, _ = upsert_profile_variant(USER_1, "Alice", "CS", 2026, 22)
        assert prof_res is not None


# -----------------------------------------------------------------------------
# 4. DB FEEDBACK & SPOTIFY
# -----------------------------------------------------------------------------
def test_db_feedback_and_spotify():
    from app.db.feedback.feedback import (
        add_ticket_comment,
        close_ticket,
        fetch_ticket_report,
        fetch_user_tickets,
        record_feedback_submission,
    )
    from app.db.spotify import (
        disconnect,
        get_connection,
        get_decrypted_refresh_token,
        mark_sync_result,
        persist_artist_signals,
        upsert_connection,
    )

    mock_table = MagicMock()

    # 1. feedback.py
    mock_table.insert.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": "ticket_1", "subject": encrypt_to_hex("Bug", category="contact")}]
    )
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        t = record_feedback_submission(USER_1, "bug", "Bug subject", "Bug message")
        assert t is not None

    mock_table.select.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"id": "ticket_1", "subject": encrypt_to_hex("Bug", category="contact"), "message": encrypt_to_hex("Details", category="contact")}
    )
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        rep = fetch_ticket_report(USER_1, "ticket_1")
        assert rep is not None

    mock_table.select.return_value.eq.return_value.order.return_value.execute.return_value = MagicMock(
        data=[{"id": "ticket_1", "subject": encrypt_to_hex("Bug", category="contact")}]
    )
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        tickets = fetch_user_tickets(USER_1)
        assert len(tickets) == 1

    mock_table.update.return_value.eq.return_value.eq.return_value.neq.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": "ticket_1", "status": "closed"}]
    )
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        cl = close_ticket(USER_1, "ticket_1", "Resolved issue")
        assert cl is not None

    mock_table.insert.return_value.execute.return_value = MagicMock(data=[{"id": "c1"}])
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        add_ticket_comment("ticket_1", USER_1, "Comment text")

    # 2. spotify.py
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{
            "user_id": USER_1,
            "spotify_user_id": "spot123",
            "refresh_token": encrypt_to_hex("refresh_tok_secret", category="oauth"),
            "disconnected_at": None,
        }]
    )
    with patch("app.db.spotify.supabase_client.table", return_value=mock_table):
        conn = get_connection(USER_1)
        assert conn is not None
        tok = get_decrypted_refresh_token(USER_1)
        assert tok == "refresh_tok_secret"

    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[{"user_id": USER_1}])
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[{"user_id": USER_1}])
    with patch("app.db.spotify.supabase_client.table", return_value=mock_table):
        upsert_connection(USER_1, "spot123", "refresh_tok_secret", "user-top-read")
        mark_sync_result(USER_1, "success")
        persist_artist_signals(USER_1, {"Queen": 0.95}, ["Queen"])
        disconnect(USER_1)
