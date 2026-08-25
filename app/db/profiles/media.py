"""Profile media storage signed URL generation and image metadata update methods."""

import json
import logging
from collections.abc import Sequence
from typing import Any, cast

from storage3.utils import StorageException

from app.core.security.crypto import encrypt_to_hex
from app.db.client import DatabaseAccessError, supabase_client

logger = logging.getLogger(__name__)

_MEDIA_BUCKET = "user_media"
_MEDIA_URL_TTL_SECONDS = 3600


def _is_safe_media_path(path: str) -> bool:
    """Verifies that a storage path does not contain traversal, backslashes, leading slash, percent encoding, or null bytes."""
    if not path:
        return False
    return not (".." in path or "\\" in path or path.startswith("/") or "\x00" in path or "%" in path)


def _sign_media_paths(paths: Sequence[str]) -> dict[str, str]:
    """Batch-exchanges user_media storage paths for short-lived signed URLs."""
    unique_paths = list(dict.fromkeys(p for p in paths if p and _is_safe_media_path(p)))
    if not unique_paths:
        return {}
    try:
        signed = supabase_client.storage.from_(_MEDIA_BUCKET).create_signed_urls(
            unique_paths,
            _MEDIA_URL_TTL_SECONDS,
        )
    except StorageException:
        logger.exception("Failed to batch-sign user_media paths")
        return {}
    result: dict[str, str] = {}
    for item in signed:
        item_dict = cast(dict[str, Any], item)
        path = item_dict.get("path")
        signed_url = item_dict.get("signedURL") or item_dict.get("signedUrl")
        if path and signed_url:
            result[str(path)] = str(signed_url)
    return result


def sign_profile_media(row: dict[str, Any]) -> dict[str, Any]:
    """Replaces profile_pic/normal_pics storage paths in a decrypted profile row with signed URLs."""
    user_id = str(row.get("id") or row.get("user_id") or "").strip()
    expected_prefix = f"{user_id}/" if user_id else None

    pic = row.get("profile_pic")
    if pic and (not _is_safe_media_path(pic) or (expected_prefix and not pic.startswith(expected_prefix))):
        logger.warning("Unsafe or foreign profile_pic ignored for user %s: %s", user_id, pic)
        pic = None
        row["profile_pic"] = None

    raw_normal_pics = row.get("normal_pics")
    normal_pics_list = (
        cast(list[Any], raw_normal_pics) if isinstance(raw_normal_pics, list) else []
    )
    normal_pics: list[str] = []
    for p in normal_pics_list:
        if isinstance(p, str) and p:
            if not _is_safe_media_path(p) or (expected_prefix and not p.startswith(expected_prefix)):
                logger.warning("Unsafe or foreign normal_pic ignored for user %s: %s", user_id, p)
                continue
            normal_pics.append(p)

    all_paths = cast(list[str], [pic, *normal_pics]) if pic else normal_pics
    signed = _sign_media_paths(all_paths)
    if pic:
        row["profile_pic"] = signed.get(pic)
    if raw_normal_pics is not None:
        row["normal_pics"] = [signed[p] for p in normal_pics if p in signed]
    return row


def sign_profile_media_bulk(
    rows: list[dict[str, Any]],
    pic_field: str = "profile_pic",
) -> None:
    """Batch signed-URL equivalent of sign_profile_media for a list of rows."""
    valid_paths: list[str] = []
    for row in rows:
        pic = row.get(pic_field)
        if not pic or not isinstance(pic, str):
            continue
        user_id = str(row.get("id") or row.get("user_id") or "").strip()
        expected_prefix = f"{user_id}/" if user_id else None
        if not _is_safe_media_path(pic) or (expected_prefix and not pic.startswith(expected_prefix)):
            logger.warning("Unsafe or foreign %s ignored for user %s: %s", pic_field, user_id, pic)
            continue
        valid_paths.append(pic)

    signed = _sign_media_paths(valid_paths)
    for row in rows:
        pic = row.get(pic_field)
        if pic:
            user_id = str(row.get("id") or row.get("user_id") or "").strip()
            expected_prefix = f"{user_id}/" if user_id else None
            if not _is_safe_media_path(pic) or (expected_prefix and not pic.startswith(expected_prefix)):
                row[pic_field] = None
            else:
                row[pic_field] = signed.get(pic)


async def update_profile_images_and_metadata(
    user_id: str,
    images: list[str],
    vibe_tags: list[str],
) -> None:
    """Encrypts and saves ordered images and vibe tags into database."""
    own_prefix = f"{user_id}/"
    for img in images:
        if img and (not img.startswith(own_prefix) or not _is_safe_media_path(img)):
            raise ValueError(f"Invalid media path for user {user_id}: {img}")

    profile_pic = images[0] if images else ""
    normal_pics = [pic for pic in images[1:] if pic] if len(images) > 1 else []

    db_mutation_payload = {
        "profile_pic": encrypt_to_hex(profile_pic),
        "normal_pics": encrypt_to_hex(json.dumps(normal_pics)),
        "ai_vibe_tags": encrypt_to_hex(json.dumps(vibe_tags)),
        "updated_at": "now()",
    }

    try:
        response = (
            supabase_client.table("profiles")
            .update(db_mutation_payload)
            .eq("id", user_id)
            .select("id")
            .execute()
        )
        if not response.data:
            raise ValueError("Profile not found")
    except Exception as e:
        logger.exception(
            "Failed to update profile images and metadata for user %s",
            user_id,
        )
        raise DatabaseAccessError("Failed to update profile images and metadata") from e
