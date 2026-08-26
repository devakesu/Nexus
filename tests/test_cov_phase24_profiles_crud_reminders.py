"""Phase 24 Coverage Suite: Comprehensive tests for profiles crud, reminder scheduler, FCM notifications, and Spotify sync services."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from postgrest.exceptions import APIError

from app.core.security.crypto import DecryptFailedError
from app.db.client import DatabaseAccessError
from app.models import DiscoveryFilters

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"


# =============================================================================
# 1. DB PROFILES CRUD DEEP TESTS
# =============================================================================

def test_db_profiles_crud_helpers_and_filtering():
    from app.db.profiles.crud import (
        _attach_empty_embeddings,
        _check_basic_overlap,
        _check_lifestyle_filters,
        _enrich_candidates_with_vectors,
        _fetch_and_decrypt_viewer,
        _get_completion_flag_column,
        _get_expanded_viewer_buckets,
        _get_target_bucket_column,
        _list_overlap,
        _map_vector_embeddings,
        _unpack_chat_presence,
        fetch_music_affinities,
        fetch_peer_profile_by_id,
        fetch_stage_1_candidates,
        is_active_profile,
    )

    # _get_completion_flag_column & _get_target_bucket_column
    assert _get_completion_flag_column("Dating") == "is_dating_active"
    assert _get_completion_flag_column("Friends") == "is_friends_active"
    assert _get_completion_flag_column("Professional") == "is_professional_active"
    assert _get_target_bucket_column("Dating") == "dating_target_buckets"
    assert _get_target_bucket_column("Friends") == "friends_target_buckets"
    assert _get_target_bucket_column("Professional") == "professional_target_buckets"

    # _attach_empty_embeddings
    rec: dict[str, Any] = {}
    _attach_empty_embeddings(rec)
    assert rec["bio_embedding"] is None
    assert rec["career_embedding"] is None
    assert rec["identity_embedding"] is None

    # _unpack_chat_presence
    cand = {"chat_presence": [{"last_active_at": "2026-08-26T00:00:00Z"}]}
    _unpack_chat_presence(cand)
    assert cand["last_active_at"] == "2026-08-26T00:00:00Z"

    cand_empty: dict[str, Any] = {"chat_presence": []}
    _unpack_chat_presence(cand_empty)
    assert "last_active_at" not in cand_empty

    # _list_overlap
    assert _list_overlap(["a", "b"], ["b", "c"]) is True
    assert _list_overlap(["a"], ["c"]) is False
    assert _list_overlap([], ["a"]) is False

    # _check_lifestyle_filters & _check_basic_overlap
    filters = DiscoveryFilters(
        smoking=["never"],
        drinking=["socially"],
        partner_values=["honesty"],
        children_plans=["someday"],
        religious_beliefs=["agnostic"],
        tech_skills=["python"],
        languages=["english"],
        causes_supported=["climate"],
    )

    match_c = {
        "id": USER_2,
        "smoking": "never",
        "drinking": "socially",
        "lifestyle": "active",
        "partner_values": ["honesty"],
        "children_plans": "someday",
        "religious_beliefs": "agnostic",
        "tech_skills": ["python"],
        "languages": ["english"],
        "activities": ["hiking"],
        "causes_supported": ["climate"],
        "age": 25,
        "is_active": True,
        "is_dating_active": True,
        "hometown": "Chicago",
        "current_place": "NYC",
        "role_at": "Developer",
    }
    with patch("app.db.profiles.crud.decrypt_profile_field"):
        assert _check_lifestyle_filters(match_c, filters) is True
        assert _check_basic_overlap(match_c, filters) is True

    # Failed overlap
    fail_c = {
        "id": USER_2,
        "smoking": "frequently",
        "drinking": "frequently",
        "lifestyle": "sedentary",
        "partner_values": ["wealth"],
        "children_plans": "never",
        "religious_beliefs": "other",
        "tech_skills": ["rust"],
        "languages": ["spanish"],
        "activities": ["gaming"],
        "causes_supported": ["none"],
        "age": 40,
    }
    with patch("app.db.profiles.crud.decrypt_profile_field"):
        assert _check_lifestyle_filters(fail_c, filters) is False
        assert _check_basic_overlap(fail_c, filters) is False

    # _get_expanded_viewer_buckets: invalid vs valid
    assert _get_expanded_viewer_buckets({}, "Dating") == ([], [])
    with patch("app.db.profiles.crud._expand_target_buckets", return_value=["M"]):
        search, targets = _get_expanded_viewer_buckets({"dating_target_buckets": ["M"], "search_bucket": "F"}, "Dating")
        assert search == ["F"]
        assert targets == ["M"]

    # _fetch_and_decrypt_viewer: APIError, DecryptFailedError, None profile
    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError, match="Failed to fetch viewer profile"):
            _fetch_and_decrypt_viewer(USER_1, "Dating")

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        assert _fetch_and_decrypt_viewer(USER_1, "Dating") is None

        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[{"id": USER_1, "name": "enc"}])
        with patch("app.db.profiles.crud.decrypt_profile_record", side_effect=DecryptFailedError("fail")):
            with pytest.raises(DecryptFailedError):
                _fetch_and_decrypt_viewer(USER_1, "Dating")

    # is_active_profile: True / False / APIError
    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().limit().execute.return_value = MagicMock(data=[{"id": USER_1}])
        assert is_active_profile(USER_1) is True

        mock_sb.table().select().eq().eq().limit().execute.return_value = MagicMock(data=[])
        assert is_active_profile(USER_1) is False

        mock_sb.table().select().eq().eq().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            is_active_profile(USER_1)

    # fetch_peer_profile_by_id: not found, DecryptFailedError, success
    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().eq().eq().neq().limit().execute.return_value = MagicMock(data=[])
        assert fetch_peer_profile_by_id(USER_2) is None

        mock_sb.table().select().eq().eq().eq().eq().neq().limit().execute.return_value = MagicMock(data=[{"id": USER_2, "name": "enc"}])
        with patch("app.db.profiles.crud.decrypt_profile_record", side_effect=DecryptFailedError("fail")):
            with pytest.raises(DecryptFailedError):
                fetch_peer_profile_by_id(USER_2)

        with patch("app.db.profiles.crud.decrypt_profile_record", return_value={"id": USER_2, "name": "Bob"}):
            p = fetch_peer_profile_by_id(USER_2)
            assert p is not None
            assert p["name"] == "Bob"

    # fetch_music_affinities: APIError & success
    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().limit().execute.side_effect = APIError({"message": "fail"})
        art, gen = fetch_music_affinities(USER_1)
        assert art == {}
        assert gen == {}

        mock_sb.table().select().eq().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().eq().limit().execute.return_value = MagicMock(data=[{"artist_affinity": {"queen": 0.8}, "genre_affinity": {"rock": 0.9}}])
        with patch("app.db.profiles.encryption._parse_encrypted_dict"):
            art, gen = fetch_music_affinities(USER_1)
            assert art == {"queen": 0.8}
            assert gen == {"rock": 0.9}

    # _map_vector_embeddings & _enrich_candidates_with_vectors
    viewer_obj: dict[str, Any] = {"id": USER_1}
    cand_obj: dict[str, Any] = {"id": USER_2}
    c_map = {USER_2: cand_obj}
    vec_records = [
        {"user_id": USER_1, "vector_profiles": {"bio_embedding": [0.1], "career_embedding": [0.2], "identity_embedding": [0.3]}},
        {"user_id": USER_2, "vector_profiles": {"bio_embedding": [0.4], "career_embedding": [0.5], "identity_embedding": [0.6]}},
    ]
    _map_vector_embeddings(vec_records, viewer_obj, c_map, USER_1)
    assert viewer_obj["bio_embedding"] == [0.1]
    assert cand_obj["bio_embedding"] == [0.4]

    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().in_().execute.return_value = MagicMock(data=vec_records)
        _enrich_candidates_with_vectors(viewer_obj, [cand_obj], USER_1)

    # fetch_stage_1_candidates: no viewer -> None, [], and success
    with patch("app.db.profiles.crud._fetch_and_decrypt_viewer", return_value=None):
        v, c = fetch_stage_1_candidates(USER_1, "Dating", filters)
        assert v is None
        assert c == []

    viewer_dict = {
        "id": USER_1,
        "target_dating_bucket": ["b1"],
        "dating_bucket": "b1",
        "app_variant": "nexus",
        "is_dating_active": True,
    }
    with patch("app.db.profiles.crud._fetch_and_decrypt_viewer", return_value=viewer_dict), \
         patch("app.db.profiles.crud.fetch_active_discovery_excluded_ids", return_value=set()), \
         patch("app.db.profiles.crud._execute_and_filter_candidates", return_value=[match_c]), \
         patch("app.db.profiles.crud.decrypt_profile_field"), \
         patch("app.db.profiles.crud.decrypt_profile_fields"), \
         patch("app.db.profiles.crud._enrich_candidates_with_vectors"):
        v_res, c_res = fetch_stage_1_candidates(USER_1, "Dating", filters)
        assert v_res is not None
        assert len(c_res) == 1


# =============================================================================
# 2. SERVICES REMINDER SCHEDULER TESTS
# =============================================================================

async def test_services_reminder_scheduler_deep():
    from app.services.reminder_scheduler import (
        _acquire_escalation_idempotency,
        _check_due_reminders,
        _check_overdue_safety_sessions,
        _check_upcoming_safety_reminders,
        _compose_session_unreachable_message,
        _dispatch_escalation_sms_and_record,
        _escalate_safety_session,
        _mask_id,
        _next_escalation_due,
        _run_account_deletion_long_tail_purge,
        _run_account_deletion_purge,
        _run_blocklist_expiry,
        _run_in_maintenance_executor,
        _run_safety_data_legal_hold_purge,
        _run_safety_evidence_retention_purge,
        get_maintenance_executor,
        start_reminder_scheduler,
        stop_reminder_scheduler,
        with_distributed_lock,
    )

    # _mask_id
    assert _mask_id("00000000-0000-0000-0000-000000000001") == "0000...0001"
    assert _mask_id("short") == "***"

    # with_distributed_lock: acquired vs locked
    @with_distributed_lock("test_lock", ttl_seconds=10)
    async def sample_job() -> None:
        pass

    mock_lock = MagicMock()
    mock_lock.acquire = AsyncMock(return_value=True)
    mock_lock.release = AsyncMock()

    with patch("app.services.reminder_scheduler.redis_client") as mock_redis:
        mock_redis.lock = MagicMock(return_value=mock_lock)
        await sample_job()

        mock_lock.acquire = AsyncMock(return_value=False)
        await sample_job()

    # _next_escalation_due
    now = datetime.now(timezone.utc)
    assert _next_escalation_due({"escalations_sent": 0}, now) is True
    assert _next_escalation_due({"escalations_sent": 1, "last_escalated_at": None}, now) is False
    assert _next_escalation_due({"escalations_sent": 1, "last_escalated_at": (now - timedelta(minutes=20)).isoformat(), "interval_seconds": 300}, now) is True
    assert _next_escalation_due({"escalations_sent": 1, "last_escalated_at": (now - timedelta(minutes=1)).isoformat(), "interval_seconds": 300}, now) is False

    # _acquire_escalation_idempotency: redis set return True vs False
    with patch("app.services.reminder_scheduler.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(return_value=True)
        assert await _acquire_escalation_idempotency("sess-1", 1) is True

        mock_redis.set = AsyncMock(return_value=False)
        assert await _acquire_escalation_idempotency("sess-1", 1) is False

        mock_redis.set = AsyncMock(side_effect=Exception("redis down"))
        assert await _acquire_escalation_idempotency("sess-1", 1) is False

    # _compose_session_unreachable_message
    msg = _compose_session_unreachable_message(
        {"label": "Coffee"},
        "sess-1",
        1,
        user_name="Alice",
    )
    assert "Alice" in msg
    assert "Coffee" in msg

    # _dispatch_escalation_sms_and_record: mock SMS & log record
    contacts = [{"contact_name": "Bob", "phone": "+1234567890"}]
    session = {"id": "sess-1", "user_id": USER_1, "user_name": "Alice", "escalation_count": 0}
    with patch("app.services.reminder_scheduler.record_safety_escalation_sent", return_value=True), \
         patch("app.services.reminder_scheduler.send_sms", return_value=MagicMock(success=True)):
        await _dispatch_escalation_sms_and_record(contacts, session, "sess-1", 1, "idem-123")

    # _escalate_safety_session: no contacts vs success
    with patch("app.services.reminder_scheduler.fetch_safety_contacts_with_id", return_value=[]), \
         patch("app.services.reminder_scheduler.record_safety_escalation_sent"):
        await _escalate_safety_session({"id": "sess-1", "user_id": USER_1, "escalation_count": 0})

    # _check_overdue_safety_sessions
    with patch("app.services.reminder_scheduler.fetch_overdue_safety_sessions", return_value=[{"id": "sess-1", "escalation_count": 0, "session_expires_at": (now - timedelta(minutes=10)).isoformat()}]), \
         patch("app.services.reminder_scheduler._escalate_safety_session"):
        await _check_overdue_safety_sessions()

    # _check_due_reminders & _check_upcoming_safety_reminders
    with patch("app.services.reminder_scheduler.fetch_due_event_reminders", return_value=[{"id": "ev-1", "sender_id": USER_1, "conversation_id": "conv-1", "tab": "Dating"}]), \
         patch("app.services.reminder_scheduler.fetch_due_safety_reminders", return_value=[{"id": "ev-2", "sender_id": USER_1, "conversation_id": "conv-1", "tab": "Dating"}]), \
         patch("app.services.reminder_scheduler.fetch_conversation_participants", return_value={"user_a_id": USER_1, "user_b_id": USER_2}), \
         patch("app.services.reminder_scheduler.send_chat_event_reminder_notification", return_value=True), \
         patch("app.services.reminder_scheduler.send_meetup_safety_reminder_notification"), \
         patch("app.services.reminder_scheduler.mark_reminder_sent"), \
         patch("app.services.reminder_scheduler.mark_safety_reminder_sent"):
        await _check_due_reminders()
        await _check_upcoming_safety_reminders()

    # Maintenance purges & executor
    get_maintenance_executor()
    await _run_in_maintenance_executor(lambda: 42)

    with patch("app.services.reminder_scheduler._run_in_maintenance_executor"):
        await _run_account_deletion_purge()
        await _run_blocklist_expiry()
        await _run_account_deletion_long_tail_purge()
        await _run_safety_evidence_retention_purge()
        await _run_safety_data_legal_hold_purge()

    # start and stop scheduler
    sched = start_reminder_scheduler()
    assert sched is not None
    stop_reminder_scheduler()


# =============================================================================
# 3. SERVICES FCM SENDER TESTS
# =============================================================================

async def test_services_fcm_sender_deep():
    from app.services.fcm_sender import (
        _deactivate_fcm_token,
        _fetch_profile_name,
        _fetch_user_fcm_tokens,
        _is_firebase_initialized,
        _send_to_tokens,
        send_chat_event_reminder_notification,
        send_chat_message_notification,
        send_like_notification,
        send_match_notification,
        send_meetup_safety_reminder_notification,
        send_prekey_replenishment_notification,
        send_trusted_contact_removed_notification,
    )

    # _is_firebase_initialized
    with patch("app.services.fcm_sender._fb.get_app", side_effect=ValueError("no app")):
        assert _is_firebase_initialized() is False

    with patch("app.services.fcm_sender._fb.get_app", return_value=MagicMock()):
        assert _is_firebase_initialized() is True

    # _fetch_user_fcm_tokens: deactivated vs active vs exception
    with patch("app.services.fcm_sender.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[{"is_deactivated": True}])
        assert _fetch_user_fcm_tokens(USER_1) == []

        mock_sb.table().select().eq().limit().execute.side_effect = Exception("DB fail")
        assert _fetch_user_fcm_tokens(USER_1) == []

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[{"is_deactivated": False}])
        mock_sb.table().select().eq().eq().execute.return_value = MagicMock(data=[{"fcm_token": "tok-123"}])
        assert _fetch_user_fcm_tokens(USER_1) == ["tok-123"]

    # _fetch_profile_name: empty, deactivated, decrypt failure
    with patch("app.services.fcm_sender.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        assert _fetch_profile_name(USER_1) is None

        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[{"name": "enc", "is_deactivated": True}])
        assert _fetch_profile_name(USER_1) is None

        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[{"name": "Alice", "is_deactivated": False}])
        with patch("app.services.fcm_sender.decrypt_pii", return_value="Alice"):
            assert _fetch_profile_name(USER_1) == "Alice"

    # _deactivate_fcm_token: success & Sentry alert on 3rd failure
    with patch("app.services.fcm_sender.supabase_client") as mock_sb:
        mock_sb.table().update().eq().execute.return_value = MagicMock()
        _deactivate_fcm_token("tok-12345678")

        mock_sb.table().update().eq().execute.side_effect = Exception("DB error")
        for _ in range(3):
            _deactivate_fcm_token("bad-token-1234")

    # _send_to_tokens: empty tokens, multicast failures with NOT_FOUND
    assert _send_to_tokens([], "title", "body", {}, "channel") == 0

    mock_resp_fail = MagicMock()
    mock_resp_fail.success = False
    mock_resp_fail.exception = MagicMock(code="NOT_FOUND")
    mock_batch_resp = MagicMock(failure_count=1, success_count=0, responses=[mock_resp_fail])

    with patch("app.services.fcm_sender._fcm.send_each_for_multicast", return_value=mock_batch_resp), \
         patch("app.services.fcm_sender._deactivate_fcm_token") as mock_deact:
        res = _send_to_tokens(["stale_token_12345678"], "title", "body", {}, "channel", is_safety_critical=True)
        assert res == 0
        assert mock_deact.called

    # High level notification functions
    with patch("app.services.fcm_sender._is_firebase_initialized", return_value=True), \
         patch("app.services.fcm_sender.get_cached_active_block_ids", return_value=set()), \
         patch("app.services.fcm_sender._fetch_user_fcm_tokens", return_value=["tok-1"]), \
         patch("app.services.fcm_sender._fetch_profile_name", return_value="Alice"), \
         patch("app.services.fcm_sender._send_to_tokens", return_value=1), \
         patch("app.services.fcm_sender.redis_client") as mock_redis:
        mock_redis.set = AsyncMock(return_value=True)

        await send_like_notification(USER_1, USER_2, is_superlike=True)
        await send_like_notification(USER_1, USER_2, is_superlike=False)
        await send_match_notification(USER_1, USER_2)
        await send_chat_message_notification(
            USER_1, USER_2, "conv-1", "Dating", "msg-1", "short ciphertext", {},
        )
        await send_trusted_contact_removed_notification(USER_1, "Bob")
        await send_meetup_safety_reminder_notification(USER_1, USER_2, "conv-1", "Dating")
        await send_prekey_replenishment_notification(USER_1)

        # Blocked sender / recipient
        with patch("app.services.fcm_sender.get_cached_active_block_ids", return_value={USER_1}):
            await send_like_notification(USER_1, USER_2, is_superlike=False)
            await send_match_notification(USER_1, USER_2)
            await send_chat_message_notification(
                USER_1, USER_2, "conv-1", "Dating", "msg-1", "short ciphertext", {},
            )

    # send_chat_event_reminder_notification
    with patch("app.services.fcm_sender._is_firebase_initialized", return_value=True), \
         patch("app.db.chat.fetch_conversation_participants", return_value={"id": "conv-1", "closed_at": None}), \
         patch("app.services.fcm_sender.get_cached_active_block_ids", return_value=set()), \
         patch("app.services.fcm_sender._fetch_user_fcm_tokens", return_value=["tok-1"]), \
         patch("app.services.fcm_sender._send_to_tokens", return_value=1):
        assert await send_chat_event_reminder_notification(USER_1, USER_2, "conv-1", "Dating") is True


# =============================================================================
# 4. SERVICES SPOTIFY SYNC TESTS
# =============================================================================

async def test_services_spotify_sync_deep():
    from app.services.spotify_sync import (
        TopArtistsResult,
        _auth_header,
        _get_with_retry,
        _parse_retry_after,
        _post_with_retry,
        blend_artist_affinity,
        compute_artist_frequency,
        compute_genre_affinity,
        compute_playlist_artist_ids_frequency,
        exchange_code,
        fetch_artist_genres_batch,
        fetch_owned_or_collaborative_playlists,
        fetch_playlist_tracks,
        fetch_spotify_user_id,
        refresh_access_token,
        revoke_refresh_token,
        run_full_sync,
        top_display_names,
    )

    # _auth_header & _parse_retry_after
    assert _auth_header("tok-123") == {"Authorization": "Bearer tok-123"}
    resp_hdr = httpx.Response(429, headers={"Retry-After": "5"})
    assert _parse_retry_after(resp_hdr) == 5.0

    resp_no_hdr = httpx.Response(429)
    assert _parse_retry_after(resp_no_hdr) == 1.0

    # _get_with_retry & _post_with_retry: 200 vs 429 retry
    dummy_req = httpx.Request("GET", "https://api.spotify.com/v1/me")
    dummy_post_req = httpx.Request("POST", "https://api.spotify.com/v1/token")

    async with httpx.AsyncClient() as client:
        with patch.object(client, "get", side_effect=[httpx.Response(429, headers={"Retry-After": "0"}, request=dummy_req), httpx.Response(200, json={"ok": True}, request=dummy_req)]), \
             patch("asyncio.sleep", new_callable=AsyncMock):
            res = await _get_with_retry(client, "https://api.spotify.com/v1/me", headers={"Authorization": "Bearer tok"})
            assert res.status_code == 200

        with patch.object(client, "post", side_effect=[httpx.Response(429, headers={"Retry-After": "0"}, request=dummy_post_req), httpx.Response(200, json={"ok": True}, request=dummy_post_req)]), \
             patch("asyncio.sleep", new_callable=AsyncMock):
            res_post = await _post_with_retry(client, "https://api.spotify.com/v1/token", data={}, auth=("id", "sec"), headers={})
            assert res_post.status_code == 200

    # exchange_code, refresh_access_token, revoke_refresh_token, fetch_spotify_user_id
    with patch("app.services.spotify_sync._post_with_retry", return_value=httpx.Response(200, json={"access_token": "new-tok", "refresh_token": "new-ref", "expires_in": 3600}, request=dummy_post_req)):
        bundle = await exchange_code("auth_code", "https://nexus.test/callback")
        assert bundle.access_token == "new-tok"

        bundle_ref = await refresh_access_token("my-refresh-token")
        assert bundle_ref.access_token == "new-tok"

    with patch("httpx.AsyncClient.post", return_value=httpx.Response(200, request=dummy_post_req)):
        assert await revoke_refresh_token("my-refresh-token") is True

    with patch("app.services.spotify_sync._get_with_retry", return_value=httpx.Response(200, json={"id": "spotify-user-999"}, request=dummy_req)):
        assert await fetch_spotify_user_id("tok") == "spotify-user-999"

    # Math affinity calculation functions
    tracks = [
        {"artists": ["Queen", "Bowie"]},
        {"artists": ["Queen"]},
    ]
    freq = compute_artist_frequency(tracks)
    assert "Queen" in freq
    assert freq["Queen"] > freq["Bowie"]

    genre_map = compute_genre_affinity({"rock": 10.0, "pop": 5.0})
    assert "rock" in genre_map
    assert genre_map["rock"] == 1.0
    assert genre_map["pop"] == 0.5

    blended, casing = blend_artist_affinity(
        native_ranked={"Queen": 1.0, "Bowie": 0.5},
        playlist_freq={"Queen": 0.5, "Beatles": 0.8},
    )
    assert "queen" in blended
    assert casing["queen"] == "Queen"

    top_names = top_display_names(blended, casing, n=2)
    assert len(top_names) == 2

    freq_ids = compute_playlist_artist_ids_frequency([
        {"artists": ["Queen"], "artist_ids": ["art-1"]},
    ], limit=50)
    assert len(freq_ids) == 1
    assert freq_ids[0][0] == "art-1"

    # fetch_artist_genres_batch
    async with httpx.AsyncClient() as client:
        with patch("app.services.spotify_sync._get_with_retry", return_value=httpx.Response(200, json={"artists": [{"id": "art-1", "name": "Queen", "genres": ["rock"]}]}, request=dummy_req)):
            genres_map = await fetch_artist_genres_batch(client, "tok", ["art-1"])
            assert "art-1" in genres_map

    # fetch_owned_or_collaborative_playlists & fetch_playlist_tracks
    async with httpx.AsyncClient() as client:
        with patch("app.services.spotify_sync._get_with_retry", return_value=httpx.Response(200, json={"items": [{"id": "pl-1", "name": "Favorites", "owner": {"id": "spot-1"}, "collaborative": False}], "next": None}, request=dummy_req)):
            pls = await fetch_owned_or_collaborative_playlists(client, "tok", "spot-1")
            assert len(pls) == 1

        with patch("app.services.spotify_sync._get_with_retry", return_value=httpx.Response(200, json={"items": [{"track": {"id": "tr-1", "name": "Bohemian Rhapsody", "artists": [{"id": "a1", "name": "Queen"}]}}], "next": None}, request=dummy_req)):
            pl_tracks = await fetch_playlist_tracks(client, "pl-1", "tok")
            assert len(pl_tracks) == 1

    # Full integration run_full_sync
    with patch("app.services.spotify_sync.fetch_top_artists_ranked", return_value=TopArtistsResult(ranked={"Queen": 1.0}, genre_weights={"rock": 1.0})), \
         patch("app.services.spotify_sync._sync_playlist_tracks", return_value=([], [])), \
         patch("app.services.spotify_sync.persist_artist_signals"), \
         patch("app.services.spotify_sync.replace_playlists"), \
         patch("app.services.spotify_sync.mark_sync_result"):
        await run_full_sync(USER_1, "tok-123", "spot-1")
