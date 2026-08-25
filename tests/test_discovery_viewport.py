from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request
from pydantic import ValidationError

from app.api.discovery.endpoints import get_discovery_viewport
from app.models import DiscoveryViewportRequest, DiscoveryViewportResponse


def _make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/discover/viewport",
    }
    return Request(scope)


@pytest.mark.anyio
@patch("app.api.discovery.endpoints.fetch_spatial_viewport")
@patch("app.api.discovery.endpoints.get_or_validate_session")
async def test_discovery_viewport_passes_tab_to_session_validation(
    mock_get_or_validate_session: MagicMock,
    mock_fetch_spatial_viewport: AsyncMock,
) -> None:
    session_id = "11111111-1111-1111-1111-111111111111"
    user_id = "22222222-2222-2222-2222-222222222222"
    expires_at = datetime.now(timezone.utc)

    mock_get_or_validate_session.return_value = (session_id, expires_at)
    mock_fetch_spatial_viewport.return_value = (
        [
            {
                "id": "33333333-3333-3333-3333-333333333333",
                "name": "Alice",
                "profile_pic": "https://example.com/pic.jpg",
                "score": 85.5,
                "x": 10.0,
                "y": 20.0,
                "orbit_tier": 1,
            },
        ],
        1,
    )

    payload = DiscoveryViewportRequest(
        tab="Friends",
        session_id=session_id,
        center_x=0.0,
        center_y=0.0,
        radius=500.0,
    )

    response = await get_discovery_viewport(
        request=_make_dummy_request(),
        payload=payload,
        user_id=user_id,
    )

    assert isinstance(response, DiscoveryViewportResponse)
    assert response.session_id == session_id
    assert response.total_nodes == 0  # Coarsened to 0 for pool <= 5
    assert len(response.nodes) == 1
    assert response.nodes[0].name == "Alice"
    assert response.nodes[0].score == 0.0

    mock_get_or_validate_session.assert_called_once_with(
        session_id,
        user_id,
        "Friends",
    )
    mock_fetch_spatial_viewport.assert_called_once_with(
        session_id=session_id,
        viewer_id=user_id,
        center_x=0.0,
        center_y=0.0,
        radius=500.0,
    )


@pytest.mark.anyio
@patch("app.api.discovery.endpoints.get_or_validate_session")
async def test_discovery_viewport_session_validation_error_propagates(
    mock_get_or_validate_session: MagicMock,
) -> None:
    session_id = "11111111-1111-1111-1111-111111111111"
    user_id = "22222222-2222-2222-2222-222222222222"

    mock_get_or_validate_session.side_effect = HTTPException(
        status_code=404,
        detail="Discovery session not found.",
    )

    payload = DiscoveryViewportRequest(
        tab="Dating",
        session_id=session_id,
        center_x=50.0,
        center_y=50.0,
        radius=300.0,
    )

    with pytest.raises(HTTPException) as exc_info:
        await get_discovery_viewport(
            request=_make_dummy_request(),
            payload=payload,
            user_id=user_id,
        )

    assert exc_info.value.status_code == 404
    assert exc_info.value.detail == "Discovery session not found."
    mock_get_or_validate_session.assert_called_once_with(
        session_id,
        user_id,
        "Dating",
    )


def test_discovery_viewport_request_validation() -> None:
    session_id = "11111111-1111-1111-1111-111111111111"

    # Valid requests for all tabs
    for tab in ("Dating", "Friends", "Professional"):
        req = DiscoveryViewportRequest(
            tab=tab,  # type: ignore[arg-type]
            session_id=session_id,
            center_x=0.0,
            center_y=0.0,
            radius=100.0,
        )
        assert req.tab == tab

    # Missing tab should raise ValidationError
    with pytest.raises(ValidationError):
        DiscoveryViewportRequest.model_validate(
            {
                "session_id": session_id,
                "center_x": 0.0,
                "center_y": 0.0,
                "radius": 100.0,
            },
        )

    # Invalid tab should raise ValidationError
    with pytest.raises(ValidationError):
        DiscoveryViewportRequest(
            tab="InvalidTab",  # type: ignore[arg-type]
            session_id=session_id,
            center_x=0.0,
            center_y=0.0,
            radius=100.0,
        )

    # Out of bounds center_x
    with pytest.raises(ValidationError):
        DiscoveryViewportRequest(
            tab="Dating",
            session_id=session_id,
            center_x=99999.0,
            center_y=0.0,
            radius=100.0,
        )

    # Out of bounds center_y
    with pytest.raises(ValidationError):
        DiscoveryViewportRequest(
            tab="Dating",
            session_id=session_id,
            center_x=0.0,
            center_y=-99999.0,
            radius=100.0,
        )


