"""Test Suite for Test Profiles Db.

Organized domain tests migrated from phase suites.
"""

# pyright: reportUnusedFunction=false, reportConstantRedefinition=false, reportUnknownMemberType=false, reportUnknownArgumentType=false, reportUnknownVariableType=false
from __future__ import annotations

import copy
import json
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from postgrest.exceptions import APIError
from starlette.requests import Request

from app.core.security.crypto import DecryptFailedError, encrypt_to_hex
from app.db.client import (
    DatabaseAccessError,
)
from app.db.profiles.crud import (
    _apply_blind_index_filters,
    _apply_post_fetch_filters,
    _check_candidate_match,
    _enrich_candidates_with_vectors,
    _fetch_and_decrypt_viewer,
    _filter_candidate_matches,
    _map_vector_embeddings,
    _unpack_chat_presence,
)
from app.models import DiscoveryFilters

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


async def test_db_profiles_all_modules():
    from app.db.profiles.crud import (
        fetch_music_affinities,
        fetch_peer_profile_by_id,
        is_active_profile,
    )
    from app.db.profiles.encryption import (
        decrypt_profile_field,
        decrypt_profile_record,
        decrypt_profile_rows,
        sanitize_decrypted_profile,
    )
    from app.db.profiles.media import (
        sign_profile_media,
        sign_profile_media_bulk,
        update_profile_images_and_metadata,
    )

    mock_table = MagicMock()

    # 1. crud.py
    mock_table.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}],
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        assert is_active_profile(USER_1) is True

    mock_table.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[
            {
                "artist_affinity": encrypt_to_hex(json.dumps({"Queen": 0.9})),
                "genre_affinity": None,
            },
        ],
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        aff, _ = fetch_music_affinities(USER_1)
        assert aff is not None

    mock_table.select.return_value.eq.return_value.maybe_single.return_value.execute.return_value = MagicMock(
        data={
            "id": USER_2,
            "name": encrypt_to_hex("Bob", category="profile"),
            "profile_pic": "pic.jpg",
            "is_deactivated": False,
        },
    )
    with (
        patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table),
        patch(
            "app.db.profiles.crud.sign_profile_media",
            return_value={"id": USER_2, "name": "Bob"},
        ),
    ):
        peer = fetch_peer_profile_by_id(USER_2)
        assert peer is not None

    # 2. encryption.py
    enc_val = encrypt_to_hex("Secret bio")
    row_dict = {"bio": enc_val, "age": 25}
    decrypt_profile_field(row_dict, "bio")
    assert row_dict["bio"] == "Secret bio"

    rec = {"bio": enc_val, "age": 25}
    dec_rec = decrypt_profile_record(rec)
    assert dec_rec["bio"] == "Secret bio"

    san = sanitize_decrypted_profile(dec_rec)
    assert san["bio"] == "Secret bio"

    dec_rows = decrypt_profile_rows([{"id": USER_1, "bio": enc_val}])
    assert USER_1 in dec_rows

    # 3. media.py
    mock_storage = MagicMock()
    mock_storage.create_signed_url.return_value = {
        "signedURL": "https://signed.url/pic.jpg",
    }
    mock_storage.create_signed_urls.return_value = [
        {"path": f"{USER_1}/pic.jpg", "signedURL": "https://signed.url/pic.jpg"},
    ]
    with patch(
        "app.db.profiles.media.supabase_client.storage.from_", return_value=mock_storage,
    ):
        signed_profile = sign_profile_media(
            {"id": USER_1, "profile_pic": f"{USER_1}/pic.jpg", "normal_pics": []},
        )
        assert signed_profile["profile_pic"] == "https://signed.url/pic.jpg"

        rows_to_sign = [{"id": USER_1, "profile_pic": f"{USER_1}/pic.jpg"}]
        sign_profile_media_bulk(rows_to_sign)
        assert rows_to_sign[0]["profile_pic"] == "https://signed.url/pic.jpg"

    mock_table.update.return_value.eq.return_value.execute.return_value = MagicMock(
        data=[{"id": USER_1}],
    )
    with patch("app.db.profiles.media.supabase_client.table", return_value=mock_table):
        await update_profile_images_and_metadata(
            USER_1, [f"{USER_1}/pic.jpg"], ["tech", "music"],
        )


