"""Test coverage suite for Spotify API endpoints and API Dependencies.

Covers:
- app/api/spotify/auth.py
- app/api/spotify/sync.py
- app/api/dependencies.py
"""

from __future__ import annotations

import json
import time
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import jwt
import pytest
from fastapi import BackgroundTasks, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials

from app.api.dependencies import (
    _build_suspension_error_detail,
    _consume_app_check_token,
    _decode_jwt,
    _should_trigger_presence,
    assert_account_active,
    assert_safety_consent,
    assert_special_category_consent,
    get_active_user_id,
    get_authenticated_user_payload,
    get_bearer_token,
    get_cached_public_user,
    get_optional_bearer_token,
    is_account_suspended,
    is_consent_stale,
    resolve_verified_user,
    verify_app_check_token,
)
from app.api.spotify.auth import (
    _consume_state,
    _html_result,
    _NativeExchangeRequest,
    _seed_and_queue_sync,
    _state_redis_key,
    _store_state,
    spotify_callback,
    spotify_connect,
    spotify_native_exchange,
)
from app.api.spotify.sync import (
    _playlist_out_from_row,
    _track_out_from_row,
    spotify_disconnect,
    spotify_playlists,
    spotify_resync,
    spotify_status,
)
from app.db.client import DatabaseAccessError

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"
USER_2 = "00000000-0000-0000-0000-000000000002"


def make_mock_request(headers: dict[str, str] | None = None) -> Request:
    raw_headers = [(k.lower().encode(), v.encode()) for k, v in (headers or {}).items()]
    scope = {
        "type": "http",
        "method": "POST",
        "path": "/api/v1/test",
        "headers": raw_headers,
        "client": ("127.0.0.1", 12345),
        "app": MagicMock(),
    }
    req = Request(scope)
    req.state.view_rate_limit = None
    return req


# ==============================================================================
# 1. SPOTIFY AUTH API TESTS
# ==============================================================================

async def test_spotify_auth_helpers():
    bg = BackgroundTasks()

    # 1. State redis helpers
    assert _state_redis_key("state123") == "spotify:oauth:state:state123"

    with patch("app.api.spotify.auth.redis_client.setex", new_callable=AsyncMock) as mock_setex:
        await _store_state("state123", USER_1)
        mock_setex.assert_awaited_once_with("spotify:oauth:state:state123", 600, USER_1)

    with patch("app.api.spotify.auth.redis_client.getdel", new_callable=AsyncMock, return_value=USER_1):
        uid = await _consume_state("state123")
        assert uid == USER_1

    # 2. HTML result rendering
    html_ok = _html_result(
        title="Connected",
        success=True,
        message="Synced successfully",
        artists=["Artist A", "Artist B"],
    )
    assert html_ok.status_code == 200
    assert "Artist A" in bytes(html_ok.body).decode("utf-8")

    html_err = _html_result(
        title="Failed",
        success=False,
        message="Error occurred",
        status_code=400,
    )
    assert html_err.status_code == 400

    # 3. Seed and queue sync
    top_artists_mock = MagicMock()
    top_artists_mock.ranked = {"artist_1": 1.0}
    top_artists_mock.genre_weights = {"pop": 1.0}

    with patch("app.api.spotify.auth.fetch_spotify_user_id", new_callable=AsyncMock, return_value="sp_user_1"), \
         patch("app.api.spotify.auth.upsert_connection"), \
         patch("app.api.spotify.auth.invalidate_viewer_discovery_sessions"), \
         patch("app.api.spotify.auth.fetch_top_artists_ranked", new_callable=AsyncMock, return_value=top_artists_mock), \
         patch("app.api.spotify.auth.compute_genre_affinity", return_value={"pop": 1.0}), \
         patch("app.api.spotify.auth.blend_artist_affinity", return_value=({"artist_1": 1.0}, {"artist_1": "Artist 1"})), \
         patch("app.api.spotify.auth.top_display_names", return_value=["Artist 1"]), \
         patch("app.api.spotify.auth.persist_artist_signals"):
        names = await _seed_and_queue_sync(bg, USER_1, "acc_token", "ref_token", "user-top-read")
        assert names == ["Artist 1"]