@pytest.mark.anyio
async def test_fetch_spatial_viewport_rejects_nan_and_inf() -> None:
    from app.db.sessions.viewport import fetch_spatial_viewport

    session_id = "11111111-1111-1111-1111-111111111111"
    user_id = "22222222-2222-2222-2222-222222222222"

    with pytest.raises(ValueError, match="must be finite floats"):
        await fetch_spatial_viewport(session_id, user_id, float("nan"), 0.0, 100.0)

    with pytest.raises(ValueError, match="must be finite floats"):
        await fetch_spatial_viewport(session_id, user_id, 0.0, float("inf"), 100.0)

    with pytest.raises(ValueError, match="must be finite floats"):
        await fetch_spatial_viewport(session_id, user_id, 0.0, 0.0, float("nan"))


@pytest.mark.anyio
@patch("app.db.sessions.viewport.get_cached_active_block_ids", new_callable=AsyncMock, return_value=set())
@patch("app.db.sessions.viewport.supabase_client.table")
async def test_fetch_spatial_viewport_clamps_coordinates_and_radius(
    mock_table: MagicMock,
    mock_get_blocks: AsyncMock,
) -> None:
    _ = mock_get_blocks
    from app.db.sessions.viewport import fetch_spatial_viewport

    mock_builder = MagicMock()
    mock_builder.select.return_value = mock_builder
    mock_builder.eq.return_value = mock_builder
    mock_builder.gte.return_value = mock_builder
    mock_builder.lte.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(data=[])
    mock_table.return_value = mock_builder

    session_id = "11111111-1111-1111-1111-111111111111"
    user_id = "22222222-2222-2222-2222-222222222222"

    # Pass excessive center_x, center_y and radius -> should clamp center to 5000.0 and radius to 1000.0
    items, _ = await fetch_spatial_viewport(session_id, user_id, 99999.0, -99999.0, 999999.0)

    assert items == []
    # Clamped center_x: 5000.0 - 1000.0 = 4000.0 to 6000.0
    mock_builder.gte.assert_any_call("x", 4000.0)
    mock_builder.lte.assert_any_call("x", 6000.0)
    # Clamped center_y: -5000.0 - 1000.0 = -6000.0 to -4000.0
    mock_builder.gte.assert_any_call("y", -6000.0)
    mock_builder.lte.assert_any_call("y", -4000.0)


@patch("app.db.sessions.auth_sessions.supabase_client.rpc")
@patch("app.db.sessions.auth_sessions.assign_orbit_positions")
def test_create_discovery_session_derives_spotify_connected_without_extra_db_query(
    mock_assign_positions: MagicMock,
    mock_rpc: MagicMock,
) -> None:
    from app.db.sessions.auth_sessions import create_discovery_session

    mock_assign_positions.return_value = [
        {
            "profile": {"id": "cand-1"},
            "score": 90.0,
            "x": 1.0,
            "y": 2.0,
            "orbit_tier": 1,
            "music_match_grade": 85,
            "viewer_spotify_connected": True,
        },
    ]

    mock_rpc_exec = MagicMock()
    mock_rpc_exec.execute.return_value.data = "session-uuid-123"
    mock_rpc.return_value = mock_rpc_exec

    session_id, _ = create_discovery_session(
        viewer_id="viewer-1",
        active_tab="Dating",
        filters={},
        ranked_items=[{"candidate": {"id": "cand-1"}}],
    )

    assert session_id == "session-uuid-123"
    mock_rpc.assert_called_once()
    args, kwargs = mock_rpc.call_args
    params = kwargs.get("params") or (args[1] if len(args) > 1 else None)
    assert params is not None
    assert params.get("p_viewer_spotify_connected") is True
    assert params.get("p_items")[0]["score"] == 90.0
    assert params.get("p_items")[0]["music_match_grade"] == 10


