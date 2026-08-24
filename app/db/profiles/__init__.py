"""Database profile CRUD, encrypted PII decoding, media storage, and discovery candidate query layer."""

from app.db.client import supabase_client
from app.db.profiles.crud import (
    _build_candidate_query,
    fetch_music_affinities,
    fetch_peer_profile_by_id,
    fetch_stage_1_candidates,
    is_active_profile,
)
from app.db.profiles.encryption import (
    TAB_SCORING_FIELDS,
    decrypt_profile_field,
    decrypt_profile_fields,
    decrypt_profile_record,
    decrypt_profile_rows,
    sanitize_decrypted_profile,
)
from app.db.profiles.media import (
    sign_profile_media,
    sign_profile_media_bulk,
    update_profile_images_and_metadata,
)

__all__ = [
    "TAB_SCORING_FIELDS",
    "_build_candidate_query",
    "decrypt_profile_field",
    "decrypt_profile_fields",
    "decrypt_profile_record",
    "decrypt_profile_rows",
    "fetch_music_affinities",
    "fetch_peer_profile_by_id",
    "fetch_stage_1_candidates",
    "is_active_profile",
    "sanitize_decrypted_profile",
    "sign_profile_media",
    "sign_profile_media_bulk",
    "supabase_client",
    "update_profile_images_and_metadata",
]
