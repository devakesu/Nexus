import uuid
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.db.discovery import fetch_active_discovery_excluded_ids, fetch_likes_for_user


@pytest.fixture
def mock_supabase() -> Any:
    with patch("app.db.discovery.exclusions.supabase_client") as mock:
        yield mock


def test_fetch_active_discovery_excluded_ids_blocks_and_actions(
    mock_supabase: MagicMock,
) -> None:
    viewer_id = str(uuid.uuid4())
    blocked_user_id = str(uuid.uuid4())
    blocker_user_id = str(uuid.uuid4())
    liked_user_id = str(uuid.uuid4())
    passed_active_user_id = str(uuid.uuid4())
    passed_expired_user_id = str(uuid.uuid4())

    # Mock response for profile_discovery_actions
    mock_actions_res = MagicMock()
    mock_actions_res.data = [
        # Blocked by viewer (actor_id = viewer_id)
        {
            "actor_id": viewer_id,
            "target_id": blocked_user_id,
            "action": "block",
            "tab": None,
            "expires_at": None,
        },
        # Blocker record where target_id is equal to viewer_id
        {
            "actor_id": blocker_user_id,
            "target_id": viewer_id,
            "action": "block",
            "tab": None,
            "expires_at": None,
        },
        # Liked by viewer on active tab
        {
            "actor_id": viewer_id,
            "target_id": liked_user_id,
            "action": "like",
            "tab": "Dating",
            "expires_at": None,
        },
        # Pass active (not expired)
        {
            "actor_id": viewer_id,
            "target_id": passed_active_user_id,
            "action": "pass",
            "tab": "Dating",
            "expires_at": "2030-01-01T00:00:00Z",
        },
        # Pass expired
        {
            "actor_id": viewer_id,
            "target_id": passed_expired_user_id,
            "action": "pass",
            "tab": "Dating",
            "expires_at": "2020-01-01T00:00:00Z",
        },
    ]

    # Mock response for matches (empty for this test)
    mock_matches_res = MagicMock()
    mock_matches_res.data = []

    # Mock the builder pattern calls to return the same query object
    mock_actions_query = MagicMock()
    mock_actions_query.select.return_value = mock_actions_query
    mock_actions_query.is_.return_value = mock_actions_query
    mock_actions_query.or_.return_value = mock_actions_query
    mock_actions_query.execute.return_value = mock_actions_res

    mock_matches_query = MagicMock()
    mock_matches_query.select.return_value = mock_matches_query
    mock_matches_query.or_.return_value = mock_matches_query
    mock_matches_query.eq.return_value = mock_matches_query
    mock_matches_query.is_.return_value = mock_matches_query
    mock_matches_query.execute.return_value = mock_matches_res

    def side_effect(table_name: str) -> Any:
        if table_name == "profile_discovery_actions":
            return mock_actions_query
        if table_name == "matches":
            return mock_matches_query
        return MagicMock()

    mock_supabase.table.side_effect = side_effect

    # Run execution
    excluded = fetch_active_discovery_excluded_ids(viewer_id, "Dating")

    # Assertions
    assert blocked_user_id in excluded
    assert blocker_user_id in excluded
    assert liked_user_id in excluded
    assert passed_active_user_id in excluded
    assert passed_expired_user_id not in excluded


