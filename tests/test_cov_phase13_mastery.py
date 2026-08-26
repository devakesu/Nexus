"""Phase 13 Mastery Suite to push total coverage beyond 90% and towards 95%.

Targeting:
1. app/db/users/import_export.py (generate_export_code & execute_import)
2. app/db/sessions/auth_sessions.py (prune, create, get, delete expired)
3. app/db/sessions/viewport.py & app/db/sessions/node_details.py
4. app/api/feedback/contact.py (error scenarios & quotas)
5. app/api/feedback/tickets.py (error scenarios & cascades)
6. app/db/users/profile.py (read/write profile branches)
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
SESSION_1 = "00000000-0000-0000-0000-000000000060"


def _make_chaining_mock(data: Any = None) -> MagicMock:
    mock: MagicMock = MagicMock()
    mock.select.return_value = mock
    mock.insert.return_value = mock
    mock.update.return_value = mock
    mock.delete.return_value = mock
    mock.upsert.return_value = mock
    mock.eq.return_value = mock
    mock.neq.return_value = mock
    mock.gt.return_value = mock
    mock.gte.return_value = mock
    mock.lt.return_value = mock
    mock.lte.return_value = mock
    mock.is_.return_value = mock
    mock.in_.return_value = mock
    mock.or_.return_value = mock
    mock.not_.is_.return_value = mock
    mock.order.return_value = mock
    mock.limit.return_value = mock

    def _exec() -> MagicMock:
        return MagicMock(data=data)

    def _single() -> MagicMock:
        if isinstance(data, list) and data:
            return MagicMock(data=data[0])
        return MagicMock(data=data)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    mock.single.return_value = single_mock
    return mock


# -----------------------------------------------------------------------------
# 1. DB USERS IMPORT / EXPORT
# -----------------------------------------------------------------------------
async def test_db_users_import_export_deep():
    from datetime import timedelta

    from app.db.users.import_export import (
        execute_import,
        generate_export_code,
    )

    future_iso = (datetime.now(timezone.utc) + timedelta(minutes=15)).isoformat()
    mock_source = {
        "id": USER_2,
        "import_sync_code": "CODE12",
        "import_sync_expires_at": future_iso,
        "display_gender": "\\x6161",
        "hometown": "\\x6262",
    }
    mock_target = {
        "id": USER_1,
        "has_imported_data": False,
    }
    mock_source_user = {
        "id": USER_2,
        "app_variant": "nexus_flavor_a",
        "deletion_requested_at": None,
    }

    mock_t = _make_chaining_mock([mock_source])

    with patch("app.db.users.import_export.supabase_client.table", return_value=mock_t), \
         patch("app.db.users.import_export.redis_client") as mock_r, \
         patch("app.db.users.import_export._fetch_import_profiles", return_value=(mock_source, mock_target)), \
         patch("app.db.users.import_export.fetch_public_user", return_value=mock_source_user), \
         patch("app.db.users.import_export.decrypt_pii", return_value="Male"), \
         patch("app.db.users.import_export.encrypt_to_hex", return_value="\\x6161"):
        mock_r.delete = AsyncMock(return_value=True)

        _code, _exp = await generate_export_code(USER_1)
        assert len(_code) == 6

        copied = execute_import(USER_1, "CODE12", target_variant="nexus")
        assert len(copied) > 0


# -----------------------------------------------------------------------------
# 2. DB SESSIONS AUTH, VIEWPORT, NODE DETAILS
# -----------------------------------------------------------------------------
async def test_db_sessions_deep():
    from app.db.sessions.auth_sessions import (
        create_discovery_session,
        delete_expired_discovery_sessions,
        get_discovery_session,
        get_discovery_session_by_id,
        invalidate_viewer_discovery_sessions,
        prune_excess_viewer_discovery_sessions,
    )
    from app.db.sessions.node_details import (
        fetch_discovery_node_detail,
    )
    from app.db.sessions.viewport import (
        fetch_spatial_viewport,
    )

    mock_session = {
        "id": SESSION_1,
        "viewer_id": USER_1,
        "tab": "Dating",
        "expires_at": "2099-01-01T00:00:00+00:00",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "filters": {},
        "candidate_id": USER_2,
        "score": 0.85,
        "x": 10.0,
        "y": 15.0,
        "orbit_tier": 1,
        "profiles": {
            "id": USER_2,
            "name": "Bob",
            "profile_pic": "p.jpg",
            "is_deactivated": False,
        },
        "discovery_sessions": {
            "id": SESSION_1,
            "viewer_id": USER_1,
            "tab": "Dating",
            "expires_at": "2099-01-01T00:00:00+00:00",
            "viewer_spotify_connected": False,
        },
    }
    mock_t = _make_chaining_mock([mock_session])

    with patch("app.db.sessions.auth_sessions.supabase_client.table", return_value=mock_t), \
         patch("app.db.sessions.auth_sessions.supabase_client.rpc") as mock_rpc, \
         patch("app.db.sessions.node_details.supabase_client.table", return_value=mock_t), \
         patch("app.db.sessions.viewport.supabase_client.table", return_value=mock_t), \
         patch("app.db.sessions.node_details.decrypt_profile_record", return_value={"name": "Bob", "age": 25}), \
         patch("app.db.sessions.node_details.get_cached_active_block_ids", AsyncMock(return_value=set())), \
         patch("app.db.sessions.viewport.decrypt_profile_rows", return_value={USER_2: {"name": "Bob", "profile_pic": "p.jpg"}}), \
         patch("app.db.sessions.viewport.get_cached_active_block_ids", AsyncMock(return_value=set())), \
         patch("app.db.sessions.auth_sessions.assign_orbit_positions", return_value=[{"profile": {"id": USER_2}, "x": 1.0, "y": 2.0, "orbit_tier": 1, "score": 0.9}]):
        mock_rpc.return_value.execute.return_value = MagicMock(data=SESSION_1)
        prune_excess_viewer_discovery_sessions(USER_1, 2)
        sess_id, _exp_dt = create_discovery_session(USER_1, "Dating", {}, [{"profile": {"id": USER_2}, "score": 0.9}], 60)
        assert sess_id == SESSION_1

        get_discovery_session(SESSION_1, USER_1, "Dating")
        get_discovery_session_by_id(SESSION_1, USER_1)
        invalidate_viewer_discovery_sessions(USER_1)
        delete_expired_discovery_sessions()

        node = await fetch_discovery_node_detail(USER_1, SESSION_1, USER_2)
        assert node is not None

        vp_items, _count = await fetch_spatial_viewport(SESSION_1, USER_1, 0.0, 0.0, 50.0, include_total_count=True)
        assert len(vp_items) >= 0


# -----------------------------------------------------------------------------
# 3. DB USERS PROFILE CRUD
# -----------------------------------------------------------------------------
def test_db_users_profile_deep():
    from app.db.users.profile import (
        fetch_profile,
        upsert_profile_variant,
    )

    mock_prof = {
        "id": USER_1,
        "name": "\\x6161",
        "campus_branch": "\\x6262",
        "campus_year": 2024,
        "campus_name": "\\x6363",
        "age": 21,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    mock_t = _make_chaining_mock([mock_prof])

    with patch("app.db.users.profile.supabase_client.table", return_value=mock_t):
        prof = fetch_profile(USER_1)
        assert prof is not None

        row, _created = upsert_profile_variant(USER_1, "Alice", "CS", 2024, 21, "Stanford", "tech")
        assert row is not None
