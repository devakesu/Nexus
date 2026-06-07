import logging

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

from app.api.dependencies import (
    get_bearer_token,
    verify_app_check_token,
    verify_app_check_with_replay_protection,
)
from app.core.config import settings
from app.core.email import extract_user_name, send_bootstrap_welcome_email
from app.core.jwks import get_live_supabase_public_key
from app.core.limiter import limiter
from app.db.client import supabase_client
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
def auth_bootstrap(
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
    )

    if not bool(user_row.get("is_active", True)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is inactive.",
        )

    if bool(user_row.get("is_suspended", False)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is suspended.",
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
            detail="Account is inactive.",
        )

    if bool(user_row.get("is_suspended", False)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is suspended.",
        )

    # Resolve name and variant-specific fields per flavor.
    if isinstance(payload, MECOnboardingRequest):
        # MEC: name is derived server-side from Google OAuth metadata.
        # Branch and year are provided in the payload.
        user_name = extract_user_name(email, auth_user)
        user_branch: str | None = payload.branch
        user_year: int | None = payload.year
        user_lifestyle: str | None = None
    else:
        # NexusOnboardingRequest: name and lifestyle are provided in the payload.
        user_name = payload.name
        user_branch = None
        user_year = None
        user_lifestyle = payload.lifestyle

    profile_row, profile_created = upsert_profile_variant(
        user_id=user_id,
        name=user_name,
        branch=user_branch,
        year=user_year,
        age=payload.age,
        app_variant=payload.app_variant,
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
            detail="Account is inactive.",
        )

    if bool(user_row.get("is_suspended", False)):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is suspended.",
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