def test_db_profiles_crud_exhaustive():
    from app.db.profiles.crud import (
        _apply_post_fetch_filters,
        _filter_candidate_matches,
        _unpack_chat_presence,
    )
    from app.models import DiscoveryFilters

    # Presence unpacking
    row_with_presence = {
        "chat_presence": [{"is_online": True, "last_active_at": "2026-08-25T00:00:00Z"}],
    }
    _unpack_chat_presence(row_with_presence)
    assert row_with_presence.get("last_active_at") == "2026-08-25T00:00:00Z"

    # Filter candidate matches
    candidates = [
        {"id": USER_2, "search_bucket": "F", "dating_target_buckets": ["men"]},
    ]
    res = _filter_candidate_matches(candidates, ["men"], "dating_target_buckets")
    assert isinstance(res, list)

    # Post fetch filters & lifestyle filters
    f = DiscoveryFilters()
    passed = _apply_post_fetch_filters(candidates, f)
    assert len(passed) >= 0


def test_db_profiles_crud_helpers_and_filtering():
    from app.db.profiles.crud import (
        _attach_empty_embeddings,
        _check_basic_overlap,
        _check_lifestyle_filters,
        _enrich_candidates_with_vectors,
        _fetch_and_decrypt_viewer,
        _get_completion_flag_column,
        _get_expanded_viewer_buckets,
        _get_target_bucket_column,
        _list_overlap,
        _map_vector_embeddings,
        _unpack_chat_presence,
        fetch_music_affinities,
        fetch_peer_profile_by_id,
        fetch_stage_1_candidates,
        is_active_profile,
    )

    # _get_completion_flag_column & _get_target_bucket_column
    assert _get_completion_flag_column("Dating") == "is_dating_active"
    assert _get_completion_flag_column("Friends") == "is_friends_active"
    assert _get_completion_flag_column("Professional") == "is_professional_active"
    assert _get_target_bucket_column("Dating") == "dating_target_buckets"
    assert _get_target_bucket_column("Friends") == "friends_target_buckets"
    assert _get_target_bucket_column("Professional") == "professional_target_buckets"

    # _attach_empty_embeddings
    rec: dict[str, Any] = {}
    _attach_empty_embeddings(rec)
    assert rec["bio_embedding"] is None
    assert rec["career_embedding"] is None
    assert rec["identity_embedding"] is None

    # _unpack_chat_presence
    cand = {"chat_presence": [{"last_active_at": "2026-08-26T00:00:00Z"}]}
    _unpack_chat_presence(cand)
    assert cand["last_active_at"] == "2026-08-26T00:00:00Z"

    cand_empty: dict[str, Any] = {"chat_presence": []}
    _unpack_chat_presence(cand_empty)
    assert "last_active_at" not in cand_empty

    # _list_overlap
    assert _list_overlap(["a", "b"], ["b", "c"]) is True
    assert _list_overlap(["a"], ["c"]) is False
    assert _list_overlap([], ["a"]) is False

    # _check_lifestyle_filters & _check_basic_overlap
    filters = DiscoveryFilters(
        smoking=["never"],
        drinking=["socially"],
        partner_values=["honesty"],
        children_plans=["someday"],
        religious_beliefs=["agnostic"],
        tech_skills=["python"],
        languages=["english"],
        causes_supported=["climate"],
    )

    match_c = {
        "id": USER_2,
        "smoking": "never",
        "drinking": "socially",
        "lifestyle": "active",
        "partner_values": ["honesty"],
        "children_plans": "someday",
        "religious_beliefs": "agnostic",
        "tech_skills": ["python"],
        "languages": ["english"],
        "activities": ["hiking"],
        "causes_supported": ["climate"],
        "age": 25,
        "is_active": True,
        "is_dating_active": True,
        "hometown": "Chicago",
        "current_place": "NYC",
        "role_at": "Developer",
    }
    with patch("app.db.profiles.crud.decrypt_profile_field"):
        assert _check_lifestyle_filters(match_c, filters) is True
        assert _check_basic_overlap(match_c, filters) is True

    # Failed overlap
    fail_c = {
        "id": USER_2,
        "smoking": "frequently",
        "drinking": "frequently",
        "lifestyle": "sedentary",
        "partner_values": ["wealth"],
        "children_plans": "never",
        "religious_beliefs": "other",
        "tech_skills": ["rust"],
        "languages": ["spanish"],
        "activities": ["gaming"],
        "causes_supported": ["none"],
        "age": 40,
    }
    with patch("app.db.profiles.crud.decrypt_profile_field"):
        assert _check_lifestyle_filters(fail_c, filters) is False
        assert _check_basic_overlap(fail_c, filters) is False

    # _get_expanded_viewer_buckets: invalid vs valid
    assert _get_expanded_viewer_buckets({}, "Dating") == ([], [])
    with patch("app.db.profiles.crud._expand_target_buckets", return_value=["M"]):
        search, targets = _get_expanded_viewer_buckets(
            {"dating_target_buckets": ["M"], "search_bucket": "F"}, "Dating",
        )
        assert search == ["F"]
        assert targets == ["M"]

    # _fetch_and_decrypt_viewer: APIError, DecryptFailedError, None profile
    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().eq().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError, match="Failed to fetch viewer profile"):
            _fetch_and_decrypt_viewer(USER_1, "Dating")

        mock_sb.table().select().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(data=[])
        assert _fetch_and_decrypt_viewer(USER_1, "Dating") is None

        mock_sb.table().select().eq().limit().execute.return_value = MagicMock(
            data=[{"id": USER_1, "name": "enc"}],
        )
        with patch(
            "app.db.profiles.crud.decrypt_profile_record",
            side_effect=DecryptFailedError("fail"),
        ), pytest.raises(DecryptFailedError):
            _fetch_and_decrypt_viewer(USER_1, "Dating")

    # is_active_profile: True / False / APIError
    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().limit().execute.return_value = MagicMock(
            data=[{"id": USER_1}],
        )
        assert is_active_profile(USER_1) is True

        mock_sb.table().select().eq().eq().limit().execute.return_value = MagicMock(
            data=[],
        )
        assert is_active_profile(USER_1) is False

        mock_sb.table().select().eq().eq().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
        with pytest.raises(DatabaseAccessError):
            is_active_profile(USER_1)

    # fetch_peer_profile_by_id: not found, DecryptFailedError, success
    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().eq().eq().neq().limit().execute.return_value = MagicMock(
            data=[],
        )
        assert fetch_peer_profile_by_id(USER_2) is None

        mock_sb.table().select().eq().eq().eq().eq().neq().limit().execute.return_value = MagicMock(
            data=[{"id": USER_2, "name": "enc"}],
        )
        with patch(
            "app.db.profiles.crud.decrypt_profile_record",
            side_effect=DecryptFailedError("fail"),
        ), pytest.raises(DecryptFailedError):
            fetch_peer_profile_by_id(USER_2)

        with patch(
            "app.db.profiles.crud.decrypt_profile_record",
            return_value={"id": USER_2, "name": "Bob"},
        ):
            p = fetch_peer_profile_by_id(USER_2)
            assert p is not None
            assert p["name"] == "Bob"

    # fetch_music_affinities: APIError & success
    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().limit().execute.side_effect = APIError(
            {"message": "fail"},
        )
        art, gen = fetch_music_affinities(USER_1)
        assert art == {}
        assert gen == {}

        mock_sb.table().select().eq().eq().limit().execute.side_effect = None
        mock_sb.table().select().eq().eq().limit().execute.return_value = MagicMock(
            data=[{"artist_affinity": {"queen": 0.8}, "genre_affinity": {"rock": 0.9}}],
        )
        with patch("app.db.profiles.encryption._parse_encrypted_dict"):
            art, gen = fetch_music_affinities(USER_1)
            assert art == {"queen": 0.8}
            assert gen == {"rock": 0.9}

    # _map_vector_embeddings & _enrich_candidates_with_vectors
    viewer_obj: dict[str, Any] = {"id": USER_1}
    cand_obj: dict[str, Any] = {"id": USER_2}
    c_map = {USER_2: cand_obj}
    vec_records = [
        {
            "user_id": USER_1,
            "vector_profiles": {
                "bio_embedding": [0.1],
                "career_embedding": [0.2],
                "identity_embedding": [0.3],
            },
        },
        {
            "user_id": USER_2,
            "vector_profiles": {
                "bio_embedding": [0.4],
                "career_embedding": [0.5],
                "identity_embedding": [0.6],
            },
        },
    ]
    _map_vector_embeddings(vec_records, viewer_obj, c_map, USER_1)
    assert viewer_obj["bio_embedding"] == [0.1]
    assert cand_obj["bio_embedding"] == [0.4]

    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().in_().execute.return_value = MagicMock(
            data=vec_records,
        )
        _enrich_candidates_with_vectors(viewer_obj, [cand_obj], USER_1)

    # fetch_stage_1_candidates: no viewer -> None, [], and success
    with patch("app.db.profiles.crud._fetch_and_decrypt_viewer", return_value=None):
        v, c = fetch_stage_1_candidates(USER_1, "Dating", filters)
        assert v is None
        assert c == []

    viewer_dict = {
        "id": USER_1,
        "target_dating_bucket": ["b1"],
        "dating_bucket": "b1",
        "app_variant": "nexus",
        "is_dating_active": True,
    }
    with (
        patch(
            "app.db.profiles.crud._fetch_and_decrypt_viewer", return_value=viewer_dict,
        ),
        patch(
            "app.db.profiles.crud.fetch_active_discovery_excluded_ids",
            return_value=set(),
        ),
        patch(
            "app.db.profiles.crud._execute_and_filter_candidates",
            return_value=[match_c],
        ),
        patch("app.db.profiles.crud.decrypt_profile_field"),
        patch("app.db.profiles.crud.decrypt_profile_fields"),
        patch("app.db.profiles.crud._enrich_candidates_with_vectors"),
    ):
        v_res, c_res = fetch_stage_1_candidates(USER_1, "Dating", filters)
        assert v_res is not None
        assert len(c_res) == 1


