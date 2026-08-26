"""Phase 21 Coverage Suite: Comprehensive coverage for app/db/spotify.py and app/api/spotify/auth.py."""

from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException
from postgrest.exceptions import APIError

from app.core.security.crypto import DecryptFailedError
from app.db.client import DatabaseAccessError

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"


# =============================================================================
# 1. DB SPOTIFY TESTS
# =============================================================================

def test_db_spotify_deep():
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

    # get_connection: APIError & empty rows
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            get_connection(USER_1)

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        assert get_connection(USER_1) is None

    # get_decrypted_refresh_token: None connection, no token, DecryptFailedError
    with patch("app.db.spotify.get_connection", return_value=None):
        assert get_decrypted_refresh_token(USER_1) is None

    with patch("app.db.spotify.get_connection", return_value={"refresh_token": None}):
        assert get_decrypted_refresh_token(USER_1) is None

    with patch("app.db.spotify.get_connection", return_value={"refresh_token": "enc_token"}), \
         patch("app.db.spotify.decrypt_pii", side_effect=DecryptFailedError("fail")):
        assert get_decrypted_refresh_token(USER_1) is None

    # upsert_connection APIError
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().upsert().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            upsert_connection(USER_1, "spot_u1", "token", "scope")

    # _sanitize_sync_error
    assert _sanitize_sync_error(None) is None
    err = "Bearer 12345 secret and test@example.com for spotify:user:alice123"
    san = _sanitize_sync_error(err)
    assert san is not None
    assert "Bearer [REDACTED]" in san
    assert "[EMAIL_REDACTED]" in san
    assert "spotify:user:[REDACTED]" in san

    # mark_sync_result APIError catch
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().update().eq().execute.side_effect = APIError({"message": "fail"})
        # Should not raise
        mark_sync_result(USER_1, "error", "some error")

    # disconnect APIError
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().delete().eq().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            disconnect(USER_1)

    # replace_playlists APIError
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().upsert().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            replace_playlists(USER_1, [{"spotify_playlist_id": "p1", "name": "P1", "tracks": [{"artists": ["A1"], "name": "T1"}]}])

    # fetch_playlists_for_owner: APIError, non-dict rows, DecryptFailedError, JSONDecodeError
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().select().eq().order().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            fetch_playlists_for_owner(USER_1)

        mock_sb.table().select().eq().order().execute.side_effect = None
        mock_sb.table().select().eq().order().execute.return_value = MagicMock(
            data=[
                "not-a-dict",
                {"spotify_playlist_id": "p1", "name": "bad_enc_name", "tracks": "bad_enc_tracks"},
                {"spotify_playlist_id": "p2", "name": None, "tracks": None},
            ],
        )
        with patch("app.db.spotify.decrypt_pii", side_effect=DecryptFailedError("fail")):
            res = fetch_playlists_for_owner(USER_1)
            assert len(res) == 2
            assert res[0]["name"] == ""
            assert res[0]["tracks"] == []

    # persist_artist_signals APIError
    with patch("app.db.spotify.supabase_client") as mock_sb:
        mock_sb.table().update().eq().execute.side_effect = APIError({"message": "fail"})
        with pytest.raises(DatabaseAccessError):
            persist_artist_signals(USER_1, {"A1": 1.0}, ["A1"], {"pop": 0.5})


# =============================================================================
# 2. API SPOTIFY AUTH TESTS
# =============================================================================