def test_fetch_active_discovery_excluded_ids_matches(mock_supabase: MagicMock) -> None:
    viewer_id = str(uuid.uuid4())
    matched_dating_user_id = str(uuid.uuid4())
    matched_professional_user_id = str(uuid.uuid4())
    dissolved_match_user_id = str(uuid.uuid4())

    # Mock response for profile_discovery_actions (empty)
    mock_actions_res = MagicMock()
    mock_actions_res.data = []

    # Mock response for matches in Dating tab (only returns active Dating match)
    mock_matches_res = MagicMock()
    mock_matches_res.data = [
        # Active match in Dating where viewer is liker
        {
            "liker_id": viewer_id,
            "liked_back_id": matched_dating_user_id,
            "tab": "Dating",
            "unmatched_at": None,
        },
    ]

    # Mock the builder pattern calls to return the same query object
    mock_actions_query = MagicMock()
    mock_actions_query.select.return_value = mock_actions_query
    mock_actions_query.is_.return_value = mock_actions_query
    mock_actions_query.or_.return_value = mock_actions_query
    mock_actions_query.execute.return_value = mock_actions_res

    mock_matches_query = MagicMock()
    mock_matches_query.select.return_value = mock_matches_query
    mock_matches_query.or_.return_value = mock_matches_query
    mock_matches_query.eq.return_value = mock_matches_query
    mock_matches_query.is_.return_value = mock_matches_query
    mock_matches_query.execute.return_value = mock_matches_res

    def side_effect(table_name: str) -> Any:
        if table_name == "profile_discovery_actions":
            return mock_actions_query
        if table_name == "matches":
            return mock_matches_query
        return MagicMock()

    mock_supabase.table.side_effect = side_effect

    # Run execution for Dating orbit
    excluded = fetch_active_discovery_excluded_ids(viewer_id, "Dating")

    # Assert matched dating user is excluded, others are not
    assert matched_dating_user_id in excluded
    assert matched_professional_user_id not in excluded
    assert dissolved_match_user_id not in excluded


def test_fetch_likes_for_user_filters_deactivated(mock_supabase: MagicMock) -> None:
    viewer_id = str(uuid.uuid4())

    mock_actions_res = MagicMock()
    mock_actions_res.data = [
        {
            "actor_id": "actor-123",
            "action": "like",
            "created_at": "2026-08-11T20:00:00Z",
            "seen_at": None,
            "actor": {"is_deactivated": False},
        },
    ]

    mock_actions_query = MagicMock()
    mock_actions_query.select.return_value = mock_actions_query
    mock_actions_query.eq.return_value = mock_actions_query
    mock_actions_query.in_.return_value = mock_actions_query
    mock_actions_query.is_.return_value = mock_actions_query
    mock_actions_query.order.return_value = mock_actions_query
    mock_actions_query.limit.return_value = mock_actions_query
    mock_actions_query.execute.return_value = mock_actions_res

    mock_supabase.table.return_value = mock_actions_query

    res = fetch_likes_for_user(viewer_id, "Dating")
    assert len(res) == 1
    assert res[0]["actor_id"] == "actor-123"

    mock_actions_query.select.assert_called_once_with(
        "actor_id, action, created_at, seen_at, actor:profiles!actor_id(is_deactivated)",
    )
    mock_actions_query.eq.assert_any_call("actor.is_deactivated", False)


def test_record_user_report_upserts_auto_block(mock_supabase: MagicMock) -> None:
    from app.db.discovery.exclusions import record_user_report

    reporter_id = "11111111-1111-1111-1111-111111111111"
    target_id = "22222222-2222-2222-2222-222222222222"

    mock_reports_table = MagicMock()
    mock_reports_table.insert.return_value = mock_reports_table
    mock_reports_table.select.return_value = mock_reports_table
    mock_reports_table.execute.return_value = MagicMock(data=[{"id": "report-uuid-123"}])

    mock_actions_table = MagicMock()
    mock_actions_table.upsert.return_value = mock_actions_table
    mock_actions_table.execute.return_value = MagicMock(data=[])

    def table_router(name: str) -> Any:
        if name == "user_reports":
            return mock_reports_table
        if name == "profile_discovery_actions":
            return mock_actions_table
        return MagicMock()

    mock_supabase.table.side_effect = table_router

    record_user_report(
        reporter_id=reporter_id,
        target_id=target_id,
        reason="harassment",
        reason_detail="Inappropriate conduct",
        tab="Dating",
    )

    mock_reports_table.insert.assert_called_once_with({
        "reporter_id": reporter_id,
        "target_id": target_id,
        "reason": "harassment",
        "reason_detail": "Inappropriate conduct",
        "tab": "Dating",
    })

    mock_actions_table.upsert.assert_called_once_with(
        {
            "actor_id": reporter_id,
            "target_id": target_id,
            "action": "block",
            "revoked_at": None,
            "metadata": {
                "source": "report",
                "report_reason": "harassment",
                "report_id": "report-uuid-123",
            },
        },
        on_conflict="actor_id,target_id,action",
    )


