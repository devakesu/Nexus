"""Test Suite for Test Discovery Db.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.security.crypto import encrypt_to_hex
from app.db.client import (
    DatabaseAccessError,
)
from app.db.discovery.exclusions import (
    _block_ids_cache_key,
    _check_pass_expiry,
    _collect_blocked_counterparty_ids,
    _process_exclusion_row,
    fetch_active_block_ids,
    fetch_active_discovery_excluded_ids,
    fetch_active_like_action,
    fetch_expired_pass_candidates,
    fetch_likes_for_user,
    has_active_discovery_action,
    mark_likes_seen,
    record_discovery_action,
    record_user_report,
    revoke_incoming_like,
    unrevoke_incoming_like,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
USER_3 = "00000000-0000-0000-0000-000000000003"
SESS_1 = "00000000-0000-0000-0000-000000000040"
SESSION_1 = "00000000-0000-0000-0000-000000000020"
ALERT_1 = "00000000-0000-0000-0000-000000000010"
CONV_1 = "00000000-0000-0000-0000-000000000020"
CONVO_1 = "00000000-0000-0000-0000-000000000020"
MATCH_1 = "00000000-0000-0000-0000-000000000010"
MSG_1 = "00000000-0000-0000-0000-000000000020"
PHONE_VALID = "+14155552671"
REPORT_1 = "00000000-0000-0000-0000-000000000050"
EVENT_1 = "00000000-0000-0000-0000-000000000033"
CONTACT_1 = "00000000-0000-0000-0000-000000000030"


def _make_chaining_mock(
    data: Any = None, error: Exception | None = None,
) -> MagicMock:
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
    mock.range.return_value = mock
    mock.contains.return_value = mock
    mock.contained_by.return_value = mock
    mock.overlaps.return_value = mock

    def _exec() -> MagicMock:
        if error:
            raise error
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    def _single() -> MagicMock:
        if error:
            raise error
        if isinstance(data, list) and data:
            return MagicMock(data=copy.deepcopy(data[0]))
        return MagicMock(data=copy.deepcopy(data) if data is not None else None)

    mock.execute = MagicMock(side_effect=_exec)
    single_mock: MagicMock = MagicMock()
    single_mock.execute = MagicMock(side_effect=_single)
    mock.maybe_single.return_value = single_mock
    mock.single.return_value = single_mock
    return mock


def make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/test",
        "headers": [],
        "client": ("127.0.0.1", 12345),
        "app": MagicMock(),
    }
    return Request(scope)


def _make_mock_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "method": "POST",
        "path": "/test",
        "headers": [(b"host", b"localhost"), (b"user-agent", b"pytest")],
        "client": ("127.0.0.1", 12345),
        "app": {},
    }
    return Request(scope)


def make_api_error(code: str = "P0001", message: str = "DB error") -> APIError:
    return APIError(
        {"code": code, "message": message, "details": "details", "hint": "hint"},
    )


pytestmark = pytest.mark.anyio


def test_db_discovery_exclusions_and_matches():
    from app.db.discovery.exclusions import (
        _block_ids_cache_key,
        _check_pass_expiry,
        fetch_active_discovery_excluded_ids,
        fetch_active_like_action,
        record_discovery_action,
    )
    from app.db.discovery.matches import (
        fetch_active_match_between,
        record_match,
        set_match_unmatched,
    )

    mock_t = _make_chaining_mock(
        [
            {
                "id": MATCH_1,
                "tab": "Dating",
                "actor_id": USER_1,
                "target_id": USER_2,
                "action": "like",
                "liker_id": USER_1,
                "liked_back_id": USER_2,
            },
        ],
    )
    now = datetime.now(timezone.utc)

    # 1. exclusions helper logic
    assert _block_ids_cache_key(USER_1) == f"discovery:block_ids:{USER_1}"
    excl: set[str] = set()
    _check_pass_expiry("2026-09-01T00:00:00Z", USER_2, now, excl)
    assert USER_2 in excl

    # 2. fetch_active_discovery_excluded_ids
    with patch(
        "app.db.discovery.exclusions.supabase_client.table", return_value=mock_t,
    ):
        excluded = fetch_active_discovery_excluded_ids(USER_1, "Dating")
        assert isinstance(excluded, set)

    # 3. fetch_active_like_action & record_discovery_action
    with patch(
        "app.db.discovery.exclusions.supabase_client.table", return_value=mock_t,
    ):
        act = fetch_active_like_action(USER_1, USER_2)
        assert act is not None
        record_discovery_action(USER_1, USER_2, "like", "Dating")

    # 4. matches.py
    with patch("app.db.discovery.matches.supabase_client.table", return_value=mock_t):
        m = fetch_active_match_between(USER_1, USER_2)
        assert m is not None
        assert m["id"] == MATCH_1
        rec = record_match(USER_1, USER_2, "Dating")
        assert rec == MATCH_1
        set_match_unmatched(USER_1, USER_2, "Dating")


def test_db_exclusions_and_safety_deep():
    from app.db.discovery.exclusions import (
        _block_ids_cache_key,
        _collect_blocked_counterparty_ids,
        fetch_active_block_ids,
        fetch_active_like_action,
        fetch_likes_for_user,
        mark_likes_seen,
        record_discovery_action,
        revoke_incoming_like,
        unrevoke_incoming_like,
    )
    from app.db.safety.alerts import (
        fetch_contact_facing_profile_summary,
        fetch_recent_safety_alert,
        fetch_safety_alert,
        record_safety_alert,
        update_alert_contacts_notified,
    )
    from app.db.safety.contacts import (
        fetch_safety_contacts,
        fetch_safety_contacts_with_id,
        sync_safety_contacts,
    )
    from app.db.safety.sessions import (
        cancel_safety_escalation,
        fetch_overdue_safety_sessions,
        fetch_safety_session,
        record_safety_escalation_sent,
    )

    encrypted_phone = encrypt_to_hex("+15555555555", category="contact")
    encrypted_name = encrypt_to_hex("Bob", category="contact")
    mock_t = _make_chaining_mock(
        [
            {
                "id": ALERT_1,
                "actor_id": USER_1,
                "target_id": USER_2,
                "action": "block",
                "tab": "Dating",
                "status": "active",
                "name": encrypted_name,
                "phone": encrypted_phone,
            },
        ],
    )

    # 1. exclusions
    with patch(
        "app.db.discovery.exclusions.supabase_client.table", return_value=mock_t,
    ):
        assert _block_ids_cache_key(USER_1) == f"discovery:block_ids:{USER_1}"
        assert _collect_blocked_counterparty_ids(
            [{"actor_id": USER_1, "target_id": USER_2}], USER_1,
        ) == {USER_2}
        b_ids = fetch_active_block_ids(USER_1)
        assert USER_2 in b_ids
        record_discovery_action(USER_1, USER_2, "like", "Dating")
        revoke_incoming_like(USER_1, USER_2)
        unrevoke_incoming_like(USER_1, USER_2)
        mark_likes_seen(USER_1)
        fetch_likes_for_user(USER_1)
        fetch_active_like_action(USER_1, USER_2)

    # 2. safety alerts & contacts & sessions
    def safety_table_factory(table_name: str):
        if table_name == "safety_contacts":
            return _make_chaining_mock(
                [
                    {
                        "id": "c1",
                        "user_id": USER_1,
                        "name": encrypted_name,
                        "phone": encrypted_phone,
                    },
                ],
            )
        return mock_t

    with (
        patch(
            "app.db.safety.alerts.supabase_client.table",
            side_effect=safety_table_factory,
        ),
        patch(
            "app.db.safety.alerts.sign_profile_media", return_value={"name": "Alice"},
        ),
    ):
        record_safety_alert(USER_1, "sos_silent", {"lat": 37.7, "lng": -122.4})
        fetch_safety_alert(ALERT_1)
        fetch_recent_safety_alert(USER_1, "sos_silent")
        update_alert_contacts_notified(ALERT_1, 2)
        fetch_contact_facing_profile_summary(USER_1)

    with (
        patch(
            "app.db.safety.contacts.supabase_client.table",
            side_effect=safety_table_factory,
        ),
        patch("app.db.safety.contacts.supabase_client.rpc") as mock_rpc,
    ):
        mock_rpc.return_value.execute.return_value = MagicMock(
            data={"blocked_indices": [], "newly_notified": []},
        )
        contacts = fetch_safety_contacts(USER_1)
        assert contacts is not None
        c_ids = fetch_safety_contacts_with_id(USER_1)
        assert c_ids is not None
        sync_safety_contacts(USER_1, [{"name": "Bob", "phone": "+15555555555"}])

    with patch("app.db.safety.sessions.supabase_client.table", return_value=mock_t):
        fetch_safety_session(SESS_1)
        fetch_overdue_safety_sessions(300)
        record_safety_escalation_sent(SESS_1, 1)
        cancel_safety_escalation(USER_1, SESS_1, "safe", note=None)


async def test_discovery_exclusions_deep():
    from app.db.discovery.exclusions import (
        _collect_blocked_counterparty_ids,
        _process_exclusion_row,
        fetch_active_block_ids,
        fetch_active_discovery_excluded_ids,
        fetch_active_like_action,
        fetch_expired_pass_candidates,
        fetch_likes_for_user,
        get_cached_active_block_ids,
        has_active_discovery_action,
        invalidate_block_cache,
        mark_likes_seen,
        record_discovery_action,
        record_user_report,
        revoke_incoming_like,
        unrevoke_incoming_like,
    )

    # get_cached_active_block_ids: json decode error
    with (
        patch("app.db.discovery.exclusions.redis_client") as mock_redis,
        patch(
            "app.db.discovery.exclusions.fetch_active_block_ids", return_value={USER_2},
        ),
    ):
        mock_redis.get = AsyncMock(return_value="invalid-json{{")
        mock_redis.set = AsyncMock()
        res = await get_cached_active_block_ids(USER_1)
        assert res == {USER_2}

    # _collect_blocked_counterparty_ids non-dict rows
    assert _collect_blocked_counterparty_ids(["invalid", 123], USER_1) == set()

    # _process_exclusion_row branches
    excluded: set[str] = set()
    now = datetime.now(timezone.utc)
    # missing actor/target
    _process_exclusion_row({}, USER_1, "Dating", now, excluded)
    # actor != viewer for non-block
    _process_exclusion_row(
        {"actor_id": "other", "target_id": "other2", "action": "like", "tab": "Dating"},
        USER_1,
        "Dating",
        now,
        excluded,
    )
    assert len(excluded) == 0

    # fetch_active_discovery_excluded_ids: APIError and Exception
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        mock_sb.table().select().is_().or_().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_active_discovery_excluded_ids(USER_1, "Dating")

        mock_sb.table().select().is_().or_().execute.side_effect = RuntimeError("Fatal")
        with pytest.raises(DatabaseAccessError):
            fetch_active_discovery_excluded_ids(USER_1, "Dating")

    # fetch_active_block_ids: APIError and Exception
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().is_().or_().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_active_block_ids(USER_1)

        mock_sb.table().select().eq().is_().or_().execute.side_effect = RuntimeError(
            "Fatal",
        )
        with pytest.raises(DatabaseAccessError):
            fetch_active_block_ids(USER_1)

    # has_active_discovery_action: Exception returns False
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().eq().is_().limit().execute.side_effect = (
            Exception("DB down")
        )
        assert has_active_discovery_action(USER_1, USER_2, "like") is False

    # record_discovery_action: APIError
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        mock_sb.table().insert().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            record_discovery_action(USER_1, USER_2, "like", "Dating")

    # record_user_report: 23505 code (duplicate report), APIError, auto-block exception
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        err_23505 = APIError({"message": "duplicate", "code": "23505"})
        err_23505.code = "23505"
        mock_sb.table().insert().select().execute.side_effect = err_23505
        # should return silently
        record_user_report(USER_1, USER_2, "spam")

        mock_sb.table().insert().select().execute.side_effect = APIError(
            {"message": "generic fail"},
        )
        with pytest.raises(DatabaseAccessError):
            record_user_report(USER_1, USER_2, "harassment")

        # Auto-block upsert exception
        mock_sb.table().insert().select().execute.side_effect = None
        mock_sb.table().insert().select().execute.return_value = MagicMock(
            data=[{"id": "rep-1"}],
        )
        mock_sb.table().upsert().execute.side_effect = Exception("Upsert block fail")
        record_user_report(USER_1, USER_2, "other")

    # fetch_expired_pass_candidates: non-dict row, non-string expires_at, parse error, and Exception
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        past_time = (now - timedelta(days=2)).isoformat()
        mock_sb.table().select().eq().eq().eq().is_().not_.is_().execute.return_value = MagicMock(
            data=[
                "not-dict",
                {"target_id": None, "expires_at": past_time},
                {"target_id": USER_2, "expires_at": 12345},
                {"target_id": USER_2, "expires_at": "invalid-date-format"},
                {"target_id": USER_2, "expires_at": past_time},
            ],
        )
        res = fetch_expired_pass_candidates(USER_1, "Dating")
        assert USER_2 in res

        mock_sb.table().select().eq().eq().eq().is_().not_.is_().execute.side_effect = (
            Exception("DB error")
        )
        assert fetch_expired_pass_candidates(USER_1, "Dating") == {}

    # invalidate_block_cache: redis delete Exception
    with (
        patch("app.db.discovery.exclusions.redis_client") as mock_redis,
        patch("app.db.sessions.auth_sessions.invalidate_viewer_discovery_sessions"),
    ):
        mock_redis.delete = AsyncMock(side_effect=Exception("Redis delete fail"))
        await invalidate_block_cache(USER_1, USER_2)

    # fetch_likes_for_user & mark_likes_seen & revoke_incoming_like APIErrors
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().in_().is_().eq().order().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_likes_for_user(USER_1)

        mock_sb.table().update().eq().in_().is_().is_().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            mark_likes_seen(USER_1)

        mock_sb.table().update().eq().eq().in_().is_().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            revoke_incoming_like(USER_1, USER_2)

        # unrevoke_incoming_like Exception
        mock_sb.table().update().eq().eq().in_().execute.side_effect = Exception(
            "Unrevoke fail",
        )
        unrevoke_incoming_like(USER_1, USER_2)

    # fetch_active_like_action: invalid uuid fallback & APIError
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().in_().is_().limit().execute.side_effect = (
            APIError({"message": "fail"})
        )
        with pytest.raises(DatabaseAccessError):
            fetch_active_like_action("not-a-uuid-actor", "not-a-uuid-target")


def test_db_discovery_exclusions_operations():
    # 1. Helper functions
    assert _block_ids_cache_key(USER_1) == f"discovery:block_ids:{USER_1}"
    counterparts = _collect_blocked_counterparty_ids(
        [
            {"actor_id": USER_1, "target_id": USER_2},
            {"actor_id": USER_3, "target_id": USER_1},
        ],
        USER_1,
    )
    assert USER_2 in counterparts
    assert USER_3 in counterparts

    # 2. Check pass expiry & process exclusion row
    now = datetime.now(timezone.utc)
    excluded_set: set[str] = set()
    _check_pass_expiry(
        (now + timedelta(hours=2)).isoformat(),
        USER_2,
        now,
        excluded_set,
    )
    assert USER_2 in excluded_set

    # _process_exclusion_row
    ex_row = {
        "action": "pass",
        "actor_id": USER_1,
        "target_id": USER_2,
        "tab": "Dating",
        "expires_at": (now + timedelta(hours=2)).isoformat(),
    }
    _process_exclusion_row(ex_row, USER_1, "Dating", now, excluded_set)
    assert USER_2 in excluded_set

    # 3. Database operations
    mock_table = MagicMock()
    mock_table.select.return_value.is_.return_value.or_.return_value.execute.return_value = MagicMock(
        data=[
            {
                "action": "block",
                "actor_id": USER_1,
                "target_id": USER_3,
                "tab": "Dating",
            },
        ],
    )
    mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(
        data=[],
    )
    with patch(
        "app.db.discovery.exclusions.supabase_client.table", return_value=mock_table,
    ):
        ex_set = fetch_active_discovery_excluded_ids(USER_1, active_tab="Dating")
        assert USER_3 in ex_set

        b_ids = fetch_active_block_ids(USER_1)
        assert isinstance(b_ids, set)

        mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(
            data=[{"id": 1}],
        )
        assert has_active_discovery_action(USER_1, USER_2, "like", tab="Dating") is True

        mock_table.upsert.return_value.execute.return_value = MagicMock(
            data=[{"id": 1}],
        )
        record_discovery_action(USER_1, USER_2, "like")

        mock_table.insert.return_value.execute.return_value = MagicMock(
            data=[{"id": 1}],
        )
        record_user_report(USER_1, USER_2, "harassment", "notes")

        mock_table.select.return_value.eq.return_value.eq.return_value.eq.return_value.is_.return_value.not_.is_.return_value.execute.return_value = MagicMock(
            data=[
                {
                    "target_id": USER_2,
                    "expires_at": (now - timedelta(hours=1)).isoformat(),
                },
            ],
        )
        exp_cands = fetch_expired_pass_candidates(USER_1, active_tab="Dating")
        assert len(exp_cands) == 1

        mock_table.select.return_value.eq.return_value.eq.return_value.in_.return_value.is_.return_value.eq.return_value.order.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[{"id": 1, "actor_id": USER_2}],
        )
        likes = fetch_likes_for_user(USER_1)
        assert len(likes) == 1

        mock_table.update.return_value.eq.return_value.eq.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(
            data=[],
        )
        mark_likes_seen(USER_1, [USER_2])

        mock_table.update.return_value.eq.return_value.eq.return_value.eq.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(
            data=[{"id": 1}],
        )
        rev = revoke_incoming_like(USER_1, USER_2)
        assert rev is True

        unrevoke_incoming_like(USER_1, USER_2)

        mock_table.select.return_value.eq.return_value.eq.return_value.in_.return_value.is_.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[{"id": 1, "action": "like"}],
        )
        assert fetch_active_like_action(USER_1, USER_2) is not None
