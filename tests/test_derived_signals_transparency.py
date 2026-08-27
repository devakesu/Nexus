from typing import Any
from unittest.mock import MagicMock, patch

from fastapi import Request

from app.api.user.profile.details import get_profile_derived_signals
from app.models import (
    ALLOWED_HIDDEN_FIELDS,
    PrivacySettingsUpdate,
    ProfileDerivedSignalsResponse,
)


def _make_dummy_request() -> Request:
    scope: dict[str, Any] = {
        "type": "http",
        "headers": [],
        "query_string": b"",
        "path": "/api/v1/profile/derived-signals",
    }
    return Request(scope)


def test_children_plans_in_allowed_hidden_fields() -> None:
    assert "children_plans" in ALLOWED_HIDDEN_FIELDS

    update = PrivacySettingsUpdate(hidden_fields=["children_plans", "top_artists"])
    assert update.hidden_fields is not None
    assert set(update.hidden_fields) == {"children_plans", "top_artists"}


@patch("app.api.user.profile.details.supabase_client")
def test_get_profile_derived_signals_transparency_endpoint(mock_supabase: MagicMock) -> None:
    user_id = "11111111-1111-1111-1111-111111111111"

    from app.core.security.crypto import encrypt_to_hex

    mock_profile_res = MagicMock()
    mock_profile_res.data = {
        "id": user_id,
        "display_sexuality": encrypt_to_hex("Asexual"),
        "ai_vibe_tags": ["Creative", "Intellectual"],
        "artist_affinity": {"Radiohead": 0.8},
        "genre_affinity": {"Indie Rock": 0.9},
        "bio_embedding": [0.1] * 768,
        "career_embedding": [0.2] * 768,
        "identity_embedding": None,
    }

    mock_privacy_res = MagicMock()
    mock_privacy_res.data = {
        "hidden_fields": ["children_plans", "top_artists"],
    }

    def table_mock(name: str) -> MagicMock:
        table = MagicMock()
        if name == "profiles":
            table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_profile_res
        elif name == "privacy_settings":
            table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_privacy_res
        return table

    mock_supabase.table.side_effect = table_mock

    req = _make_dummy_request()
    res = get_profile_derived_signals(request=req, _device=None, user_id=user_id)

    assert isinstance(res, ProfileDerivedSignalsResponse)
    assert res.user_id == user_id
    assert res.ai_vibe_tags == ["Creative", "Intellectual"]
    assert res.artist_affinity == {"Radiohead": 0.8}
    assert res.genre_affinity == {"Indie Rock": 0.9}
    assert res.orientation_weight_profile == "Asexual"
    assert res.embedding_signals["bio_embedding"]["generated"] is True
    assert res.embedding_signals["bio_embedding"]["dimension"] == 768
    assert res.embedding_signals["career_embedding"]["generated"] is True
    assert res.embedding_signals["identity_embedding"]["generated"] is False
    assert "children_plans" in res.hidden_profile_fields
    assert "top_artists" in res.hidden_profile_fields
    assert "Dating" in res.active_scoring_weights
    assert "GDPR" in res.transparency_notice
