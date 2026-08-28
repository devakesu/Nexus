"""Unit tests for profile service background recompilation resilience and value dimensions derivation."""

from unittest.mock import MagicMock, patch

import numpy as np

from app.services.profile import recompile_and_push_vectors
from app.services.value_dimensions import (
    _get_anchor_vecs,
    derive_value_dimensions,
    recompile_value_dimensions,
)


def test_recompile_and_push_vectors_cooldown_active():
    """When Redis cooldown key is active, vector recompilation should be skipped."""
    with patch("app.services.profile.sync_redis_client.set", return_value=False) as mock_set:
        with patch("app.services.profile.supabase_client") as mock_supabase:
            recompile_and_push_vectors("user-123")
            mock_set.assert_called_once_with("user:vector_recompile_cooldown:user-123", "1", ex=60, nx=True)
            mock_supabase.table.assert_not_called()


def test_recompile_and_push_vectors_profile_not_found():
    """When profile is missing in database, recompilation should safely return."""
    mock_res = MagicMock()
    mock_res.data = None
    mock_table = MagicMock()
    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_res

    with patch("app.services.profile.sync_redis_client.set", return_value=True):
        with patch("app.services.profile.supabase_client.table", return_value=mock_table):
            recompile_and_push_vectors("user-123")


def test_recompile_and_push_vectors_pseudonym_map_fallback_success():
    """When pseudonym map upsert returns empty list (conflict), fallback select should resolve the pseudonym."""
    profile_data = {
        "id": "user-123",
        "bio": "enc_bio",
        "lifestyle": "enc_life",
        "campus_name": "MIT",
    }
    mock_prof_res = MagicMock(data=profile_data)

    mock_map_upsert_res = MagicMock(data=[])
    mock_map_select_res = MagicMock(data={"pseudonym_id": "pseudo-xyz-999"})
    mock_vec_upsert_res = MagicMock(data=[{"pseudonym_id": "pseudo-xyz-999"}])

    def table_mock(table_name: str) -> MagicMock:
        mock_t = MagicMock()
        if table_name == "profiles":
            mock_t.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_prof_res
        elif table_name == "profile_pseudonym_map":
            mock_t.upsert.return_value.select.return_value.execute.return_value = mock_map_upsert_res
            mock_t.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_map_select_res
        elif table_name == "vector_profiles":
            mock_t.upsert.return_value.execute.return_value = mock_vec_upsert_res
        return mock_t

    with patch("app.services.profile.sync_redis_client.set", side_effect=Exception("Redis down")):
        with patch("app.services.profile.supabase_client.table", side_effect=table_mock):
            with patch("app.services.profile.decrypt_profile_record", return_value=profile_data):
                with patch("app.services.profile.sanitize_decrypted_profile", return_value=profile_data):
                    with patch(
                        "app.services.profile.generate_nexus_intent_embeddings",
                        return_value={
                            "bio_embedding": [0.1, 0.2],
                            "career_embedding": [0.3, 0.4],
                            "identity_embedding": [0.5, 0.6],
                        },
                    ):
                        recompile_and_push_vectors("user-123", plaintext_bio="Hello world!")


def test_recompile_and_push_vectors_pseudonym_map_fallback_failure_aborts():
    """When fallback select also returns None, recompilation should log error and abort without raising."""
    profile_data = {"id": "user-123", "bio": "test"}
    mock_prof_res = MagicMock(data=profile_data)
    mock_map_upsert_res = MagicMock(data=[])
    mock_map_select_res = MagicMock(data=None)

    def table_mock(table_name: str) -> MagicMock:
        mock_t = MagicMock()
        if table_name == "profiles":
            mock_t.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_prof_res
        elif table_name == "profile_pseudonym_map":
            mock_t.upsert.return_value.select.return_value.execute.return_value = mock_map_upsert_res
            mock_t.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = mock_map_select_res
        return mock_t

    with patch("app.services.profile.sync_redis_client.set", return_value=True):
        with patch("app.services.profile.supabase_client.table", side_effect=table_mock):
            with patch("app.services.profile.decrypt_profile_record", return_value=profile_data):
                with patch("app.services.profile.sanitize_decrypted_profile", return_value=profile_data):
                    with patch(
                        "app.services.profile.generate_nexus_intent_embeddings",
                        return_value={"bio_embedding": [], "career_embedding": [], "identity_embedding": []},
                    ):
                        recompile_and_push_vectors("user-123")


def test_recompile_and_push_vectors_general_exception_handled():
    """Unexpected exception in vector recompilation is caught and logged silently."""
    with patch("app.services.profile.sync_redis_client.set", return_value=True):
        with patch("app.services.profile.supabase_client.table", side_effect=RuntimeError("DB completely broken")):
            recompile_and_push_vectors("user-123")


def test_value_dimensions_anchor_vecs_initialization():
    """Test cold-start initialization of anchor vectors and normalization."""
    import app.services.value_dimensions as vd_mod

    vd_mod._anchor_vecs = None

    mock_model = MagicMock()
    mock_model.encode.return_value = np.array([[1.0, 0.0], [0.0, 1.0]], dtype=np.float32)

    with patch("app.services.value_dimensions.get_embedding_model", return_value=mock_model):
        anchors = _get_anchor_vecs()
        assert isinstance(anchors, dict)
        assert len(anchors) > 0
        # Second call returns cached dict without re-encoding
        anchors_cached = _get_anchor_vecs()
        assert anchors is anchors_cached


def test_derive_value_dimensions_exception_fallback():
    """On model encoding or calculation failure, derive_value_dimensions falls back to default dimensions."""
    mock_model = MagicMock()
    mock_model.encode.side_effect = RuntimeError("Embedding model inference error")

    with patch("app.services.value_dimensions.get_embedding_model", return_value=mock_model):
        with patch(
            "app.services.value_dimensions._get_anchor_vecs",
            return_value={
                "technology_optimism": np.array([1.0, 0.0]),
                "environmentalism": np.array([0.0, 1.0]),
                "civil_liberties": np.array([1.0, 1.0]),
            },
        ):
            result = derive_value_dimensions(
                interests={"tech": 1},
                sub_interests={"tech": ["coding"]},
                causes_supported=["climate"],
                tech_skills=["python"],
                activities=["running"],
                lifestyle="morning person",
                bio="developer",
            )
            assert isinstance(result, dict)
            assert result.get("technology_optimism") == 5


def test_recompile_value_dimensions_cooldown_and_execution():
    """Test recompile_value_dimensions cooldown branch."""
    with patch("app.services.value_dimensions.sync_redis_client.set", return_value=False):
        recompile_value_dimensions("user-123")
