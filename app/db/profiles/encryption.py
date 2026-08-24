"""Profile field PII encryption, decryption, and payload sanitization routines."""

import json
import logging
from collections.abc import Sequence
from typing import Any, cast

from app.core.config import DiscoveryTab
from app.core.security.crypto import DecryptFailedError, decrypt_pii
from app.db.client import ProfileDecodeError
from app.db.profiles.media import sign_profile_media_bulk

logger = logging.getLogger(__name__)

SCALAR_ENCRYPTED_FIELDS: frozenset[str] = frozenset(
    {
        "name",
        "display_gender",
        "display_sexuality",
        "pronouns",
        "bio",
        "campus_branch",
        "campus_name",
        "hometown",
        "current_place",
        "children_plans",
        "religious_beliefs",
        "lifestyle",
        "drinking",
        "smoking",
        "role_at",
        "profile_pic",
    },
)

ARRAY_ENCRYPTED_FIELDS: frozenset[str] = frozenset(
    {
        "looking_for",
        "activities",
        "causes_supported",
        "top_artists",
        "tech_skills",
        "role_type",
        "languages",
        "ai_vibe_tags",
        "pets",
        "normal_pics",
        "partner_values",
    },
)

DICT_ENCRYPTED_FIELDS: frozenset[str] = frozenset(
    {
        "interests",
        "sub_interests",
        "value_dimensions",
        "artist_affinity",
        "genre_affinity",
    },
)

ALL_ENCRYPTED_FIELDS: frozenset[str] = (
    SCALAR_ENCRYPTED_FIELDS | ARRAY_ENCRYPTED_FIELDS | DICT_ENCRYPTED_FIELDS
)

TAB_SCORING_FIELDS: dict[DiscoveryTab, frozenset[str]] = {
    "Dating": frozenset(
        {
            "value_dimensions",
            "partner_values",
            "interests",
            "sub_interests",
            "dating_for",
            "drinking",
            "smoking",
            "children_plans",
            "religious_beliefs",
            "activities",
            "artist_affinity",
            "genre_affinity",
            "hometown",
            "current_place",
            "pets",
            "ai_vibe_tags",
            "causes_supported",
            "display_sexuality",
        },
    ),
    "Friends": frozenset(
        {
            "activities",
            "interests",
            "sub_interests",
            "artist_affinity",
            "genre_affinity",
            "ai_vibe_tags",
            "hometown",
            "current_place",
            "pets",
            "drinking",
            "smoking",
            "causes_supported",
            "lifestyle",
            "languages",
            "value_dimensions",
            "religious_beliefs",
        },
    ),
    "Professional": frozenset(
        {
            "activities",
            "interests",
            "sub_interests",
            "tech_skills",
            "causes_supported",
            "languages",
            "ai_vibe_tags",
            "value_dimensions",
            "role_at",
            "role_type",
            "looking_for",
            "campus_branch",
            "artist_affinity",
            "genre_affinity",
        },
    ),
}


def _parse_encrypted_scalar(row: dict[str, Any], field: str) -> None:
    """Parse encrypted scalar field."""
    raw = row.get(field)
    if raw is None:
        row[field] = None
        return
    if not isinstance(raw, (str, bytes, memoryview)):
        return

    try:
        row[field] = decrypt_pii(raw)
    except DecryptFailedError:
        row[field] = "__DECRYPTION_FAILED__"


def _parse_encrypted_list(row: dict[str, Any], field: str) -> None:
    """Parse encrypted list field."""
    raw = row.get(field)
    if raw is None:
        row[field] = []
        return
    if not isinstance(raw, (str, bytes, memoryview)):
        return

    try:
        decrypted = decrypt_pii(raw)
    except DecryptFailedError:
        row[field] = ["__DECRYPTION_FAILED__"]
        return

    if decrypted == "":
        row[field] = []
        return

    try:
        parsed = json.loads(decrypted)
    except json.JSONDecodeError:
        parsed = [v.strip() for v in decrypted.split(",") if v.strip()]

    if not isinstance(parsed, list):
        parsed = [str(parsed)]

    row[field] = parsed


def _parse_encrypted_dict(row: dict[str, Any], field: str) -> None:
    """Parse encrypted dictionary field."""
    raw = row.get(field)
    if raw is None:
        row[field] = {}
        return
    if not isinstance(raw, (str, bytes, memoryview)):
        return

    try:
        decrypted = decrypt_pii(raw)
    except DecryptFailedError:
        row[field] = {"__DECRYPTION_FAILED__": True}
        return

    if decrypted == "":
        row[field] = {}
        return

    try:
        parsed = json.loads(decrypted)
    except json.JSONDecodeError as e:
        raise ProfileDecodeError(
            f"{field} decrypted to invalid JSON object payload",
        ) from e

    if not isinstance(parsed, dict):
        raise ProfileDecodeError(f"{field} must decrypt to a dict")

    row[field] = parsed


def decrypt_profile_field(row: dict[str, Any], field: str) -> None:
    """Decrypt a specific profile field in-place if present and encrypted."""
    if field not in row or row[field] is None:
        return
    if field in SCALAR_ENCRYPTED_FIELDS:
        _parse_encrypted_scalar(row, field)
    elif field in ARRAY_ENCRYPTED_FIELDS:
        _parse_encrypted_list(row, field)
    elif field in DICT_ENCRYPTED_FIELDS:
        _parse_encrypted_dict(row, field)


def decrypt_profile_fields(
    row: dict[str, Any],
    fields: set[str] | frozenset[str] | Sequence[str],
) -> dict[str, Any]:
    """Decrypt only the specified fields on a profile record in-place."""
    for field in fields:
        decrypt_profile_field(row, field)
    return row


def decrypt_profile_record(row: dict[str, Any]) -> dict[str, Any]:
    """Decrypt and normalize all encrypted profile fields on a single profile in memory."""
    return decrypt_profile_fields(row, ALL_ENCRYPTED_FIELDS)


def sanitize_decrypted_profile(row: dict[str, Any]) -> dict[str, Any]:
    """Replaces decryption failure sentinels with empty/safe equivalents in-place."""
    for k, v in list(row.items()):
        if v == "__DECRYPTION_FAILED__":
            row[k] = ""
        elif v == ["__DECRYPTION_FAILED__"]:
            row[k] = []
        elif v == {"__DECRYPTION_FAILED__": True}:
            row[k] = {}
    return row


def decrypt_profile_rows(profiles_data: list[Any]) -> dict[str, dict[str, Any]]:
    """Decrypt profile_pic on a list of raw profile rows, keyed by profile id."""
    profile_map: dict[str, dict[str, Any]] = {}
    for p in profiles_data:
        if not isinstance(p, dict):
            continue
        p_dict = cast(dict[str, Any], p)
        pid = str(p_dict.get("id") or "")
        raw_pic = p_dict.get("profile_pic")
        if raw_pic:
            try:
                p_dict["profile_pic"] = decrypt_pii(raw_pic)
            except DecryptFailedError:
                p_dict["profile_pic"] = None
        profile_map[pid] = p_dict
    sign_profile_media_bulk(list(profile_map.values()))
    return profile_map
