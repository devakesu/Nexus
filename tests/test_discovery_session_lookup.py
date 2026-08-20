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
    assert "Discovery session not found" in exc_info.value.detail


