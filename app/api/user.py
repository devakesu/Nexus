import json
import logging
from datetime import datetime, timezone
from typing import Any, cast

from fastapi import (
    APIRouter,
    BackgroundTasks,
    Body,
    Depends,
    Header,
    HTTPException,
    Request,
    status,
)
from starlette.concurrency import run_in_threadpool

from app.api.dependencies import (
    assert_account_active,
    get_authenticated_user_id,
    get_authenticated_user_payload,
    verify_app_check_with_replay_protection,
)
from app.core.config import settings
from app.core.crypto import compute_blind_index, encrypt_to_hex
from app.core.email import extract_user_name, send_bootstrap_welcome_email
from app.core.limiter import limiter
from app.db.client import supabase_client
from app.db.profiles import (
    decrypt_profile_record,
    sanitize_decrypted_profile,
    sign_profile_media_bulk,
    update_profile_images_and_metadata,
)
from app.db.users import (
    fetch_profile,
    fetch_public_user,
    is_allowed_email,
    update_user_terms,
    upsert_profile_variant,
    upsert_public_user,
)
from app.models import (
    ALLOWED_HIDDEN_FIELDS,
    AcceptTermsRequest,
    AcceptTermsResponse,
    AuthBootstrapResponse,
    CompleteOnboardingResponse,
    EmailNotificationSettingsResponse,
    EmailNotificationSettingsUpdate,
    MECOnboardingRequest,
    ModerationSubjectsRequest,
    OnboardingPayload,
    PrivacySettingsResponse,
    PrivacySettingsUpdate,
    ProfileDetailsUpdate,
    ProfileImagesAndTagsUpdate,
)
from app.services.profile import recompile_and_push_vectors
from app.services.value_dimensions import recompile_value_dimensions

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

logger = logging.getLogger(__name__)

router = APIRouter()



@router.post("/api/v1/auth/bootstrap", response_model=AuthBootstrapResponse)
@limiter.limit(settings.rate_limit_auth)
async def auth_bootstrap(
    request: Request,
    background_tasks: BackgroundTasks,
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user: dict[str, Any] = Depends(get_authenticated_user_payload),  # noqa: B008
    x_app_variant: str | None = Header(None, alias="X-App-Variant"),
):
    _ = request

    user_id = str(auth_user.get("id") or "").strip()
    email = str(auth_user.get("email") or "").strip().lower()
    phone = str(auth_user.get("phone") or "").strip()

    if not user_id or (not email and not phone):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user payload is incomplete.",
        )

    app_variant = (x_app_variant or "nexus").strip().lower()
    if app_variant not in ("nexus", "nexus_mec"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Unrecognized X-App-Variant header value.",
        )

    is_allowed = await run_in_threadpool(
        is_allowed_email,
        email,
        app_variant=app_variant,
    )
    if email and not is_allowed:
        try:
            await run_in_threadpool(supabase_client.auth.admin.delete_user, user_id)
        except Exception as err:  # noqa: BLE001
            logger.error("Failed to delete unauthorized user %s: %s", user_id, err)
        required_domain = settings.allowed_email_domains.get(
            app_variant,
            "your approved domain",
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"Only @{required_domain} accounts are allowed for this app variant. "
                "Please sign in with your campus Google Workspace account."
            ),
        )

    user_row, newly_created = await run_in_threadpool(
        upsert_public_user,
        user_id=user_id,
        email=email if email else None,
        mobile=phone if phone else None,
        app_variant=app_variant,
    )

    assert_account_active(user_row)

    if newly_created and email:
        background_tasks.add_task(
            send_bootstrap_welcome_email,
            email=email,
            auth_user=auth_user,
            app_variant=app_variant,
        )

    return AuthBootstrapResponse(
        user_id=str(user_row["id"]),
        email=(
            str(user_row["email"]).strip().lower()
            if user_row.get("email")
            else (email if email else None)
        ),
        is_active=bool(user_row.get("is_active", True)),
        is_suspended=bool(user_row.get("is_suspended", False)),
        moderation_status=str(user_row.get("moderation_status") or "clear"),
        accepted_terms_version=user_row.get("accepted_terms_version"),
        terms_accepted_at=user_row.get("terms_accepted_at"),
        newly_created=newly_created,
    )


