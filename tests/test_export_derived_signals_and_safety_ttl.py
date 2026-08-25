"""Unit tests for derived signals disclosure and safety evidence signed URL TTL reduction in export."""

from unittest.mock import MagicMock, patch

from app.core.security.crypto import encrypt_to_hex
from app.db.users.export import (
    _EXPORT_SIGNED_URL_TTL_SECONDS,
    _SAFETY_EVIDENCE_SIGNED_URL_TTL_SECONDS,
    _build_profile_section,
    _build_safety_evidence,
)


def test_export_profile_includes_derived_spotify_affinity_and_disclosure_note() -> None:
    """_build_profile_section must export decrypted artist_affinity, genre_affinity, and derived_signals_note."""
    user_id = "00000000-0000-0000-0000-000000000001"

    mock_profile_raw = {
        "id": user_id,
        "name": encrypt_to_hex("Alice"),
        "age": 25,
        "artist_affinity": encrypt_to_hex('{"radiohead": 0.85, "daft punk": 0.72}'),
        "genre_affinity": encrypt_to_hex('{"indie rock": 0.9, "electronic": 0.65}'),
        "music_taste_synced_at": "2026-08-20T10:00:00Z",
        "profile_pic": None,
        "normal_pics": None,
    }

    mock_res = MagicMock()
    mock_res.data = mock_profile_raw

    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_res

    with patch("app.db.users.export.supabase_client.table", return_value=mock_table):
        res = _build_profile_section(user_id)

    assert res["name"] == "Alice"
    assert res["artist_affinity"] == {"radiohead": 0.85, "daft punk": 0.72}
    assert res["genre_affinity"] == {"indie rock": 0.9, "electronic": 0.65}
    assert res["music_taste_synced_at"] == "2026-08-20T10:00:00Z"
    assert "derived_signals_note" in res
    assert "algorithmic signals derived from your connected Spotify listening history" in res["derived_signals_note"]


def test_export_safety_evidence_uses_1h_signed_url_ttl() -> None:
    """_build_safety_evidence must sign URLs with 1-hour TTL rather than 24h."""
    user_id = "00000000-0000-0000-0000-000000000002"

    mock_evidence_rows = [
        {
            "id": "ev-1",
            "alert_id": "alert-1",
            "storage_path": "evidence/audio_1.enc",
            "content_type": "audio/mp4",
            "duration_seconds": 30,
            "created_at": "2026-08-25T12:00:00Z",
        },
    ]

    mock_res = MagicMock()
    mock_res.data = mock_evidence_rows

    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.execute.return_value = mock_res

    mock_storage_bucket = MagicMock()
    mock_storage_bucket.create_signed_urls.return_value = [
        {"path": "evidence/audio_1.enc", "signedURL": "https://storage.example.com/signed-1h"},
    ]

    with patch("app.db.users.export.supabase_client.table", return_value=mock_table), \
         patch("app.db.users.export.supabase_client.storage.from_", return_value=mock_storage_bucket):
        evidence = _build_safety_evidence(user_id)

    assert len(evidence) == 1
    assert evidence[0]["download_url"] == "https://storage.example.com/signed-1h"

    # Verify create_signed_urls was called with TTL = 3600 (1h), not 86400 (24h)
    mock_storage_bucket.create_signed_urls.assert_called_once_with(
        ["evidence/audio_1.enc"],
        _SAFETY_EVIDENCE_SIGNED_URL_TTL_SECONDS,
    )
    assert _SAFETY_EVIDENCE_SIGNED_URL_TTL_SECONDS == 3600
    assert _EXPORT_SIGNED_URL_TTL_SECONDS == 86400