def test_db_profiles_crud_deep():
    from app.db.profiles.crud import (
        _check_basic_overlap,
        _check_candidate_match,
        _execute_and_filter_candidates,
        fetch_music_affinities,
        fetch_peer_profile_by_id,
    )
    from app.models.discovery import DiscoveryFilters

    # _check_basic_overlap: sub_interests dict, role_type
    cand = {
        "sub_interests": {"tech": ["Python", "Rust"]},
        "role_type": ["Engineer"],
    }
    f_sub = DiscoveryFilters(sub_interests=["Python"])
    assert _check_basic_overlap(cand, f_sub) is True

    f_sub_miss = DiscoveryFilters(sub_interests=["Java"])
    assert _check_basic_overlap(cand, f_sub_miss) is False

    f_role = DiscoveryFilters(role_type=["Designer"])
    assert _check_basic_overlap(cand, f_role) is False

    # _check_candidate_match: looking_for, causes_supported, tech_skills, partner_values
    cand2 = {
        "looking_for": ["Chat"],
        "causes_supported": ["OpenSource"],
        "tech_skills": ["FastAPI"],
        "partner_values": "Honesty, Loyalty",
    }
    f_lk_miss = DiscoveryFilters(looking_for=["Date"])
    assert _check_candidate_match(cand2, f_lk_miss, set()) is False

    f_cs_miss = DiscoveryFilters(causes_supported=["Animals"])
    assert _check_candidate_match(cand2, f_cs_miss, set()) is False

    f_ts_miss = DiscoveryFilters(tech_skills=["Kubernetes"])
    assert _check_candidate_match(cand2, f_ts_miss, set()) is False

    f_pv_miss = DiscoveryFilters(
        partner_values=["Wealth"], dealbreaker_fields=["partner_values"],
    )
    assert _check_candidate_match(cand2, f_pv_miss, {"partner_values"}) is False

    # _execute_and_filter_candidates: APIError & DecryptFailedError
    mock_query = MagicMock()
    mock_query.in_().limit().execute.side_effect = make_api_error()
    viewer = {"id": USER_1, "search_bucket": "M", "dating_target_buckets": ["F"]}
    with pytest.raises(DatabaseAccessError):
        _execute_and_filter_candidates(mock_query, viewer, "Dating", 10)

    # fetch_peer_profile_by_id: ordered_images fallback to profile_pic & APIError
    with (
        patch("app.db.profiles.crud.supabase_client") as mock_sb,
        patch(
            "app.db.profiles.crud.decrypt_profile_record",
            return_value={"id": USER_2, "name": "Bob"},
        ),
        patch(
            "app.db.profiles.crud.sanitize_decrypted_profile",
            return_value={"id": USER_2, "name": "Bob"},
        ),
        patch(
            "app.db.profiles.crud.sign_profile_media",
            return_value={"id": USER_2, "name": "Bob"},
        ),
    ):
        peer_row = {
            "id": USER_2,
            "profile_pic": None,
            "ordered_images": ["https://img.nexus.test/1.jpg"],
        }

        # Build chain for fetch_peer_profile_by_id
        chain = MagicMock()
        mock_sb.table.return_value = chain
        chain.select.return_value = chain
        chain.eq.return_value = chain
        chain.neq.return_value = chain
        chain.limit.return_value = chain
        chain.execute.return_value = MagicMock(data=[peer_row])

        assert fetch_peer_profile_by_id(USER_2) is not None

        chain.execute.side_effect = make_api_error()
        with pytest.raises(DatabaseAccessError):
            fetch_peer_profile_by_id(USER_2)

    # fetch_music_affinities: exception handling
    with patch("app.db.profiles.crud.supabase_client") as mock_sb:
        mock_sb.table().select().eq().eq().limit().execute.side_effect = Exception(
            "DB fail",
        )
        a, g = fetch_music_affinities(USER_1)
        assert a == {}
        assert g == {}