def test_record_user_report_with_chat_evidence(mock_supabase: MagicMock) -> None:
    from app.db.discovery.exclusions import record_user_report

    reporter_id = "11111111-1111-1111-1111-111111111111"
    target_id = "22222222-2222-2222-2222-222222222222"
    convo_id = "33333333-3333-3333-3333-333333333333"
    evidence = [
        {
            "message_id": "msg-1",
            "sender_id": target_id,
            "message_type": "text",
            "content": "offensive message",
            "created_at": "2026-08-24T12:00:00Z",
            "is_mine": False,
        }
    ]

    mock_reports_table = MagicMock()
    mock_reports_table.insert.return_value = mock_reports_table
    mock_reports_table.select.return_value = mock_reports_table
    mock_reports_table.execute.return_value = MagicMock(data=[{"id": "report-uuid-456"}])

    mock_actions_table = MagicMock()
    mock_actions_table.upsert.return_value = mock_actions_table
    mock_actions_table.execute.return_value = MagicMock(data=[])

    def table_router(name: str) -> Any:
        if name == "user_reports":
            return mock_reports_table
        if name == "profile_discovery_actions":
            return mock_actions_table
        return MagicMock()

    mock_supabase.table.side_effect = table_router

    record_user_report(
        reporter_id=reporter_id,
        target_id=target_id,
        reason="harassment",
        reason_detail="Severe harassment in chat",
        tab="Dating",
        conversation_id=convo_id,
        evidence=evidence,
    )

    mock_reports_table.insert.assert_called_once_with({
        "reporter_id": reporter_id,
        "target_id": target_id,
        "reason": "harassment",
        "reason_detail": "Severe harassment in chat",
        "tab": "Dating",
        "metadata": {
            "conversation_id": convo_id,
            "chat_evidence": evidence,
        },
    })



@pytest.mark.anyio
@patch("app.db.discovery.exclusions.redis_client")
@patch("app.db.sessions.auth_sessions.invalidate_viewer_discovery_sessions")
async def test_invalidate_block_cache_deletes_redis_keys_and_discovery_sessions(
    mock_invalidate_sessions: MagicMock,
    mock_redis: MagicMock,
) -> None:
    from app.db.discovery.exclusions import invalidate_block_cache

    mock_redis.delete = AsyncMock()

    await invalidate_block_cache("user-111", "user-222")

    assert mock_redis.delete.call_count == 2
    mock_redis.delete.assert_any_call("discovery:block_ids:user-111")
    mock_redis.delete.assert_any_call("discovery:block_ids:user-222")

    assert mock_invalidate_sessions.call_count == 2
    mock_invalidate_sessions.assert_any_call("user-111")
    mock_invalidate_sessions.assert_any_call("user-222")


def test_fetch_stage_1_candidates_filters_large_exclusion_set(mock_supabase: MagicMock) -> None:
    from app.db.profiles.crud import fetch_stage_1_candidates
    from app.models import DiscoveryFilters

    viewer_id = "00000000-0000-0000-0000-000000000001"
    # Create 1005 excluded IDs
    excluded_set = {f"excluded-{i}" for i in range(1005)}

    viewer_data = {
        "id": viewer_id,
        "search_bucket": "M",
        "dating_target_bucket": ["F"],
        "app_variant": "nexus",
    }

    # Candidate whose ID is beyond the 1000 DB cap
    leaked_candidate_id = "excluded-1004"
    valid_candidate_id = "valid-candidate-9999"

    mock_candidates_res = MagicMock()
    mock_candidates_res.data = [
        {
            "id": leaked_candidate_id,
            "search_bucket": "F",
            "dating_target_bucket": ["M"],
            "age": 25,
        },
        {
            "id": valid_candidate_id,
            "search_bucket": "F",
            "dating_target_bucket": ["M"],
            "age": 26,
        },
    ]

    with (
        patch("app.db.profiles.crud._fetch_and_decrypt_viewer", return_value=viewer_data),
        patch("app.db.profiles.crud.fetch_active_discovery_excluded_ids", return_value=excluded_set),
        patch("app.db.profiles.crud._execute_and_filter_candidates", return_value=list(mock_candidates_res.data)),
        patch("app.db.profiles.crud._enrich_candidates_with_vectors"),
    ):
        filters = DiscoveryFilters()
        viewer, candidates = fetch_stage_1_candidates(
            viewer_id=viewer_id,
            active_tab="Dating",
            filters=filters,
        )

        assert viewer is not None
        assert len(candidates) == 1
        assert candidates[0]["id"] == valid_candidate_id
        assert not any(c["id"] == leaked_candidate_id for c in candidates)