async def test_spotify_native_exchange():
    req = make_mock_request()
    bg = BackgroundTasks()
    payload = _NativeExchangeRequest(code="auth_code_123", redirect_uri="nexus://spotify-callback")

    # 1. Unconfigured redirect uri -> 500
    with patch("app.api.spotify.auth.settings.spotify_redirect_uri", ""):
        with pytest.raises(HTTPException) as exc_500:
            await spotify_native_exchange(request=req, body=payload, background_tasks=bg, user_id=USER_1)
        assert exc_500.value.status_code == 500

    # 2. Invalid redirect uri -> 400
    with patch("app.api.spotify.auth.settings.spotify_redirect_uri", "https://nexus.app/callback"), \
         patch("app.api.spotify.auth.settings.spotify_allowed_redirect_uris", []):
        with pytest.raises(HTTPException) as exc_400:
            await spotify_native_exchange(request=req, body=payload, background_tasks=bg, user_id=USER_1)
        assert exc_400.value.status_code == 400

    # 3. exchange_code error -> 502
    with patch("app.api.spotify.auth.settings.spotify_redirect_uri", "https://nexus.app/callback"), \
         patch("app.api.spotify.auth.settings.spotify_allowed_redirect_uris", ["nexus://spotify-callback"]), \
         patch("app.api.spotify.auth.exchange_code", side_effect=Exception("Spotify connection failed")):
        with pytest.raises(HTTPException) as exc_502:
            await spotify_native_exchange(request=req, body=payload, background_tasks=bg, user_id=USER_1)
        assert exc_502.value.status_code == 502

    # 4. Successful native exchange
    tokens_mock = MagicMock(access_token="acc_123", refresh_token="ref_123", scope="user-top-read")
    with patch("app.api.spotify.auth.settings.spotify_redirect_uri", "https://nexus.app/callback"), \
         patch("app.api.spotify.auth.settings.spotify_allowed_redirect_uris", ["nexus://spotify-callback"]), \
         patch("app.api.spotify.auth.exchange_code", new_callable=AsyncMock, return_value=tokens_mock), \
         patch("app.api.spotify.auth._seed_and_queue_sync", new_callable=AsyncMock, return_value=["Coldplay", "Adele"]):
        res = await spotify_native_exchange(request=req, body=payload, background_tasks=bg, user_id=USER_1)
        assert res["synced"] == 2
        assert res["artists"] == ["Coldplay", "Adele"]


