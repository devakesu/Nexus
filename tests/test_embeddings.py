from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from app.services.embeddings import (
    generate_nexus_intent_embeddings,
    get_embedding_model,
)


@patch("app.services.embeddings.get_embedding_model")
def test_generate_nexus_intent_embeddings_sanitizes_and_caps_bio(mock_get_model: MagicMock) -> None:
    mock_model = MagicMock()
    mock_model.encode.return_value = np.array([0.1, 0.2, 0.3])
    mock_get_model.return_value = mock_model

    long_bio = "  " + "A" * 800 + "   \n\n\t  "
    profile = {
        "lifestyle": "Active gym goer",
        "partner_values": ["Honesty", "Ambition"],
        "religious_beliefs": "Spiritual",
        "children_plans": "Someday",
        "campus_branch": "CSE",
        "campus_year": 3,
        "role_at": "ML Engineer",
        "looking_for": ["Hackathon Partner"],
        "tech_skills": ["Python", "PyTorch"],
        "sub_interests": {"tech": ["AI", "Robotics"]},
        "display_gender": "Non-binary",
        "pronouns": "they/them",
        "causes_supported": ["Open Source"],
        "activities": ["Coding club"],
    }

    result = generate_nexus_intent_embeddings(profile=profile, raw_plaintext_bio=long_bio)

    assert "bio_embedding" in result
    assert "career_embedding" in result
    assert "identity_embedding" in result
    assert result["bio_embedding"] == [0.1, 0.2, 0.3]

    assert mock_model.encode.call_count == 3
    bio_call_arg = mock_model.encode.call_args_list[0][0][0]
    career_call_arg = mock_model.encode.call_args_list[1][0][0]
    identity_call_arg = mock_model.encode.call_args_list[2][0][0]

    # Verify bio was capped at 500 characters
    assert "A" * 500 in bio_call_arg
    assert "A" * 501 not in bio_call_arg
    # Verify structured non-sensitive fields were included in context
    assert "Lifestyle & Day Structure: Active gym goer" in bio_call_arg
    assert "Intent/Values Checklist: Honesty, Ambition" in bio_call_arg

    # Verify special-category / sensitive fields are strictly EXCLUDED from all embedding contexts
    all_contexts = [bio_call_arg, career_call_arg, identity_call_arg]
    for ctx in all_contexts:
        assert "Spiritual" not in ctx
        assert "Someday" not in ctx
        assert "religious_beliefs" not in ctx
        assert "children_plans" not in ctx
        assert "display_sexuality" not in ctx

    # Verify context length caps
    assert len(bio_call_arg) <= 1024
    assert len(career_call_arg) <= 1024
    assert len(identity_call_arg) <= 1024


@patch("app.services.embeddings.SentenceTransformer")
def test_get_embedding_model_success(mock_st_class: MagicMock) -> None:
    import app.services.embeddings as emb_module

    emb_module._model = None

    mock_instance = MagicMock()
    mock_instance.encode.return_value = np.array([0.1, 0.2])
    mock_st_class.return_value = mock_instance

    model = get_embedding_model()
    assert model == mock_instance
    mock_instance.encode.assert_called_once_with("test")


@patch("app.services.embeddings.SentenceTransformer")
def test_get_embedding_model_initialization_failure(mock_st_class: MagicMock) -> None:
    import app.services.embeddings as emb_module

    emb_module._model = None

    mock_instance = MagicMock()
    mock_instance.encode.side_effect = Exception("Model inference test failure")
    mock_st_class.return_value = mock_instance

    with pytest.raises(RuntimeError) as exc_info:
        get_embedding_model()
    assert "Embedding model failed to initialize" in str(exc_info.value)
    assert emb_module._model is None


@patch("app.services.profile.supabase_client")
@patch("app.services.profile.sync_redis_client")
def test_recompile_and_push_vectors_cooldown(
    mock_redis: MagicMock,
    mock_supabase: MagicMock,
) -> None:
    from app.services.profile import recompile_and_push_vectors

    # 1. Cooldown active -> set returns False -> skips DB fetch
    mock_redis.set.return_value = False
    recompile_and_push_vectors("user-123")
    mock_supabase.table.assert_not_called()

    # 2. Cooldown not active -> set returns True -> proceeds to DB fetch
    mock_redis.set.return_value = True
    mock_select = MagicMock()
    mock_select.return_value.data = None  # profile not found
    mock_supabase.table.return_value.select.return_value.eq.return_value.maybe_single.return_value.execute = mock_select
    recompile_and_push_vectors("user-123")
    mock_supabase.table.assert_called_with("profiles")


