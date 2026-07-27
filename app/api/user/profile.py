"""Profile media updates, details GET/PATCH endpoints, and moderation subjects lookup."""

import json
import logging
from datetime import datetime, timedelta, timezone
from typing import Any, cast

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Body,
    Depends,
    HTTPException,
    Request,
    status,
)
from postgrest.exceptions import APIError

from app.api.dependencies import (
    assert_special_category_consent,
    get_active_user_id,
    verify_app_check_with_replay_protection,
)
from app.core.crypto import compute_blind_index, encrypt_to_hex
from app.core.limiter import limiter
from app.core.moderation import NameModerationError, validate_display_name
from app.db.client import parse_utc_datetime, supabase_client
from app.db.profiles import (
    decrypt_profile_record,
    sanitize_decrypted_profile,
    sign_profile_media_bulk,
    update_profile_images_and_metadata,
)
from app.db.users import (
    fetch_public_user,
)
from app.models import (
    ModerationSubjectItem,
    ModerationSubjectsRequest,
    ProfileDetailsResponse,
    ProfileDetailsUpdate,
    ProfileImagesAndTagsUpdate,
    ProfileUpdateResponse,
)
from app.services.profile import recompile_and_push_vectors
from app.services.value_dimensions import recompile_value_dimensions

logger = logging.getLogger(__name__)

router = APIRouter()

_VALUE_DIMENSION_TRIGGER_FIELDS = frozenset(
    {
        "interests",
        "sub_interests",
        "causes_supported",
        "tech_skills",
        "activities",
        "lifestyle",
    },
)

_AGE_CHANGE_WINDOW_DAYS = 365
_AGE_CHANGE_MAX_PER_WINDOW = 2
_NAME_CHANGE_WINDOW_DAYS = 365
_NAME_CHANGE_MAX_PER_WINDOW = 2

_SPECIAL_CATEGORY_OPT_OUT_VALUES = {
    "display_sexuality": "Prefer not to say",
    "religious_beliefs": "Prefer not to say",
}


def _assert_no_decryption_failures(profile: dict[str, Any]) -> None:
    for val in profile.values():
        if (
            val == "__DECRYPTION_FAILED__"
            or val == ["__DECRYPTION_FAILED__"]
            or val == {"__DECRYPTION_FAILED__": True}
        ):
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=(
                    "Profile decryption failed due to data corruption or key mismatch."
                ),
            )


def _rolling_change_window_status(
    table: str,
    user_id: str,
    window_days: int,
    max_changes: int,
) -> tuple[int, bool, datetime | None]:
    cutoff = datetime.now(timezone.utc) - timedelta(days=window_days)
    try:
        res = (
            supabase_client.table(table)
            .select("changed_at")
            .eq("user_id", user_id)
            .gte("changed_at", cutoff.isoformat())
            .order("changed_at")
            .execute()
        )
    except Exception as e:
        logger.exception(
            "Failed to check rolling change-window eligibility",
            extra={"user_id": user_id, "table": table},
        )
        raise HTTPException(
            status_code=500,
            detail="Internal server error.",
        ) from e

    rows = cast("list[dict[str, Any]]", getattr(res, "data", None) or [])
    used = len(rows)
    eligible = used < max_changes
    next_eligible = (
        parse_utc_datetime(rows[0]["changed_at"]) + timedelta(days=window_days)
        if not eligible
        else None
    )
    return used, eligible, next_eligible


def _build_ordered_images(profile: dict[str, Any]) -> list[str]:
    profile_pic = profile.get("profile_pic")
    normal_pics = profile.get("normal_pics")
    ordered_images: list[str] = []
    if profile_pic and isinstance(profile_pic, str) and profile_pic.strip():
        ordered_images.append(profile_pic)
    if isinstance(normal_pics, list):
        for p in cast(list[object], normal_pics):
            if isinstance(p, str) and p.strip():
                ordered_images.append(p)
    return ordered_images


def _sets_special_category_data(payload: ProfileDetailsUpdate) -> bool:
    return any(
        (val := getattr(payload, field, None)) is not None and val != opt_out
        for field, opt_out in _SPECIAL_CATEGORY_OPT_OUT_VALUES.items()
    )


def _resolve_field(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    field_name: str,
) -> Any:
    payload_val = getattr(payload, field_name, None)
    return payload_val if payload_val is not None else profile.get(field_name)