async def test_spotify_connect_and_callback():
    req = make_mock_request()
    bg = BackgroundTasks()

    # 1. spotify_connect - unconfigured -> 503
    with patch("app.api.spotify.auth.settings.spotify_client_id", ""):
        with pytest.raises(HTTPException) as exc_conn_503:
            await spotify_connect(request=req, user_id=USER_1)
        assert exc_conn_503.value.status_code == 503

    # 2. spotify_connect - success
    with patch("app.api.spotify.auth.settings.spotify_client_id", "spotify_client_123"), \
         patch("app.api.spotify.auth.settings.spotify_redirect_uri", "https://nexus.app/callback"), \
         patch("app.api.spotify.auth._store_state", new_callable=AsyncMock):
        conn_res = await spotify_connect(request=req, user_id=USER_1)
        assert "accounts.spotify.com/authorize" in conn_res["auth_url"]

    # 3. spotify_callback - error parameter -> 400
    cb_err = await spotify_callback(request=req, background_tasks=bg, error="access_denied")
    assert cb_err.status_code == 400

    # 4. spotify_callback - state expired -> 400
    with patch("app.api.spotify.auth._consume_state", new_callable=AsyncMock, return_value=None):
        cb_exp = await spotify_callback(request=req, background_tasks=bg, code="code123", state="st123")
        assert cb_exp.status_code == 400

    # 5. spotify_callback - missing redirect_uri -> 500
    with patch("app.api.spotify.auth._consume_state", new_callable=AsyncMock, return_value=USER_1), \
         patch("app.api.spotify.auth.settings.spotify_redirect_uri", ""):
        cb_no_redir = await spotify_callback(request=req, background_tasks=bg, code="code123", state="st123")
        assert cb_no_redir.status_code == 500

    # 6. spotify_callback - exchange error -> 500
    with patch("app.api.spotify.auth._consume_state", new_callable=AsyncMock, return_value=USER_1), \
         patch("app.api.spotify.auth.settings.spotify_redirect_uri", "https://nexus.app/callback"), \
         patch("app.api.spotify.auth.exchange_code", side_effect=Exception("Exchange failed")):
        cb_exch_err = await spotify_callback(request=req, background_tasks=bg, code="code123", state="st123")
        assert cb_exch_err.status_code == 500

    # 7. spotify_callback - no top artists -> 422
    tokens_mock = MagicMock(access_token="acc_123", refresh_token="ref_123", scope="user-top-read")
    with patch("app.api.spotify.auth._consume_state", new_callable=AsyncMock, return_value=USER_1), \
         patch("app.api.spotify.auth.settings.spotify_redirect_uri", "https://nexus.app/callback"), \
         patch("app.api.spotify.auth.exchange_code", new_callable=AsyncMock, return_value=tokens_mock), \
         patch("app.api.spotify.auth._seed_and_queue_sync", new_callable=AsyncMock, return_value=[]):
        cb_no_art = await spotify_callback(request=req, background_tasks=bg, code="code123", state="st123")
        assert cb_no_art.status_code == 422

    # 8. spotify_callback - success -> 200
    with patch("app.api.spotify.auth._consume_state", new_callable=AsyncMock, return_value=USER_1), \
         patch("app.api.spotify.auth.settings.spotify_redirect_uri", "https://nexus.app/callback"), \
         patch("app.api.spotify.auth.exchange_code", new_callable=AsyncMock, return_value=tokens_mock), \
         patch("app.api.spotify.auth._seed_and_queue_sync", new_callable=AsyncMock, return_value=["Radiohead", "Daft Punk"]):
        cb_ok = await spotify_callback(request=req, background_tasks=bg, code="code123", state="st123")
        assert cb_ok.status_code == 200


# ==============================================================================
# 2. SPOTIFY SYNC API TESTS
# ==============================================================================

