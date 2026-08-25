from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException

from app.db.client import DatabaseAccessError
from app.db.sessions.auth_sessions import (
    get_discovery_session,
    get_discovery_session_by_id,
)
from app.services.discovery import get_or_validate_session


@patch("app.db.sessions.auth_sessions.supabase_client.table")
def test_get_discovery_session_found(mock_table: MagicMock) -> None:
    builder = MagicMock()
    builder.select.return_value = builder
    builder.eq.return_value = builder
    builder.maybe_single.return_value = builder
    builder.execute.return_value = MagicMock(
        data={"id": "s-1", "viewer_id": "v-1", "tab": "Dating", "expires_at": "2026-08-13T19:00:00Z"},
    )
    mock_table.return_value = builder

    res = get_discovery_session("s-1", "v-1", "Dating")
    assert res is not None
    assert res["id"] == "s-1"
    assert res["tab"] == "Dating"


@patch("app.db.sessions.auth_sessions.supabase_client.table")
def test_get_discovery_session_not_found_returns_none(mock_table: MagicMock) -> None:
    builder = MagicMock()
    builder.select.return_value = builder
    builder.eq.return_value = builder
    builder.maybe_single.return_value = builder
    builder.execute.return_value = MagicMock(data=None)
    mock_table.return_value = builder

    res = get_discovery_session("s-1", "v-1", "Dating")
    assert res is None


@patch("app.db.sessions.auth_sessions.supabase_client.table")
def test_get_discovery_session_malformed_raises_database_access_error(mock_table: MagicMock) -> None:
    builder = MagicMock()
    builder.select.return_value = builder
    builder.eq.return_value = builder
    builder.maybe_single.return_value = builder
    builder.execute.return_value = MagicMock(data="malformed-string-not-dict")
    mock_table.return_value = builder

    with pytest.raises(DatabaseAccessError) as exc_info:
        get_discovery_session("s-1", "v-1", "Dating")
    assert "malformed data" in str(exc_info.value)


@patch("app.db.sessions.auth_sessions.supabase_client.table")
def test_get_discovery_session_by_id_found(mock_table: MagicMock) -> None:
    builder = MagicMock()
    builder.select.return_value = builder
    builder.eq.return_value = builder
    builder.maybe_single.return_value = builder
    builder.execute.return_value = MagicMock(
        data={"id": "s-1", "viewer_id": "v-1", "tab": "Friends", "expires_at": "2026-08-13T19:00:00Z"},
    )
    mock_table.return_value = builder

    res = get_discovery_session_by_id("s-1", "v-1")
    assert res is not None
    assert res["id"] == "s-1"
    assert res["tab"] == "Friends"


@patch("app.db.sessions.auth_sessions.supabase_client.table")
def test_get_discovery_session_by_id_not_found_returns_none(mock_table: MagicMock) -> None:
    builder = MagicMock()
    builder.select.return_value = builder
    builder.eq.return_value = builder
    builder.maybe_single.return_value = builder
    builder.execute.return_value = MagicMock(data=None)
    mock_table.return_value = builder

    res = get_discovery_session_by_id("s-1", "v-1")
    assert res is None


@patch("app.db.sessions.auth_sessions.supabase_client.table")
def test_get_discovery_session_by_id_malformed_raises_database_access_error(mock_table: MagicMock) -> None:
    builder = MagicMock()
    builder.select.return_value = builder
    builder.eq.return_value = builder
    builder.maybe_single.return_value = builder
    builder.execute.return_value = MagicMock(data=["not-a-dict"])
    mock_table.return_value = builder

    with pytest.raises(DatabaseAccessError) as exc_info:
        get_discovery_session_by_id("s-1", "v-1")
    assert "malformed data" in str(exc_info.value)


@patch("app.services.discovery.get_discovery_session")
def test_get_or_validate_session_valid(mock_get_session: MagicMock) -> None:
    future_time = datetime.now(timezone.utc) + timedelta(hours=1)
    mock_get_session.return_value = {
        "id": "sess-123",
        "viewer_id": "user-456",
        "tab": "Dating",
        "expires_at": future_time.isoformat(),
    }
    session_id, expires_at = get_or_validate_session("sess-123", "user-456", "Dating")
    assert session_id == "sess-123"
    assert expires_at == future_time


@patch("app.services.discovery.get_discovery_session")
def test_get_or_validate_session_not_found(mock_get_session: MagicMock) -> None:
    mock_get_session.return_value = None
    with pytest.raises(HTTPException) as exc_info:
        get_or_validate_session("sess-not-exist", "user-456", "Dating")
    assert exc_info.value.status_code == 404


