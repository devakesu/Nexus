import json
import logging
from datetime import datetime
from typing import Any, cast

import jwt
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
from pydantic import BaseModel

from app.api.dependencies import (
    get_bearer_token,
    verify_app_check_token,
    verify_app_check_with_replay_protection,
)
from app.core.config import settings
from app.core.crypto import compute_blind_index, encrypt_pii
from app.core.email import extract_user_name, send_bootstrap_welcome_email
from app.core.jwks import get_live_supabase_public_key
from app.core.limiter import limiter
from app.db.client import supabase_client
from app.db.profiles import decrypt_profile_record
from app.db.users import (
    fetch_public_user,
    get_supabase_user_from_jwt,
    is_allowed_email,
    update_user_terms,
    upsert_profile_variant,
    upsert_public_user,
)
from app.models import (
    AcceptTermsRequest,
    AcceptTermsResponse,
    AuthBootstrapResponse,
    CompleteOnboardingResponse,
    MECOnboardingRequest,
    OnboardingPayload,
    ProfileImagesAndTagsUpdate,
)

logger = logging.getLogger(__name__)

router = APIRouter()


def get_authenticated_user_id(authorization: str | None = Header(None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Missing or malformed Authorization header credentials.",
        )

    token = authorization.split(" ", 1)[1]

    try:
        public_key = get_live_supabase_public_key(token)
        payload = jwt.decode(
            token,
            public_key,
            algorithms=["ES256"],
            audience="authenticated",
        )

        user_uuid: str | None = payload.get("sub")
        if not user_uuid:
            raise HTTPException(
                status_code=401,
                detail="Invalid token: sub claim missing.",
            )

        return user_uuid

    except jwt.ExpiredSignatureError as err:
        raise HTTPException(
            status_code=401,
            detail="Authentication session expired.",
        ) from err
    except jwt.InvalidTokenError as err:
        logger.warning("JWT validation failed")
        raise HTTPException(
            status_code=401,
            detail="Cryptographic signature verification failed.",
        ) from err


@router.post("/api/v1/auth/bootstrap", response_model=AuthBootstrapResponse)
@limiter.limit(settings.rate_limit_auth)
def auth_bootstrap(  # noqa: C901
    request: Request,
    background_tasks: BackgroundTasks,
    _device: None = Depends(verify_app_check_with_replay_protection),
    access_token: str = Depends(get_bearer_token),
    x_app_variant: str | None = Header(None, alias="X-App-Variant"),
):
    _ = request

    auth_user = get_supabase_user_from_jwt(access_token)

    user_id = str(auth_user.get("id") or "").strip()
    email = str(auth_user.get("email") or "").strip().lower()
    phone = str(auth_user.get("phone") or "").strip()

    if not user_id or (not email and not phone):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authenticated user payload is incomplete.",
        )

    # Determine which variant this client is running under.
    # Defaults to 'nexus' (main) when the header is absent or unrecognised.
    app_variant = (x_app_variant or "nexus").strip().lower()
    if app_variant not in ("nexus", "nexus_mec"):
        app_variant = "nexus"

    if email and not is_allowed_email(email, app_variant=app_variant):
        try:
            supabase_client.auth.admin.delete_user(user_id)
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

    user_row, newly_created = upsert_public_user(
        user_id=user_id,
        email=email if email else None,
        mobile=phone if phone else None,
        app_variant=app_variant,
    )

    if not bool(user_row.get("is_active", True)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Account is inactive. Please contact support at "
                f"support@{settings.app_domain} for assistance."
            ),
        )

    if bool(user_row.get("is_suspended", False)):
        suspended_until = user_row.get("suspended_until")
        reason_code = user_row.get("moderation_reason_code")
        reason_suffix = f" (Reason: {reason_code})" if reason_code else ""
        if suspended_until:
            try:
                dt = datetime.fromisoformat(str(suspended_until).replace("Z", "+00:00"))
                formatted_time = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
            except ValueError:
                formatted_time = str(suspended_until)
            detail = (
                f"Your Account is suspended until {formatted_time}{reason_suffix}. "
                f"Please contact support at support@{settings.app_domain} for "
                "assistance."
            )
        else:
            detail = (
                f"Your Account is suspended indefinitely{reason_suffix}. Please "
                f"contact support at support@{settings.app_domain} for assistance."
            )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=detail,
        )

    if newly_created and email:
        background_tasks.add_task(
            send_bootstrap_welcome_email,
            email=email,
            auth_user=auth_user,
        )

    return AuthBootstrapResponse(
        user_id=str(user_row["id"]),
        email=str(user_row["email"]) if user_row.get("email") else None,
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
    _device: None = Depends(verify_app_check_token),
    access_token: str = Depends(get_bearer_token),
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

    auth_user = get_supabase_user_from_jwt(access_token)

    user_id = str(auth_user.get("id") or "").strip()
    email = str(auth_user.get("email") or "").strip().lower()

    if not user_id or not email:
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

    if not bool(user_row.get("is_active", True)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Account is inactive. Please contact support at "
                f"support@{settings.app_domain} for assistance."
            ),
        )

    if bool(user_row.get("is_suspended", False)):
        suspended_until = user_row.get("suspended_until")
        reason_code = user_row.get("moderation_reason_code")
        reason_suffix = f" (Reason: {reason_code})" if reason_code else ""
        if suspended_until:
            try:
                dt = datetime.fromisoformat(str(suspended_until).replace("Z", "+00:00"))
                formatted_time = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
            except ValueError:
                formatted_time = str(suspended_until)
            detail = (
                f"Your Account is suspended until {formatted_time}{reason_suffix}. "
                f"Please contact support at support@{settings.app_domain} for "
                "assistance."
            )
        else:
            detail = (
                f"Your Account is suspended indefinitely{reason_suffix}. Please "
                f"contact support at support@{settings.app_domain} for assistance."
            )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=detail,
        )

    # Resolve name and variant-specific fields per flavor.
    if isinstance(payload, MECOnboardingRequest):
        # MEC: name is derived server-side from Google OAuth metadata.
        # Branch and year are provided in the payload.
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
        app_variant=payload.app_variant,
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
    access_token: str = Depends(get_bearer_token),
):
    _ = request

    auth_user = get_supabase_user_from_jwt(access_token)

    user_id = str(auth_user.get("id") or "").strip()
    email = str(auth_user.get("email") or "").strip().lower()

    if not user_id or not email:
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

    if not bool(user_row.get("is_active", True)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                "Account is inactive. Please contact support at "
                f"support@{settings.app_domain} for assistance."
            ),
        )

    if bool(user_row.get("is_suspended", False)):
        suspended_until = user_row.get("suspended_until")
        reason_code = user_row.get("moderation_reason_code")
        reason_suffix = f" (Reason: {reason_code})" if reason_code else ""
        if suspended_until:
            try:
                dt = datetime.fromisoformat(str(suspended_until).replace("Z", "+00:00"))
                formatted_time = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
            except ValueError:
                formatted_time = str(suspended_until)
            detail = (
                f"Your Account is suspended until {formatted_time}{reason_suffix}. "
                f"Please contact support at support@{settings.app_domain} for "
                "assistance."
            )
        else:
            detail = (
                f"Your Account is suspended indefinitely{reason_suffix}. Please "
                f"contact support at support@{settings.app_domain} for assistance."
            )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=detail,
        )

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
def update_profile_media_and_tags(
    request: Request,
    payload: ProfileImagesAndTagsUpdate = Body(...),  # noqa: B008
    user_id: str = Depends(get_authenticated_user_id),
):
    """
    Synchronized Edge-AI Payload Ingestion Gateway.
    Symmetrically encrypts pre-calculated edge AI token lists and storage
    pointers directly into database binary BYTEA columns via the trusted
    service tunnel.
    """
    _ = request

    # 1. Double-Serialize and Encrypt into binary formats for BYTEA columns
    encrypted_avatar: bytes = encrypt_pii(payload.profile_pic)
    encrypted_gallery_json: bytes = encrypt_pii(
        json.dumps(payload.normal_pics),
    )
    encrypted_tags_json: bytes = encrypt_pii(json.dumps(payload.ai_vibe_tags))

    # 2. Package database parameters mapping structures safely
    db_mutation_payload = {
        "profile_pic": encrypted_avatar,
        "normal_pics": encrypted_gallery_json,
        "ai_vibe_tags": encrypted_tags_json,
        "updated_at": "now()",
    }

    try:
        # 3. Direct execution over the high-privilege service-role bypass tunnel
        response = (
            supabase_client.table("profiles")
            .update(db_mutation_payload)
            .eq("id", user_id)
            .execute()
        )

        if not response.data:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=(
                    "Target account context mismatch. "
                    "Profile row modification rejected."
                ),
            )

        return {
            "status": "success",
            "detail": (
                "On-device AI features and assets committed to "
                "cryptographic vault spaces."
            ),
        }

    except Exception as network_write_exception:
        # Protects cloud configuration traces from leaking inside exceptions
        logger.exception(
            "Supabase database transaction aborted for user %s",
            user_id,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server metadata pipeline error: Data synchronization failed.",
        ) from network_write_exception


