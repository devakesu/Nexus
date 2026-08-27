"""Test Suite for Test Safety Db.

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
from app.db.client import DatabaseAccessError
from app.db.safety.alerts import (
    fetch_alerts_for_session,
    fetch_contact_facing_profile_summary,
    fetch_recent_safety_alert,
    fetch_safety_alert,
    purge_expired_safety_evidence,
    purge_safety_data_for_purged_accounts,
    record_safety_alert,
    update_alert_contacts_notified,
)
from app.db.safety.contacts import (
    _phone_blind_index,
    fetch_safety_contact_by_id,
    fetch_safety_contacts,
    fetch_safety_contacts_with_id,
    remove_safety_contact_self_service,
    sync_safety_contacts,
)
from app.db.safety.sessions import (
    _decrypt_session_row,
    cancel_safety_escalation,
    end_safety_session,
    fetch_overdue_safety_sessions,
    fetch_safety_session,
    fetch_safety_session_for_user,
    heartbeat_safety_session,
    record_safety_escalation_sent,
    start_safety_session,
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


def test_db_safety_modules_deep():
    from app.db.safety.alerts import (
        fetch_contact_facing_profile_summary,
        fetch_safety_alert,
        record_safety_alert,
        update_alert_contacts_notified,
    )
    from app.db.safety.contacts import (
        fetch_safety_contacts,
        remove_safety_contact_self_service,
        sync_safety_contacts,
    )
    from app.db.safety.evidence import (
        create_evidence_download_url,
        register_safety_evidence,
    )
    from app.db.safety.sessions import (
        cancel_safety_escalation,
        end_safety_session,
        heartbeat_safety_session,
        start_safety_session,
    )

    mock_profile_raw = {
        "id": USER_1,
        "name": encrypt_to_hex("Alice", category="profile"),
        "display_gender": encrypt_to_hex("Woman", category="profile"),
        "profile_pic": encrypt_to_hex("pic.jpg", category="profile"),
        "normal_pics": encrypt_to_hex("[]", category="profile"),
        "hometown": encrypt_to_hex("SF", category="profile"),
        "current_place": encrypt_to_hex("Berkeley", category="profile"),
    }
    mock_t = _make_chaining_mock([mock_profile_raw])

    with (
        patch("app.db.safety.alerts.supabase_client.table", return_value=mock_t),
        patch(
            "app.db.safety.alerts.sign_profile_media", return_value={"name": "Alice"},
        ),
    ):
        a = record_safety_alert(USER_1, "sos_silent", {"lat": 37.77, "lng": -122.41})
        assert a is not None
        al = fetch_safety_alert("alert_1")
        assert al is not None
        update_alert_contacts_notified("alert_1", 2)
        summary = fetch_contact_facing_profile_summary(USER_1)
        assert summary is not None
        assert summary.get("name") == "Alice"

    # 2. contacts.py
    mock_contact_raw = {
        "id": "ct_1",
        "user_id": USER_1,
        "name": encrypt_to_hex("Bob", category="contact"),
        "phone": encrypt_to_hex("+15555555555", category="contact"),
    }
    mock_ct_t = _make_chaining_mock([mock_contact_raw])
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(
        data={"blocked_indices": [], "newly_notified_indices": []},
    )
    with (
        patch("app.db.safety.contacts.supabase_client.rpc", return_value=mock_rpc),
        patch("app.db.safety.contacts.supabase_client.table", return_value=mock_ct_t),
        patch(
            "app.db.safety.contacts.fetch_safety_contact_by_id",
            return_value={
                "id": "ct_1",
                "user_id": USER_1,
                "name": "Bob",
                "phone": "+15555555555",
            },
        ),
    ):
        contacts = fetch_safety_contacts(USER_1)
        assert len(contacts) == 1
        assert contacts[0]["name"] == "Bob"
        sync_safety_contacts(USER_1, [{"name": "Bob", "phone": "+15555555555"}])
        removed = remove_safety_contact_self_service("ct_1")
        assert removed is not None
        assert removed["name"] == "Bob"

    SESS_1 = "00000000-0000-0000-0000-000000000044"
    # 3. sessions.py
    mock_sess_raw = {
        "id": SESS_1,
        "user_id": USER_1,
        "status": "active",
        "interval_seconds": 900,
        "next_checkin_at": "2026-08-26T15:00:00Z",
        "escalations_sent": 0,
        "last_escalated_at": None,
    }
    mock_sess_t = _make_chaining_mock([mock_sess_raw])
    mock_rpc.execute.return_value = MagicMock(data=[mock_sess_raw])
    with (
        patch("app.db.safety.sessions.supabase_client.rpc", return_value=mock_rpc),
        patch("app.db.safety.sessions.supabase_client.table", return_value=mock_sess_t),
    ):
        s = start_safety_session(
            USER_1, "Date", 900, "2026-08-26T16:00:00Z", {"mode": "test"}, 80, "wifi",
        )
        assert s is not None
        hb = heartbeat_safety_session(
            USER_1, SESS_1, "2026-08-26T17:00:00Z", 75, "wifi",
        )
        assert hb is not None
        end_safety_session(USER_1, SESS_1)
        cancel_safety_escalation(USER_1, SESS_1, "false_alarm", "I am okay")

    # 4. evidence.py
    mock_ev_raw = {"id": "ev_1", "alert_id": "alert_1", "file_path": "path/to/ev.enc"}
    mock_ev_t = _make_chaining_mock([mock_ev_raw])
    mock_storage = MagicMock()
    mock_storage.create_signed_url.return_value = {"signedURL": "https://download.url"}
    with (
        patch("app.db.safety.evidence.supabase_client.table", return_value=mock_ev_t),
        patch(
            "app.db.safety.evidence.supabase_client.storage.from_",
            return_value=mock_storage,
        ),
    ):
        ev = register_safety_evidence(
            USER_1, "alert_1", "path/to/ev.enc", "media_key", "audio/mp4", 60.0,
        )
        assert ev is not None
        url = create_evidence_download_url("path/to/ev.enc", 3600)
        assert url == "https://download.url"


def test_db_safety_evidence_and_sessions_errors():
    from app.db.client import DatabaseAccessError
    from app.db.safety.evidence import (
        create_evidence_download_url,
        fetch_evidence_for_alert_ids,
        register_safety_evidence,
    )
    from app.db.safety.sessions import (
        end_safety_session,
        heartbeat_safety_session,
        start_safety_session,
    )

    mock_evidence = {
        "id": "ev1",
        "alert_id": ALERT_1,
        "storage_path": f"{ALERT_1}/audio.mp4",
        "media_key_base64": encrypt_to_hex("media_key_bytes", category="media_escrow"),
        "content_type": "audio/mp4",
        "duration_seconds": 30.0,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    mock_ok = _make_chaining_mock([mock_evidence])
    mock_err = _make_chaining_mock(error=APIError({"message": "DB error"}))

    with (
        patch("app.db.safety.evidence.supabase_client.table", return_value=mock_ok),
        patch("app.db.safety.evidence.supabase_client.storage.from_") as mock_storage,
        patch("app.db.safety.sessions.supabase_client.rpc") as mock_rpc,
        patch("app.db.safety.sessions.supabase_client.table", return_value=mock_ok),
    ):
        mock_storage.return_value.create_signed_url.return_value = {
            "signedURL": "https://signed.url",
        }
        mock_rpc.return_value.execute.return_value = MagicMock(
            data=[{"id": SESS_1, "status": "active"}],
        )
        register_safety_evidence(
            USER_1,
            ALERT_1,
            f"{ALERT_1}/audio.mp4",
            "media_key_bytes",
            "audio/mp4",
            30.0,
        )
        fetch_evidence_for_alert_ids([ALERT_1])
        create_evidence_download_url(f"{ALERT_1}/audio.mp4", 300)

        start_safety_session(
            USER_1,
            "walk_home",
            1800,
            datetime.now(timezone.utc).isoformat(),
            {"lat": 37.7, "lng": -122.4},
            85,
            "wifi",
        )
        heartbeat_safety_session(
            USER_1, SESS_1, datetime.now(timezone.utc).isoformat(), 80, "wifi",
        )
        end_safety_session(USER_1, SESS_1)

    with (
        patch("app.db.safety.evidence.supabase_client.table", return_value=mock_err),
        patch(
            "app.db.safety.sessions.supabase_client.rpc",
            side_effect=APIError({"message": "DB error"}),
        ),
        patch("app.db.safety.sessions.supabase_client.table", return_value=mock_err),
    ):
        with pytest.raises(DatabaseAccessError):
            register_safety_evidence(
                USER_1,
                ALERT_1,
                f"{ALERT_1}/audio.mp4",
                "media_key_bytes",
                "audio/mp4",
                30.0,
            )
        with pytest.raises(DatabaseAccessError):
            fetch_evidence_for_alert_ids([ALERT_1])
        with pytest.raises(DatabaseAccessError):
            start_safety_session(
                USER_1,
                "walk_home",
                1800,
                datetime.now(timezone.utc).isoformat(),
                {"lat": 37.7, "lng": -122.4},
                85,
                "wifi",
            )
        with pytest.raises(DatabaseAccessError):
            heartbeat_safety_session(
                USER_1, SESS_1, datetime.now(timezone.utc).isoformat(), 80, "wifi",
            )
        with pytest.raises(DatabaseAccessError):
            end_safety_session(USER_1, SESS_1)


def test_db_safety_alerts_deep():
    from app.db.safety.alerts import (
        fetch_alerts_for_session,
        fetch_contact_facing_profile_summary,
        purge_expired_safety_evidence,
        purge_safety_data_for_purged_accounts,
        record_safety_alert,
    )

    mock_alert = {
        "id": "alt_1",
        "alert_type": "sos",
        "current_location": "\\x6464",
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    mock_t = _make_chaining_mock([mock_alert])
    mock_client = MagicMock()
    mock_client.table.return_value = mock_t
    mock_client.storage.from_.return_value.remove.return_value = True

    with (
        patch("app.db.safety.alerts.supabase_client", mock_client),
        patch(
            "app.db.safety.alerts.decrypt_pii",
            return_value='{"lat": 37.77, "lng": -122.41}',
        ),
        patch("app.db.safety.alerts.encrypt_to_hex", return_value="\\x6464"),
        patch(
            "app.db.safety.alerts.decrypt_profile_record",
            return_value={"name": "Alice"},
        ),
        patch(
            "app.db.safety.alerts.sign_profile_media", return_value={"name": "Alice"},
        ),
    ):
        summary = fetch_contact_facing_profile_summary(USER_1)
        assert summary is not None

        alert_res = record_safety_alert(
            USER_1, "sos", {"lat": 37.77, "lng": -122.41}, SESSION_1,
        )
        assert alert_res is not None

        alerts = fetch_alerts_for_session(SESSION_1, decrypt_locations=True)
        assert len(alerts) > 0

        purge_expired_safety_evidence()
        purge_safety_data_for_purged_accounts()


def test_db_safety_contacts_deep():
    from app.db.safety.contacts import (
        fetch_safety_contact_by_id,
        fetch_safety_contacts,
        fetch_safety_contacts_with_id,
        remove_safety_contact_self_service,
        sync_safety_contacts,
    )

    mock_contact = {
        "id": CONTACT_1,
        "user_id": USER_1,
        "name": "\\x6161",
        "phone": "\\x6262",
    }
    mock_t = _make_chaining_mock([mock_contact])

    with (
        patch("app.db.safety.contacts.supabase_client.table", return_value=mock_t),
        patch("app.db.safety.contacts.supabase_client.rpc") as mock_rpc,
        patch("app.db.safety.contacts.decrypt_pii", return_value="+15551234567"),
        patch("app.db.safety.contacts.encrypt_to_hex", return_value="\\x6262"),
    ):
        mock_rpc.return_value.execute.return_value = MagicMock(
            data={"blocked_indices": [], "newly_notified_indices": []},
        )

        blocked, _newly = sync_safety_contacts(
            USER_1, [{"name": "Dad", "phone": "+15551234567"}],
        )
        assert isinstance(blocked, list)

        contacts = fetch_safety_contacts(USER_1)
        assert len(contacts) > 0

        contacts_id = fetch_safety_contacts_with_id(USER_1)
        assert len(contacts_id) > 0

        single = fetch_safety_contact_by_id(CONTACT_1)
        assert single is not None

        removed = remove_safety_contact_self_service(CONTACT_1)
        assert removed is not None


def test_db_safety_error_branches():
    from app.db.safety.alerts import (
        fetch_alerts_for_session,
        fetch_contact_facing_profile_summary,
        record_safety_alert,
    )
    from app.db.safety.contacts import (
        fetch_safety_contact_by_id,
        fetch_safety_contacts,
        fetch_safety_contacts_with_id,
        sync_safety_contacts,
    )

    err_table = MagicMock()
    err_table.select.return_value = err_table
    err_table.insert.return_value = err_table
    err_table.delete.return_value = err_table
    err_table.upsert.return_value = err_table
    err_table.eq.return_value = err_table
    err_table.order.return_value = err_table
    err_table.limit.return_value = err_table
    err_table.execute.side_effect = APIError({"message": "DB Error", "code": "500"})

    single_mock = MagicMock()
    single_mock.execute.side_effect = APIError(
        {"message": "DB Single Error", "code": "500"},
    )
    err_table.maybe_single.return_value = single_mock
    err_table.single.return_value = single_mock

    mock_client = MagicMock()
    mock_client.table.return_value = err_table
    mock_client.rpc.return_value.execute.side_effect = APIError(
        {"message": "RPC Error", "code": "500"},
    )

    with (
        patch("app.db.safety.alerts.supabase_client", mock_client),
        patch("app.db.safety.contacts.supabase_client", mock_client),
    ):
        with pytest.raises(DatabaseAccessError):
            fetch_contact_facing_profile_summary(USER_1)

        with pytest.raises(DatabaseAccessError):
            record_safety_alert(USER_1, "sos", {"lat": 1.0, "lng": 1.0})

        with pytest.raises(DatabaseAccessError):
            fetch_alerts_for_session(SESSION_1)

        with pytest.raises(DatabaseAccessError):
            sync_safety_contacts(USER_1, [{"name": "A", "phone": "+15550000000"}])

        with pytest.raises(DatabaseAccessError):
            fetch_safety_contacts(USER_1)

        with pytest.raises(DatabaseAccessError):
            fetch_safety_contacts_with_id(USER_1)

        with pytest.raises(DatabaseAccessError):
            fetch_safety_contact_by_id(CONTACT_1)


def test_db_safety_alerts_deep_p20():
    from app.db.safety.alerts import (
        fetch_alerts_for_session,
        fetch_contact_facing_profile_summary,
        fetch_recent_safety_alert,
        fetch_safety_alert,
        purge_expired_safety_evidence,
        purge_safety_data_for_purged_accounts,
        record_safety_alert,
        update_alert_contacts_notified,
    )

    # fetch_contact_facing_profile_summary: res is None, APIError, DecryptFailedError
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        assert fetch_contact_facing_profile_summary(USER_1) is None

        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_contact_facing_profile_summary(USER_1)

        mock_sb.table().select().eq().maybe_single().execute.side_effect = None
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data={"name": "enc"},
        )
        with patch(
            "app.db.safety.alerts.decrypt_profile_record",
            side_effect=DecryptFailedError("fail"),
        ):
            assert fetch_contact_facing_profile_summary(USER_1) is None

    # record_safety_alert: rows empty & APIError
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().insert().select().execute.return_value = MagicMock(data=[])
        with pytest.raises(
            DatabaseAccessError, match="Safety alert insert returned no row",
        ):
            record_safety_alert(
                USER_1, "emergency", {"lat": 1.0, "lng": 2.0}, session_id=SESSION_1,
            )

        mock_sb.table().insert().select().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            record_safety_alert(USER_1, "emergency", None)

    # fetch_safety_alert: res is None & APIError
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        assert fetch_safety_alert(ALERT_1) is None

        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_safety_alert(ALERT_1)

    # fetch_recent_safety_alert: session_id provided & Exception
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().gte().order().limit().eq().execute.return_value = MagicMock(
            data=[{"id": ALERT_1}],
        )
        res = fetch_recent_safety_alert(USER_1, "emergency", session_id=SESSION_1)
        assert res == {"id": ALERT_1}

        mock_sb.table().select().eq().eq().gte().order().limit().eq().execute.side_effect = Exception(
            "DB error",
        )
        assert (
            fetch_recent_safety_alert(USER_1, "emergency", session_id=SESSION_1) is None
        )

    # update_alert_contacts_notified: APIError
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().update().eq().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            update_alert_contacts_notified(ALERT_1, 3)

    # fetch_alerts_for_session: stale location & APIError
    now = datetime.now(timezone.utc)
    old_time = (now - timedelta(hours=2)).isoformat()
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().eq().order().execute.return_value = MagicMock(
            data=[{"current_location": "enc_loc", "created_at": old_time}],
        )
        alerts = fetch_alerts_for_session(
            SESSION_1, decrypt_locations=True, max_location_age=timedelta(minutes=30),
        )
        assert alerts[0]["current_location"] is None

        mock_sb.table().select().eq().order().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_alerts_for_session(SESSION_1)

    # purge_expired_safety_evidence: fetch APIError, empty rows, delete APIError, storage remove Exception
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().lt().execute.side_effect = APIError(
            {"message": "fail"},
        )
        purge_expired_safety_evidence()

        mock_sb.table().select().lt().execute.side_effect = None
        mock_sb.table().select().lt().execute.return_value = MagicMock(data=[])
        purge_expired_safety_evidence()

        mock_sb.table().select().lt().execute.return_value = MagicMock(
            data=[{"id": "ev1", "storage_path": "path1"}],
        )
        mock_sb.table().delete().in_().execute.side_effect = APIError(
            {"message": "fail"},
        )
        purge_expired_safety_evidence()

        mock_sb.table().delete().in_().execute.side_effect = None
        mock_sb.storage.from_().remove.side_effect = Exception("Storage fail")
        purge_expired_safety_evidence()

    # purge_safety_data_for_purged_accounts: fetch APIError, empty user_ids, evidence APIError, safety_alerts APIError
    with patch("app.db.safety.alerts.supabase_client") as mock_sb:
        mock_sb.table().select().not_.is_().lte().execute.side_effect = APIError(
            {"message": "fail"},
        )
        purge_safety_data_for_purged_accounts()

        mock_sb.table().select().not_.is_().lte().execute.side_effect = None
        mock_sb.table().select().not_.is_().lte().execute.return_value = MagicMock(
            data=[],
        )
        purge_safety_data_for_purged_accounts()

        mock_sb.table().select().not_.is_().lte().execute.return_value = MagicMock(
            data=[{"id": USER_1}],
        )
        mock_sb.table().select().in_().execute.side_effect = APIError(
            {"message": "fail"},
        )
        mock_sb.table().delete().in_().execute.side_effect = APIError(
            {"message": "fail"},
        )
        purge_safety_data_for_purged_accounts()


def test_db_safety_sessions_deep():
    from app.db.safety.sessions import (
        _decrypt_session_row,
        cancel_safety_escalation,
        end_safety_session,
        fetch_overdue_safety_sessions,
        fetch_safety_session,
        fetch_safety_session_for_user,
        heartbeat_safety_session,
        record_safety_escalation_sent,
        start_safety_session,
    )

    # _decrypt_session_row branches
    assert _decrypt_session_row({}) == {}
    row_with_dict_ctx = {"event_context": {"foo": "bar"}}
    assert _decrypt_session_row(row_with_dict_ctx)["event_context"] == {"foo": "bar"}

    with patch(
        "app.db.safety.sessions.decrypt_pii", side_effect=Exception("decrypt fail"),
    ):
        row_broken_enc = {"label": "enc", "event_context": "broken-enc"}
        dec = _decrypt_session_row(row_broken_enc)
        assert dec["event_context"] == {}

    # start_safety_session insert returned no row
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.rpc().execute.return_value = MagicMock(data="unexpected-string")
        with pytest.raises(
            DatabaseAccessError, match="Safety session insert returned no row",
        ):
            start_safety_session(
                USER_1, "Label", 60, "2026-08-26T20:00:00Z", None, 90, "wifi",
            )

    # heartbeat_safety_session: no rows, updated_rows empty, APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().eq().execute.return_value = MagicMock(
            data=[],
        )
        assert (
            heartbeat_safety_session(
                USER_1, SESSION_1, "2026-08-26T20:00:00Z", 80, "4g",
            )
            is None
        )

        mock_sb.table().select().eq().eq().eq().execute.return_value = MagicMock(
            data=[{"id": SESSION_1, "next_checkin_at": "2026-08-26T19:00:00Z"}],
        )
        mock_sb.table().update().eq().eq().eq().select().execute.return_value = (
            MagicMock(data=[])
        )
        assert (
            heartbeat_safety_session(
                USER_1, SESSION_1, "2026-08-26T20:00:00Z", 80, "4g",
            )
            is None
        )

        mock_sb.table().select().eq().eq().eq().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            heartbeat_safety_session(
                USER_1, SESSION_1, "2026-08-26T20:00:00Z", 80, "4g",
            )

    # end_safety_session APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().update().eq().eq().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            end_safety_session(USER_1, SESSION_1)

    # fetch_overdue_safety_sessions APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().is_().eq().eq().is_().is_().lt().lt().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_overdue_safety_sessions(60)

    # record_safety_escalation_sent APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().update().eq().lt().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            record_safety_escalation_sent(SESSION_1, 2)

    # fetch_safety_session & fetch_safety_session_for_user APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            fetch_safety_session(SESSION_1)

        mock_sb.table().select().eq().eq().maybe_single().execute.side_effect = (
            APIError({"message": "fail"})
        )
        with pytest.raises(DatabaseAccessError):
            fetch_safety_session_for_user(USER_1, SESSION_1)

    # cancel_safety_escalation: rows empty & APIError
    with patch("app.db.safety.sessions.supabase_client") as mock_sb:
        mock_sb.table().update().eq().eq().is_().select().execute.return_value = (
            MagicMock(data=[])
        )
        assert cancel_safety_escalation(USER_1, SESSION_1, "false_alarm", None) is None

        mock_sb.table().update().eq().eq().is_().select().execute.side_effect = (
            APIError({"message": "fail"})
        )
        with pytest.raises(DatabaseAccessError):
            cancel_safety_escalation(USER_1, SESSION_1, "false_alarm", "note")


def test_db_safety_contacts_deep_p27():
    from app.db.safety.contacts import (
        fetch_safety_contact_by_id,
        remove_safety_contact_self_service,
        sync_safety_contacts,
    )

    # sync_safety_contacts notices direct query fallback
    contacts = [{"name": "Mom", "phone": "+14155552671"}]
    with (
        patch("app.db.safety.contacts.supabase_client") as mock_sb,
        patch("app.db.safety.contacts._phone_blind_index", return_value="idx-1"),
    ):
        mock_sb.rpc().execute.return_value = MagicMock(data=None)
        mock_sb.table().select().eq().execute.return_value = MagicMock(
            data=[{"phone_blind_index": "idx-1", "self_removed_at": "2026-01-01"}],
        )
        blocked, _ = sync_safety_contacts(USER_1, contacts)
        assert len(blocked) == 1

    # fetch_safety_contact_by_id: not found
    with patch("app.db.safety.contacts.supabase_client") as mock_sb:
        mock_sb.table().select().eq().maybe_single().execute.return_value = MagicMock(
            data=None,
        )
        assert fetch_safety_contact_by_id("c-1") is None

    # remove_safety_contact_self_service: contact None, APIError notice, APIError delete
    with patch("app.db.safety.contacts.fetch_safety_contact_by_id", return_value=None):
        assert remove_safety_contact_self_service("c-1") is None

    with (
        patch(
            "app.db.safety.contacts.fetch_safety_contact_by_id",
            return_value={"id": "c-1", "user_id": USER_1, "phone": "+14155552671"},
        ),
        patch("app.db.safety.contacts.supabase_client") as mock_sb,
    ):
        mock_sb.table().upsert().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            remove_safety_contact_self_service("c-1")

        mock_sb.table().upsert().execute.side_effect = None
        mock_sb.table().delete().eq().execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            remove_safety_contact_self_service("c-1")


def test_db_safety_alerts_sessions_and_contacts():
    # Contacts
    idx = _phone_blind_index("+14155552671")
    assert isinstance(idx, str)

    def fresh_contact():
        return {
            "id": "contact-1",
            "user_id": USER_1,
            "name": encrypt_to_hex("Bob", category="contact"),
            "phone": encrypt_to_hex("+14155552671", category="contact"),
        }

    mock_table = _make_chaining_mock([fresh_contact()])
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(
        data={"blocked_indices": [], "newly_notified_indices": []},
    )

    with (
        patch("app.db.safety.contacts.supabase_client.table", return_value=mock_table),
        patch("app.db.safety.contacts.supabase_client.rpc", return_value=mock_rpc),
    ):
        sync_safety_contacts(USER_1, [{"phone": "+14155552671", "name": "Bob"}])
        c_list = fetch_safety_contacts(USER_1)
        assert len(c_list) >= 1
        fetch_safety_contacts_with_id(USER_1)
        fetch_safety_contact_by_id("contact-1")
        remove_safety_contact_self_service("contact-1")

    # Sessions
    enc_label = encrypt_to_hex("Home", category="media_escrow")
    dec_sess = _decrypt_session_row({"id": SESSION_1, "label": enc_label})
    assert dec_sess["label"] == "Home"

    now = datetime.now(timezone.utc)
    mock_sess_table = _make_chaining_mock(
        [
            {
                "id": SESSION_1,
                "user_id": USER_1,
                "status": "active",
                "label": enc_label,
                "next_checkin_at": (now + timedelta(hours=2)).isoformat(),
            },
        ],
    )
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(
        data={
            "id": SESSION_1,
            "user_id": USER_1,
            "status": "active",
            "label": enc_label,
        },
    )

    with (
        patch(
            "app.db.safety.sessions.supabase_client.table", return_value=mock_sess_table,
        ),
        patch("app.db.safety.sessions.supabase_client.rpc", return_value=mock_rpc),
    ):
        s_row = start_safety_session(
            USER_1,
            label="Cafe",
            interval_seconds=3600,
            next_checkin_at=(now + timedelta(hours=1)).isoformat(),
            event_context={},
            battery_percent=90,
            connection_type="wifi",
        )
        assert s_row is not None
        heartbeat_safety_session(
            USER_1,
            SESSION_1,
            next_checkin_at=(now + timedelta(minutes=15)).isoformat(),
            battery_percent=85,
            connection_type="wifi",
        )
        end_safety_session(USER_1, SESSION_1)
        fetch_overdue_safety_sessions(grace_seconds=60)
        record_safety_escalation_sent(SESSION_1, new_count=1)
        fetch_safety_session(SESSION_1)
        fetch_safety_session_for_user(USER_1, SESSION_1)
        cancel_safety_escalation(USER_1, SESSION_1, reason="safe", note="ok")

    # Alerts
    mock_alert_table = _make_chaining_mock(
        [
            {
                "id": ALERT_1,
                "session_id": SESSION_1,
                "alert_type": "overdue",
                "storage_path": "u1/alert.jpg",
            },
        ],
    )
    mock_storage = MagicMock()
    with (
        patch(
            "app.db.safety.alerts.supabase_client.table", return_value=mock_alert_table,
        ),
        patch(
            "app.db.safety.alerts.supabase_client.storage.from_",
            return_value=mock_storage,
        ),
    ):
        fetch_contact_facing_profile_summary(USER_1)
        record_safety_alert(USER_1, "overdue", None, session_id=SESSION_1)
        fetch_safety_alert(ALERT_1)
        fetch_recent_safety_alert(USER_1, alert_type="overdue")
        update_alert_contacts_notified(ALERT_1, count=2)
        fetch_alerts_for_session(SESSION_1)
        purge_expired_safety_evidence()
        purge_safety_data_for_purged_accounts()