@patch("app.services.discovery.get_discovery_session")
def test_get_or_validate_session_expired(mock_get_session: MagicMock) -> None:
    past_time = datetime.now(timezone.utc) - timedelta(minutes=5)
    mock_get_session.return_value = {
        "id": "sess-123",
        "viewer_id": "user-456",
        "tab": "Dating",
        "expires_at": past_time.isoformat(),
    }
    with pytest.raises(HTTPException) as exc_info:
        get_or_validate_session("sess-123", "user-456", "Dating")
    assert exc_info.value.status_code == 410
    assert "Discovery session expired" in exc_info.value.detail


@patch("app.services.discovery.get_discovery_session")
def test_get_or_validate_session_malformed_expiry_raises_410(mock_get_session: MagicMock) -> None:
    # Non-string, non-datetime object
    mock_get_session.return_value = {
        "id": "sess-123",
        "viewer_id": "user-456",
        "tab": "Dating",
        "expires_at": None,
    }
    with pytest.raises(HTTPException) as exc_info:
        get_or_validate_session("sess-123", "user-456", "Dating")
    assert exc_info.value.status_code == 410
    assert "Discovery session expired" in exc_info.value.detail

    # Malformed datetime string
    mock_get_session.return_value = {
        "id": "sess-123",
        "viewer_id": "user-456",
        "tab": "Dating",
        "expires_at": "not-a-valid-date",
    }
    with pytest.raises(HTTPException) as exc_info:
        get_or_validate_session("sess-123", "user-456", "Dating")
    assert exc_info.value.status_code == 410
    assert "Discovery session expired" in exc_info.value.detail


@patch("app.services.discovery.get_discovery_session")
def test_get_or_validate_session_mismatched_tab_raises_404(mock_get_session: MagicMock) -> None:
    future_time = datetime.now(timezone.utc) + timedelta(hours=1)
    # Session exists for Dating, but active_tab is Friends
    mock_get_session.return_value = {
        "id": "sess-123",
        "viewer_id": "user-456",
        "tab": "Dating",
        "expires_at": future_time.isoformat(),
    }
    with pytest.raises(HTTPException) as exc_info:
        get_or_validate_session("sess-123", "user-456", "Friends")
    assert exc_info.value.status_code == 404
@patch("app.services.discovery.sync_redis_client")
@patch("app.services.discovery.fetch_stage_1_candidates")
def test_create_new_discovery_session_probing_rate_limit(
    mock_fetch_candidates: MagicMock,
    mock_redis: MagicMock,
) -> None:
    from app.models import DiscoveryFilters
    from app.services.discovery import create_new_discovery_session

    # User has mutated sensitive profile fields 4 times
    mock_redis.get.return_value = "4"
    # User tries to create 6th session after mutations
    mock_redis.incr.return_value = 6

    filters = DiscoveryFilters()
    with pytest.raises(HTTPException) as exc_info:
        create_new_discovery_session("user-probe-123", "Dating", filters)

    assert exc_info.value.status_code == 429
    assert "rate limit exceeded" in exc_info.value.detail.lower()


@patch("app.services.discovery.sync_redis_client")
@patch("app.services.discovery.fetch_stage_1_candidates")
def test_create_new_discovery_session_distinct_filter_rate_limit(
    mock_fetch_candidates: MagicMock,
    mock_redis: MagicMock,
) -> None:
    from app.models import DiscoveryFilters
    from app.services.discovery import create_new_discovery_session

    # No mutation probing
    mock_redis.get.return_value = None
    # User has tried >15 distinct filter queries
    mock_redis.scard.return_value = 16

    filters = DiscoveryFilters(religious_beliefs=["Atheist"])
    with pytest.raises(HTTPException) as exc_info:
        create_new_discovery_session("user-probe-filters", "Dating", filters)

    assert exc_info.value.status_code == 429
    assert "filter search rate limit exceeded" in exc_info.value.detail.lower()


@patch("app.services.discovery.sync_redis_client")
@patch("app.services.discovery.fetch_stage_1_candidates")
def test_create_new_discovery_session_rejects_incomplete_profile(
    mock_fetch_candidates: MagicMock,
    mock_redis: MagicMock,
) -> None:
    from app.models import DiscoveryFilters
    from app.services.discovery import create_new_discovery_session

    mock_redis.get.return_value = None
    mock_redis.scard.return_value = 0

    # Viewer has is_dating_active=False
    incomplete_viewer = {
        "id": "viewer-incomplete",
        "name": "Bob",
        "is_dating_active": False,
    }
    mock_fetch_candidates.return_value = (incomplete_viewer, [])

    filters = DiscoveryFilters()
    with pytest.raises(HTTPException) as exc_info:
        create_new_discovery_session("viewer-incomplete", "Dating", filters)

    assert exc_info.value.status_code == 403
    assert "Profile incomplete for Dating tab" in exc_info.value.detail