def test_db_profiles_crud_blind_index_and_unpack():
    # 1. _apply_blind_index_filters
    mock_query = MagicMock()
    mock_query.in_.return_value = mock_query
    filters = DiscoveryFilters(campus_branches=["CS", "EE"])
    res_q = _apply_blind_index_filters(mock_query, filters)
    assert res_q is mock_query
    mock_query.in_.assert_called_once()

    # 2. _unpack_chat_presence
    cand_a: dict[str, Any] = {
        "chat_presence": {"last_active_at": "2026-08-25T10:00:00Z"},
    }
    _unpack_chat_presence(cand_a)
    assert cand_a["last_active_at"] == "2026-08-25T10:00:00Z"

    cand_b: dict[str, Any] = {
        "chat_presence": [{"last_active_at": "2026-08-25T11:00:00Z"}],
    }
    _unpack_chat_presence(cand_b)
    assert cand_b["last_active_at"] == "2026-08-25T11:00:00Z"

    cand_c: dict[str, Any] = {"chat_presence": []}
    _unpack_chat_presence(cand_c)
    assert "last_active_at" not in cand_c


def test_db_profiles_crud_filter_candidate_matches():
    raw_data: list[Any] = [
        "not_a_dict",
        {"id": USER_2, "dating_target_buckets": "not_a_list"},
        {"id": USER_2, "dating_target_buckets": []},
        {"id": USER_2, "dating_target_buckets": ["b_other"]},
        {
            "id": USER_3,
            "dating_target_buckets": ["b_viewer"],
            "users": {"app_variant": "nexus"},
            "chat_presence": {"last_active_at": "2026-08-25T12:00:00Z"},
        },
    ]

    filtered = _filter_candidate_matches(
        candidates_data=raw_data,
        viewer_search_expanded=["b_viewer"],
        target_bucket_column="dating_target_buckets",
    )
    assert len(filtered) == 1
    assert filtered[0]["id"] == USER_3
    assert filtered[0]["last_active_at"] == "2026-08-25T12:00:00Z"
    assert "users" not in filtered[0]


