import asyncio
import logging

from fastapi import APIRouter, Body, Depends, HTTPException, Request

from app.api.dependencies import get_authenticated_user_id, verify_app_check_token
from app.core.config import settings
from app.core.limiter import limiter
from app.core.sms import compose_inform_message, compose_sos_message, send_sms
from app.db.client import DatabaseAccessError
from app.db.safety import (
    fetch_safety_contacts,
    record_safety_alert,
    register_safety_evidence,
    sync_safety_contacts,
    update_alert_contacts_notified,
)
from app.models import (
    SafetyAlertRequest,
    SafetyAlertResponse,
    SafetyContactsSyncRequest,
    SafetyEvidenceRegisterRequest,
    SafetyEvidenceRegisterResponse,
)

router = APIRouter()
logger = logging.getLogger(__name__)


@router.put("/api/v1/safety/contacts")
@limiter.limit(settings.rate_limit_safety)
async def put_safety_contacts(
    request: Request,
    payload: SafetyContactsSyncRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
) -> dict[str, int]:
    _ = request
    try:
        await asyncio.to_thread(
            sync_safety_contacts,
            user_id,
            [c.model_dump() for c in payload.contacts],
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error syncing safety contacts",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err
    return {"count": len(payload.contacts)}


@router.post("/api/v1/safety/alert", response_model=SafetyAlertResponse)
@limiter.limit(settings.rate_limit_safety)
async def send_safety_alert(
    request: Request,
    payload: SafetyAlertRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
) -> SafetyAlertResponse:
    """Composes and sends the SOS/inform SMS to every trusted contact on
    file, then logs the alert (and how many contacts were actually reached)
    for audit purposes. Notifying remaining contacts continues even if one
    send fails - a partial alert is far better than none.
    """
    _ = request

    try:
        contacts = await asyncio.to_thread(fetch_safety_contacts, user_id)
    except DatabaseAccessError as err:
        logger.exception(
            "Database error fetching safety contacts for alert",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    if not contacts:
        raise HTTPException(
            status_code=400,
            detail="No trusted contacts on file to alert.",
        )

    display_name = payload.session_label or "A Nexus user"
    location = (
        payload.current_location.model_dump()
        if payload.current_location is not None
        else None
    )

    if payload.alert_type == "inform":
        body = compose_inform_message(
            name=display_name,
            location=location,
            event_label=payload.event_label,
        )
    else:
        body = compose_sos_message(
            name=display_name,
            silent=payload.alert_type == "sos_silent",
            location=location,
            event_label=payload.event_label,
        )

    notified = 0
    for contact in contacts:
        result = await send_sms(contact["phone"], body)
        if result.success:
            notified += 1
        else:
            logger.warning(
                "Failed to notify a trusted contact",
                extra={"user_id": user_id, "alert_type": payload.alert_type},
            )

    try:
        row = await asyncio.to_thread(
            record_safety_alert,
            user_id,
            payload.alert_type,
            location,
        )
        await asyncio.to_thread(
            update_alert_contacts_notified,
            str(row["id"]),
            notified,
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error recording safety alert",
            extra={"user_id": user_id, "alert_type": payload.alert_type},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    return SafetyAlertResponse(
        id=str(row["id"]),
        contacts_notified=notified,
        contacts_total=len(contacts),
    )


@router.post(
    "/api/v1/safety/evidence",
    response_model=SafetyEvidenceRegisterResponse,
)
@limiter.limit(settings.rate_limit_safety)
async def register_evidence(
    request: Request,
    payload: SafetyEvidenceRegisterRequest = Body(...),  # noqa: B008
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id),
) -> SafetyEvidenceRegisterResponse:
    """Registers a Digital Witness (Silent SOS) evidence segment already
    uploaded (as ciphertext) to the safety_evidence storage bucket. The
    decryption key is escrowed here for a future OTP-authenticated
    trusted-contact portal - see the safety_evidence table comment.
    """
    _ = request

    own_prefix = f"{user_id}/"
    if not payload.storage_path.startswith(own_prefix):
        raise HTTPException(
            status_code=422,
            detail="storage_path may only reference your own uploads.",
        )

    try:
        row = await asyncio.to_thread(
            register_safety_evidence,
            user_id,
            payload.alert_id,
            payload.storage_path,
            payload.media_key_base64,
            payload.content_type,
            payload.duration_seconds,
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error registering safety evidence",
            extra={"user_id": user_id, "alert_id": payload.alert_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    return SafetyEvidenceRegisterResponse(id=str(row["id"]))