async def test_spotify_sync_endpoints():
    req = make_mock_request()
    bg = BackgroundTasks()

    # 1. Track and Playlist row converters
    t_out = _track_out_from_row({"spotify_track_id": "tr_1", "name": "Song 1", "artists": ["Singer 1"]})
    assert t_out.name == "Song 1"

    p_out = _playlist_out_from_row({
        "id": "pl_db_1",
        "spotify_playlist_id": "pl_1",
        "name": "My Favorites",
        "is_collaborative": False,
        "track_count": 1,
        "tracks": [{"spotify_track_id": "tr_1", "name": "Song 1", "artists": ["Singer 1"]}],
        "synced_at": datetime.now(timezone.utc),
    })
    assert p_out.name == "My Favorites"
    assert len(p_out.tracks) == 1

    # 2. spotify_status - disconnected
    with patch("app.api.spotify.sync.get_connection", return_value=None):
        stat_disc = await spotify_status(request=req, user_id=USER_1)
        assert stat_disc.connected is False

    # 3. spotify_status - connected
    with patch("app.api.spotify.sync.get_connection", return_value={"last_synced_at": "2026-08-01T00:00:00Z"}), \
         patch("app.api.spotify.sync.fetch_playlists_for_owner", return_value=[{"id": "pl_1"}]):
        stat_conn = await spotify_status(request=req, user_id=USER_1)
        assert stat_conn.connected is True
        assert stat_conn.playlist_count == 1

    # 4. spotify_playlists - DB error -> 500
    with patch("app.api.spotify.sync.get_connection", return_value={"last_synced_at": "2026-08-01T00:00:00Z"}), \
         patch("app.api.spotify.sync.fetch_playlists_for_owner", side_effect=DatabaseAccessError("DB error")):
        with pytest.raises(HTTPException) as exc_pl_500:
            await spotify_playlists(request=req, user_id=USER_1)
        assert exc_pl_500.value.status_code == 500

    # 5. spotify_playlists - success
    with patch("app.api.spotify.sync.get_connection", return_value={"last_synced_at": "2026-08-01T00:00:00Z"}), \
         patch("app.api.spotify.sync.fetch_playlists_for_owner", return_value=[]):
        pls = await spotify_playlists(request=req, user_id=USER_1)
        assert pls.connected is True
        assert len(pls.playlists) == 0

    # 6. spotify_resync - no refresh token -> 404
    with patch("app.api.spotify.sync.get_decrypted_refresh_token", return_value=None):
        with pytest.raises(HTTPException) as exc_resync_404:
            await spotify_resync(request=req, background_tasks=bg, user_id=USER_1)
        assert exc_resync_404.value.status_code == 404

    # 7. spotify_resync - refresh success
    ref_tokens = MagicMock(access_token="new_acc_123", refresh_token="new_ref_123", scope="user-top-read")
    with patch("app.api.spotify.sync.get_decrypted_refresh_token", return_value="old_ref_123"), \
         patch("app.api.spotify.sync.refresh_access_token", new_callable=AsyncMock, return_value=ref_tokens), \
         patch("app.api.spotify.sync.get_connection", return_value={"spotify_user_id": "sp_user_1"}), \
         patch("app.api.spotify.sync.upsert_connection"):
        resync_res = await spotify_resync(request=req, background_tasks=bg, user_id=USER_1)
        assert resync_res["syncing"] is True

    # 8. spotify_disconnect - DB error -> 500
    with patch("app.api.spotify.sync.get_decrypted_refresh_token", return_value="ref_123"), \
         patch("app.api.spotify.sync.disconnect_connection", side_effect=DatabaseAccessError("DB error")):
        with pytest.raises(HTTPException) as exc_disc_500:
            await spotify_disconnect(request=req, background_tasks=bg, user_id=USER_1)
        assert exc_disc_500.value.status_code == 500

    # 9. spotify_disconnect - success
    with patch("app.api.spotify.sync.get_decrypted_refresh_token", return_value="ref_123"), \
         patch("app.api.spotify.sync.disconnect_connection"), \
         patch("app.api.spotify.sync.invalidate_viewer_discovery_sessions"):
        disc_res = await spotify_disconnect(request=req, background_tasks=bg, user_id=USER_1)
        assert disc_res["disconnected"] is True


# ==============================================================================
# 3. API DEPENDENCIES & AUTH GUARDS TESTS
# ==============================================================================

async def test_bearer_token_dependencies():
    # 1. get_bearer_token
    with pytest.raises(HTTPException) as exc_no_creds:
        get_bearer_token(credentials=None)
    assert exc_no_creds.value.status_code == 401

    with pytest.raises(HTTPException) as exc_bad_scheme:
        get_bearer_token(credentials=HTTPAuthorizationCredentials(scheme="Basic", credentials="xyz"))
    assert exc_bad_scheme.value.status_code == 401

    token = get_bearer_token(credentials=HTTPAuthorizationCredentials(scheme="Bearer", credentials="jwt.token.here"))
    assert token == "jwt.token.here"

    # 2. get_optional_bearer_token
    assert get_optional_bearer_token(credentials=None) is None
    assert get_optional_bearer_token(credentials=HTTPAuthorizationCredentials(scheme="Basic", credentials="xyz")) is None
    assert get_optional_bearer_token(credentials=HTTPAuthorizationCredentials(scheme="Bearer", credentials="jwt.token.here")) == "jwt.token.here"