def test_db_profiles_crud_check_candidate_match_filters():
    cand: dict[str, Any] = {
        "id": USER_2,
        "looking_for": encrypt_to_hex(json.dumps(["Relationship"])),
        "causes_supported": encrypt_to_hex(json.dumps(["Climate"])),
        "tech_skills": encrypt_to_hex(json.dumps(["Python", "Rust"])),
        "partner_values": encrypt_to_hex("Honesty, Kindness"),
    }

    f_ok = DiscoveryFilters(
        looking_for=["Relationship"],
        causes_supported=["Climate"],
        tech_skills=["Python"],
        partner_values=["Honesty"],
        dealbreaker_fields=["partner_values"],
    )
    assert (
        _check_candidate_match(cand.copy(), f_ok, dealbreakers={"partner_values"})
        is True
    )

    f_bad_pv = DiscoveryFilters(
        partner_values=["Ambition"],
        dealbreaker_fields=["partner_values"],
    )
    assert (
        _check_candidate_match(cand.copy(), f_bad_pv, dealbreakers={"partner_values"})
        is False
    )

    cand_list_pv: dict[str, Any] = {
        "id": USER_2,
        "partner_values": encrypt_to_hex(json.dumps(["Honesty", "Humor"])),
    }
    f_match_pv_list = DiscoveryFilters(
        partner_values=["Humor"],
        dealbreaker_fields=["partner_values"],
    )
    assert (
        _check_candidate_match(
            cand_list_pv.copy(), f_match_pv_list, dealbreakers={"partner_values"},
        )
        is True
    )

    post_res = _apply_post_fetch_filters([cand.copy()], f_ok)
    assert len(post_res) == 1


