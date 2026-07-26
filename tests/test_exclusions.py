import uuid
from typing import Any
from unittest.mock import MagicMock, patch

import pytest

from app.db.exclusions import fetch_active_discovery_excluded_ids


@pytest.fixture
def mock_supabase() -> Any:
    with patch("app.db.exclusions.supabase_client") as mock:
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