async def test_api_spotify_auth_deep():
    from app.api.spotify.auth import (
        _fallback_playlist_sync,
        _NativeExchangeRequest,
        _seed_and_queue_sync,
        spotify_callback,
        spotify_native_exchange,
    )

    # _fallback_playlist_sync exception
    with patch("httpx.AsyncClient.get", side_effect=Exception("network fail")):
        blended, display_names = await _fallback_playlist_sync(
            "token", "spot_u1", {"Artist1": 1.0}, USER_1,
        )
        assert "artist1" in blended
        assert "Artist1" in display_names

    # _seed_and_queue_sync with discovery session invalidation exception
    bg = MagicMock()
    with patch("app.api.spotify.auth.fetch_spotify_user_id", AsyncMock(return_value="spot_u1")), \
         patch("app.api.spotify.auth.upsert_connection"), \
         patch("app.api.spotify.auth.invalidate_viewer_discovery_sessions", side_effect=Exception("cache error")), \
         patch("app.api.spotify.auth.fetch_top_artists_ranked", AsyncMock(return_value=MagicMock(ranked={"A1": 1.0}, genre_weights={"pop": 1.0}))), \
         patch("app.api.spotify.auth.persist_artist_signals"):
        names = await _seed_and_queue_sync(bg, USER_1, "acc_token", None, "user-top-read")
        assert len(names) > 0

    # spotify_native_exchange errors
    mock_req = MagicMock()
    with patch("app.api.spotify.auth.settings.spotify_redirect_uri", "https://app.nexus.test/spotify/callback"):
        # invalid redirect_uri
        with pytest.raises(HTTPException, match="Invalid redirect_uri"):
            await spotify_native_exchange(
                mock_req,
                _NativeExchangeRequest(code="c", redirect_uri="https://attacker.test/cb"),
                bg,
                _device=None,
                user_id=USER_1,
            )

        # exchange_code Exception -> 502
        with patch("app.api.spotify.auth.exchange_code", AsyncMock(side_effect=Exception("bad code"))):
            with pytest.raises(HTTPException, match="Failed to exchange Spotify authorization code"):
                await spotify_native_exchange(
                    mock_req,
                    _NativeExchangeRequest(code="c", redirect_uri="https://app.nexus.test/spotify/callback"),
                    bg,
                    _device=None,
                    user_id=USER_1,
                )

        # empty access_token -> 502
        with patch("app.api.spotify.auth.exchange_code", AsyncMock(return_value=MagicMock(access_token=""))):
            with pytest.raises(HTTPException, match="Spotify did not return a valid access token"):
                await spotify_native_exchange(
                    mock_req,
                    _NativeExchangeRequest(code="c", redirect_uri="https://app.nexus.test/spotify/callback"),
                    bg,
                    _device=None,
                    user_id=USER_1,
                )

        # seed_and_queue_sync failure -> 502
        with patch("app.api.spotify.auth.exchange_code", AsyncMock(return_value=MagicMock(access_token="tok", refresh_token="ref", scope="s"))), \
             patch("app.api.spotify.auth._seed_and_queue_sync", AsyncMock(side_effect=Exception("sync fail"))):
            with pytest.raises(HTTPException, match="Failed to fetch data from Spotify"):
                await spotify_native_exchange(
                    mock_req,
                    _NativeExchangeRequest(code="c", redirect_uri="https://app.nexus.test/spotify/callback"),
                    bg,
                    _device=None,
                    user_id=USER_1,
                )

    # spotify_callback HTML responses for token exchange fail, missing access_token, sync setup exception
    with patch("app.api.spotify.auth.settings.spotify_redirect_uri", "https://app.nexus.test/spotify/callback"), \
         patch("app.api.spotify.auth.redis_client.getdel", AsyncMock(return_value=USER_1)), \
         patch("app.api.spotify.auth.redis_client.delete", AsyncMock()):
        
        # Token exchange exception
        with patch("app.api.spotify.auth.exchange_code", AsyncMock(side_effect=Exception("fail"))):
            resp = await spotify_callback(mock_req, bg, code="c", state="s")
            assert resp.status_code == 500

        # Missing access_token
        with patch("app.api.spotify.auth.exchange_code", AsyncMock(return_value=MagicMock(access_token=""))):
            resp = await spotify_callback(mock_req, bg, code="c", state="s")
            assert resp.status_code == 502

        # Sync setup exception
        with patch("app.api.spotify.auth.exchange_code", AsyncMock(return_value=MagicMock(access_token="t", refresh_token="r", scope="s"))), \
             patch("app.api.spotify.auth._seed_and_queue_sync", AsyncMock(side_effect=Exception("sync error"))):
            resp = await spotify_callback(mock_req, bg, code="c", state="s")
            assert resp.status_code == 500
