"""Test Suite for Test Chat Db.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
from datetime import datetime, timedelta, timezone
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.security.crypto import DecryptFailedError, encrypt_to_hex
from app.db.chat.chat import (
    _apply_reactivation_updates,
    _collect_user_conv_media_paths,
    _decrypt_float_field,
    _decrypt_str_field,
    _partition_reactivation_conversations,
    batch_delete_conversations_chat_media,
    batch_fetch_presence_from_db,
    batch_fetch_user_share_flags,
    close_conversation_for_match_action,
    create_event_with_message,
    decrypt_event_row,
    delete_conversation_chat_media,
    delete_user_chat_media,
    fetch_conversation_for_match,
    fetch_conversation_participants,
    fetch_conversations_for_user,
    fetch_due_event_reminders,
    fetch_due_safety_reminders,
    fetch_event,
    fetch_presence,
    fetch_started_match_ids,
    fetch_user_share_flags,
    get_or_create_conversation,
    insert_message,
    mark_messages_read,
    mark_reminder_sent,
    mark_safety_reminder_sent,
    reopen_conversations_for_reactivation,
    update_event_status,
    upsert_presence_heartbeat,
)
from app.db.chat.keys import (
    bulk_insert_one_time_prekeys,
    count_unused_one_time_prekeys,
    fetch_active_matches_for_targets,
    fetch_identity_key,
    fetch_key_bundle,
    fetch_x3dh_key_bundle_unified,
    has_active_match,
    mark_session_established,
    upsert_identity_key,
    upsert_signed_prekey,
)
from app.db.client import (
    ConversationClosedError,
    DatabaseAccessError,
    ProfileNotFoundError,
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


def test_db_chat_edge_cases():
    from app.db.chat.chat import (
        _apply_reactivation_updates,
        _collect_user_conv_media_paths,
        _partition_reactivation_conversations,
        create_event_with_message,
        insert_message,
        update_event_status,
    )

    # 1. insert_message error cases
    mock_table = MagicMock()
    mock_table.insert.return_value.execute.side_effect = APIError(
        {"message": "closed conversation"},
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(ConversationClosedError):
            insert_message(CONV_1, USER_1, "signal_text", "cipher", {})

    mock_table.insert.return_value.execute.side_effect = APIError(
        {"message": "random db error"},
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError):
            insert_message(CONV_1, USER_1, "signal_text", "cipher", {})

    # 2. _collect_user_conv_media_paths exception
    mock_storage = MagicMock()
    mock_storage.list.side_effect = Exception("Storage error")
    with patch(
        "app.db.chat.chat.supabase_client.storage.from_", return_value=mock_storage,
    ):
        paths = _collect_user_conv_media_paths(CONV_1, USER_1)
        assert paths == []

    # 3. _partition_reactivation_conversations & _apply_reactivation_updates
    rows = [
        {"id": "c1", "user_a_id": USER_1, "user_b_id": USER_2, "match_id": "m1"},
        {"id": "c2", "user_a_id": USER_2, "user_b_id": USER_1, "match_id": "m2"},
    ]
    with patch(
        "app.db.discovery.exclusions.fetch_active_block_ids", return_value={USER_2},
    ):
        reopen, blocked = _partition_reactivation_conversations(rows, USER_1)
        assert reopen == []
        assert blocked == ["c1", "c2"]

    mock_table.update.return_value.in_.return_value.execute.return_value = MagicMock(
        data=[],
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        _apply_reactivation_updates(["c1"], ["c2"], USER_1)

    # 4. create_event_with_message error handling & rollback
    mock_table.insert.return_value.execute.side_effect = APIError(
        {"message": "Event insert failed"},
    )
    mock_table.delete.return_value.eq.return_value.execute.return_value = MagicMock()
    with (
        patch("app.db.chat.chat.insert_message", return_value={"id": "m99"}),
        patch("app.db.chat.chat.supabase_client.table", return_value=mock_table),
    ):
        with pytest.raises(DatabaseAccessError):
            create_event_with_message(
                CONV_1,
                USER_1,
                "cipher",
                {},
                datetime.now(timezone.utc),
                None,
                None,
                None,
            )

    # 5. update_event_status not found
    mock_table.update.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(
        data=[],
    )
    mock_table.update.return_value.eq.return_value.select.return_value.execute.side_effect = None
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        res = update_event_status("ev_none", "cancelled")
        assert res is None


def test_db_chat_keys_edge_cases():
    from app.db.chat.keys import (
        _from_bytea,
        _to_bytea_hex,
        bulk_insert_one_time_prekeys,
        count_unused_one_time_prekeys,
        fetch_identity_key,
        fetch_key_bundle,
        fetch_x3dh_key_bundle_unified,
        mark_session_established,
        upsert_identity_key,
        upsert_signed_prekey,
    )

    # 1. Bytea helpers
    assert _to_bytea_hex(b"hello") == "\\x68656c6c6f"
    assert _from_bytea("\\x68656c6c6f") == b"hello"
    assert _from_bytea(b"hello") == b"hello"

    mock_table = MagicMock()
    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[])
    mock_table.delete.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[],
    )
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[],
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        upsert_identity_key(USER_1, b"pubkey32bytes0000000000000000000", 12345)

    # 2. Signed prekey upsert
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data=None)
    with patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_rpc):
        upsert_signed_prekey(USER_1, 1, b"pubkey", b"sig")

    # 3. count_unused_one_time_prekeys
    mock_table.select.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(
        count=15,
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        count = count_unused_one_time_prekeys(USER_1)
        assert count == 15

    # 4. bulk_insert_one_time_prekeys
    bulk_insert_one_time_prekeys(USER_1, [])
    mock_table.insert.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"pub"}])

    # 5. mark_session_established
    mock_table.update.return_value.eq.return_value.or_.return_value.execute.return_value = MagicMock(
        data=[],
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        mark_session_established(USER_1, CONV_1)

    # 6. Key bundle fetches
    mock_key_t = _make_chaining_mock(
        [
            {
                "identity_public_key": "\\x68656c6c6f",
                "registration_id": 123,
                "key_id": 1,
                "public_key": "\\x68656c6c6f",
                "signature": "\\x68656c6c6f",
            },
        ],
    )
    mock_claim_rpc = MagicMock()
    mock_claim_rpc.execute.return_value = MagicMock(
        data=[{"key_id": 9, "public_key": "\\x68656c6c6f"}],
    )
    with (
        patch("app.db.chat.keys.supabase_client.table", return_value=mock_key_t),
        patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_claim_rpc),
    ):
        ident = fetch_identity_key(USER_1)
        assert ident is not None
        bundle = fetch_key_bundle(USER_1)
        assert bundle is not None
        u_bundle, u_err = fetch_x3dh_key_bundle_unified(USER_1, USER_2)
        assert u_bundle is not None or u_err is not None


def test_db_chat_deep():
    from app.db.chat.chat import (
        _apply_reactivation_updates,
        _partition_reactivation_conversations,
        batch_delete_conversations_chat_media,
        batch_fetch_presence_from_db,
        batch_fetch_user_share_flags,
        close_conversation_for_match_action,
        delete_conversation_chat_media,
        delete_user_chat_media,
        fetch_due_event_reminders,
        fetch_due_safety_reminders,
        fetch_presence,
        fetch_started_match_ids,
        fetch_user_share_flags,
        get_or_create_conversation,
        mark_reminder_sent,
        mark_safety_reminder_sent,
        reopen_conversations_for_reactivation,
        upsert_presence_heartbeat,
    )

    mock_t = _make_chaining_mock(
        [
            {
                "id": CONV_1,
                "user_a_id": USER_1,
                "user_b_id": USER_2,
                "match_id": MATCH_1,
                "tab": "Dating",
                "closed_at": None,
                "is_online": True,
                "last_seen_at": datetime.now(timezone.utc).isoformat(),
            },
        ],
    )

    # 1. media removal helpers
    with patch("app.db.chat.chat.supabase_client.storage.from_") as mock_storage:
        mock_storage.return_value.list.return_value = [{"name": "img.png"}]
        mock_storage.return_value.remove.return_value = True
        delete_conversation_chat_media(CONV_1)
        delete_user_chat_media(USER_1, [CONV_1])
        batch_delete_conversations_chat_media([CONV_1])

    # 2. get or create conv & events
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_t):
        conv = get_or_create_conversation(USER_1, MATCH_1)
        assert conv is not None
        close_conversation_for_match_action(USER_1, USER_2, "Dating", reason="unmatch")

        # Reactivation partition
        reopen_ids, blocked_ids = _partition_reactivation_conversations(
            [{"id": CONV_1, "user_a_id": USER_1, "user_b_id": USER_2}],
            USER_1,
        )
        _apply_reactivation_updates(reopen_ids, blocked_ids, USER_1)
        reopen_conversations_for_reactivation(USER_1)

        # Presence & flags
        pres = fetch_presence(USER_1)
        assert pres is not None
        b_pres = batch_fetch_presence_from_db([USER_1, USER_2])
        assert b_pres is not None
        flags = fetch_user_share_flags(USER_1)
        assert flags is not None
        b_flags = batch_fetch_user_share_flags([USER_1, USER_2])
        assert b_flags is not None
        upsert_presence_heartbeat(USER_1, is_online=True)

        # Reminders & matches
        fetch_due_event_reminders(30)
        fetch_due_safety_reminders(30)
        mark_reminder_sent("e1")
        mark_safety_reminder_sent("e1")
        fetch_started_match_ids(USER_1)


def test_db_chat_keys_and_errors():
    from app.db.chat.keys import (
        bulk_insert_one_time_prekeys,
        count_unused_one_time_prekeys,
        fetch_active_matches_for_targets,
        fetch_identity_key,
        fetch_key_bundle,
        fetch_x3dh_key_bundle_unified,
        has_active_match,
        upsert_identity_key,
        upsert_signed_prekey,
    )
    from app.db.client import DatabaseAccessError

    mock_row = {
        "id": "k1",
        "key_id": 1,
        "public_key": "\\x6161",
        "signature": "\\x6262",
        "identity_public_key": "\\x6363",
        "registration_id": 12345,
    }
    mock_ok = _make_chaining_mock([mock_row])
    mock_err = _make_chaining_mock(error=APIError({"message": "DB error"}))

    # Success paths
    with (
        patch("app.db.chat.keys.supabase_client.table", return_value=mock_ok),
        patch("app.db.chat.keys.supabase_client.rpc") as mock_rpc,
    ):
        mock_rpc.return_value.execute.return_value = MagicMock(
            data=[{"key_id": 1, "public_key": "\\x6161"}],
        )
        upsert_identity_key(USER_1, b"x" * 32, 12345)
        fetch_identity_key(USER_1)
        upsert_signed_prekey(USER_1, 1, b"x" * 32, b"s" * 64)
        bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"x" * 32}])
        count_unused_one_time_prekeys(USER_1)
        has_active_match(USER_1, USER_2)
        fetch_active_matches_for_targets(USER_1, [USER_2])
        fetch_key_bundle(USER_1)
        fetch_x3dh_key_bundle_unified(USER_1, USER_2)

    # Error / exception handling paths
    with (
        patch("app.db.chat.keys.supabase_client.table", return_value=mock_err),
        patch(
            "app.db.chat.keys.supabase_client.rpc",
            side_effect=APIError({"message": "DB error"}),
        ),
    ):
        with pytest.raises(DatabaseAccessError):
            upsert_identity_key(USER_1, b"x" * 32, 12345)
        with pytest.raises(DatabaseAccessError):
            fetch_identity_key(USER_1)
        with pytest.raises(DatabaseAccessError):
            upsert_signed_prekey(USER_1, 1, b"x" * 32, b"s" * 64)
        with pytest.raises(DatabaseAccessError):
            bulk_insert_one_time_prekeys(
                USER_1, [{"key_id": 1, "public_key": b"x" * 32}],
            )
        with pytest.raises(DatabaseAccessError):
            count_unused_one_time_prekeys(USER_1)
        with pytest.raises(DatabaseAccessError):
            has_active_match(USER_1, USER_2)
        with pytest.raises(DatabaseAccessError):
            fetch_active_matches_for_targets(USER_1, [USER_2])
        with pytest.raises(DatabaseAccessError):
            fetch_key_bundle(USER_1)


def test_db_chat_edge_cases_p9():
    from app.db.chat.chat import (
        create_event_with_message,
        decrypt_event_row,
        fetch_conversation_for_match,
        fetch_conversation_participants,
        fetch_conversations_for_user,
        fetch_event,
        insert_message,
        mark_messages_read,
    )
    from app.db.client import DatabaseAccessError

    mock_row = {
        "id": CONV_1,
        "user_a_id": USER_1,
        "user_b_id": USER_2,
        "match_id": "m1",
        "tab": "Dating",
        "closed_at": None,
        "content": encrypt_to_hex("Hello", category="chat"),
        "title": encrypt_to_hex("Coffee Date", category="chat"),
        "location": encrypt_to_hex("Cafe", category="chat"),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    mock_ok = _make_chaining_mock([mock_row])
    mock_err = _make_chaining_mock(error=APIError({"message": "DB error"}))

    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_ok):
        fetch_conversations_for_user(USER_1)
        fetch_conversation_for_match("m1")
        fetch_conversation_participants(CONV_1)
        insert_message(CONV_1, USER_1, "text", "msg_bytes", {})
        create_event_with_message(
            CONV_1,
            USER_1,
            "event_bytes",
            {},
            datetime.now(timezone.utc),
            37.7,
            -122.4,
            "Cafe",
            True,
            1800,
        )
        fetch_event("e1")
        mark_messages_read(CONV_1, USER_1)
        decrypt_event_row(mock_row)

    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_err):
        with pytest.raises(DatabaseAccessError):
            fetch_conversations_for_user(USER_1)
        with pytest.raises(DatabaseAccessError):
            fetch_conversation_for_match("m1")
        with pytest.raises(DatabaseAccessError):
            fetch_conversation_participants(CONV_1)
        with pytest.raises(DatabaseAccessError):
            insert_message(CONV_1, USER_1, "text", "msg_bytes", {})
        with pytest.raises(DatabaseAccessError):
            create_event_with_message(
                CONV_1,
                USER_1,
                "event_bytes",
                {},
                datetime.now(timezone.utc),
                37.7,
                -122.4,
                "Cafe",
                True,
                1800,
            )
        with pytest.raises(DatabaseAccessError):
            fetch_event("e1")
        with pytest.raises(DatabaseAccessError):
            mark_messages_read(CONV_1, USER_1)


def test_chat_create_conversation_errors():
    from app.db.chat.chat import get_or_create_conversation

    mock_match = {
        "id": MATCH_1,
        "liker_id": USER_1,
        "liked_back_id": USER_2,
        "tab": "Dating",
    }

    # Case 1: insert returns empty, fallback fetch returns None -> raises DatabaseAccessError
    with (
        patch("app.db.chat.chat.supabase_client") as mock_sb,
        patch("app.db.chat.chat.fetch_conversation_for_match", return_value=None),
    ):
        mock_sb.table().select().eq().is_().maybe_single().execute.return_value = (
            MagicMock(data=mock_match)
        )
        mock_sb.table().upsert().execute.return_value = MagicMock(data=[])
        with pytest.raises(DatabaseAccessError, match="Failed to create conversation"):
            get_or_create_conversation(USER_1, MATCH_1)

    # Case 2: APIError raised during insert -> raises DatabaseAccessError
    with (
        patch("app.db.chat.chat.supabase_client") as mock_sb,
        patch("app.db.chat.chat.fetch_conversation_for_match", return_value=None),
    ):
        mock_sb.table().select().eq().is_().maybe_single().execute.return_value = (
            MagicMock(data=mock_match)
        )
        mock_sb.table().upsert().execute.side_effect = APIError(
            {"message": "DB Error", "code": "500"},
        )
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
    with (
        patch(
            "app.db.chat.chat._collect_user_conv_media_paths", return_value=["p1", "p2"],
        ),
        patch("app.db.chat.chat.supabase_client") as mock_sb,
    ):
        mock_sb.storage.from_().remove.side_effect = Exception("Remove fail")
        delete_user_chat_media(USER_1, [CONV_1])

    # batch_delete_conversations_chat_media with subdirectories and nested errors
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        # First list returns a root folder (no id, no metadata, no dot in name) and a file
        mock_sb.storage.from_().list.side_effect = [
            [{"name": ""}, {"name": "subfolder"}, {"name": "file.jpg"}],
            Exception("Subfolder list fail"),  # list subfolder fails
            Exception("Storage down"),  # next conv list fails
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
        mock_sb.table().update().or_().is_().select().eq().execute.side_effect = (
            APIError({"message": "fail"})
        )
        with pytest.raises(DatabaseAccessError):
            close_conversation_for_match_action(USER_1, USER_2, tab="Dating")

    # _fetch_conversations_for_reactivation APIError & generic Exception
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().select().or_().eq().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError, match="Failed to fetch"):
            _fetch_conversations_for_reactivation(USER_1)

        mock_sb.table().select().or_().eq().execute.side_effect = RuntimeError("Fatal")
        with pytest.raises(DatabaseAccessError, match="Unexpected error"):
            _fetch_conversations_for_reactivation(USER_1)

    # _apply_reactivation_updates: APIError and generic Exception on reopen
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().update().in_().execute.side_effect = APIError(
            {"message": "fail"},
        )
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
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        res = fetch_user_share_flags(USER_1)
        assert res == {"share_active_status": True, "share_read_receipts": True}

        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_user_share_flags(USER_1)

    # batch_fetch_user_share_flags: empty list & APIError
    assert batch_fetch_user_share_flags([]) == {}
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().select().in_().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            batch_fetch_user_share_flags([USER_1])

    # upsert_presence_heartbeat: redis fail -> fallback DB fails with APIError
    with (
        patch("app.db.chat.chat.sync_redis_client") as mock_redis,
        patch("app.db.chat.chat.supabase_client") as mock_sb,
    ):
        mock_redis.set.side_effect = Exception("Redis connection closed")
        mock_sb.table().upsert().execute.side_effect = APIError({"message": "DB fail"})
        with pytest.raises(DatabaseAccessError):
            upsert_presence_heartbeat(USER_1, True)

    # fetch_presence: redis error -> DB fallback raises APIError
    with (
        patch("app.db.chat.chat.sync_redis_client") as mock_redis,
        patch("app.db.chat.chat.supabase_client") as mock_sb,
    ):
        mock_redis.get.side_effect = Exception("Redis error")
        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError(
            {"message": "DB fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_presence(USER_1)

    # batch_fetch_presence_from_db: empty list & APIError
    assert batch_fetch_presence_from_db([]) == {}
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().select().in_().execute.side_effect = APIError(
            {"message": "DB fail"},
        )
        with pytest.raises(DatabaseAccessError):
            batch_fetch_presence_from_db([USER_1])

    # mark_messages_read: APIError
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().update().eq().neq().is_().execute.side_effect = APIError(
            {"message": "fail"},
        )
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
    with patch(
        "app.db.chat.chat.decrypt_pii", side_effect=DecryptFailedError("failed"),
    ):
        assert _decrypt_float_field("12.34") == 12.34
        assert _decrypt_float_field("not-a-float") is None

    # _decrypt_str_field
    assert _decrypt_str_field(None) is None
    with patch(
        "app.db.chat.chat.decrypt_pii", side_effect=DecryptFailedError("failed"),
    ):
        assert _decrypt_str_field("plain-text") == "plain-text"

    # decrypt_event_row
    assert decrypt_event_row(None) is None
    with patch(
        "app.db.chat.chat.decrypt_pii", side_effect=DecryptFailedError("failed"),
    ):
        dec = decrypt_event_row(
            {
                "event_time": "2026-08-26T20:00:00Z",
                "location_lat": "40.7128",
                "location_lng": "-74.0060",
                "location_label": "Central Park",
            },
        )
        assert dec is not None
        assert dec["location_lat"] == 40.7128

    # create_event_with_message: insert returned no row & APIError with orphan cleanup APIError
    with (
        patch("app.db.chat.chat.insert_message", return_value={"id": "msg-1"}),
        patch("app.db.chat.chat.supabase_client") as mock_sb,
    ):
        mock_sb.table().insert().execute.return_value = MagicMock(data=[])
        with pytest.raises(DatabaseAccessError, match="Event insert returned no row"):
            create_event_with_message(
                CONV_1, USER_1, "c", {}, datetime.now(timezone.utc), 1.0, 2.0, "Place",
            )

        # APIError on insert and APIError on cleanup
        mock_sb.table().insert().execute.side_effect = APIError(
            {"message": "event insert fail"},
        )
        mock_sb.table().delete().eq().execute.side_effect = APIError(
            {"message": "cleanup fail"},
        )
        with pytest.raises(DatabaseAccessError, match="Failed to insert event"):
            create_event_with_message(
                CONV_1, USER_1, "c", {}, datetime.now(timezone.utc), 1.0, 2.0, "Place",
            )

    # fetch_event
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        assert fetch_event(EVENT_1) is None

        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_event(EVENT_1)

    # update_event_status
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().update().eq().select().execute.return_value = MagicMock(data=[])
        assert update_event_status(EVENT_1, "confirmed") is None

        mock_sb.table().update().eq().select().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            update_event_status(EVENT_1, "confirmed")

    # fetch_due_event_reminders & fetch_due_safety_reminders
    now = datetime.now(timezone.utc)
    future_30m = now + timedelta(minutes=30)

    def _mock_decrypt_event(r: dict[str, object] | None) -> dict[str, object] | None:
        return r

    with (
        patch("app.db.chat.chat.supabase_client") as mock_sb,
        patch("app.db.chat.chat.decrypt_event_row", side_effect=_mock_decrypt_event),
    ):
        mock_sb.table().select().is_().neq().limit().execute.return_value = MagicMock(
            data=["not-dict", {"id": EVENT_1, "event_time": future_30m}],
        )
        due = fetch_due_event_reminders(window_minutes=60)
        assert len(due) == 1

        mock_sb.table().select().is_().neq().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_due_event_reminders()

        # fetch_due_safety_reminders
        mock_sb.table().select().eq().is_().neq().limit().execute.return_value = (
            MagicMock(
                data=["not-dict", {"id": EVENT_1, "event_time": future_30m}],
            )
        )
        safety_due = fetch_due_safety_reminders(window_minutes=35)
        assert len(safety_due) == 1

        mock_sb.table().select().eq().is_().neq().limit().execute.side_effect = (
            APIError({"message": "fail"})
        )
        with pytest.raises(DatabaseAccessError):
            fetch_due_safety_reminders()

    # mark_reminder_sent & mark_safety_reminder_sent APIError
    with patch("app.db.chat.chat.supabase_client") as mock_sb:
        mock_sb.table().update().eq().is_().select().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            mark_reminder_sent(EVENT_1)
        with pytest.raises(DatabaseAccessError):
            mark_safety_reminder_sent(EVENT_1)


def test_db_chat_keys_deep():
    from app.db.chat.keys import (
        _from_bytea,
        bulk_insert_one_time_prekeys,
        count_unused_one_time_prekeys,
        fetch_active_matches_for_targets,
        fetch_identity_key,
        fetch_key_bundle,
        fetch_x3dh_key_bundle_unified,
        has_active_match,
        mark_session_established,
        upsert_identity_key,
        upsert_signed_prekey,
    )

    # _from_bytea representations
    assert _from_bytea(memoryview(b"abc")) == b"abc"
    assert _from_bytea(b"abc") == b"abc"
    assert _from_bytea("\\x616263") == b"abc"
    with pytest.raises(DatabaseAccessError):
        _from_bytea(12345)

    # upsert_identity_key: 23503 error, generic APIError, user_devices exception
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().upsert().execute.side_effect = make_api_error("23503")
        with pytest.raises(ProfileNotFoundError):
            upsert_identity_key(USER_1, b"key", 1)

        mock_sb.table().upsert().execute.side_effect = make_api_error("P0001")
        with pytest.raises(DatabaseAccessError):
            upsert_identity_key(USER_1, b"key", 1)

        mock_sb.table().upsert().execute.side_effect = None
        mock_sb.table().delete().eq().execute.return_value = MagicMock()
        mock_sb.table().update().eq().execute.side_effect = Exception("device fail")
        upsert_identity_key(USER_1, b"key", 1)

    # fetch_identity_key: None row, APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        assert fetch_identity_key(USER_1) is None

        mock_sb.table().select().eq().maybe_single().execute.side_effect = (
            make_api_error()
        )
        with pytest.raises(DatabaseAccessError):
            fetch_identity_key(USER_1)

    # upsert_signed_prekey: 23503, generic APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.rpc().execute.side_effect = make_api_error("23503")
        with pytest.raises(ProfileNotFoundError):
            upsert_signed_prekey(USER_1, 1, b"pub", b"sig")

        mock_sb.rpc().execute.side_effect = make_api_error("P0001")
        with pytest.raises(DatabaseAccessError):
            upsert_signed_prekey(USER_1, 1, b"pub", b"sig")

    # bulk_insert_one_time_prekeys: empty, 23503, generic APIError
    bulk_insert_one_time_prekeys(USER_1, [])
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().insert().execute.side_effect = make_api_error("23503")
        with pytest.raises(ProfileNotFoundError):
            bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"pub"}])

        mock_sb.table().insert().execute.side_effect = make_api_error("P0001")
        with pytest.raises(DatabaseAccessError):
            bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"pub"}])

    # count_unused_one_time_prekeys: APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().select().eq().is_().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            count_unused_one_time_prekeys(USER_1)

    # has_active_match: APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().select().or_().is_().limit().execute.side_effect = (
            make_api_error()
        )
        with pytest.raises(DatabaseAccessError):
            has_active_match(USER_1, USER_2)

    # fetch_active_matches_for_targets: empty, APIError
    assert fetch_active_matches_for_targets(USER_1, []) == set()
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().select().or_().is_().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            fetch_active_matches_for_targets(USER_1, [USER_2])

    # fetch_key_bundle: identity not found, signed prekey not found, APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        assert fetch_key_bundle(USER_1) is None

        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data={"identity_public_key": b"ID", "registration_id": 123},
        )
        mock_sb.table().select().eq().is_().order().limit().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        assert fetch_key_bundle(USER_1) is None

        mock_sb.table().select().eq().maybe_single().execute.side_effect = (
            make_api_error()
        )
        with pytest.raises(DatabaseAccessError):
            fetch_key_bundle(USER_1)

    # fetch_x3dh_key_bundle_unified: rpc error field, fallback not matched, fallback identity not found
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.rpc().execute.return_value = MagicMock(data={"error": "NOT_MATCHED"})
        b, err = fetch_x3dh_key_bundle_unified(USER_1, USER_2)
        assert b is None
        assert err == "NOT_MATCHED"

        mock_sb.rpc().execute.side_effect = Exception("RPC failed")
        with patch("app.db.chat.keys.has_active_match", return_value=False):
            b_fallback, err_fallback = fetch_x3dh_key_bundle_unified(USER_1, USER_2)
            assert b_fallback is None
            assert err_fallback == "NOT_MATCHED"

        with (
            patch("app.db.chat.keys.has_active_match", return_value=True),
            patch("app.db.chat.keys.fetch_key_bundle", return_value=None),
        ):
            b_none, err_none = fetch_x3dh_key_bundle_unified(USER_1, USER_2)
            assert b_none is None
            assert err_none == "IDENTITY_NOT_FOUND"

    # mark_session_established: APIError
    with patch("app.db.chat.keys.supabase_client") as mock_sb:
        mock_sb.table().update().eq().or_().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            mark_session_established(USER_1, CONV_1)


def test_db_chat_conversations_and_messages():
    mock_table = MagicMock()

    # 1. fetch_conversation_for_match APIError
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.side_effect = APIError(
        {"message": "DB error"},
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(DatabaseAccessError):
            fetch_conversation_for_match(MATCH_1)

    # 2. get_or_create_conversation
    existing_conv = {
        "id": CONV_1,
        "user_a_id": USER_2,
        "user_b_id": USER_3,
        "match_id": MATCH_1,
    }
    with patch(
        "app.db.chat.chat.fetch_conversation_for_match", return_value=existing_conv,
    ), pytest.raises(
        DatabaseAccessError, match="User is not a participant of this match",
    ):
        get_or_create_conversation(USER_1, MATCH_1)

    mock_table.select.return_value.eq.return_value.is_.return_value.maybe_single.return_value.execute.side_effect = None
    mock_table.select.return_value.eq.return_value.is_.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data=None,
    )
    with (
        patch("app.db.chat.chat.fetch_conversation_for_match", return_value=None),
        patch("app.db.chat.chat.supabase_client.table", return_value=mock_table),
    ):
        with pytest.raises(DatabaseAccessError, match="No active match found"):
            get_or_create_conversation(USER_1, MATCH_1)

    mock_table.select.return_value.eq.return_value.is_.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={
            "id": MATCH_1,
            "liker_id": USER_2,
            "liked_back_id": USER_3,
            "tab": "Dating",
        },
    )
    with (
        patch("app.db.chat.chat.fetch_conversation_for_match", return_value=None),
        patch("app.db.chat.chat.supabase_client.table", return_value=mock_table),
    ):
        with pytest.raises(
            DatabaseAccessError, match="User is not a participant of this match",
        ):
            get_or_create_conversation(USER_1, MATCH_1)

    mock_table.select.return_value.eq.return_value.is_.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={
            "id": MATCH_1,
            "liker_id": USER_1,
            "liked_back_id": USER_2,
            "tab": "Dating",
        },
    )
    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[])
    with (
        patch(
            "app.db.chat.chat.fetch_conversation_for_match",
            side_effect=[
                None,
                {"id": CONV_1, "user_a_id": USER_1, "user_b_id": USER_2},
            ],
        ),
        patch("app.db.chat.chat.supabase_client.table", return_value=mock_table),
    ):
        c = get_or_create_conversation(USER_1, MATCH_1)
        assert c["id"] == CONV_1

    # 3. fetch_conversations_for_user & fetch_started_match_ids & close_conversation_for_match_action
    conv_data = [
        {
            "id": CONV_1,
            "user_a_id": USER_1,
            "user_b_id": USER_2,
            "last_message_at": "2026-08-25T10:00:00Z",
        },
    ]
    mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.not_.is_.return_value.order.return_value.limit.return_value.execute.return_value = MagicMock(
        data=conv_data,
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        convs = fetch_conversations_for_user(USER_1, tab="Dating")
        assert len(convs) == 1

        mock_table.select.return_value.or_.return_value.eq.return_value.is_.return_value.not_.is_.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[{"match_id": MATCH_1}],
        )
        started = fetch_started_match_ids(USER_1, tab="Dating")
        assert MATCH_1 in started

        mock_table.update.return_value.or_.return_value.is_.return_value.select.return_value.execute.return_value = MagicMock(
            data=[],
        )
        close_conversation_for_match_action(
            USER_1, USER_2, tab="Dating", reason="unmatched",
        )

    # 4. insert_message (success & closed error)
    mock_table.insert.return_value.execute.return_value = MagicMock(
        data=[
            {
                "id": "msg-100",
                "conversation_id": CONV_1,
                "sender_id": USER_1,
                "ciphertext": "cipher",
            },
        ],
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        m = insert_message(CONV_1, USER_1, "text", "cipher", {})
        assert m["id"] == "msg-100"

    mock_table.insert.return_value.execute.side_effect = APIError(
        {"message": "closed conversation"},
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        with pytest.raises(ConversationClosedError):
            insert_message(CONV_1, USER_1, "text", "cipher", {})

    # 5. Media cleanup and participants
    mock_storage = MagicMock()
    mock_storage.remove.return_value = MagicMock()
    mock_table.select.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[
            {
                "ciphertext_metadata": {
                    "attachment_paths": [f"{CONV_1}/{USER_1}/img.jpg"],
                },
            },
        ],
    )
    with (
        patch("app.db.chat.chat.supabase_client.table", return_value=mock_table),
        patch(
            "app.db.chat.chat.supabase_client.storage.from_", return_value=mock_storage,
        ),
    ):
        delete_conversation_chat_media(CONV_1)
        delete_user_chat_media(USER_1, [CONV_1])
        batch_delete_conversations_chat_media([CONV_1])
        _collect_user_conv_media_paths(CONV_1, USER_1)

    # 6. Reactivation partition, updates, reopen
    conv_rows = [
        {"id": CONV_1, "user_a_id": USER_1, "user_b_id": USER_2},
        {"id": "conv-2", "user_a_id": USER_1, "user_b_id": USER_3},
    ]
    with patch(
        "app.db.discovery.exclusions.fetch_active_block_ids", return_value={USER_3},
    ):
        reopen_ids, blocked_ids = _partition_reactivation_conversations(
            conv_rows, USER_1,
        )
        assert CONV_1 in reopen_ids
        assert "conv-2" in blocked_ids

        mock_table.update.return_value.in_.return_value.execute.return_value = (
            MagicMock(data=[])
        )
        mock_table.select.return_value.or_.return_value.eq.return_value.execute.return_value = MagicMock(
            data=[],
        )
        with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
            _apply_reactivation_updates(reopen_ids, blocked_ids, USER_1)
            reopen_conversations_for_reactivation(USER_1)

    # 7. fetch_presence & batch_fetch_presence_from_db & flags & heartbeat
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.side_effect = None
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={
            "user_id": USER_1,
            "is_online": True,
            "last_active_at": "2026-08-25T10:00:00Z",
        },
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        p = fetch_presence(USER_1)
        assert p is not None
        assert p["is_online"] is True

        mock_table.select.return_value.in_.return_value.execute.return_value = (
            MagicMock(data=[{"user_id": USER_1, "is_online": True}])
        )
        batch_p = batch_fetch_presence_from_db([USER_1])
        assert USER_1 in batch_p

        mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[{"share_active_status": True, "share_read_receipts": True}],
        )
        flags = fetch_user_share_flags(USER_1)
        assert flags.get("share_active_status") is True

        mock_table.select.return_value.in_.return_value.execute.return_value = (
            MagicMock(
                data=[
                    {
                        "id": USER_1,
                        "share_active_status": True,
                        "share_read_receipts": True,
                    },
                ],
            )
        )
        b_flags = batch_fetch_user_share_flags([USER_1])
        assert USER_1 in b_flags

        upsert_presence_heartbeat(USER_1, is_online=True)
        fetch_conversation_participants(CONV_1)
        mark_messages_read(CONV_1, USER_1)

    # 8. Event helpers and reminders
    mock_table.insert.return_value.execute.side_effect = None
    enc_lat = encrypt_to_hex("37.7749", category="chat")
    enc_name = encrypt_to_hex("Coffee Shop", category="chat")
    assert _decrypt_float_field(enc_lat) == 37.7749
    assert _decrypt_str_field(enc_name) == "Coffee Shop"
    assert _decrypt_float_field(None) is None
    assert _decrypt_str_field(None) is None

    ev_row = {
        "id": "ev-1",
        "location_lat": enc_lat,
        "location_lng": encrypt_to_hex("-122.4194", category="chat"),
        "location_label": enc_name,
    }
    dec_ev = decrypt_event_row(ev_row)
    assert dec_ev is not None
    assert dec_ev["location_lat"] == 37.7749

    mock_table.insert.return_value.execute.return_value = MagicMock(
        data=[{"id": "ev-1", "conversation_id": CONV_1, "creator_id": USER_1}],
    )
    with patch("app.db.chat.chat.supabase_client.table", return_value=mock_table):
        ev = create_event_with_message(
            CONV_1,
            USER_1,
            "cipher",
            {},
            datetime.now(timezone.utc),
            37.77,
            -122.41,
            "Cafe",
        )
        assert ev["message"]["id"] == "ev-1"

        mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
            data={
                "id": "ev-1",
                "location_lat": None,
                "location_lng": None,
                "location_label": None,
            },
        )
        assert fetch_event("ev-1") is not None

        mock_table.update.return_value.eq.return_value.select.return_value.execute.return_value = MagicMock(
            data=[{"id": "ev-1", "status": "confirmed"}],
        )
        up_ev = update_event_status("ev-1", "confirmed")
        assert up_ev is not None

        enc_due_time = encrypt_to_hex(
            (datetime.now(timezone.utc) + timedelta(minutes=15)).isoformat(),
            category="chat",
        )
        mock_table.select.return_value.is_.return_value.neq.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[
                {
                    "id": "ev-1",
                    "event_time": enc_due_time,
                    "location_lat": None,
                    "location_lng": None,
                    "location_label": None,
                },
            ],
        )
        due_evs = fetch_due_event_reminders(window_minutes=60)
        assert len(due_evs) == 1

        mock_table.update.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(
            data=[{"id": "ev-1"}],
        )
        assert mark_reminder_sent("ev-1") is True

        mock_table.select.return_value.eq.return_value.is_.return_value.neq.return_value.limit.return_value.execute.return_value = MagicMock(
            data=[
                {
                    "id": "ev-1",
                    "event_time": enc_due_time,
                    "location_lat": None,
                    "location_lng": None,
                    "location_label": None,
                },
            ],
        )
        due_saf = fetch_due_safety_reminders(window_minutes=35)
        assert len(due_saf) == 1

        assert mark_safety_reminder_sent("ev-1") is True


def test_db_chat_keys_operations():
    mock_table = MagicMock()

    # 1. upsert_identity_key
    err_23503 = APIError({"message": "foreign key", "code": "23503"})
    mock_table.upsert.return_value.execute.side_effect = err_23503
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        with pytest.raises(ProfileNotFoundError):
            upsert_identity_key(USER_1, b"pk_bytes", 100)

    # 2. fetch_identity_key
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.side_effect = None
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data=None,
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        assert fetch_identity_key(USER_1) is None

    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"identity_public_key": "\\x010203", "registration_id": 999},
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        k = fetch_identity_key(USER_1)
        assert k is not None
        assert k["registration_id"] == 999

    # 3. upsert_signed_prekey
    mock_rpc = MagicMock()
    mock_rpc.execute.side_effect = err_23503
    with patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_rpc):
        with pytest.raises(ProfileNotFoundError):
            upsert_signed_prekey(USER_1, 1, b"pk", b"sig")

    # 4. bulk_insert_one_time_prekeys & count_unused_one_time_prekeys
    mock_table.insert.return_value.execute.return_value = MagicMock(data=[{"id": 1}])
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        bulk_insert_one_time_prekeys(USER_1, [{"key_id": 1, "public_key": b"pk1"}])

    mock_table.select.return_value.eq.return_value.is_.return_value.execute.return_value = MagicMock(
        count=42, data=[],
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        assert count_unused_one_time_prekeys(USER_1) == 42

    # 5. has_active_match & fetch_active_matches_for_targets & fetch_key_bundle & unified
    mock_table.select.return_value.or_.return_value.or_.return_value.is_.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": MATCH_1}],
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        assert has_active_match(USER_1, USER_2) is True

    mock_table.select.return_value.or_.return_value.is_.return_value.execute.return_value = MagicMock(
        data=[{"liker_id": USER_2, "liked_back_id": USER_1}],
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        targets = fetch_active_matches_for_targets(USER_1, [USER_2])
        assert USER_2 in targets

    # mock for fetch_key_bundle
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"identity_public_key": "\\x0102", "registration_id": 123},
    )
    mock_table.select.return_value.eq.return_value.is_.return_value.order.return_value.limit.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={"key_id": 1, "public_key": "\\x0304", "signature": "\\x0506"},
    )
    mock_rpc.execute.side_effect = None
    mock_rpc.execute.return_value = MagicMock(
        data=[{"key_id": 10, "public_key": "\\x0708"}],
    )
    with (
        patch("app.db.chat.keys.supabase_client.table", return_value=mock_table),
        patch("app.db.chat.keys.supabase_client.rpc", return_value=mock_rpc),
    ):
        bundle = fetch_key_bundle(USER_1)
        assert bundle is not None
        assert bundle.get("registration_id") == 123

        with patch("app.db.chat.keys.has_active_match", return_value=True):
            u_bundle, err_code = fetch_x3dh_key_bundle_unified(USER_1, USER_2)
            assert u_bundle is not None
            assert u_bundle["registration_id"] == 123
            assert err_code is None

    mock_table.update.return_value.eq.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[{"id": 1}],
    )
    with patch("app.db.chat.keys.supabase_client.table", return_value=mock_table):
        mark_session_established(USER_1, CONV_1)