from unittest.mock import PropertyMock


async def test_jwt_decoding_and_authenticated_payload():
    req = make_mock_request()

    # 1. Symmetric HS256 decode
    with patch("app.core.config.Settings.is_jwks", new_callable=PropertyMock, return_value=False):
        # Invalid secret configuration type
        with pytest.raises(jwt.InvalidTokenError):
            _decode_jwt("token", secret={"not": "string"}, public_key=None)

    # 2. get_authenticated_user_payload - missing sub claim -> 401
    with patch("app.core.config.Settings.is_jwks", new_callable=PropertyMock, return_value=False), \
         patch("app.api.dependencies.settings.supabase_jwt_secret", "secret_key"), \
         patch("app.api.dependencies._decode_jwt", return_value={"aud": "authenticated"}):
        with pytest.raises(HTTPException) as exc_no_sub:
            await get_authenticated_user_payload(request=req, token="test_token")
        assert exc_no_sub.value.status_code == 401

    # 3. get_authenticated_user_payload - ExpiredSignatureError -> 401
    with patch("app.core.config.Settings.is_jwks", new_callable=PropertyMock, return_value=False), \
         patch("app.api.dependencies.settings.supabase_jwt_secret", "secret_key"), \
         patch("app.api.dependencies._decode_jwt", side_effect=jwt.ExpiredSignatureError("Expired")):
        with pytest.raises(HTTPException) as exc_exp:
            await get_authenticated_user_payload(request=req, token="test_token")
        assert exc_exp.value.status_code == 401

    # 4. get_authenticated_user_payload - success
    with patch("app.core.config.Settings.is_jwks", new_callable=PropertyMock, return_value=False), \
         patch("app.api.dependencies.settings.supabase_jwt_secret", "secret_key"), \
         patch("app.api.dependencies._decode_jwt", return_value={"sub": USER_1, "aud": "authenticated"}):
        payload = await get_authenticated_user_payload(request=req, token="test_token")
        assert payload["sub"] == USER_1
        assert req.state.user_id == USER_1


async def test_presence_and_account_status():
    # 1. Presence throttle check
    assert _should_trigger_presence("presence_user_1") is True
    assert _should_trigger_presence("presence_user_1") is False

    # 2. Account suspended check
    assert is_account_suspended({"is_suspended": False}) is False
    assert is_account_suspended({"is_suspended": True, "suspended_until": None}) is True
    future_dt = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
    assert is_account_suspended({"is_suspended": True, "suspended_until": future_dt}) is True
    past_dt = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    assert is_account_suspended({"is_suspended": True, "suspended_until": past_dt}) is False

    # 3. Build suspension error detail
    for reason in ["spam", "harassment", "csam", "fraud", "inappropriate_content", "terms_violation", "unknown"]:
        detail = _build_suspension_error_detail({"is_suspended": True, "moderation_reason_code": reason})
        assert "suspended" in detail.lower()

    # 4. assert_account_active
    with pytest.raises(HTTPException) as exc_inactive:
        assert_account_active({"is_active": False})
    assert exc_inactive.value.status_code == 403

    with pytest.raises(HTTPException) as exc_del:
        assert_account_active({"is_active": True, "deletion_requested_at": "2026-08-01T00:00:00Z"})
    assert exc_del.value.status_code == 403

    with pytest.raises(HTTPException) as exc_ban:
        assert_account_active({"is_active": True, "moderation_status": "Banned"})
    assert exc_ban.value.status_code == 403

    with pytest.raises(HTTPException) as exc_susp:
        assert_account_active({"is_active": True, "is_suspended": True, "suspended_until": None})
    assert exc_susp.value.status_code == 403

    # Active user -> no error
    assert_account_active({"is_active": True, "moderation_status": "Active", "is_suspended": False})


