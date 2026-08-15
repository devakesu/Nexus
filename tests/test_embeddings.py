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
    # Verify structured fields were included in context
    assert "Lifestyle & Day Structure: Active gym goer" in bio_call_arg
    assert "Intent/Values Checklist: Honesty, Ambition" in bio_call_arg

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

