import uuid
from typing import Any
from unittest.mock import MagicMock, patch

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