@router.post(
    "/api/v1/auth/complete-onboarding",
    response_model=CompleteOnboardingResponse,
)
@limiter.limit(settings.rate_limit_auth)
def complete_onboarding(
    request: Request,
    payload: OnboardingPayload = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user: dict[str, Any] = Depends(get_authenticated_user_payload),  # noqa: B008
):
    """
    Complete the onboarding flow.

    Accepts a discriminated union payload keyed on `app_variant`:
      - 'nexus'     → NexusOnboardingRequest  (dating_intent, hobbies)
      - 'nexus_mec' → MECOnboardingRequest    (major, grad_year, campus_clubs)

    Common fields (branch, year, age, name) are stored directly on the profile.
    Variant-specific fields are stored in the variant_metadata JSONB column.
    """
    _ = request

    user_id = str(auth_user.get("id") or "").strip()
    email_raw = auth_user.get("email")
    email = str(email_raw).strip().lower() if email_raw else None

    if not user_id or (not email and not auth_user.get("phone")):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user payload is incomplete.",
        )

    user_row = fetch_public_user(user_id)
    if not user_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User bootstrap row not found. Complete bootstrap first.",
        )

    assert_account_active(user_row)

    if fetch_profile(user_id) is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Onboarding has already been completed.",
        )

    # Resolve name and variant-specific fields per flavor.
    if isinstance(payload, MECOnboardingRequest):
        # MEC: name is derived server-side from Google OAuth metadata.
        if not email:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email is required for campus MEC onboarding.",
            )
        user_name = extract_user_name(email, auth_user)
        user_branch: str | None = payload.campus_branch
        user_year: int | None = payload.campus_year
        user_campus_name: str | None = payload.campus_name
        user_lifestyle: str | None = None
    else:
        # NexusOnboardingRequest: name and lifestyle are provided in the payload.
        user_name = payload.name
        user_branch = None
        user_year = None
        user_campus_name = None
        user_lifestyle = payload.lifestyle

    upsert_public_user(
        user_id=user_id,
        mobile=payload.phone,
    )

    profile_row, profile_created = upsert_profile_variant(
        user_id=user_id,
        name=user_name,
        campus_branch=user_branch,
        campus_year=user_year,
        age=payload.age,
        campus_name=user_campus_name,
        lifestyle=user_lifestyle,
    )

    stored_terms_version, stored_terms_accepted_at = update_user_terms(
        user_id=user_id,
        accepted_terms_version=payload.accepted_terms_version,
    )

    return CompleteOnboardingResponse(
        user_id=user_id,
        profile_created=profile_created,
        terms_recorded=True,
        accepted_terms_version=stored_terms_version,
        terms_accepted_at=stored_terms_accepted_at,
        profile=profile_row,
    )


@router.post(
    "/api/v1/auth/accept-terms",
    response_model=AcceptTermsResponse,
)
@limiter.limit(settings.rate_limit_auth)
def accept_terms(
    request: Request,
    payload: AcceptTermsRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_with_replay_protection),
    auth_user: dict[str, Any] = Depends(get_authenticated_user_payload),  # noqa: B008
):
    _ = request

    user_id = str(auth_user.get("id") or "").strip()
    email = str(auth_user.get("email") or "").strip().lower()
    phone = str(auth_user.get("phone") or "").strip()

    if not user_id or (not email and not phone):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user payload is incomplete.",
        )

    user_row = fetch_public_user(user_id)
    if not user_row:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User bootstrap row not found. Complete bootstrap first.",
        )

    assert_account_active(user_row)

    stored_terms_version, stored_terms_accepted_at = update_user_terms(
        user_id=user_id,
        accepted_terms_version=payload.accepted_terms_version,
    )

    return AcceptTermsResponse(
        user_id=user_id,
        accepted_terms_version=stored_terms_version,
        terms_accepted_at=stored_terms_accepted_at,
        terms_recorded=True,
    )


