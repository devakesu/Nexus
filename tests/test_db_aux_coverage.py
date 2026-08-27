"""Test coverage suite for DB Aux layers (Feedback, Spotify, Client).

Covers:
- app/db/feedback/feedback.py
- app/db/spotify.py
- app/db/client.py
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from unittest.mock import MagicMock, patch

import pytest

from app.core.security.crypto import encrypt_to_hex
from app.db.client import (
    ConversationClosedError,
    DatabaseAccessError,
    ProfileDecodeError,
    ProfileNotFoundError,
    normalize_uuid,
    parse_utc_datetime,
    utcnow,
    validate_device_id,
    validate_fcm_token,
)
from app.db.feedback.feedback import (
    add_ticket_comment,
    close_ticket,
    fetch_ticket_comments,
    fetch_ticket_report,
    fetch_ticket_status_history,
    fetch_user_email,
    fetch_user_tickets,
    record_feedback_submission,
)
from app.db.spotify import (
    _sanitize_sync_error,
    disconnect,
    fetch_playlists_for_owner,
    get_connection,
    get_decrypted_refresh_token,
    mark_sync_result,
    persist_artist_signals,
    replace_playlists,
    upsert_connection,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
REPORT_1 = "00000000-0000-0000-0000-000000000077"


# ==============================================================================
# 1. CLIENT UTILS & EXCEPTIONS TESTS
# ==============================================================================

def test_db_client_utilities_and_errors():
    now = utcnow()
    assert isinstance(now, datetime)
    assert now.tzinfo is not None

    parsed_str = parse_utc_datetime("2026-08-25T12:00:00Z")
    assert parsed_str.tzinfo is not None

    naive_dt = datetime(2026, 8, 25, 12, 0, 0)
    parsed_naive = parse_utc_datetime(naive_dt)
    assert parsed_naive.tzinfo == timezone.utc

    u_str = normalize_uuid(USER_1)
    assert u_str == USER_1

    with pytest.raises(ValueError):
        normalize_uuid("")

    with pytest.raises(ValueError):
        normalize_uuid("invalid-uuid")

    # validate_fcm_token
    token = validate_fcm_token("fcm_token_123:abc-xyz")
    assert token == "fcm_token_123:abc-xyz"

    with pytest.raises(ValueError):
        validate_fcm_token("")

    with pytest.raises(ValueError):
        validate_fcm_token("invalid fcm token with spaces!")

    # validate_device_id
    dev_id = validate_device_id("dev-id-123.456")
    assert dev_id == "dev-id-123.456"

    with pytest.raises(ValueError):
        validate_device_id("")

    with pytest.raises(ValueError):
        validate_device_id("invalid device id with spaces!")

    # Exceptions instantiation
    assert issubclass(ConversationClosedError, DatabaseAccessError)
    assert isinstance(ProfileDecodeError("err"), Exception)
    assert isinstance(ProfileNotFoundError("err"), Exception)


# ==============================================================================
# 2. FEEDBACK TICKETING TESTS
# ==============================================================================

def test_feedback_ticketing():
    now = datetime.now(timezone.utc)
    mock_table = MagicMock()

    # 1. record_feedback_submission
    mock_table.insert.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": REPORT_1, "status": "open", "created_at": now.isoformat()}],
    )
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        rep = record_feedback_submission(
            user_id=USER_1,
            query_type="bug",
            subject="Crash on login",
            message="App crashes when pressing sign-in",
            github_issue_url="https://github.com/issue/1",
            attachment_paths=["feedback/screen.png"],
            app_version="1.0.0",
            platform="ios",
            device_info={"model": "iPhone 15"},
            contact_email="test@nexus.app",
        )
        assert rep["id"] == REPORT_1

    # 2. fetch_user_email
    mock_admin = MagicMock()
    mock_admin.get_user_by_id.return_value = MagicMock(user=MagicMock(email="test@nexus.app"))
    with patch("app.db.feedback.feedback.supabase_client.auth.admin", mock_admin):
        email = fetch_user_email(USER_1)
        assert email == "test@nexus.app"

    mock_admin.get_user_by_id.side_effect = Exception("Admin lookup failed")
    with patch("app.db.feedback.feedback.supabase_client.auth.admin", mock_admin):
        assert fetch_user_email(USER_1) is None

    # 3. fetch_user_tickets
    mock_table.select.return_value.eq.return_value.order.return_value.execute.side_effect = lambda: MagicMock(
        data=[
            {
                "id": REPORT_1,
                "query_type": "bug",
                "subject": encrypt_to_hex("Crash on login", category="contact"),
                "status": "open",
                "created_at": now.isoformat(),
            },
        ],
    )
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        t_list = fetch_user_tickets(USER_1, limit=10, offset=0)
        assert len(t_list) == 1
        assert t_list[0]["subject"] == "Crash on login"

    # 4. fetch_ticket_report
    mock_table.select.return_value.eq.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={
            "id": REPORT_1,
            "query_type": "bug",
            "subject": encrypt_to_hex("Crash on login", category="contact"),
            "message": encrypt_to_hex("App crashes", category="contact"),
            "status": "open",
            "created_at": now.isoformat(),
        },
    )
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        ticket = fetch_ticket_report(USER_1, REPORT_1)
        assert ticket is not None
        assert ticket["subject"] == "Crash on login"
        assert ticket["message"] == "App crashes"

    # 5. fetch_ticket_status_history & fetch_ticket_comments & add_ticket_comment
    mock_table.select.return_value.eq.return_value.order.return_value.execute.side_effect = None
    mock_table.select.return_value.eq.return_value.order.return_value.execute.return_value = MagicMock(
        data=[{"status": "open", "note": "Report logged", "changed_by": None, "created_at": now.isoformat()}],
    )
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        history = fetch_ticket_status_history(REPORT_1)
        assert len(history) == 1
        assert history[0]["status"] == "open"

    mock_table.select.return_value.eq.return_value.order.return_value.execute.return_value = MagicMock(
        data=[{"id": "c1", "author_id": USER_1, "body": "Any updates?", "created_at": now.isoformat()}],
    )
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        comments = fetch_ticket_comments(REPORT_1)
        assert len(comments) == 1
        assert comments[0]["body"] == "Any updates?"

    mock_table.insert.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": "c2", "author_id": USER_1, "body": "Thanks!", "created_at": now.isoformat()}],
    )
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        comm = add_ticket_comment(REPORT_1, USER_1, "Thanks!")
        assert comm["id"] == "c2"

    # 6. close_ticket
    mock_table.update.return_value.eq.return_value.eq.return_value.neq.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"id": REPORT_1, "status": "closed"}],
    )
    with patch("app.db.feedback.feedback.supabase_client.table", return_value=mock_table):
        closed = close_ticket(USER_1, REPORT_1, reason="Resolved by user")
        assert closed is not None
        assert closed["status"] == "closed"


# ==============================================================================
# 3. SPOTIFY PERSISTENCE & AFFINITY SIGNALS
# ==============================================================================

def test_spotify_persistence_and_signals():
    now = datetime.now(timezone.utc)
    mock_table = MagicMock()

    # 1. get_connection & get_decrypted_refresh_token & upsert_connection
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[
            {
                "user_id": USER_1,
                "spotify_user_id": "spot_user_1",
                "refresh_token": encrypt_to_hex("refresh_secret_123", category="oauth"),
                "granted_scopes": "user-read-email",
                "connected_at": now.isoformat(),
            },
        ],
    )
    with patch("app.db.spotify.supabase_client.table", return_value=mock_table):
        conn = get_connection(USER_1)
        assert conn is not None
        assert conn["spotify_user_id"] == "spot_user_1"

        token = get_decrypted_refresh_token(USER_1)
        assert token == "refresh_secret_123"

    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.spotify.supabase_client.table", return_value=mock_table):
        upsert_connection(USER_1, "spot_user_1", "refresh_secret_123", "user-read-email")

    # 2. _sanitize_sync_error & mark_sync_result
    sanitized = _sanitize_sync_error("Error with spotify:user:12345 and bearer abc.def.ghi and test@nexus.app")
    assert sanitized is not None
    assert "spotify:user:[REDACTED]" in sanitized
    assert "bearer [REDACTED]" in sanitized
    assert "[EMAIL_REDACTED]" in sanitized

    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.spotify.supabase_client.table", return_value=mock_table):
        mark_sync_result(USER_1, status="success", error=None)

    # 3. disconnect
    mock_table.delete.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.spotify.supabase_client.table", return_value=mock_table):
        disconnect(USER_1)

    # 4. replace_playlists & fetch_playlists_for_owner
    mock_table.upsert.return_value.execute.return_value = MagicMock(data=[])
    mock_delete = MagicMock()
    mock_delete.eq.return_value.not_.return_value.in_.return_value.execute.return_value = MagicMock(data=[])
    mock_table.delete.return_value = mock_delete
    with patch("app.db.spotify.supabase_client.table", return_value=mock_table):
        replace_playlists(
            USER_1,
            [
                {
                    "spotify_playlist_id": "pl1",
                    "name": "Chill Vibes",
                    "is_collaborative": False,
                    "track_count": 1,
                    "tracks": [{"spotify_track_id": "tr1", "name": "Song 1", "artists": ["Artist A"]}],
                },
            ],
        )

    mock_table.select.return_value.eq.return_value.order.return_value.execute.return_value = MagicMock(
        data=[
            {
                "id": "p_row1",
                "spotify_playlist_id": "pl1",
                "name": encrypt_to_hex("Chill Vibes", category="oauth"),
                "is_collaborative": False,
                "track_count": 1,
                "tracks": encrypt_to_hex(json.dumps([{"spotify_track_id": "tr1", "name": "Song 1", "artists": ["Artist A"]}]), category="oauth"),
                "synced_at": now.isoformat(),
            },
        ],
    )
    with patch("app.db.spotify.supabase_client.table", return_value=mock_table):
        pls = fetch_playlists_for_owner(USER_1)
        assert len(pls) == 1
        assert pls[0]["name"] == "Chill Vibes"
        assert pls[0]["tracks"][0]["name"] == "Song 1"

    # 5. persist_artist_signals
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.db.spotify.supabase_client.table", return_value=mock_table):
        persist_artist_signals(
            user_id=USER_1,
            artist_affinity={"Artist A": 0.95},
            top_artists=["Artist A"],
            genre_affinity={"Indie": 0.8},
        )
