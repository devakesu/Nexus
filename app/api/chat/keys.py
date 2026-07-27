"""FastAPI router for Signal Protocol End-to-End Encryption (E2EE) key exchange management.

Exposes endpoints for uploading user identity keys, signed prekeys, one-time prekey batches,
and fetching recipient key bundles to initiate encrypted chat sessions.
"""

import asyncio
import logging

from fastapi import APIRouter, Body, Depends, HTTPException, Path, Request, status

from app.api.dependencies import get_active_user_id, verify_app_check_token
from app.core.config import settings
from app.core.limiter import limiter
from app.db.chat import (
    bulk_insert_one_time_prekeys,
    count_unused_one_time_prekeys,
    fetch_key_bundle,
    has_active_match,
    mark_session_established,
    upsert_identity_key,
    upsert_signed_prekey,
)
from app.db.client import DatabaseAccessError, ProfileNotFoundError
from app.models import (
    EstablishSessionRequest,
    KeyBundleResponse,
    OneTimePrekeyCountResponse,
    UploadIdentityKeyRequest,
    UploadOneTimePrekeysRequest,
    UploadSignedPrekeyRequest,
)

router = APIRouter()
logger = logging.getLogger(__name__)


@router.put("/api/v1/chat/keys/identity")
@limiter.limit(settings.rate_limit_discover)
async def upload_identity_key(
    request: Request,
    payload: UploadIdentityKeyRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Stores caller's long-term Signal E2EE identity public key.

        Args:
            request: FastAPI HTTP request object.
            payload: Identity key payload containing base64 public key.
            _device: App Check attestation guard.
            user_id: Verified user ID string.

        Returns:
            dict[str, bool]: Success status dict."""
    _ = request
    try:
        await asyncio.to_thread(
            upsert_identity_key,
            user_id,
            payload.identity_public_key,
            payload.registration_id,
        )
        return {"success": True}
    except ProfileNotFoundError as err:
        logger.warning(
            "Upload identity key requested but profile not found",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found. Complete onboarding first.",
        ) from err
    except DatabaseAccessError as err:
        logger.exception("Failed to upload identity key", extra={"user_id": user_id})
        raise HTTPException(
            status_code=503, detail="Service temporarily unavailable.",
        ) from err


@router.put("/api/v1/chat/keys/signed-prekey")
@limiter.limit(settings.rate_limit_discover)
async def upload_signed_prekey(
    request: Request,
    payload: UploadSignedPrekeyRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Stores caller's signed prekey for Signal protocol session establishment.

        Args:
            request: FastAPI HTTP request object.
            payload: Signed prekey payload containing public key and signature.
            _device: App Check attestation guard.
            user_id: Verified user ID string.

        Returns:
            dict[str, bool]: Success status dict."""
    _ = request
    try:
        await asyncio.to_thread(
            upsert_signed_prekey,
            user_id,
            payload.key_id,
            payload.public_key,
            payload.signature,
        )
        return {"success": True}
    except ProfileNotFoundError as err:
        logger.warning(
            "Upload signed prekey requested but profile not found",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found. Complete onboarding first.",
        ) from err
    except DatabaseAccessError as err:
        logger.exception("Failed to upload signed prekey", extra={"user_id": user_id})
        raise HTTPException(
            status_code=503, detail="Service temporarily unavailable.",
        ) from err


@router.post("/api/v1/chat/keys/one-time-prekeys")
@limiter.limit(settings.rate_limit_discover)
async def upload_one_time_prekeys(
    request: Request,
    payload: UploadOneTimePrekeysRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Uploads a batch of one-time prekeys to maintain E2EE session pool.

        Args:
            request: FastAPI HTTP request object.
            payload: Batch prekey upload model containing key list.
            _device: App Check attestation guard.
            user_id: Verified user ID string.

        Returns:
            dict[str, int]: Count of prekeys stored."""
    _ = request
    try:
        await asyncio.to_thread(
            bulk_insert_one_time_prekeys,
            user_id,
            [
                {"key_id": p.key_id, "public_key": p.public_key}
                for p in payload.prekeys
            ],
        )
        return {"success": True}
    except ProfileNotFoundError as err:
        logger.warning(
            "Upload one-time prekeys requested but profile not found",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found. Complete onboarding first.",
        ) from err
    except DatabaseAccessError as err:
        logger.exception(
            "Failed to upload one-time prekeys", extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=503, detail="Service temporarily unavailable.",
        ) from err


@router.get(
    "/api/v1/chat/keys/one-time-prekeys/count",
    response_model=OneTimePrekeyCountResponse,
)
@limiter.limit(settings.rate_limit_discover)
async def get_one_time_prekey_count(
    request: Request,
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> OneTimePrekeyCountResponse:
    """Returns remaining count of unconsumed one-time prekeys for caller.

        Args:
            request: FastAPI HTTP request object.
            _device: App Check attestation guard.
            user_id: Verified user ID string.

        Returns:
            PrekeyCountResponse: Remaining prekey count."""
    _ = request
    try:
        count = await asyncio.to_thread(count_unused_one_time_prekeys, user_id)
        return OneTimePrekeyCountResponse(count=count)
    except DatabaseAccessError as err:
        logger.exception(
            "Failed to count one-time prekeys", extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=503, detail="Service temporarily unavailable.",
        ) from err


@router.get(
    "/api/v1/chat/keys/bundle/{target_user_id}",
    response_model=KeyBundleResponse,
)
@limiter.limit(settings.rate_limit_discover)
async def get_key_bundle(
    request: Request,
    target_user_id: str = Path(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> KeyBundleResponse:
    """Retrieves E2EE public key bundle for establishing encrypted chat session with peer.

        Args:
            request: FastAPI HTTP request object.
            target_user_id: UUID string of target recipient user.
            _device: App Check attestation guard.
            user_id: Verified caller user ID.

        Returns:
            KeyBundleResponse: Signal protocol prekey bundle model.

        Raises:
            HTTPException: 404 if peer key bundle is unavailable."""
    _ = request
    try:
        if not await asyncio.to_thread(has_active_match, user_id, target_user_id):
            raise HTTPException(
                status_code=403,
                detail="You can only fetch key bundles for an active match.",
            )

        bundle = await asyncio.to_thread(fetch_key_bundle, target_user_id)
        if bundle is None:
            raise HTTPException(
                status_code=404,
                detail="This user has not set up secure messaging yet.",
            )

        import base64
        return KeyBundleResponse(
            user_id=target_user_id,
            identity_public_key=base64.b64encode(bundle["identity_public_key"]),
            registration_id=bundle["registration_id"],
            signed_prekey_id=bundle["signed_prekey_id"],
            signed_prekey_public=base64.b64encode(bundle["signed_prekey_public"]),
            signed_prekey_signature=base64.b64encode(bundle["signed_prekey_signature"]),
            one_time_prekey_id=bundle["one_time_prekey_id"],
            one_time_prekey_public=(
                base64.b64encode(bundle["one_time_prekey_public"])
                if bundle["one_time_prekey_public"] is not None
                else None
            ),
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Failed to fetch key bundle",
            extra={"user_id": user_id, "target_user_id": target_user_id},
        )
        raise HTTPException(
            status_code=503, detail="Service temporarily unavailable.",
        ) from err
    except HTTPException:
        raise


@router.post("/api/v1/chat/sessions/establish")
@limiter.limit(settings.rate_limit_discover)
async def establish_session(
    request: Request,
    payload: EstablishSessionRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_active_user_id),
) -> dict[str, bool]:
    """Diagnostics-only: records that user_id completed X3DH toward its peer.

    Never touches key material - the actual session state lives entirely
    on-device.
    """
    _ = request
    try:
        await asyncio.to_thread(
            mark_session_established, user_id, payload.conversation_id,
        )
        return {"success": True}
    except DatabaseAccessError as err:
        logger.exception(
            "Failed to mark session established",
            extra={"user_id": user_id, "conversation_id": payload.conversation_id},
        )
        raise HTTPException(
            status_code=503, detail="Service temporarily unavailable.",
        ) from err
