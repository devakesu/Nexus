"""Test coverage suite for Value Dimensions and Profile Vector compilation services.

Covers:
- app/services/value_dimensions.py
- app/services/profile.py
"""

from __future__ import annotations

import json
from unittest.mock import MagicMock, patch

import numpy as np
import pytest

from app.core.security.crypto import encrypt_to_hex
from app.services.profile import recompile_and_push_vectors
from app.services.value_dimensions import (
    _DEFAULT_DIMENSIONS,
    _compile_filtered_text_for_dimension,
    _sim_to_score,
    derive_value_dimensions,
    recompile_value_dimensions,
)

pytestmark = pytest.mark.anyio

USER_1 = "00000000-0000-0000-0000-000000000001"


# ==============================================================================
# 1. VALUE DIMENSIONS SCORING & COMPILATION
# ==============================================================================

def test_value_dimensions_internals_and_derivation():
    # 1. _sim_to_score
    assert _sim_to_score(0.10) == 0
    assert _sim_to_score(0.60) == 9
    assert 0 <= _sim_to_score(0.35) <= 9

    # 2. _compile_filtered_text_for_dimension
    compiled_text = _compile_filtered_text_for_dimension(
        dimension="technology_optimism",
        interests={"Coding": 5, "Gardening": 3},
        sub_interests={"Tech": ["AI", "Cybersecurity", "Baking"]},
        causes_supported=["Tech Ethics"],
        tech_skills=["Python", "Flutter & Dart"],
        activities=["Design", "Hiking"],
        lifestyle="Passionate about AI innovation and digital autonomy",
        bio="Software engineer dedicated to programming and tech ethics",
    )
    assert "Coding" in compiled_text or "coding" in compiled_text.lower()
    assert "AI" in compiled_text or "ai" in compiled_text.lower()
    assert "Python" in compiled_text
    assert "AI innovation" in compiled_text

    # 3. derive_value_dimensions with empty signals -> default values
    defaults = derive_value_dimensions({}, {}, [], [], [], "", "")
    assert defaults == _DEFAULT_DIMENSIONS

    # 4. derive_value_dimensions with populated signals
    mock_model = MagicMock()
    # Mock return 384-dim normalized embedding vectors
    mock_model.encode.return_value = np.ones((1, 384), dtype=np.float32) / np.sqrt(384)
    with patch("app.services.value_dimensions.get_embedding_model", return_value=mock_model), \
         patch("app.services.value_dimensions._get_anchor_vecs", return_value={
             "civil_liberties": np.ones((384,), dtype=np.float32) / np.sqrt(384),
             "environmentalism": np.ones((384,), dtype=np.float32) / np.sqrt(384),
             "technology_optimism": np.ones((384,), dtype=np.float32) / np.sqrt(384),
         }):
        dims = derive_value_dimensions(
            interests={"Coding": 5},
            sub_interests={"Tech": ["AI"]},
            causes_supported=["Tech Ethics"],
            tech_skills=["Python"],
            activities=["Design"],
            lifestyle="Tech enthusiast",
            bio="Building software",
        )
        assert len(dims) == 3
        assert "technology_optimism" in dims


def test_recompile_value_dimensions_flow():
    mock_table = MagicMock()

    # 1. Cooldown active -> skipped
    with patch("app.services.value_dimensions.sync_redis_client.set", return_value=False):
        recompile_value_dimensions(USER_1)

    # 2. Profile missing -> skipped
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(data=None)
    with patch("app.services.value_dimensions.sync_redis_client.set", return_value=True), \
         patch("app.services.value_dimensions.supabase_client.table", return_value=mock_table):
        recompile_value_dimensions(USER_1)

    # 3. Successful recompilation & database update
    mock_profile_raw = {
        "interests": encrypt_to_hex(json.dumps({"Coding": 5})),
        "sub_interests": encrypt_to_hex(json.dumps({"Tech": ["AI"]})),
        "causes_supported": encrypt_to_hex(json.dumps(["Tech Ethics"])),
        "tech_skills": encrypt_to_hex(json.dumps(["Python"])),
        "activities": encrypt_to_hex(json.dumps(["Design"])),
        "lifestyle": encrypt_to_hex("Tech enthusiast"),
        "bio": encrypt_to_hex("Building software"),
    }
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data=mock_profile_raw,
    )
    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(data=[])
    with patch("app.services.value_dimensions.sync_redis_client.set", return_value=True), \
         patch("app.services.value_dimensions.supabase_client.table", return_value=mock_table), \
         patch("app.services.value_dimensions.derive_value_dimensions", return_value={"technology_optimism": 8}):
        recompile_value_dimensions(USER_1)
        mock_table.update.assert_called_once()


# ==============================================================================
# 2. PROFILE VECTOR COMPILATION SERVICE
# ==============================================================================

def test_recompile_and_push_vectors_flow():
    mock_table = MagicMock()

    # 1. Cooldown active -> skipped
    with patch("app.services.profile.sync_redis_client.set", return_value=False):
        recompile_and_push_vectors(USER_1)

    # 2. Profile not found -> skipped
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(data=None)
    with patch("app.services.profile.sync_redis_client.set", return_value=True), \
         patch("app.services.profile.supabase_client.table", return_value=mock_table):
        recompile_and_push_vectors(USER_1)

    # 3. Successful vector calculation and pseudonym mapping
    mock_prof_data = {
        "id": USER_1,
        "bio": encrypt_to_hex("Hello world bio"),
        "campus_branch": "CSE",
        "campus_year": 2026,
    }
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data=mock_prof_data,
    )

    mock_map_table = MagicMock()
    mock_map_table.upsert.return_value.select.return_value.execute.return_value = MagicMock(
        data=[{"pseudonym_id": "pseudo_123"}],
    )
    mock_vec_table = MagicMock()
    mock_vec_table.upsert.return_value.execute.return_value = MagicMock(data=[])

    def table_router(name: str):
        if name == "profiles":
            return mock_table
        if name == "profile_pseudonym_map":
            return mock_map_table
        if name == "vector_profiles":
            return mock_vec_table
        return MagicMock()

    mock_vectors = {
        "bio_embedding": [0.1] * 384,
        "career_embedding": [0.2] * 384,
        "identity_embedding": [0.3] * 384,
    }

    with patch("app.services.profile.sync_redis_client.set", return_value=True), \
         patch("app.services.profile.supabase_client.table", side_effect=table_router), \
         patch("app.services.profile.generate_nexus_intent_embeddings", return_value=mock_vectors):
        recompile_and_push_vectors(USER_1, plaintext_bio="Custom bio text")
        mock_vec_table.upsert.assert_called_once()
