"""Profile details GET and PATCH API endpoints."""

import json
import logging
from datetime import datetime, timezone
from typing import Any, cast

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Body,
    Depends,
    HTTPException,
    status,
)
from postgrest.exceptions import APIError

import app.api.user as user_module
from app.api.dependencies import (
    assert_special_category_consent,
    get_active_user_id,
    verify_app_check_token,
    verify_app_check_with_replay_protection,
)
from app.api.user.profile.helpers import (
    _AGE_CHANGE_MAX_PER_WINDOW,
    _AGE_CHANGE_WINDOW_DAYS,
    _NAME_CHANGE_MAX_PER_WINDOW,
    _NAME_CHANGE_WINDOW_DAYS,
    _VALUE_DIMENSION_TRIGGER_FIELDS,
    _assert_no_decryption_failures,
    _build_ordered_images,
    _rolling_change_window_status,
    _sets_special_category_data,
    _validate_common_activation,
    _validate_dating_activation,
    _validate_friends_activation,
    _validate_professional_activation,
)
from app.core.security.crypto import compute_blind_index, encrypt_to_hex
from app.core.utils.moderation import NameModerationError, validate_display_name
from app.db.client import supabase_client
from app.db.profiles import decrypt_profile_record
from app.db.users import fetch_public_user
from app.models import (
    ProfileDetailsResponse,
    ProfileDetailsUpdate,
    ProfileUpdateResponse,
)
from app.services.profile import recompile_and_push_vectors
from app.services.value_dimensions import recompile_value_dimensions

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/api/v1/profile/details", response_model=ProfileDetailsResponse)
def get_profile_details(
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, Any]:
    """Retrieves the caller's complete decrypted profile details."""
    try:
        select_cols = (
            "id, name, age, campus_year, campus_branch, campus_name, "
            "display_gender, display_sexuality, pronouns, bio, search_bucket, "
            "hometown, current_place, partner_values, children_plans, "
            "religious_beliefs, lifestyle, drinking, smoking, role_at, "
            "role_type, dating_target_buckets, dating_for, friends_target_buckets, "
            "professional_target_buckets, looking_for, activities, "
            "causes_supported, top_artists, tech_skills, languages, "
            "pets, interests, sub_interests, profile_pic, normal_pics, "
            "ai_vibe_tags, is_dating_active, is_friends_active, "
            "is_professional_active"
        )
        res = (
            supabase_client.table("profiles")
            .select(select_cols)
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        data = getattr(res, "data", None)
        if data is None:
            raise HTTPException(status_code=404, detail="Profile not found")

        if not isinstance(data, dict):
            raise HTTPException(
                status_code=500,
                detail="Invalid profile data structure",
            )

        profile = decrypt_profile_record(cast(dict[str, Any], data))
        _assert_no_decryption_failures(profile)

        ordered_images = _build_ordered_images(profile)

        age_changes_used_in_window, age_change_eligible, age_next_eligible_dt = (
            _rolling_change_window_status(
                "profile_age_change_log",
                user_id,
                _AGE_CHANGE_WINDOW_DAYS,
                _AGE_CHANGE_MAX_PER_WINDOW,
            )
        )
        (
            name_changes_used_in_window,
            name_change_eligible,
            name_next_eligible_dt,
        ) = _rolling_change_window_status(
            "profile_name_change_log",
            user_id,
            _NAME_CHANGE_WINDOW_DAYS,
            _NAME_CHANGE_MAX_PER_WINDOW,
        )

        return {
            "name": profile.get("name"),
            "age": profile.get("age"),
            "campus_year": profile.get("campus_year"),
            "campus_branch": profile.get("campus_branch"),
            "campus_name": profile.get("campus_name"),
            "display_gender": profile.get("display_gender"),
            "display_sexuality": profile.get("display_sexuality"),
            "pronouns": profile.get("pronouns"),
            "bio": profile.get("bio") or "",
            "search_bucket": profile.get("search_bucket") or "NB",
            "hometown": profile.get("hometown"),
            "current_place": profile.get("current_place"),
            "partner_values": profile.get("partner_values"),
            "children_plans": profile.get("children_plans"),
            "religious_beliefs": profile.get("religious_beliefs"),
            "lifestyle": profile.get("lifestyle"),
            "drinking": profile.get("drinking"),
            "smoking": profile.get("smoking"),
            "role_at": profile.get("role_at"),
            "role_type": profile.get("role_type") or [],
            "dating_target_buckets": profile.get("dating_target_buckets") or [],
            "dating_for": profile.get("dating_for") or [],
            "friends_target_buckets": profile.get("friends_target_buckets") or [],
            "professional_target_buckets": (
                profile.get("professional_target_buckets") or []
            ),
            "looking_for": profile.get("looking_for") or [],
            "activities": profile.get("activities") or [],
            "causes_supported": profile.get("causes_supported") or [],
            "top_artists": profile.get("top_artists") or [],
            "tech_skills": profile.get("tech_skills") or [],
            "languages": profile.get("languages") or [],
            "pets": profile.get("pets") or [],
            "interests": profile.get("interests") or {},
            "sub_interests": profile.get("sub_interests") or {},
            "ordered_images": ordered_images,
            "ai_vibe_tags": profile.get("ai_vibe_tags") or [],
            "is_dating_active": bool(profile.get("is_dating_active", False)),
            "is_friends_active": bool(profile.get("is_friends_active", False)),
            "is_professional_active": bool(
                profile.get("is_professional_active", False),
            ),
            "age_changes_used_in_window": age_changes_used_in_window,
            "age_change_eligible": age_change_eligible,
            "age_next_eligible_at": (
                age_next_eligible_dt.isoformat() if age_next_eligible_dt else None
            ),
            "name_changes_used_in_window": name_changes_used_in_window,
            "name_change_eligible": name_change_eligible,
            "name_next_eligible_at": (
                name_next_eligible_dt.isoformat() if name_next_eligible_dt else None
            ),
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to get profile details")
        raise HTTPException(
            status_code=500,
            detail="Internal server error.",
        ) from e


def _validate_tab_activation(
    tab: str,
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
) -> list[str]:
    missing: list[str] = []
    _validate_common_activation(profile, payload, missing)
    if tab == "Dating":
        _validate_dating_activation(profile, payload, missing)
    elif tab == "Friends":
        _validate_friends_activation(profile, payload, missing)
    elif tab == "Professional":
        _validate_professional_activation(profile, payload, missing)
    return missing


@router.patch("/api/v1/profile/details", response_model=ProfileUpdateResponse)
def update_profile_details(  # noqa: C901
    background_tasks: BackgroundTasks,
    payload: ProfileDetailsUpdate = Body(...),
    user_id: str = Depends(get_active_user_id),
    _device: None = Depends(verify_app_check_with_replay_protection),
) -> dict[str, Any]:
    """Updates existing user profile fields and re-indexes discovery vectors."""
    if _sets_special_category_data(payload):
        consent_user_row = fetch_public_user(user_id)
        if not consent_user_row:
            raise HTTPException(
                status_code=404,
                detail="User bootstrap row not found.",
            )
        assert_special_category_consent(consent_user_row)

    if "campus_year" in payload.model_fields_set or payload.campus_name is not None:
        try:
            campus_res = (
                user_module.supabase_client.table("profiles")
                .select("campus_name, campus_year")
                .eq("id", user_id)
                .maybe_single()
                .execute()
            )
            campus_data = cast(
                dict[str, Any],
                getattr(campus_res, "data", None) or {},
            )
            decrypted_campus = user_module.decrypt_profile_record(campus_data)
            existing_campus_name = decrypted_campus.get("campus_name")
            existing_campus_year = decrypted_campus.get("campus_year")
        except Exception as e:
            logger.exception("Failed to fetch current profile for campus validation")
            raise HTTPException(
                status_code=500,
                detail="Internal server error during campus validation.",
            ) from e

        incoming_campus_name = (
            payload.campus_name.strip()
            if payload.campus_name is not None
            else (existing_campus_name or "")
        )

        incoming_campus_year = (
            payload.campus_year
            if "campus_year" in payload.model_fields_set
            else existing_campus_year
        )

        if incoming_campus_name and incoming_campus_name != "__DECRYPTION_FAILED__":
            letters_count = sum(c.isalpha() for c in incoming_campus_name)
            if letters_count < 3:
                raise HTTPException(
                    status_code=400,
                    detail="Institute name must contain at least three letters.",
                )

        is_empty_or_failed = (
            not incoming_campus_name
            or not incoming_campus_name.strip()
            or incoming_campus_name == "__DECRYPTION_FAILED__"
        )
        if incoming_campus_year is not None and is_empty_or_failed:
            raise HTTPException(
                status_code=400,
                detail="Cannot select a campus year when institute is empty.",
            )

    update_data: dict[str, Any] = {}

    new_name: str | None = None
    new_age: int | None = None
    if payload.name is not None or payload.age is not None:
        try:
            identity_res = (
                supabase_client.table("profiles")
                .select("name, age")
                .eq("id", user_id)
                .maybe_single()
                .execute()
            )
        except Exception as e:
            logger.exception(
                "Failed to fetch current name/age for change comparison",
                extra={"user_id": user_id},
            )
            raise HTTPException(
                status_code=500,
                detail="Internal server error.",
            ) from e

        identity_data = cast(
            "dict[str, Any]",
            getattr(identity_res, "data", None) or {},
        )

        if payload.name is not None:
            candidate_name = payload.name.strip()
            current_name = cast("str | None", identity_data.get("name"))
            if candidate_name != current_name:
                new_name = candidate_name
                try:
                    validate_display_name(new_name)
                except NameModerationError as e:
                    raise HTTPException(status_code=422, detail=e.detail) from e

                _, name_eligible, name_next_eligible = _rolling_change_window_status(
                    "profile_name_change_log",
                    user_id,
                    _NAME_CHANGE_WINDOW_DAYS,
                    _NAME_CHANGE_MAX_PER_WINDOW,
                )
                if not name_eligible:
                    if name_next_eligible is None:
                        name_next_eligible = datetime.now(timezone.utc)
                    raise HTTPException(
                        status_code=403,
                        detail=(
                            "You've used both name changes allowed this year. "
                            f"You can change your name again on "
                            f"{name_next_eligible:%B %d, %Y}."
                        ),
                    )

        if payload.age is not None:
            current_age = cast("int | None", identity_data.get("age"))
            if payload.age != current_age:
                caller_row = fetch_public_user(user_id)
                caller_variant = (caller_row or {}).get("app_variant") or "nexus"
                max_age = 80 if caller_variant == "nexus" else 27
                if payload.age > max_age:
                    raise HTTPException(
                        status_code=400,
                        detail=(
                            f"Age must be between 18 and {max_age} for "
                            "your account type."
                        ),
                    )
                new_age = payload.age
                _, age_eligible, age_next_eligible = _rolling_change_window_status(
                    "profile_age_change_log",
                    user_id,
                    _AGE_CHANGE_WINDOW_DAYS,
                    _AGE_CHANGE_MAX_PER_WINDOW,
                )
                if not age_eligible:
                    if age_next_eligible is None:
                        age_next_eligible = datetime.now(timezone.utc)
                    raise HTTPException(
                        status_code=403,
                        detail=(
                            "You've used both age changes allowed this year. "
                            f"You can change your age again on "
                            f"{age_next_eligible:%B %d, %Y}."
                        ),
                    )

    if payload.campus_branch is not None:
        update_data["campus_branch"] = encrypt_to_hex(payload.campus_branch.strip())
        update_data["campus_branch_blind_index"] = compute_blind_index(
            payload.campus_branch,
        )
    if "campus_year" in payload.model_fields_set:
        update_data["campus_year"] = payload.campus_year
    if payload.campus_name is not None:
        update_data["campus_name"] = encrypt_to_hex(payload.campus_name.strip())
    if payload.search_bucket is not None:
        update_data["search_bucket"] = payload.search_bucket
    if payload.dating_target_buckets is not None:
        update_data["dating_target_buckets"] = payload.dating_target_buckets
    if payload.dating_for is not None:
        update_data["dating_for"] = payload.dating_for
    if payload.friends_target_buckets is not None:
        update_data["friends_target_buckets"] = payload.friends_target_buckets
    if payload.professional_target_buckets is not None:
        update_data["professional_target_buckets"] = payload.professional_target_buckets

    scalar_fields = [
        "display_gender",
        "display_sexuality",
        "pronouns",
        "bio",
        "hometown",
        "current_place",
        "children_plans",
        "religious_beliefs",
        "lifestyle",
        "drinking",
        "smoking",
        "role_at",
    ]
    for field in scalar_fields:
        val = getattr(payload, field, None)
        if val is not None:
            update_data[field] = encrypt_to_hex(val)

    if payload.profile_pic is not None:
        update_data["profile_pic"] = encrypt_to_hex(payload.profile_pic)
    if payload.normal_pics is not None:
        update_data["normal_pics"] = encrypt_to_hex(json.dumps(payload.normal_pics))

    if payload.drinking is not None:
        update_data["drinking_blind_index"] = compute_blind_index(payload.drinking)
    if payload.smoking is not None:
        update_data["smoking_blind_index"] = compute_blind_index(payload.smoking)
    if payload.children_plans is not None:
        update_data["children_plans_blind_index"] = compute_blind_index(
            payload.children_plans,
        )
    if payload.religious_beliefs is not None:
        update_data["religious_beliefs_blind_index"] = compute_blind_index(
            payload.religious_beliefs,
        )

    array_fields = [
        "looking_for",
        "activities",
        "causes_supported",
        "top_artists",
        "tech_skills",
        "languages",
        "pets",
        "role_type",
        "partner_values",
    ]
    for field in array_fields:
        val = getattr(payload, field, None)
        if val is not None:
            update_data[field] = encrypt_to_hex(json.dumps(val))

    for field in ("interests", "sub_interests"):
        val = getattr(payload, field, None)
        if val is not None:
            update_data[field] = encrypt_to_hex(json.dumps(val))

    need_profile_fetch = (
        (payload.is_dating_active is True)
        or (payload.is_friends_active is True)
        or (payload.is_professional_active is True)
        or (payload.bio is not None)
    )
    profile = None
    if need_profile_fetch:
        profile_res = (
            user_module.supabase_client.table("profiles")
            .select(
                "name,age,profile_pic,normal_pics,interests,sub_interests,"
                "drinking,smoking,partner_values,dating_target_buckets,dating_for,"
                "friends_target_buckets,causes_supported,"
                "professional_target_buckets,looking_for,tech_skills,"
                "bio,is_dating_active,is_friends_active,is_professional_active",
            )
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        profile_data = getattr(profile_res, "data", None)
        if not profile_data or not isinstance(profile_data, dict):
            raise HTTPException(status_code=404, detail="Profile not found")
        profile = user_module.decrypt_profile_record(cast(dict[str, Any], profile_data))

    if profile is not None:
        dating_active = (
            payload.is_dating_active
            if payload.is_dating_active is not None
            else profile.get("is_dating_active", False)
        )
        friends_active = (
            payload.is_friends_active
            if payload.is_friends_active is not None
            else profile.get("is_friends_active", False)
        )
        professional_active = (
            payload.is_professional_active
            if payload.is_professional_active is not None
            else profile.get("is_professional_active", False)
        )

        is_activating = (
            (payload.is_dating_active is True)
            or (payload.is_friends_active is True)
            or (payload.is_professional_active is True)
        )

        if not is_activating and (
            dating_active or friends_active or professional_active
        ):
            final_bio = (
                payload.bio
                if payload.bio is not None
                else profile.get("bio")
            )
            if final_bio == "__DECRYPTION_FAILED__":
                pass
            else:
                if (
                    not isinstance(final_bio, str)
                    or sum(c.isalpha() for c in final_bio) < 3
                ):
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=(
                            "Bio is required when orbits are active and "
                            "must contain at least three alphabetic characters."
                        ),
                    )

    if payload.is_dating_active is not None:
        if payload.is_dating_active:
            if profile is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Profile must be loaded for dating tab activation",
                )
            missing = _validate_tab_activation("Dating", profile, payload)
            if missing:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={
                        "message": "Dating profile incomplete",
                        "missing_fields": missing,
                    },
                )
            update_data["is_dating_active"] = True
        else:
            update_data["is_dating_active"] = False

    if payload.is_friends_active is not None:
        if payload.is_friends_active:
            if profile is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Profile must be loaded for friends tab activation",
                )
            missing = _validate_tab_activation("Friends", profile, payload)
            if missing:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={
                        "message": "Friends profile incomplete",
                        "missing_fields": missing,
                    },
                )
            update_data["is_friends_active"] = True
        else:
            update_data["is_friends_active"] = False

    if payload.is_professional_active is not None:
        if payload.is_professional_active:
            if profile is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Profile must be loaded for professional tab activation",
                )
            missing = _validate_tab_activation("Professional", profile, payload)
            if missing:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail={
                        "message": "Professional profile incomplete",
                        "missing_fields": missing,
                    },
                )
            update_data["is_professional_active"] = True
        else:
            update_data["is_professional_active"] = False

    if not update_data and new_age is None and new_name is None:
        return {"status": "success", "detail": "No fields to update."}

    has_other_updates = bool(update_data)
    if has_other_updates:
        update_data["updated_at"] = datetime.now(timezone.utc).isoformat()

    try:
        if new_age is not None:
            try:
                user_module.supabase_client.rpc(
                    "apply_age_change",
                    {
                        "p_user_id": user_id,
                        "p_new_age": new_age,
                        "p_min_interval_days": _AGE_CHANGE_WINDOW_DAYS,
                        "p_max_changes": _AGE_CHANGE_MAX_PER_WINDOW,
                    },
                ).execute()
            except APIError as e:
                if e.message == "age_change_limit_reached":
                    raise HTTPException(
                        status_code=403,
                        detail=(
                            "You've used both age changes allowed this year."
                        ),
                    ) from e
                if e.message == "profile_not_found":
                    raise HTTPException(
                        status_code=404,
                        detail="Profile not found. Complete onboarding first.",
                    ) from e
                logger.exception(
                    "Unexpected apply_age_change failure",
                    extra={"user_id": user_id},
                )
                raise HTTPException(
                    status_code=500,
                    detail="Internal server error.",
                ) from e

        if new_name is not None:
            try:
                user_module.supabase_client.rpc(
                    "apply_name_change",
                    {
                        "p_user_id": user_id,
                        "p_new_name": new_name,
                        "p_min_interval_days": _NAME_CHANGE_WINDOW_DAYS,
                        "p_max_changes": _NAME_CHANGE_MAX_PER_WINDOW,
                    },
                ).execute()
            except APIError as e:
                if e.message == "name_change_limit_reached":
                    raise HTTPException(
                        status_code=403,
                        detail=(
                            "You've used both name changes allowed this year."
                        ),
                    ) from e
                if e.message == "profile_not_found":
                    raise HTTPException(
                        status_code=404,
                        detail="Profile not found. Complete onboarding first.",
                    ) from e
                logger.exception(
                    "Unexpected apply_name_change failure",
                    extra={"user_id": user_id},
                )
                raise HTTPException(
                    status_code=500,
                    detail="Internal server error.",
                ) from e

        if update_data:
            res = (
                user_module.supabase_client.table("profiles")
                .update(update_data)
                .eq("id", user_id)
                .execute()
            )
            if not getattr(res, "data", None):
                raise HTTPException(
                    status_code=404,
                    detail="Profile not found. Complete onboarding first.",
                )

        plaintext_bio = (payload.bio or "").strip()
        background_tasks.add_task(recompile_and_push_vectors, user_id, plaintext_bio)

        if payload.model_fields_set & _VALUE_DIMENSION_TRIGGER_FIELDS:
            background_tasks.add_task(recompile_value_dimensions, user_id)

        return {"status": "success", "detail": "Profile details synchronized."}
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to update profile details")
        raise HTTPException(
            status_code=500,
            detail="Internal server error.",
        ) from e
