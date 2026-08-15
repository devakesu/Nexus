"""FastAPI endpoints and business logic for the trusted contact and safety portals."""

import asyncio
import logging
from typing import Any, cast

from fastapi import APIRouter, Body, Header, HTTPException, Request
from fastapi.responses import HTMLResponse

from app.api.safety.portal.html import _CONTACT_PORTAL_PAGE_HTML, _PORTAL_PAGE_HTML
from app.core.config import settings
from app.core.email import send_trusted_contact_removed_email
from app.core.infra.cache import redis_client
from app.core.infra.limiter import limiter
from app.core.infra.tasks import safe_create_task
from app.core.security.portal_auth import (
    generate_otp_code,
    hash_otp,
    make_portal_access_token,
    normalize_phone,
    verify_otp_hash,
    verify_portal_access_token,
)
from app.core.utils.sms import (
    compose_contact_self_removed_message,
    send_sms,
    verify_contact_portal_token,
)
from app.db.client import DatabaseAccessError
from app.db.safety import (
    create_evidence_download_url,
    fetch_alerts_for_session,
    fetch_contact_facing_profile_summary,
    fetch_evidence_for_alert_ids,
    fetch_safety_contact_by_id,
    fetch_safety_contacts,
    fetch_safety_session,
    remove_safety_contact_self_service,
)
from app.db.users import fetch_public_user, get_user_email_by_id
from app.models import (
    SafetyContactPortalDetailsResponse,
    SafetyContactPortalOtpRequestRequest,
    SafetyContactPortalOtpRequestResponse,
    SafetyContactPortalOtpVerifyRequest,
    SafetyContactPortalOtpVerifyResponse,
    SafetyContactPortalRemoveResponse,
    SafetyLocation,
    SafetyPortalDetailsResponse,
    SafetyPortalEvidenceItem,
    SafetyPortalOtpRequestRequest,
    SafetyPortalOtpRequestResponse,
    SafetyPortalOtpVerifyRequest,
    SafetyPortalOtpVerifyResponse,
)
from app.services.fcm_sender import send_trusted_contact_removed_notification

router = APIRouter()
logger = logging.getLogger(__name__)

_OTP_TTL_SECONDS = 600
_OTP_MAX_ATTEMPTS = 5
_OTP_RESEND_COOLDOWN_SECONDS = 60
_EVIDENCE_URL_TTL_SECONDS = 600


def _otp_key(session_id: str, phone_norm: str) -> str:
    """Executes otp key operation.

        Args:
            session_id: Input session id parameter.
            phone_norm: Input phone norm parameter.

        Returns:
            str: Response payload or result."""
    return f"safety_portal:otp:{session_id}:{phone_norm}"


def _attempts_key(session_id: str, phone_norm: str) -> str:
    """Executes attempts key operation.

        Args:
            session_id: Input session id parameter.
            phone_norm: Input phone norm parameter.

        Returns:
            str: Response payload or result."""
    return f"safety_portal:otp_attempts:{session_id}:{phone_norm}"


def _resend_key(session_id: str, phone_norm: str) -> str:
    """Executes resend key operation.

        Args:
            session_id: Input session id parameter.
            phone_norm: Input phone norm parameter.

        Returns:
            str: Response payload or result."""
    return f"safety_portal:otp_resend:{session_id}:{phone_norm}"