@patch("app.services.discovery.sync_redis_client")
@patch("app.services.discovery.fetch_stage_1_candidates")
def test_create_new_discovery_session_hourly_rate_limit(
    mock_fetch_candidates: MagicMock,
    mock_redis: MagicMock,
) -> None:
    from app.models import DiscoveryFilters
    from app.services.discovery import create_new_discovery_session

    # Hourly rate limit exceeded (21 > 20)
    mock_redis.incr.return_value = 21

    filters = DiscoveryFilters()
    with pytest.raises(HTTPException) as exc_info:
        create_new_discovery_session("user-heavy-creator", "Dating", filters)

    assert exc_info.value.status_code == 429
    assert "hourly discovery session creation limit exceeded" in exc_info.value.detail.lower()


@patch("app.db.sessions.auth_sessions.prune_excess_viewer_discovery_sessions")
@patch("app.db.sessions.auth_sessions.supabase_client.rpc")
def test_create_discovery_session_deduplicates_candidate_items(
    mock_rpc: MagicMock,
    mock_prune: MagicMock,
) -> None:
    from app.db.sessions.auth_sessions import create_discovery_session

    mock_builder = MagicMock()
    mock_builder.execute.return_value = MagicMock(data="new-session-id-123")
    mock_rpc.return_value = mock_builder

    ranked_items = [
        {"profile": {"id": "cand-1"}, "score": 80.0},
        {"profile": {"id": "cand-2"}, "score": 75.0},
        # Duplicate of cand-1
        {"profile": {"id": "cand-1"}, "score": 90.0},
        {"profile": {"id": "cand-3"}, "score": 70.0},
    ]

    session_id, _ = create_discovery_session(
        viewer_id="viewer-123",
        active_tab="Dating",
        filters={},
        ranked_items=ranked_items,
    )

    assert session_id == "new-session-id-123"
    mock_rpc.assert_called_once()
    call_args = mock_rpc.call_args[0]
    payload = call_args[1]
    items = payload["p_items"]

    assert len(items) == 3
    assert [it["candidate_id"] for it in items] == ["cand-1", "cand-2", "cand-3"]
    assert [it["position"] for it in items] == [0, 1, 2]


@patch("app.services.discovery.sync_redis_client")
@patch("app.services.discovery.fetch_stage_1_candidates")
def test_create_new_discovery_session_rejects_underage_viewer(
    mock_fetch_candidates: MagicMock,
    mock_redis: MagicMock,
) -> None:
    from app.models import DiscoveryFilters
    from app.services.discovery import create_new_discovery_session

    mock_redis.get.return_value = None
    mock_redis.scard.return_value = 0

    underage_viewer = {
        "id": "viewer-underage",
        "name": "Underage User",
        "age": 17,
        "is_dating_active": True,
    }
    mock_fetch_candidates.return_value = (underage_viewer, [])

    filters = DiscoveryFilters()
    with pytest.raises(HTTPException) as exc_info:
        create_new_discovery_session("viewer-underage", "Dating", filters)

    assert exc_info.value.status_code == 403
    assert "underage accounts (age < 18)" in exc_info.value.detail.lower()


@patch("app.services.discovery.sync_redis_client")
@patch("app.services.discovery.fetch_stage_1_candidates")
def test_create_new_discovery_session_rejects_disjoint_search_bucket_filter(
    mock_fetch_candidates: MagicMock,
    mock_redis: MagicMock,
) -> None:
    from app.models import DiscoveryFilters
    from app.services.discovery import create_new_discovery_session

    mock_redis.get.return_value = None
    mock_redis.scard.return_value = 0

    viewer_dating_f = {
        "id": "viewer-seeking-f",
        "name": "Alice",
        "age": 22,
        "is_dating_active": True,
        "dating_target_buckets": ["F"],
    }
    mock_fetch_candidates.return_value = (viewer_dating_f, [])

    # Filter requests "M" which does not intersect with viewer's ["F"] target buckets
    filters = DiscoveryFilters(search_bucket_filter=["M"])
    with pytest.raises(HTTPException) as exc_info:
        create_new_discovery_session("viewer-seeking-f", "Dating", filters)

    assert exc_info.value.status_code == 400
    assert "search_bucket_filter does not intersect" in exc_info.value.detail.lower()