async def test_user_caching_and_active_user_id():
    # 1. get_cached_public_user - cache hit
    user_data = {"id": USER_1, "is_active": True}
    with patch("app.api.dependencies.redis_client.get", new_callable=AsyncMock, return_value=json.dumps(user_data)):
        cached = await get_cached_public_user(USER_1)
        assert cached is not None
        assert cached["id"] == USER_1

    # 2. get_cached_public_user - DB fetch
    with patch("app.api.dependencies.redis_client.get", new_callable=AsyncMock, return_value=None), \
         patch("app.api.dependencies.fetch_public_user", return_value=user_data), \
         patch("app.api.dependencies.redis_client.set", new_callable=AsyncMock):
        fetched = await get_cached_public_user(USER_1)
        assert fetched is not None
        assert fetched["id"] == USER_1

    # 3. get_active_user_id - not found -> 404
    with patch("app.api.dependencies.get_cached_public_user", return_value=None):
        with pytest.raises(HTTPException) as exc_not_found:
            await get_active_user_id(user_id=USER_1)
        assert exc_not_found.value.status_code == 404

    # 4. get_active_user_id - success
    with patch("app.api.dependencies.get_cached_public_user", return_value=user_data):
        active_id = await get_active_user_id(user_id=USER_1)
        assert active_id == USER_1


async def test_consent_and_app_check_dependencies():
    # 1. is_consent_stale
    with patch("app.api.dependencies.settings.current_terms_version", "2.0.0"):
        assert is_consent_stale(None) is True
        assert is_consent_stale("1.0.0") is True
        assert is_consent_stale("2.0.0") is False

    # 2. assert_safety_consent and require_safety_consent
    with patch("app.api.dependencies.settings.current_terms_version", "2.0.0"):
        with pytest.raises(HTTPException) as exc_stale_safety:
            assert_safety_consent({"safety_data_consent_version": "1.0.0"})
        assert exc_stale_safety.value.status_code == 412

        with pytest.raises(HTTPException) as exc_stale_special:
            assert_special_category_consent({"special_category_consent_version": "1.0.0"})
        assert exc_stale_special.value.status_code == 412

    # 3. verify_app_check_token
    with patch("app.api.dependencies.settings.enforce_app_check", False):
        verify_app_check_token(x_firebase_appcheck=None)

    with patch("app.api.dependencies.settings.enforce_app_check", True):
        with pytest.raises(HTTPException) as exc_missing_appcheck:
            verify_app_check_token(x_firebase_appcheck=None)
        assert exc_missing_appcheck.value.status_code == 401

        with patch("app.api.dependencies.app_check.verify_token", side_effect=Exception("Invalid token")):
            with pytest.raises(HTTPException) as exc_bad_appcheck:
                verify_app_check_token(x_firebase_appcheck="bad_token")
            assert exc_bad_appcheck.value.status_code == 403

    # 4. _consume_app_check_token & replay protection
    with patch("app.api.dependencies.redis_client.set", new_callable=AsyncMock, return_value=False):
        with pytest.raises(HTTPException) as exc_replay:
            await _consume_app_check_token("token123", int(time.time()) + 100, strict=False)
        assert exc_replay.value.status_code == 403

    # 5. resolve_verified_user
    with patch("app.db.users.get_user_email_by_id", return_value="user@example.com"):
        uid, mail = await resolve_verified_user(USER_1, None)
        assert uid == USER_1
        assert mail == "user@example.com"

    with patch("app.db.users.get_user_id_by_email", return_value=USER_2):
        uid2, mail2 = await resolve_verified_user(None, "user2@example.com")
        assert uid2 == USER_2
        assert mail2 == "user2@example.com"

    with pytest.raises(HTTPException) as exc_no_usr:
        await resolve_verified_user(None, None)
    assert exc_no_usr.value.status_code == 400