class ProfileDetailsUpdate(BaseModel):
    name: str | None = None
    age: int | None = None
    campus_branch: str | None = None
    campus_year: int | None = None
    campus_name: str | None = None
    display_gender: str | None = None
    display_sexuality: str | None = None
    pronouns: str | None = None
    search_buckets: list[str] | None = None
    hometown: str | None = None
    current_place: str | None = None
    partner_values: str | None = None
    children_plans: str | None = None
    religious_beliefs: str | None = None
    lifestyle: str | None = None
    drinking: str | None = None
    smoking: str | None = None
    role: str | None = None
    target_buckets: list[str] | None = None
    looking_for: list[str] | None = None
    activities: list[str] | None = None
    causes_supported: list[str] | None = None
    top_artists: list[str] | None = None
    tech_skills: list[str] | None = None
    languages: list[str] | None = None
    pets: list[str] | None = None
    interests: dict[str, int] | None = None
    sub_interests: dict[str, list[str]] | None = None



@router.get("/api/v1/profile/details")
def get_profile_details(
    user_id: str = Depends(get_authenticated_user_id),
) -> dict[str, Any]:
    try:
        res = (
            supabase_client.table("profiles")
            .select("*")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        data = getattr(res, "data", None)
        if data is None:
            raise HTTPException(status_code=404, detail="Profile not found")

        # Decrypt PII fields
        if not isinstance(data, dict):
            raise HTTPException(
                status_code=500,
                detail="Invalid profile data structure",
            )

        profile = decrypt_profile_record(cast(dict[str, Any], data))

        return {
            "name": profile.get("name"),
            "age": profile.get("age"),
            "campus_year": profile.get("campus_year"),
            "campus_branch": profile.get("campus_branch"),
            "campus_name": profile.get("campus_name"),
            "display_gender": profile.get("display_gender"),
            "display_sexuality": profile.get("display_sexuality"),
            "pronouns": profile.get("pronouns"),
            "search_buckets": profile.get("search_buckets") or [],
            "hometown": profile.get("hometown"),
            "current_place": profile.get("current_place"),
            "partner_values": profile.get("partner_values"),
            "children_plans": profile.get("children_plans"),
            "religious_beliefs": profile.get("religious_beliefs"),
            "lifestyle": profile.get("lifestyle"),
            "drinking": profile.get("drinking"),
            "smoking": profile.get("smoking"),
            "role": profile.get("role"),
            "target_buckets": profile.get("target_buckets") or [],
            "looking_for": profile.get("looking_for") or [],
            "activities": profile.get("activities") or [],
            "causes_supported": profile.get("causes_supported") or [],
            "top_artists": profile.get("top_artists") or [],
            "tech_skills": profile.get("tech_skills") or [],
            "languages": profile.get("languages") or [],
            "pets": profile.get("pets") or [],
            "interests": profile.get("interests") or {},
            "sub_interests": profile.get("sub_interests") or {},
        }
    except Exception as e:
        logger.exception("Failed to get profile details")
        raise HTTPException(status_code=500, detail=str(e)) from e


@router.post("/api/v1/profile/details")
def update_profile_details(  # noqa: C901
    payload: ProfileDetailsUpdate = Body(...),  # noqa: B008
    user_id: str = Depends(get_authenticated_user_id),
) -> dict[str, Any]:
    update_data: dict[str, Any] = {}
    if payload.name is not None:
        update_data["name"] = payload.name.strip()
    if payload.age is not None:
        update_data["age"] = payload.age
    if payload.campus_branch is not None:
        update_data["campus_branch"] = payload.campus_branch.strip()
        update_data["campus_branch_blind_index"] = compute_blind_index(
            payload.campus_branch,
        )
    if "campus_year" in payload.model_fields_set:
        update_data["campus_year"] = payload.campus_year
    if payload.campus_name is not None:
        update_data["campus_name"] = payload.campus_name.strip()
    if payload.search_buckets is not None:
        update_data["search_buckets"] = payload.search_buckets
    if payload.target_buckets is not None:
        update_data["target_buckets"] = payload.target_buckets

    # Encrypted scalar fields
    scalar_fields = [
        "display_gender",
        "display_sexuality",
        "pronouns",
        "hometown",
        "current_place",
        "partner_values",
        "children_plans",
        "religious_beliefs",
        "lifestyle",
        "drinking",
        "smoking",
        "role",
    ]
    for field in scalar_fields:
        val = getattr(payload, field, None)
        if val is not None:
            enc = encrypt_pii(val)
            update_data[field] = f"\\x{enc.hex()}" if enc else None

    # Blind indexes computation for exact match filters
    if payload.drinking is not None:
        update_data["drinking_blind_index"] = compute_blind_index(payload.drinking)
    if payload.smoking is not None:
        update_data["smoking_blind_index"] = compute_blind_index(payload.smoking)
    if payload.role is not None:
        update_data["role_blind_index"] = compute_blind_index(payload.role)

    # Encrypted array fields (JSON array payload serialized before encryption)
    array_fields = [
        "looking_for",
        "activities",
        "causes_supported",
        "top_artists",
        "tech_skills",
        "languages",
        "pets",
    ]
    for field in array_fields:
        val = getattr(payload, field, None)
        if val is not None:
            enc = encrypt_pii(json.dumps(val))
            update_data[field] = f"\\x{enc.hex()}" if enc else None

    # Encrypted dict fields (JSON object payload serialized before encryption)
    dict_fields = [
        "interests",
        "sub_interests",
    ]
    for field in dict_fields:
        val = getattr(payload, field, None)
        if val is not None:
            enc = encrypt_pii(json.dumps(val))
            update_data[field] = f"\\x{enc.hex()}" if enc else None

    if not update_data:
        return {"status": "success", "detail": "No fields to update."}

    update_data["updated_at"] = "now()"

    try:
        res = (
            supabase_client.table("profiles")
            .update(update_data)
            .eq("id", user_id)
            .execute()
        )
        res_data = getattr(res, "data", None)
        if not res_data:
            raise HTTPException(status_code=404, detail="Profile not found")
        return {"status": "success", "detail": "Profile details synchronized."}
    except Exception as e:
        logger.exception("Failed to update profile details")
        raise HTTPException(status_code=500, detail=str(e)) from e
