"""Phase 18 Coverage Suite: Comprehensive coverage for app/db/chat/chat.py and app/db/discovery/exclusions.py."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from postgrest.exceptions import APIError

from app.core.security.crypto import DecryptFailedError
from app.db.client import DatabaseAccessError

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"
CONV_1 = "00000000-0000-0000-0000-000000000010"
EVENT_1 = "00000000-0000-0000-0000-000000000020"
MATCH_1 = "00000000-0000-0000-0000-000000000030"


# =============================================================================
# 1. DB CHAT CHAT TESTS
# =============================================================================

def test_chat_create_conversation_errors():
    from app.db.chat.chat import get_or_create_conversation

    mock_match = {"id": MATCH_1, "liker_id": USER_1, "liked_back_id": USER_2, "tab": "Dating"}

    # Case 1: insert returns empty, fallback fetch returns None -> raises DatabaseAccessError
    with patch("app.db.chat.chat.supabase_client") as mock_sb, \
         patch("app.db.chat.chat.fetch_conversation_for_match", return_value=None):
        mock_sb.table().select().eq().is_().maybe_single().execute.return_value = MagicMock(data=mock_match)
        mock_sb.table().upsert().execute.return_value = MagicMock(data=[])
        with pytest.raises(DatabaseAccessError, match="Failed to create conversation"):
            get_or_create_conversation(USER_1, MATCH_1)

    # Case 2: APIError raised during insert -> raises DatabaseAccessError
    with patch("app.db.chat.chat.supabase_client") as mock_sb, \
         patch("app.db.chat.chat.fetch_conversation_for_match", return_value=None):
        mock_sb.table().select().eq().is_().maybe_single().execute.return_value = MagicMock(data=mock_match)
        mock_sb.table().upsert().execute.side_effect = APIError({"message": "DB Error", "code": "500"})
        with pytest.raises(DatabaseAccessError, match="Failed to create conversation"):
            get_or_create_conversation(USER_1, MATCH_1)


def test_chat_media_deletion_helpers():
    from app.db.chat.chat import (
        _collect_user_conv_media_paths,
        batch_delete_conversations_chat_media,
        delete_conversation_chat_media,
        delete_user_chat_media,
    )

    # Empty inputs
    delete_conversation_chat_media("")
    delete_user_chat_media("", [CONV_1])
    delete_user_chat_media(USER_1, [])
    batch_delete_conversations_chat_media([])

    # Exception in _collect_user_conv_media_paths
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.storage.from_().list.side_effect = Exception("Storage timeout")
        res = _collect_user_conv_media_paths(CONV_1, USER_1)
        assert res == []

    # delete_user_chat_media with paths and remove throwing Exception
    with patch("app.db.chat.chat._collect_user_conv_media_paths", return_value=["p1", "p2"]), \
         patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.storage.from_().remove.side_effect = Exception("Remove fail")
        delete_user_chat_media(USER_1, [CONV_1])

    # batch_delete_conversations_chat_media with subdirectories and nested errors
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        # First list returns a root folder (no id, no metadata, no dot in name) and a file
        mock_sb.storage.from_().list.side_effect = [
            [{"name": ""}, {"name": "subfolder"}, {"name": "file.jpg"}],
            Exception("Subfolder list fail"),  # list subfolder fails
            Exception("Storage down"),         # next conv list fails
        ]
        mock_sb.storage.from_().remove.side_effect = Exception("Batch remove failed")
        batch_delete_conversations_chat_media([CONV_1, "conv_2", ""])


def test_chat_close_and_reactivation_errors():
    from app.db.chat.chat import (
        _apply_reactivation_updates,
        _fetch_conversations_for_reactivation,
        close_conversation_for_match_action,
    )

    # close_conversation_for_match_action with APIError
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().update().or_().is_().select().eq().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            close_conversation_for_match_action(USER_1, USER_2, tab="Dating")

    # _fetch_conversations_for_reactivation APIError & generic Exception
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().select().or_().eq().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError, match="Failed to fetch"):
            _fetch_conversations_for_reactivation(USER_1)

        mock_sb.table().select().or_().eq().execute.side_effect = RuntimeError("Fatal")
        with pytest.raises(DatabaseAccessError, match="Unexpected error"):
            _fetch_conversations_for_reactivation(USER_1)

    # _apply_reactivation_updates: APIError and generic Exception on reopen
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().update().in_().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError, match="Failed to reopen"):
            _apply_reactivation_updates(["c1"], [], USER_1)

        mock_sb.table().update().in_().execute.side_effect = RuntimeError("Fatal")
        with pytest.raises(DatabaseAccessError, match="Unexpected error reopening"):
            _apply_reactivation_updates(["c1"], [], USER_1)

        # Exception on blocked update
        mock_sb.table().update().in_().execute.side_effect = Exception("Block fail")
        _apply_reactivation_updates([], ["c2"], USER_1)


def test_chat_share_flags_and_presence():
    from app.db.chat.chat import (
        batch_fetch_presence_from_db,
        batch_fetch_user_share_flags,
        fetch_presence,
        fetch_user_share_flags,
        mark_messages_read,
        upsert_presence_heartbeat,
    )

    # fetch_user_share_flags: data is None fallback & APIError
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=None)
        res = fetch_user_share_flags(USER_1)
        assert res == {"share_active_status": True, "share_read_receipts": True}

        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_user_share_flags(USER_1)

    # batch_fetch_user_share_flags: empty list & APIError
    assert batch_fetch_user_share_flags([]) == {}
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().select().in_().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            batch_fetch_user_share_flags([USER_1])

    # upsert_presence_heartbeat: redis fail -> fallback DB fails with APIError
    with patch("app.db.chat.chat.sync_redis_client") as mock_redis, \
         patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_redis.set.side_effect = Exception("Redis connection closed")
        mock_sb.table().upsert().execute.side_effect = APIError({"message": "DB fail"})
        with pytest.raises(DatabaseAccessError):
            upsert_presence_heartbeat(USER_1, True)

    # fetch_presence: redis error -> DB fallback raises APIError
    with patch("app.db.chat.chat.sync_redis_client") as mock_redis, \
         patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_redis.get.side_effect = Exception("Redis error")
        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError({"message": "DB fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_presence(USER_1)

    # batch_fetch_presence_from_db: empty list & APIError
    assert batch_fetch_presence_from_db([]) == {}
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().select().in_().execute.side_effect = APIError({"message": "DB fail"})
        with pytest.raises(DatabaseAccessError):
            batch_fetch_presence_from_db([USER_1])

    # mark_messages_read: APIError
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().update().eq().neq().is_().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            mark_messages_read(CONV_1, USER_1)


def test_chat_decryption_and_events():
    from app.db.chat.chat import (
        _decrypt_float_field,
        _decrypt_str_field,
        create_event_with_message,
        decrypt_event_row,
        fetch_due_event_reminders,
        fetch_due_safety_reminders,
        fetch_event,
        mark_reminder_sent,
        mark_safety_reminder_sent,
        update_event_status,
    )

    # _decrypt_float_field
    assert _decrypt_float_field(None) is None
    with patch("app.db.chat.chat.decrypt_pii", side_effect=DecryptFailedError("failed")):
        assert _decrypt_float_field("12.34") == 12.34
        assert _decrypt_float_field("not-a-float") is None

    # _decrypt_str_field
    assert _decrypt_str_field(None) is None
    with patch("app.db.chat.chat.decrypt_pii", side_effect=DecryptFailedError("failed")):
        assert _decrypt_str_field("plain-text") == "plain-text"

    # decrypt_event_row
    assert decrypt_event_row(None) is None
    with patch("app.db.chat.chat.decrypt_pii", side_effect=DecryptFailedError("failed")):
        dec = decrypt_event_row({
            "event_time": "2026-08-26T20:00:00Z",
            "location_lat": "40.7128",
            "location_lng": "-74.0060",
            "location_label": "Central Park",
        })
        assert dec is not None
        assert dec["location_lat"] == 40.7128

    # create_event_with_message: insert returned no row & APIError with orphan cleanup APIError
    with patch("app.db.chat.chat.insert_message", return_value={"id": "msg-1"}), \
         patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().insert().execute.return_value = MagicMock(data=[])
        with pytest.raises(DatabaseAccessError, match="Event insert returned no row"):
            create_event_with_message(CONV_1, USER_1, "c", {}, datetime.now(timezone.utc), 1.0, 2.0, "Place")

        # APIError on insert and APIError on cleanup
        mock_sb.table().insert().execute.side_effect = APIError({"message": "event insert fail"})
        mock_sb.table().delete().eq().execute.side_effect = APIError({"message": "cleanup fail"})
        with pytest.raises(DatabaseAccessError, match="Failed to insert event"):
            create_event_with_message(CONV_1, USER_1, "c", {}, datetime.now(timezone.utc), 1.0, 2.0, "Place")

    # fetch_event
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(data=None)
        assert fetch_event(EVENT_1) is None

        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_event(EVENT_1)

    # update_event_status
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().update().eq().select().execute.return_value = MagicMock(data=[])
        assert update_event_status(EVENT_1, "confirmed") is None

        mock_sb.table().update().eq().select().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            update_event_status(EVENT_1, "confirmed")

    # fetch_due_event_reminders & fetch_due_safety_reminders
    now = datetime.now(timezone.utc)
    future_30m = now + timedelta(minutes=30)
    
    def _mock_decrypt_event(r: dict[str, object] | None) -> dict[str, object] | None:
        return r

    with patch("app.db.chat.chat.supabase_client") as mock_sb, \
         patch("app.db.chat.chat.decrypt_event_row", side_effect=_mock_decrypt_event):
        mock_sb.table().select().is_().neq().limit().execute.return_value = MagicMock(
            data=["not-dict", {"id": EVENT_1, "event_time": future_30m}],
        )
        due = fetch_due_event_reminders(window_minutes=60)
        assert len(due) == 1

        mock_sb.table().select().is_().neq().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_due_event_reminders()

        # fetch_due_safety_reminders
        mock_sb.table().select().eq().is_().neq().limit().execute.return_value = MagicMock(
            data=["not-dict", {"id": EVENT_1, "event_time": future_30m}],
        )
        safety_due = fetch_due_safety_reminders(window_minutes=35)
        assert len(safety_due) == 1

        mock_sb.table().select().eq().is_().neq().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_due_safety_reminders()

    # mark_reminder_sent & mark_safety_reminder_sent APIError
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().update().eq().is_().select().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            mark_reminder_sent(EVENT_1)
        with pytest.raises(DatabaseAccessError):
            mark_safety_reminder_sent(EVENT_1)


# =============================================================================
# 2. DB DISCOVERY EXCLUSIONS TESTS
# =============================================================================

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
    with patch("app.db.discovery.exclusions.redis_client") as mock_redis, \
         patch("app.db.discovery.exclusions.fetch_active_block_ids", return_value={USER_2}):
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
    _process_exclusion_row({"actor_id": "other", "target_id": "other2", "action": "like", "tab": "Dating"}, USER_1, "Dating", now, excluded)
    assert len(excluded) == 0

    # fetch_active_discovery_excluded_ids: APIError and Exception
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        mock_sb.table().select().is_().or_().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_active_discovery_excluded_ids(USER_1, "Dating")

        mock_sb.table().select().is_().or_().execute.side_effect = RuntimeError("Fatal")
        with pytest.raises(DatabaseAccessError):
            fetch_active_discovery_excluded_ids(USER_1, "Dating")

    # fetch_active_block_ids: APIError and Exception
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().is_().or_().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_active_block_ids(USER_1)

        mock_sb.table().select().eq().is_().or_().execute.side_effect = RuntimeError("Fatal")
        with pytest.raises(DatabaseAccessError):
            fetch_active_block_ids(USER_1)

    # has_active_discovery_action: Exception returns False
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().eq().is_().limit().execute.side_effect = Exception("DB down")
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

        mock_sb.table().insert().select().execute.side_effect = APIError({"message": "generic fail"})
        with pytest.raises(DatabaseAccessError):
            record_user_report(USER_1, USER_2, "harassment")

        # Auto-block upsert exception
        mock_sb.table().insert().select().execute.side_effect = None
        mock_sb.table().insert().select().execute.return_value = MagicMock(data=[{"id": "rep-1"}])
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

        mock_sb.table().select().eq().eq().eq().is_().not_.is_().execute.side_effect = Exception("DB error")
        assert fetch_expired_pass_candidates(USER_1, "Dating") == {}

    # invalidate_block_cache: redis delete Exception
    with patch("app.db.discovery.exclusions.redis_client") as mock_redis, \
         patch("app.db.sessions.auth_sessions.invalidate_viewer_discovery_sessions"):
        mock_redis.delete = AsyncMock(side_effect=Exception("Redis delete fail"))
        await invalidate_block_cache(USER_1, USER_2)

    # fetch_likes_for_user & mark_likes_seen & revoke_incoming_like APIErrors
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().in_().is_().eq().order().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_likes_for_user(USER_1)

        mock_sb.table().update().eq().in_().is_().is_().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            mark_likes_seen(USER_1)

        mock_sb.table().update().eq().eq().in_().is_().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            revoke_incoming_like(USER_1, USER_2)

        # unrevoke_incoming_like Exception
        mock_sb.table().update().eq().eq().in_().execute.side_effect = Exception("Unrevoke fail")
        unrevoke_incoming_like(USER_1, USER_2)

    # fetch_active_like_action: invalid uuid fallback & APIError
    with patch("app.db.discovery.exclusions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().in_().is_().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_active_like_action("not-a-uuid-actor", "not-a-uuid-target")