def test_fetch_stage_1_candidates_lazy_decryption(mock_supabase: MagicMock) -> None:
    """Verify that Stage 1 discovery decrypts minimally and lazily without full PII loops."""
    from app.core.security.crypto import encrypt_pii
    from app.db.profiles.crud import fetch_stage_1_candidates
    from app.models import DiscoveryFilters

    viewer_id = "00000000-0000-0000-0000-000000000001"
    viewer_data = {
        "id": viewer_id,
        "search_bucket": "M",
        "dating_target_buckets": ["F"],
        "app_variant": "nexus",
    }

    # Encrypt some fields
    cand_matching_id = "cand-matching-1"
    cand_failing_id = "cand-failing-2"

    raw_bio_token = encrypt_pii("Very long bio text")
    raw_languages_matching = encrypt_pii('["English", "Spanish"]')
    raw_languages_failing = encrypt_pii('["French"]')
    raw_interests_matching = encrypt_pii('{"Music": 5, "Tech": 4}')

    mock_candidates_data = [
        {
            "id": cand_failing_id,
            "search_bucket": "F",
            "dating_target_buckets": ["M"],
            "age": 25,
            "bio": raw_bio_token,
            "languages": raw_languages_failing,
            "interests": raw_interests_matching,
        },
        {
            "id": cand_matching_id,
            "search_bucket": "F",
            "dating_target_buckets": ["M"],
            "age": 26,
            "bio": raw_bio_token,
            "languages": raw_languages_matching,
            "interests": raw_interests_matching,
        },
    ]

    with (
        patch("app.db.profiles.crud._fetch_and_decrypt_viewer", return_value=viewer_data),
        patch("app.db.profiles.crud.fetch_active_discovery_excluded_ids", return_value=set()),
        patch("app.db.profiles.crud._execute_and_filter_candidates", return_value=mock_candidates_data),
        patch("app.db.profiles.crud._enrich_candidates_with_vectors"),
    ):
        filters = DiscoveryFilters(languages=["English"])
        viewer, candidates = fetch_stage_1_candidates(
            viewer_id=viewer_id,
            active_tab="Dating",
            filters=filters,
        )

        assert viewer is not None
        assert len(candidates) == 1
        matched = candidates[0]
        assert matched["id"] == cand_matching_id
        # Languages and scoring fields (interests) are decrypted
        assert matched["languages"] == ["English", "Spanish"]
        assert matched["interests"] == {"Music": 5, "Tech": 4}
        # Non-scoring field 'bio' was NOT decrypted during Stage 1 candidate generation
        assert matched["bio"] == raw_bio_token


@patch("app.db.profiles.crud.supabase_client")
def test_fetch_stage_1_candidates_emits_debug_logs_not_info(mock_supabase: MagicMock) -> None:
    from app.db.profiles.crud import fetch_stage_1_candidates
    from app.models import DiscoveryFilters

    _ = mock_supabase
    viewer_data = {
        "id": "viewer-123",
        "app_variant": "nexus",
        "interests": "{}",
    }

    with (
        patch("app.db.profiles.crud.logger") as mock_logger,
        patch("app.db.profiles.crud._fetch_and_decrypt_viewer", return_value=viewer_data),
        patch("app.db.profiles.crud.fetch_active_discovery_excluded_ids", return_value=set()),
        patch("app.db.profiles.crud._execute_and_filter_candidates", return_value=[]),
        patch("app.db.profiles.crud._attach_empty_embeddings"),
    ):
        filters = DiscoveryFilters()
        fetch_stage_1_candidates(
            viewer_id="viewer-123",
            active_tab="Dating",
            filters=filters,
        )

        mock_logger.info.assert_not_called()
        assert mock_logger.debug.call_count >= 1