def _validate_common_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_name = _resolve_field(profile, payload, "name")
    val_age = _resolve_field(profile, payload, "age")
    val_sub_interests = _resolve_field(profile, payload, "sub_interests")
    val_profile_pic = _resolve_field(profile, payload, "profile_pic")
    val_normal_pics = _resolve_field(profile, payload, "normal_pics")
    val_bio = _resolve_field(profile, payload, "bio")

    if not isinstance(val_name, str) or not val_name.strip():
        missing.append("name")
    if val_age is None:
        missing.append("age")

    sub_count = (
        sum(len(v) for v in cast(dict[str, list[str]], val_sub_interests).values())
        if isinstance(val_sub_interests, dict)
        else 0
    )
    if val_sub_interests != {"__DECRYPTION_FAILED__": True} and sub_count < 2:
        missing.append("interests")
    if val_profile_pic != "__DECRYPTION_FAILED__" and (
        not isinstance(val_profile_pic, str) or not val_profile_pic.strip()
    ):
        missing.append("profile_pic")
    if val_normal_pics != ["__DECRYPTION_FAILED__"] and (
        not isinstance(val_normal_pics, list)
        or len(cast(list[Any], val_normal_pics)) < 1
    ):
        missing.append("normal_pics")
    if val_bio == "__DECRYPTION_FAILED__":
        pass
    else:
        if not isinstance(val_bio, str) or sum(c.isalpha() for c in val_bio) < 3:
            missing.append("bio")


def _validate_dating_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_drinking = _resolve_field(profile, payload, "drinking")
    val_smoking = _resolve_field(profile, payload, "smoking")
    val_dating_target_buckets = _resolve_field(
        profile,
        payload,
        "dating_target_buckets",
    )
    val_dating_for = _resolve_field(profile, payload, "dating_for")
    val_partner_values = _resolve_field(profile, payload, "partner_values")

    if not isinstance(val_drinking, str) or not val_drinking.strip():
        missing.append("drinking")
    if not isinstance(val_smoking, str) or not val_smoking.strip():
        missing.append("smoking")
    if (
        not isinstance(val_dating_target_buckets, list)
        or len(cast(list[Any], val_dating_target_buckets)) < 1
    ):
        missing.append("dating_target_buckets")
    if not isinstance(val_dating_for, list) or len(cast(list[Any], val_dating_for)) < 1:
        missing.append("dating_for")
    if (
        not isinstance(val_partner_values, list)
        or len(cast(list[Any], val_partner_values)) < 1
    ):
        missing.append("partner_values")


def _validate_friends_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_causes = _resolve_field(profile, payload, "causes_supported")
    val_friends_target = _resolve_field(profile, payload, "friends_target_buckets")

    if (
        not isinstance(val_causes, list)
        or len(cast(list[Any], val_causes)) < 1
    ):
        missing.append("causes_supported")
    if (
        not isinstance(val_friends_target, list)
        or len(cast(list[Any], val_friends_target)) < 1
    ):
        missing.append("friends_target_buckets")


def _validate_professional_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_looking = _resolve_field(profile, payload, "looking_for")
    val_skills = _resolve_field(profile, payload, "tech_skills")
    val_professional_target = _resolve_field(
        profile,
        payload,
        "professional_target_buckets",
    )

    if not isinstance(val_looking, list) or len(cast(list[Any], val_looking)) < 1:
        missing.append("looking_for")
    if not isinstance(val_skills, list) or len(cast(list[Any], val_skills)) < 1:
        missing.append("tech_skills")
    if (
        not isinstance(val_professional_target, list)
        or len(cast(list[Any], val_professional_target)) < 1
    ):
        missing.append("professional_target_buckets")


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


@router.post("/api/v1/profile/media", status_code=status.HTTP_200_OK)
@limiter.limit("5/minute")
async def update_profile_media_and_tags(
    request: Request,
    payload: ProfileImagesAndTagsUpdate = Body(...),
    user_id: str = Depends(get_active_user_id),
    _device: None = Depends(verify_app_check_with_replay_protection),
):
    """Executes update profile media and tags operation."""
    _ = request
    try:
        await update_profile_images_and_metadata(
            user_id=user_id,
            images=[payload.profile_pic, *payload.normal_pics],
            vibe_tags=payload.ai_vibe_tags,
        )
        return {"status": "success", "detail": "Profile media synchronized."}
    except ValueError as err:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=(
                "Target account context mismatch. Profile row modification rejected."
            ),
        ) from err
    except Exception as e:
        logger.exception("Profile media update failed for user %s", user_id)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server metadata pipeline error: Data synchronization failed.",
        ) from e


@router.get("/api/v1/profile/details", response_model=ProfileDetailsResponse)
def get_profile_details(
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


@router.post(
    "/api/v1/users/moderation-subjects",
    response_model=list[ModerationSubjectItem],
)
def get_moderation_subjects(
    payload: ModerationSubjectsRequest = Body(...),
    user_id: str = Depends(get_active_user_id),
) -> list[dict[str, Any]]:
    """
    Returns basic decrypted profile info for users the caller has actively
    blocked or hidden.
    """
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
                supabase_client.table("profiles")
                .select("campus_name, campus_year")
                .eq("id", user_id)
                .maybe_single()
                .execute()
            )
            campus_data = cast(
                dict[str, Any],
                getattr(campus_res, "data", None) or {},
            )
            decrypted_campus = decrypt_profile_record(campus_data)
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
            supabase_client.table("profiles")
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
        profile = decrypt_profile_record(cast(dict[str, Any], profile_data))

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
                supabase_client.rpc(
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
                supabase_client.rpc(
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
                supabase_client.table("profiles")
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
