import logging

import jwt
from fastapi import APIRouter, Body, Depends, Header, HTTPException, Request, status

from app.api.dependencies import get_bearer_token, verify_app_check_token
from app.core.config import settings
from app.core.jwks import get_live_supabase_public_key
from app.core.limiter import limiter
from app.db.users import (
    fetch_public_user,
    get_supabase_user_from_jwt,
    is_allowed_college_email,
    update_user_terms,
    upsert_profile,
    upsert_public_user,
)
from app.models import (
    AcceptTermsRequest,
    AcceptTermsResponse,
    AuthBootstrapResponse,
    CompleteOnboardingRequest,
    CompleteOnboardingResponse,
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
    _device: None = Depends(verify_app_check_token),
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

    if not is_allowed_college_email(email):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only college email accounts are allowed.",
        )

    user_row, newly_created = upsert_public_user(user_id=user_id, email=email)

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

    return AuthBootstrapResponse(
        user_id=str(user_row["id"]),
        email=str(user_row["email"]),
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
    payload: CompleteOnboardingRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
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

    profile_row, profile_created = upsert_profile(
        user_id=user_id,
        name=payload.name,
        branch=payload.branch,
        year=payload.year,
        age=payload.age,
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
    _device: None = Depends(verify_app_check_token),
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
