"""Moderation subject lookup endpoint."""

import logging
from typing import Any, cast

from fastapi import APIRouter, Body, Depends, HTTPException, Request

from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.db.client import supabase_client
from app.db.profiles import (
    decrypt_profile_record,
    sanitize_decrypted_profile,
    sign_profile_media_bulk,
)
from app.models import ModerationSubjectItem, ModerationSubjectsRequest

logger = logging.getLogger(__name__)

router = APIRouter()


@router.post(
    "/api/v1/users/moderation-subjects",
    response_model=list[ModerationSubjectItem],
)
def get_moderation_subjects(
    request: Request,
    payload: ModerationSubjectsRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> list[dict[str, Any]]:
    """Returns basic decrypted profile info for users the caller has blocked or hidden."""
    _ = request
    try:
        validated_res = (
            supabase_client.table("profile_discovery_actions")
            .select("target_id")
            .eq("actor_id", user_id)
            .in_("target_id", payload.target_ids)
            .in_("action", ["block", "hide"])
            .is_("revoked_at", "null")
            .execute()
        )
        valid_ids: list[str] = list(
            {
                row["target_id"]
                for row in cast(
                    list[dict[str, Any]],
                    validated_res.data or [],
                )
            },
        )
        if not valid_ids:
            return []

        profiles_res = (
            supabase_client.table("profiles")
            .select(
                "id, name, age, campus_year, campus_name, campus_branch, "
                "hometown, current_place, profile_pic",
            )
            .in_("id", valid_ids)
            .execute()
        )

        results: list[dict[str, Any]] = []
        for row in cast(list[dict[str, Any]], profiles_res.data or []):
            try:
                decrypted = decrypt_profile_record(dict(row))
                decrypted = sanitize_decrypted_profile(decrypted)
            except (ValueError, KeyError, TypeError, AttributeError):
                decrypted = sanitize_decrypted_profile(dict(row))
            results.append(
                {
                    "id": decrypted.get("id"),
                    "name": decrypted.get("name"),
                    "age": decrypted.get("age"),
                    "campus_year": decrypted.get("campus_year"),
                    "campus_name": decrypted.get("campus_name"),
                    "campus_branch": decrypted.get("campus_branch"),
                    "hometown": decrypted.get("hometown"),
                    "current_place": decrypted.get("current_place"),
                    "profile_pic": decrypted.get("profile_pic"),
                },
            )
        sign_profile_media_bulk(results)
        return results
    except Exception as e:
        logger.exception("Failed to fetch moderation subjects")
        raise HTTPException(status_code=500, detail="Internal server error.") from e
