"""Unit tests for db/discovery/matches.py coverage, race conditions, and error recovery."""

from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError

from app.db.client import DatabaseAccessError
from app.db.discovery.matches import (
    fetch_active_match_between,
    fetch_matches_for_user,
    record_match,
    record_mutual_pass,
    set_match_unmatched,
)

UUID_A = "11111111-1111-1111-1111-111111111111"
UUID_B = "22222222-2222-2222-2222-222222222222"


def test_record_match_existing_and_upsert_success():
    """Test record_match when an active match already exists or is newly inserted."""
    # 1. Existing active match
    mock_existing_res = MagicMock(data=[{"id": "match-existing-1"}])
    mock_table = MagicMock()
    mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.limit.return_value.execute.return_value = mock_existing_res

    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table):
        m_id = record_match(UUID_A, UUID_B, tab="Dating")
        assert m_id == "match-existing-1"

    # 2. Newly inserted match
    mock_existing_none = MagicMock(data=[])
    mock_upsert_res = MagicMock(data=[{"id": "match-new-2"}])
    mock_table2 = MagicMock()
    mock_table2.select.return_value.or_.return_value.eq.return_value.is_.return_value.limit.return_value.execute.return_value = mock_existing_none
    mock_table2.upsert.return_value.execute.return_value = mock_upsert_res

    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table2):
        m_id2 = record_match(UUID_A, UUID_B, tab="Dating")
        assert m_id2 == "match-new-2"


def test_record_match_empty_row_and_race_condition():
    """Test record_match empty row error and duplicate 23505 race condition recovery."""
    # 1. Empty row after upsert raises DatabaseAccessError
    mock_empty = MagicMock(data=[])
    mock_table = MagicMock()
    mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.limit.return_value.execute.return_value = mock_empty
    mock_table.upsert.return_value.execute.return_value = mock_empty

    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError, match="Match insert returned no row"):
            record_match(UUID_A, UUID_B)

    # 2. Race condition 23505 recovering winning match
    api_err_23505 = APIError({"code": "23505", "message": "duplicate key value violates unique constraint"})
    mock_win = MagicMock(data=[{"id": "match-race-winner"}])

    mock_table_race = MagicMock()
    mock_table_race.select.return_value.or_.return_value.eq.return_value.is_.return_value.limit.return_value.execute.side_effect = [
        mock_empty,  # initial check
        mock_win,    # race condition recovery
    ]
    mock_table_race.upsert.return_value.execute.side_effect = api_err_23505

    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table_race):
        m_id = record_match(UUID_A, UUID_B)
        assert m_id == "match-race-winner"

    # 3. Unrecoverable API error
    mock_table_err = MagicMock()
    mock_table_err.select.return_value.or_.return_value.eq.return_value.is_.return_value.limit.return_value.execute.return_value = mock_empty
    mock_table_err.upsert.return_value.execute.side_effect = APIError({"code": "42P01", "message": "relation does not exist"})

    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table_err):
        with pytest.raises(DatabaseAccessError, match="Failed to record match"):
            record_match(UUID_A, UUID_B)


def test_fetch_matches_for_user_and_limit_and_error():
    """Test fetch_matches_for_user counterpart mapping, limit warning, and error handling."""
    rows = [
        {"id": "m1", "liker_id": UUID_A, "liked_back_id": UUID_B, "created_at": "2026-08-28T00:00:00Z"},
        {"id": "m2", "liker_id": UUID_B, "liked_back_id": UUID_A, "created_at": "2026-08-27T00:00:00Z"},
    ]
    mock_query = MagicMock()
    mock_query.limit.return_value.execute.return_value = MagicMock(data=rows)
    mock_query.lt.return_value = mock_query

    mock_table = MagicMock()
    mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.order.return_value = mock_query

    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table):
        # Keyset cursor pagination and limit warning test (limit=2 equals row count)
        result = fetch_matches_for_user(UUID_A, tab="Dating", limit=2, before_created_at="2026-08-29T00:00:00Z")
        assert len(result) == 2
        assert result[0]["matched_user_id"] == UUID_B
        assert result[1]["matched_user_id"] == UUID_B

    # APIError test
    mock_table_err = MagicMock()
    mock_table_err.select.return_value.or_.return_value.eq.return_value.is_.return_value.order.return_value.limit.return_value.execute.side_effect = APIError({"code": "500", "message": "query failed"})
    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table_err):
        with pytest.raises(DatabaseAccessError, match="Failed to fetch matches"):
            fetch_matches_for_user(UUID_A)


def test_set_match_unmatched_and_record_mutual_pass():
    """Test set_match_unmatched with/without tab, error handling, and record_mutual_pass."""
    mock_table = MagicMock()
    mock_q = MagicMock()
    mock_table.update.return_value.or_.return_value.is_.return_value = mock_q

    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table):
        # 1. With tab
        set_match_unmatched(UUID_A, UUID_B, tab="Dating")
        mock_q.eq.assert_called_once_with("tab", "Dating")
        mock_q.eq.return_value.execute.assert_called_once()

        # 2. Without tab
        mock_q.reset_mock()
        set_match_unmatched(UUID_A, UUID_B, tab=None)
        mock_q.execute.assert_called_once()

        # 3. APIError
        mock_table.update.return_value.or_.return_value.is_.return_value.execute.side_effect = APIError({"code": "500", "message": "update failed"})
        with pytest.raises(DatabaseAccessError, match="Failed to set match unmatched"):
            set_match_unmatched(UUID_A, UUID_B)

    # 4. record_mutual_pass calls record_discovery_action in both directions
    with patch("app.db.discovery.matches.record_discovery_action") as mock_record_action:
        record_mutual_pass(UUID_A, UUID_B, tab="Dating", days=14)
        assert mock_record_action.call_count == 2


def test_fetch_active_match_between_coverage():
    """Test fetch_active_match_between invalid UUIDs, found/not-found, and APIError."""
    # 1. Invalid UUID returns None
    assert fetch_active_match_between("invalid-uuid", UUID_B) is None
    assert fetch_active_match_between(UUID_A, "not-a-uuid") is None

    # 2. Match found
    mock_res_found = MagicMock(data=[{"id": "match-active", "tab": "Dating"}])
    mock_table = MagicMock()
    mock_table.select.return_value.or_.return_value.is_.return_value.limit.return_value.execute.return_value = mock_res_found

    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table):
        match_dict = fetch_active_match_between(UUID_A, UUID_B)
        assert match_dict is not None
        assert match_dict["id"] == "match-active"

    # 3. Match not found (empty data)
    mock_table_none = MagicMock()
    mock_table_none.select.return_value.or_.return_value.is_.return_value.limit.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table_none):
        assert fetch_active_match_between(UUID_A, UUID_B) is None

    # 4. APIError wraps in DatabaseAccessError
    mock_table_err = MagicMock()
    mock_table_err.select.return_value.or_.return_value.is_.return_value.limit.return_value.execute.side_effect = APIError({"code": "500", "message": "fetch error"})
    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_table_err):
        with pytest.raises(DatabaseAccessError, match="Failed to fetch active match"):
            fetch_active_match_between(UUID_A, UUID_B)
