"""Unit tests for spatial viewport database queries, count operations, and filtering edge cases."""

from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError

from app.db.client import DatabaseAccessError
from app.db.sessions.viewport import (
    _fetch_total_session_items_count,
    _filter_and_sort_viewport_items,
    _query_spatial_viewport,
    fetch_spatial_viewport,
)


@pytest.mark.anyio
async def test_filter_and_sort_viewport_items_skips_and_deactivated():
    """Test filtering of non-dict, missing profile, hard excluded, deactivated, and out-of-radius items."""
    rows = [
        "not-a-dict",
        {"profiles": None},
        {"candidate_id": "c-excluded", "profiles": {"id": "c-excluded"}},
        {"candidate_id": "c-deactivated", "profiles": {"id": "c-deactivated", "is_deactivated": True}},
        {"candidate_id": "c-far", "x": 100.0, "y": 100.0, "profiles": {"id": "c-far", "name": "Far", "is_deactivated": False}},
        {"candidate_id": "c-close", "x": 1.0, "y": 1.0, "score": 85, "orbit_tier": 1, "profiles": {"id": "c-close", "name": "Close", "is_deactivated": False}},
    ]

    with patch("app.db.sessions.viewport.get_cached_active_block_ids", return_value={"c-excluded"}):
        with patch("app.db.sessions.viewport.decrypt_profile_rows", return_value={"c-close": {"name": "Decrypted Close", "profile_pic": "pic.jpg"}}):
            result = await _filter_and_sort_viewport_items(
                rows=rows,
                viewer_id="viewer-1",
                center_x=0.0,
                center_y=0.0,
                radius=5.0,
            )
            assert len(result) == 1
            assert result[0]["id"] == "c-close"
            assert result[0]["name"] == "Decrypted Close"


def test_fetch_total_session_items_count_errors():
    """Test error handling in _fetch_total_session_items_count."""
    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.side_effect = APIError({"code": "500", "message": "count error"})

    with patch("app.db.sessions.viewport.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError, match="Failed to count spatial session items"):
            _fetch_total_session_items_count("sess-1", "viewer-1")

    mock_table.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.side_effect = RuntimeError("network crash")
    with patch("app.db.sessions.viewport.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError, match="Unexpected spatial session count failure"):
            _fetch_total_session_items_count("sess-1", "viewer-1")


def test_query_spatial_viewport_errors():
    """Test error handling in _query_spatial_viewport."""
    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.eq.return_value.gte.return_value.lte.return_value.gte.return_value.lte.return_value.execute.side_effect = APIError({"code": "500", "message": "query error"})

    with patch("app.db.sessions.viewport.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError, match="Failed to fetch spatial viewport"):
            _query_spatial_viewport("sess-1", "viewer-1", -10, 10, -10, 10)

    mock_table.select.return_value.eq.return_value.eq.return_value.gte.return_value.lte.return_value.gte.return_value.lte.return_value.execute.side_effect = RuntimeError("network crash")
    with patch("app.db.sessions.viewport.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError, match="Unexpected spatial viewport fetch failure"):
            _query_spatial_viewport("sess-1", "viewer-1", -10, 10, -10, 10)


@pytest.mark.anyio
async def test_fetch_spatial_viewport_validation_and_clamping():
    """Test validation of non-finite inputs, coordinate clamping, and include_total_count."""
    # 1. Non-finite values raise ValueError
    with pytest.raises(ValueError, match="Spatial viewport parameters.*must be finite floats"):
        await fetch_spatial_viewport("sess-1", "viewer-1", float("nan"), 0.0, 10.0)

    with pytest.raises(ValueError, match="Spatial viewport parameters.*must be finite floats"):
        await fetch_spatial_viewport("sess-1", "viewer-1", 0.0, float("inf"), 10.0)

    with pytest.raises(ValueError, match="Spatial viewport parameters.*must be finite floats"):
        await fetch_spatial_viewport("sess-1", "viewer-1", 0.0, 0.0, float("-inf"))

    # 2. Clamping and include_total_count
    mock_res = MagicMock(data=[])
    with patch("app.db.sessions.viewport._query_spatial_viewport", return_value=mock_res) as mock_query:
        with patch("app.db.sessions.viewport._filter_and_sort_viewport_items", return_value=[]):
            with patch("app.db.sessions.viewport._fetch_total_session_items_count", return_value=42):
                items, count = await fetch_spatial_viewport(
                    session_id="sess-1",
                    viewer_id="viewer-1",
                    center_x=99999.0,   # clamps to 5000.0
                    center_y=-99999.0,  # clamps to -5000.0
                    radius=5000.0,      # clamps to 1000.0
                    include_total_count=True,
                )
                assert count == 42
                assert items == []
                mock_query.assert_called_once_with(
                    "sess-1",
                    "viewer-1",
                    4000.0,
                    6000.0,
                    -6000.0,
                    -4000.0,
                )