def test_coarsen_total_nodes() -> None:
    from app.api.discovery.endpoints import _coarsen_total_nodes

    assert _coarsen_total_nodes(0) == 0
    assert _coarsen_total_nodes(-5) == 0
    assert _coarsen_total_nodes(1) == 0
    assert _coarsen_total_nodes(5) == 0
    assert _coarsen_total_nodes(7) == 10
    assert _coarsen_total_nodes(10) == 10
    assert _coarsen_total_nodes(11) == 25
    assert _coarsen_total_nodes(25) == 25
    assert _coarsen_total_nodes(26) == 50
    assert _coarsen_total_nodes(50) == 50
    assert _coarsen_total_nodes(73) == 100
    assert _coarsen_total_nodes(150) == 250
    assert _coarsen_total_nodes(320) == 500
    assert _coarsen_total_nodes(840) == 800


def test_quantize_score() -> None:
    from app.db.discovery.orbit import quantize_score

    assert quantize_score(0.0) == 0.0
    assert quantize_score(0.12) == 0.2
    assert quantize_score(0.38) == 0.4
    assert quantize_score(0.55) == 0.6
    assert quantize_score(0.79) == 0.8
    assert quantize_score(0.96) == 1.0
    assert quantize_score(85.5) == 90.0
    assert quantize_score(72.0) == 70.0


def test_quantize_score_session_noise_deterministic_within_session() -> None:
    from app.db.discovery.orbit import quantize_score

    session_id = "11111111-2222-3333-4444-555555555555"
    candidate_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    score1 = quantize_score(0.65, session_id=session_id, candidate_id=candidate_id)
    score2 = quantize_score(0.65, session_id=session_id, candidate_id=candidate_id)
    assert score1 == score2
    assert 0.1 <= score1 <= 1.0

    score_pct1 = quantize_score(75.0, session_id=session_id, candidate_id=candidate_id)
    score_pct2 = quantize_score(75.0, session_id=session_id, candidate_id=candidate_id)
    assert score_pct1 == score_pct2
    assert 10.0 <= score_pct1 <= 100.0


def test_quantize_score_temporal_noise_varies_across_sessions() -> None:
    from app.db.discovery.orbit import quantize_score

    candidate_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    scores: set[float] = set()
    for i in range(10):
        session_id = f"session-id-variant-{i}"
        scores.add(quantize_score(0.6, session_id=session_id, candidate_id=candidate_id))

    # Across 10 distinct session IDs, noise perturbation should produce multiple tier shifts (0.5, 0.6, 0.7)
    assert len(scores) > 1
    for s in scores:
        assert 0.1 <= s <= 1.0


def test_quantize_score_zero_stays_zero() -> None:
    from app.db.discovery.orbit import quantize_score

    assert quantize_score(0.0, session_id="sess-1", candidate_id="cand-1") == 0.0
    assert quantize_score(-5.0, session_id="sess-1", candidate_id="cand-1") == 0.0


def test_node_to_out_omits_score() -> None:
    from app.api.discovery.endpoints import _node_to_out

    node = {"id": "cand-123", "name": "Alice", "score": 80.0, "x": 10.0, "y": 20.0, "orbit_tier": 1}
    out = _node_to_out(node, session_id="sess-alpha")
    assert out.score == 0.0
    assert out.id == "cand-123"
    assert out.orbit_tier == 1


def test_node_detail_applies_session_noise() -> None:
    from app.db.discovery.orbit import build_tab_aware_orbit_node_detail

    payload = {
        "id": "cand-456",
        "name": "Bob",
        "score": 0.8,
        "session_id": "sess-beta",
        "music_match_grade": 8,
    }
    detail = build_tab_aware_orbit_node_detail("Dating", payload)
    assert 0.1 <= detail.score <= 1.0
    assert detail.id == "cand-456"
    assert detail.music_match_grade == 7


def test_quantize_music_match_grade_tiers() -> None:
    from app.db.discovery.orbit import quantize_music_match_grade

    assert quantize_music_match_grade(None) is None
    assert quantize_music_match_grade("invalid") is None
    assert quantize_music_match_grade(0) == 0
    assert quantize_music_match_grade(1) == 0
    assert quantize_music_match_grade(2) == 0
    assert quantize_music_match_grade(3) == 3
    assert quantize_music_match_grade(4) == 3
    assert quantize_music_match_grade(5) == 3
    assert quantize_music_match_grade(6) == 7
    assert quantize_music_match_grade(7) == 7
    assert quantize_music_match_grade(8) == 7
    assert quantize_music_match_grade(9) == 10
    assert quantize_music_match_grade(10) == 10






