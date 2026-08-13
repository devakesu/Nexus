from unittest.mock import MagicMock, patch
import pytest

from app.db.client import DatabaseAccessError
from app.db.sessions.auth_sessions import (
    get_discovery_session,
    get_discovery_session_by_id,
)


@patch("app.db.sessions.auth_sessions.supabase_client.table")
def test_get_discovery_session_found(mock_table: MagicMock) -> None:
    builder = MagicMock()
    builder.select.return_value = builder
    builder.eq.return_value = builder
    builder.maybe_single.return_value = builder
    builder.execute.return_value = MagicMock(
        data={"id": "s-1", "viewer_id": "v-1", "tab": "Dating", "expires_at": "2026-08-13T19:00:00Z"}
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
        data={"id": "s-1", "viewer_id": "v-1", "tab": "Friends", "expires_at": "2026-08-13T19:00:00Z"}
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