@router.post(
    "/api/v1/safety/portal/{session_id}/otp/request",
    response_model=SafetyPortalOtpRequestResponse,
)
@limiter.limit(settings.rate_limit_safety_portal)
async def request_portal_otp(
    request: Request,
    session_id: str,
    payload: SafetyPortalOtpRequestRequest = Body(...),
) -> SafetyPortalOtpRequestResponse:
    """Dispatches phone OTP to a trusted contact attempting portal login."""
    _ = request
    phone_norm = normalize_phone(payload.phone)

    resend_key = _resend_key(session_id, phone_norm)
    if await redis_client.exists(resend_key):
        raise HTTPException(
            status_code=429,
            detail="Please wait a bit before requesting another code.",
        )
    await redis_client.set(resend_key, "1", ex=_OTP_RESEND_COOLDOWN_SECONDS, nx=True)

    try:
        session = await asyncio.to_thread(fetch_safety_session, session_id)
        contacts = (
            await asyncio.to_thread(fetch_safety_contacts, str(session["user_id"]))
            if session is not None
            else []
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error looking up safety session for portal OTP",
            extra={"session_id": session_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    matched_phone = next(
        (
            c["phone"]
            for c in contacts
            if normalize_phone(str(c["phone"])) == phone_norm
        ),
        None,
    )

    if matched_phone is not None and phone_norm:
        code = generate_otp_code()
        await redis_client.setex(
            _otp_key(session_id, phone_norm),
            _OTP_TTL_SECONDS,
            hash_otp(session_id, phone_norm, code),
        )
        safe_create_task(
            send_sms(
                matched_phone,
                f"Your Nexus Meetup Safety verification code is {code}. It "
                "expires in 10 minutes. Do not share this code.",
            ),
        )

    return SafetyPortalOtpRequestResponse(sent=True)


@router.post(
    "/api/v1/safety/portal/{session_id}/otp/verify",
    response_model=SafetyPortalOtpVerifyResponse,
)
@limiter.limit(settings.rate_limit_safety_portal)
async def verify_portal_otp(
    request: Request,
    session_id: str,
    payload: SafetyPortalOtpVerifyRequest = Body(...),
) -> SafetyPortalOtpVerifyResponse:
    """Verifies trusted contact phone OTP and issues a portal access token."""
    _ = request
    phone_norm = normalize_phone(payload.phone)

    attempts_key = _attempts_key(session_id, phone_norm)
    attempts = await redis_client.get(attempts_key)
    if attempts and int(attempts) >= _OTP_MAX_ATTEMPTS:
        raise HTTPException(
            status_code=429,
            detail="Too many incorrect attempts. Please request a new code.",
        )

    otp_key = _otp_key(session_id, phone_norm)
    stored_hash = await redis_client.get(otp_key)
    if not stored_hash:
        raise HTTPException(
            status_code=400,
            detail="That code has expired or was never requested. Request a new one.",
        )

    if not verify_otp_hash(session_id, phone_norm, payload.code, cast(str, stored_hash)):
        await redis_client.incr(attempts_key)
        await redis_client.expire(attempts_key, _OTP_TTL_SECONDS)
        raise HTTPException(status_code=400, detail="Incorrect code.")

    await redis_client.delete(otp_key)
    await redis_client.delete(attempts_key)

    token = make_portal_access_token(session_id, phone_norm)
    return SafetyPortalOtpVerifyResponse(token=token, expires_in=30 * 60)


@router.get(
    "/api/v1/safety/portal/{session_id}/details",
    response_model=SafetyPortalDetailsResponse,
)
@limiter.limit(settings.rate_limit_safety_portal)
async def get_portal_details(
    request: Request,
    session_id: str,
    authorization: str | None = Header(default=None),
) -> SafetyPortalDetailsResponse:
    """Executes get portal details operation."""
    _ = request
    token = _extract_bearer_token(authorization)
    if token is None or verify_portal_access_token(session_id, token) is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired portal session. Please verify again.",
        )

    try:
        session = await asyncio.to_thread(fetch_safety_session, session_id)
        if session is None:
            raise HTTPException(
                status_code=404,
                detail="This safety session no longer exists.",
            )

        alerts = await asyncio.to_thread(fetch_alerts_for_session, session_id)
        alert_ids = [str(a["id"]) for a in alerts]
        evidence_rows = await asyncio.to_thread(
            fetch_evidence_for_alert_ids, alert_ids,
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error fetching safety portal details",
            extra={"session_id": session_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    last_location = None
    last_location_at = None
    for alert in alerts:
        if alert.get("current_location"):
            last_location = SafetyLocation(**alert["current_location"])
            last_location_at = alert.get("created_at")
            break

    evidence: list[SafetyPortalEvidenceItem] = []
    for row in evidence_rows:
        download_url = await asyncio.to_thread(
            create_evidence_download_url,
            row["storage_path"],
            _EVIDENCE_URL_TTL_SECONDS,
        )
        if download_url is None:
            continue
        evidence.append(
            SafetyPortalEvidenceItem(
                id=str(row["id"]),
                content_type=row["content_type"],
                duration_seconds=row.get("duration_seconds"),
                download_url=download_url,
                media_key_base64=row["media_key_base64"],
                created_at=row["created_at"],
            ),
        )

    event_context = session.get("event_context")
    event_label = (
        cast(dict[str, Any], event_context).get("label")
        if isinstance(event_context, dict)
        else None
    )

    return SafetyPortalDetailsResponse(
        label=session.get("label"),
        event_label=event_label,
        status=session["status"],
        last_location=last_location,
        last_location_at=last_location_at,
        evidence=evidence,
    )


def _extract_bearer_token(authorization: str | None) -> str | None:
    """Extract bearer token."""
    if not authorization or not authorization.lower().startswith("bearer "):
        return None
    return authorization.split(" ", 1)[1].strip() or None


def _contact_otp_key(contact_id: str, phone_norm: str) -> str:
    """Contact otp key."""
    return f"safety_contact_portal:otp:{contact_id}:{phone_norm}"


def _contact_attempts_key(contact_id: str, phone_norm: str) -> str:
    """Contact attempts key."""
    return f"safety_contact_portal:otp_attempts:{contact_id}:{phone_norm}"


def _contact_resend_key(contact_id: str, phone_norm: str) -> str:
    """Contact resend key."""
    return f"safety_contact_portal:otp_resend:{contact_id}:{phone_norm}"


@router.post(
    "/api/v1/safety/contact/{contact_id}/otp/request",
    response_model=SafetyContactPortalOtpRequestResponse,
)
@limiter.limit(settings.rate_limit_safety_portal)
async def request_contact_portal_otp(
    request: Request,
    contact_id: str,
    payload: SafetyContactPortalOtpRequestRequest = Body(...),
) -> SafetyContactPortalOtpRequestResponse:
    _ = request
    actual_contact_id = verify_contact_portal_token(contact_id)
    if actual_contact_id is None:
        raise HTTPException(
            status_code=400,
            detail="Invalid contact token.",
        )
    contact_id = actual_contact_id
    phone_norm = normalize_phone(payload.phone)

    resend_key = _contact_resend_key(contact_id, phone_norm)
    if await redis_client.exists(resend_key):
        raise HTTPException(
            status_code=429,
            detail="Please wait a bit before requesting another code.",
        )
    await redis_client.set(resend_key, "1", ex=_OTP_RESEND_COOLDOWN_SECONDS, nx=True)

    try:
        contact = await asyncio.to_thread(fetch_safety_contact_by_id, contact_id)
    except DatabaseAccessError as err:
        logger.exception(
            "Database error looking up safety contact for portal OTP",
            extra={"contact_id": contact_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    matched = (
        contact is not None
        and normalize_phone(str(contact["phone"])) == phone_norm
    )

    if matched and phone_norm and contact is not None:
        code = generate_otp_code()
        await redis_client.setex(
            _contact_otp_key(contact_id, phone_norm),
            _OTP_TTL_SECONDS,
            hash_otp(contact_id, phone_norm, code),
        )
        safe_create_task(
            send_sms(
                str(contact["phone"]),
                f"Your Nexus verification code is {code}. It expires in "
                "10 minutes. Do not share this code.",
            ),
        )

    return SafetyContactPortalOtpRequestResponse(sent=True)


@router.post(
    "/api/v1/safety/contact/{contact_id}/otp/verify",
    response_model=SafetyContactPortalOtpVerifyResponse,
)
@limiter.limit(settings.rate_limit_safety_portal)
async def verify_contact_portal_otp(
    request: Request,
    contact_id: str,
    payload: SafetyContactPortalOtpVerifyRequest = Body(...),
) -> SafetyContactPortalOtpVerifyResponse:
    _ = request
    actual_contact_id = verify_contact_portal_token(contact_id)
    if actual_contact_id is None:
        raise HTTPException(
            status_code=400,
            detail="Invalid contact token.",
        )
    contact_id = actual_contact_id
    phone_norm = normalize_phone(payload.phone)

    attempts_key = _contact_attempts_key(contact_id, phone_norm)
    attempts = await redis_client.get(attempts_key)
    if attempts and int(attempts) >= _OTP_MAX_ATTEMPTS:
        raise HTTPException(
            status_code=429,
            detail="Too many incorrect attempts. Please request a new code.",
        )

    otp_key = _contact_otp_key(contact_id, phone_norm)
    stored_hash = await redis_client.get(otp_key)
    if not stored_hash:
        raise HTTPException(
            status_code=400,
            detail="That code has expired or was never requested. Request a new one.",
        )

    if not verify_otp_hash(contact_id, phone_norm, payload.code, cast(str, stored_hash)):
        await redis_client.incr(attempts_key)
        await redis_client.expire(attempts_key, _OTP_TTL_SECONDS)
        raise HTTPException(status_code=400, detail="Incorrect code.")

    await redis_client.delete(otp_key)
    await redis_client.delete(attempts_key)

    token = make_portal_access_token(contact_id, phone_norm)
    return SafetyContactPortalOtpVerifyResponse(token=token, expires_in=30 * 60)


@router.get(
    "/api/v1/safety/contact/{contact_id}/details",
    response_model=SafetyContactPortalDetailsResponse,
)
@limiter.limit(settings.rate_limit_safety_portal)
async def get_contact_portal_details(
    request: Request,
    contact_id: str,
    authorization: str | None = Header(default=None),
) -> SafetyContactPortalDetailsResponse:
    _ = request
    actual_contact_id = verify_contact_portal_token(contact_id)
    if actual_contact_id is None:
        raise HTTPException(
            status_code=400,
            detail="Invalid contact token.",
        )
    contact_id = actual_contact_id
    token = _extract_bearer_token(authorization)
    if token is None or verify_portal_access_token(contact_id, token) is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired portal session. Please verify again.",
        )

    try:
        contact = await asyncio.to_thread(fetch_safety_contact_by_id, contact_id)
        if contact is None:
            raise HTTPException(
                status_code=404,
                detail="This trusted contact listing no longer exists.",
            )
        profile = await asyncio.to_thread(
            fetch_contact_facing_profile_summary, str(contact["user_id"]),
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error fetching contact portal details",
            extra={"contact_id": contact_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    if profile is None:
        raise HTTPException(
            status_code=404,
            detail="This trusted contact listing no longer exists.",
        )

    return SafetyContactPortalDetailsResponse(
        user_name=str(profile.get("name") or "A Nexus user"),
        profile_pic=cast("str | None", profile.get("profile_pic")),
        hometown=cast("str | None", profile.get("hometown")),
        current_place=cast("str | None", profile.get("current_place")),
    )


async def _notify_user_of_contact_self_removal(
    user_id: str,
    contact_name: str,
) -> None:
    try:
        user_row = await asyncio.to_thread(fetch_public_user, user_id)
        profile = await asyncio.to_thread(fetch_contact_facing_profile_summary, user_id)
        email = await asyncio.to_thread(get_user_email_by_id, user_id)
    except DatabaseAccessError:
        logger.exception(
            "Failed to load context for contact self-removal notification",
            extra={"user_id": user_id},
        )
        return

    user_name = str((profile or {}).get("name") or "there")
    mobile = (user_row or {}).get("mobile") if user_row else None

    notify_tasks: list[Any] = [
        send_trusted_contact_removed_notification(user_id, contact_name),
    ]
    if mobile:
        notify_tasks.append(
            send_sms(
                str(mobile),
                compose_contact_self_removed_message(contact_name=contact_name),
            ),
        )
    if email:
        notify_tasks.append(
            send_trusted_contact_removed_email(email, user_name, contact_name),
        )
    await asyncio.gather(*notify_tasks, return_exceptions=True)


@router.post(
    "/api/v1/safety/contact/{contact_id}/remove",
    response_model=SafetyContactPortalRemoveResponse,
)
@limiter.limit(settings.rate_limit_safety_portal)
async def remove_trusted_contact(
    request: Request,
    contact_id: str,
    authorization: str | None = Header(default=None),
) -> SafetyContactPortalRemoveResponse:
    _ = request
    actual_contact_id = verify_contact_portal_token(contact_id)
    if actual_contact_id is None:
        raise HTTPException(
            status_code=400,
            detail="Invalid contact token.",
        )
    contact_id = actual_contact_id
    token = _extract_bearer_token(authorization)
    if token is None or verify_portal_access_token(contact_id, token) is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired portal session. Please verify again.",
        )

    try:
        removed = await asyncio.to_thread(
            remove_safety_contact_self_service, contact_id,
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error removing trusted contact",
            extra={"contact_id": contact_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    if removed is not None:
        safe_create_task(
            _notify_user_of_contact_self_removal(
                str(removed["user_id"]), str(removed["name"]),
            ),
        )

    return SafetyContactPortalRemoveResponse(removed=True)


@router.get("/api/v1/safety/portal/{session_id}")
@limiter.limit(settings.rate_limit_safety_portal)
async def portal_page(request: Request, session_id: str) -> HTMLResponse:
    """Serves the (static, session-id-agnostic) portal shell."""
    _ = request
    _ = session_id
    return HTMLResponse(_PORTAL_PAGE_HTML)


@router.get("/api/v1/safety/contact/{contact_id}")
@limiter.limit(settings.rate_limit_safety_portal)
async def contact_portal_page(request: Request, contact_id: str) -> HTMLResponse:
    """Serves the (static, contact-id-agnostic) self-removal portal shell."""
    _ = request
    actual_contact_id = verify_contact_portal_token(contact_id)
    if actual_contact_id is None:
        raise HTTPException(
            status_code=400,
            detail="Invalid contact token.",
        )
    return HTMLResponse(_CONTACT_PORTAL_PAGE_HTML)