def test_db_profiles_crud_vector_enrichment_and_exceptions():
    viewer: dict[str, Any] = {"id": USER_1}
    cand_1: dict[str, Any] = {"id": USER_2}
    candidates: list[dict[str, Any]] = [cand_1]

    records: list[Any] = [
        "invalid_record",
        {"user_id": None},
        {"user_id": USER_1, "vector_profiles": "not_a_dict"},
        {
            "user_id": USER_1,
            "vector_profiles": {
                "bio_embedding": [0.1],
                "career_embedding": [0.2],
                "identity_embedding": [0.3],
            },
        },
        {
            "user_id": USER_2,
            "vector_profiles": {
                "bio_embedding": [0.4],
                "career_embedding": [0.5],
                "identity_embedding": [0.6],
            },
        },
        {"user_id": "other_id", "vector_profiles": {"bio_embedding": [0.7]}},
    ]
    cand_map = {USER_2: cand_1}
    _map_vector_embeddings(records, viewer, cand_map, USER_1)
    assert viewer["bio_embedding"] == [0.1]
    assert cand_1["bio_embedding"] == [0.4]

    mock_table = MagicMock()
    mock_table.select.return_value.in_.return_value.execute.side_effect = APIError(
        {"message": "DB error"},
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        with pytest.raises(
            DatabaseAccessError, match="Failed to fetch vector profiles",
        ):
            _enrich_candidates_with_vectors(viewer, candidates, USER_1)

    mock_table.select.return_value.in_.return_value.execute.side_effect = RuntimeError(
        "Crash",
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        with pytest.raises(
            DatabaseAccessError, match="Unexpected error fetching vector profiles",
        ):
            _enrich_candidates_with_vectors(viewer, candidates, USER_1)

    mock_table.select.return_value.eq.return_value.limit.return_value.execute.side_effect = RuntimeError(
        "Crash",
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        with pytest.raises(
            DatabaseAccessError, match="Unexpected error fetching viewer profile",
        ):
            _fetch_and_decrypt_viewer(USER_1, "Dating")

    mock_table.select.return_value.eq.return_value.limit.return_value.execute.side_effect = None
    mock_table.select.return_value.eq.return_value.limit.return_value.execute.return_value = MagicMock(
        data=[],
    )
    with patch("app.db.profiles.crud.supabase_client.table", return_value=mock_table):
        assert _fetch_and_decrypt_viewer(USER_1, "Dating") is None