@router.post("/api/v1/profile/media", status_code=status.HTTP_200_OK)
@limiter.limit("5/minute")
async def update_profile_media_and_tags(
    request: Request,
    payload: ProfileImagesAndTagsUpdate = Body(...),  # noqa: B008
    user_id: str = Depends(get_authenticated_user_id),
    _device: None = Depends(verify_app_check_with_replay_protection),
):
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


@router.get("/api/v1/profile/details")
def get_profile_details(
    user_id: str = Depends(get_authenticated_user_id),
) -> dict[str, Any]:
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

        # Check if any field failed decryption
        for val in profile.values():
            if (
                val == "__DECRYPTION_FAILED__"
                or val == ["__DECRYPTION_FAILED__"]
                or val == {"__DECRYPTION_FAILED__": True}
            ):
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=(
                        "Profile decryption failed due to data "
                        "corruption or key mismatch."
                    ),
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
            "ordered_images": (
                [profile.get("profile_pic")] + (profile.get("normal_pics") or [])
                if profile.get("profile_pic")
                else (profile.get("normal_pics") or [])
            ),
            "ai_vibe_tags": profile.get("ai_vibe_tags") or [],
            "is_dating_active": bool(profile.get("is_dating_active", False)),
            "is_friends_active": bool(profile.get("is_friends_active", False)),
            "is_professional_active": bool(
                profile.get("is_professional_active", False),
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


@router.post("/api/v1/users/moderation-subjects")
def get_moderation_subjects(
    payload: ModerationSubjectsRequest = Body(...),  # noqa: B008
    user_id: str = Depends(get_authenticated_user_id),
) -> list[dict[str, Any]]:
    """
    Returns basic decrypted profile info for users the caller has actively
    blocked or hidden.

    Validates each requested target_id against profile_discovery_actions
    before returning data.
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
            except Exception:  # noqa: BLE001
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
    val_interests = _resolve_field(profile, payload, "interests")
    val_profile_pic = _resolve_field(profile, payload, "profile_pic")
    val_normal_pics = _resolve_field(profile, payload, "normal_pics")

    if not isinstance(val_name, str) or not val_name.strip():
        missing.append("name")
    if val_age is None:
        missing.append("age")
    if val_interests != {"__DECRYPTION_FAILED__": True} and (
        not isinstance(val_interests, dict)
        or len(cast(dict[Any, Any], val_interests)) < 3
    ):
        missing.append("interests")
    if val_profile_pic != "__DECRYPTION_FAILED__" and (
        not isinstance(val_profile_pic, str) or not val_profile_pic.strip()
    ):
        missing.append("profile_pic")
    if val_normal_pics != ["__DECRYPTION_FAILED__"] and (
        not isinstance(val_normal_pics, list)
        or len(cast(list[Any], val_normal_pics)) < 2
    ):
        missing.append("normal_pics")


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
    val_friends_target_buckets = _resolve_field(
        profile,
        payload,
        "friends_target_buckets",
    )
    val_sub_interests = _resolve_field(profile, payload, "sub_interests")
    val_causes_supported = _resolve_field(profile, payload, "causes_supported")

    if (
        not isinstance(val_friends_target_buckets, list)
        or len(cast(list[Any], val_friends_target_buckets)) < 1
    ):
        missing.append("friends_target_buckets")
    sub_count = (
        sum(len(v) for v in cast(dict[str, list[str]], val_sub_interests).values())
        if isinstance(val_sub_interests, dict)
        else 0
    )
    if sub_count < 2:
        missing.append("sub_interests")
    if (
        not isinstance(val_causes_supported, list)
        or len(cast(list[Any], val_causes_supported)) < 1
    ):
        missing.append("causes_supported")


def _validate_professional_activation(
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
    missing: list[str],
) -> None:
    val_professional_target_buckets = _resolve_field(
        profile,
        payload,
        "professional_target_buckets",
    )
    val_looking_for = _resolve_field(profile, payload, "looking_for")
    val_tech_skills = _resolve_field(profile, payload, "tech_skills")

    if (
        not isinstance(val_professional_target_buckets, list)
        or len(cast(list[Any], val_professional_target_buckets)) < 1
    ):
        missing.append("professional_target_buckets")
    if (
        not isinstance(val_looking_for, list)
        or len(cast(list[Any], val_looking_for)) < 1
    ):
        missing.append("looking_for")
    if (
        not isinstance(val_tech_skills, list)
        or len(cast(list[Any], val_tech_skills)) < 1
    ):
        missing.append("tech_skills")


def _validate_tab_activation(
    tab_name: str,
    profile: dict[str, Any],
    payload: ProfileDetailsUpdate,
) -> list[str]:
    """
    Validates required profile fields for activating a specific tab.
    Supports 'Dating', 'Friends', or 'Professional'.
    """
    missing: list[str] = []
    _validate_common_activation(profile, payload, missing)

    if tab_name == "Dating":
        _validate_dating_activation(profile, payload, missing)
    elif tab_name == "Friends":
        _validate_friends_activation(profile, payload, missing)
    elif tab_name == "Professional":
        _validate_professional_activation(profile, payload, missing)

    return missing


@router.patch("/api/v1/profile/details")
def update_profile_details(  # noqa: C901
    background_tasks: BackgroundTasks,
    payload: ProfileDetailsUpdate = Body(...),  # noqa: B008
    user_id: str = Depends(get_authenticated_user_id),
    _device: None = Depends(verify_app_check_with_replay_protection),
) -> dict[str, Any]:
    update_data: dict[str, Any] = {}

    if payload.name is not None:
        update_data["name"] = payload.name.strip()
    if payload.age is not None:
        update_data["age"] = payload.age
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
        "partner_values",
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
    )
    profile = None
    if need_profile_fetch:
        profile_res = (
            supabase_client.table("profiles")
            .select(
                "name,age,profile_pic,normal_pics,interests,sub_interests,"
                "drinking,smoking,partner_values,dating_target_buckets,dating_for,"
                "friends_target_buckets,causes_supported,"
                "professional_target_buckets,looking_for,tech_skills",
            )
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        profile_data = getattr(profile_res, "data", None)
        if not profile_data or not isinstance(profile_data, dict):
            raise HTTPException(status_code=404, detail="Profile not found")
        profile = decrypt_profile_record(cast(dict[str, Any], profile_data))

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

    if not update_data:
        return {"status": "success", "detail": "No fields to update."}

    update_data["updated_at"] = datetime.now(timezone.utc).isoformat()

    try:
        res = (
            supabase_client.table("profiles")
            .update(update_data)
            .eq("id", user_id)
            .execute()
        )
        if not getattr(res, "data", None):
            raise HTTPException(status_code=404, detail="Profile not found")

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


def _to_privacy_settings_response(data: dict[str, Any]) -> PrivacySettingsResponse:
    raw: list[str] = list(data.get("hidden_profile_fields") or [])
    # Defensively strip any field names that are no longer in the allowed set.
    hidden: list[str] = [f for f in raw if f in ALLOWED_HIDDEN_FIELDS]
    return PrivacySettingsResponse(
        hidden_fields=hidden,
        share_active_status=bool(data.get("share_active_status", True)),
        share_read_receipts=bool(data.get("share_read_receipts", True)),
    )


@router.get(
    "/api/v1/profile/privacy-settings",
    response_model=PrivacySettingsResponse,
)
def get_privacy_settings(
    user_id: str = Depends(get_authenticated_user_id),
) -> PrivacySettingsResponse:
    try:
        res = (
            supabase_client.table("profiles")
            .select("hidden_profile_fields, share_active_status, share_read_receipts")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        data = getattr(res, "data", None)
        if data is None:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_privacy_settings_response(data)
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to fetch privacy settings for user %s", user_id)
        raise HTTPException(status_code=500, detail="Internal server error.") from e


@router.patch(
    "/api/v1/profile/privacy-settings",
    response_model=PrivacySettingsResponse,
)
def update_privacy_settings(
    payload: PrivacySettingsUpdate = Body(...),  # noqa: B008
    user_id: str = Depends(get_authenticated_user_id),
) -> PrivacySettingsResponse:
    update_data: dict[str, Any] = {}
    if payload.hidden_fields is not None:
        update_data["hidden_profile_fields"] = payload.hidden_fields
    if payload.share_active_status is not None:
        update_data["share_active_status"] = payload.share_active_status
    if payload.share_read_receipts is not None:
        update_data["share_read_receipts"] = payload.share_read_receipts
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update.")

    try:
        res = (
            supabase_client.table("profiles")
            .update(update_data)
            .eq("id", user_id)
            .select("hidden_profile_fields, share_active_status, share_read_receipts")
            .execute()
        )
        rows = cast(list[dict[str, Any]], getattr(res, "data", None) or [])
        if not rows:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_privacy_settings_response(rows[0])
    except HTTPException:
        raise
    except Exception as e:
        logger.exception("Failed to update privacy settings for user %s", user_id)
        raise HTTPException(status_code=500, detail="Internal server error.") from e


_EMAIL_NOTIFICATION_COLUMNS = (
    "email_notify_matches, email_notify_messages, email_notify_digest, "
    "email_notify_product_updates, email_notify_promotions"
)


def _to_email_notification_settings_response(
    data: dict[str, Any],
) -> EmailNotificationSettingsResponse:
    return EmailNotificationSettingsResponse(
        email_notify_matches=bool(data.get("email_notify_matches", True)),
        email_notify_messages=bool(data.get("email_notify_messages", True)),
        email_notify_digest=bool(data.get("email_notify_digest", True)),
        email_notify_product_updates=bool(
            data.get("email_notify_product_updates", True),
        ),
        email_notify_promotions=bool(data.get("email_notify_promotions", True)),
    )


@router.get(
    "/api/v1/profile/email-notification-settings",
    response_model=EmailNotificationSettingsResponse,
)
def get_email_notification_settings(
    user_id: str = Depends(get_authenticated_user_id),
) -> EmailNotificationSettingsResponse:
    try:
        res = (
            supabase_client.table("profiles")
            .select(_EMAIL_NOTIFICATION_COLUMNS)
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        data = getattr(res, "data", None)
        if data is None:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_email_notification_settings_response(data)
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(
            "Failed to fetch email notification settings for user %s", user_id,
        )
        raise HTTPException(status_code=500, detail="Internal server error.") from e


@router.patch(
    "/api/v1/profile/email-notification-settings",
    response_model=EmailNotificationSettingsResponse,
)
def update_email_notification_settings(
    payload: EmailNotificationSettingsUpdate = Body(...),  # noqa: B008
    user_id: str = Depends(get_authenticated_user_id),
) -> EmailNotificationSettingsResponse:
    update_data = payload.model_dump(exclude_none=True)
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update.")

    try:
        res = (
            supabase_client.table("profiles")
            .update(update_data)
            .eq("id", user_id)
            .select(_EMAIL_NOTIFICATION_COLUMNS)
            .execute()
        )
        rows = cast(list[dict[str, Any]], getattr(res, "data", None) or [])
        if not rows:
            raise HTTPException(status_code=404, detail="Profile not found")
        return _to_email_notification_settings_response(rows[0])
    except HTTPException:
        raise
    except Exception as e:
        logger.exception(
            "Failed to update email notification settings for user %s", user_id,
        )
        raise HTTPException(status_code=500, detail="Internal server error.") from e
