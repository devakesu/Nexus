"""FastAPI router for trusted contact portal authentication, alert viewing, and self-service opt-out.

Exposes web and API endpoints for non-user trusted contacts to authenticate via phone OTP,
view active safety alerts, inspect location history/audio evidence, and remove themselves as contacts.
"""

import asyncio
import logging
from typing import Any, cast

from fastapi import APIRouter, Body, Header, HTTPException, Request
from fastapi.responses import HTMLResponse

from app.core.cache import redis_client
from app.core.config import settings
from app.core.email import send_trusted_contact_removed_email
from app.core.limiter import limiter
from app.core.portal_auth import (
    generate_otp_code,
    hash_otp,
    make_portal_access_token,
    normalize_phone,
    verify_otp_hash,
    verify_portal_access_token,
)
from app.core.sms import compose_contact_self_removed_message, send_sms
from app.core.tasks import safe_create_task
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

# Trusted contacts have no Nexus account, so every endpoint below is reached
# straight from an SMS link with no App Check token or bearer auth available
# - unlike every other router in this backend. Rate limiting (by IP, since
# there's no user to key on) and the OTP-attempt/resend caps below are the
# actual security boundary here, not the usual auth dependency stack.

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
    """Dispatches phone OTP to a trusted contact attempting portal login.

        Args:
            request: FastAPI HTTP request object.
            payload: Portal OTP request model containing phone number.

        Returns:
            dict[str, bool]: Delivery success status."""
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
        # Not awaited: awaiting the Twilio round-trip here would make a
        # match take measurably longer than a non-match, undermining the
        # anti-enumeration goal above (the response should look the same
        # either way, not just say the same thing).
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
    """Verifies trusted contact phone OTP and issues a portal access token.

        Args:
            request: FastAPI HTTP request object.
            payload: Portal OTP verification model.

        Returns:
            dict[str, str]: Portal access JWT token string."""
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

    # redis_client is configured with decode_responses=True (app/core/cache.py),
    # so this is always str at runtime - redis-py's stubs just don't narrow that.
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
    """Executes get portal details operation.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            session_id: Input session id parameter.
            authorization: Bearer HTTP authorization header string containing Supabase JWT.

        Returns:
            SafetyPortalDetailsResponse: Response payload or result."""
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
                # SECURITY NOTE: Storing and returning media_key_base64 here escrows the per-file
                # AES-GCM key server-side in plaintext. This allows trusted contacts to decrypt
                # without the app, but deviates from a pure E2E posture as DB compromises, service-role
                # access, or portal auth bugs can expose the media keys.
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
    """Extract bearer token.

        Args:
            authorization: Bearer HTTP authorization header string containing Supabase JWT.

        Returns:
            str | None: Response payload or result."""
    if not authorization or not authorization.lower().startswith("bearer "):
        return None
    return authorization.split(" ", 1)[1].strip() or None


# ---------------------------------------------------------------------------
# Trusted-contact self-removal portal
#
# Reached from the one-time "you were added" notice SMS (app/api/safety.py,
# app/core/sms.py::compose_contact_added_message), not from an active SOS
# session - so this is scoped by contact_id (a safety_contacts row), not
# session_id, but otherwise follows the exact same "OTP + rate limiting is
# the real boundary, no account, no App Check" posture as the section
# above. Distinct Redis key/rate-limit namespace so the two flows can never
# collide even though both ultimately key off a UUID string.
# ---------------------------------------------------------------------------


def _contact_otp_key(contact_id: str, phone_norm: str) -> str:
    """Contact otp key.

        Args:
            contact_id: Input contact id parameter.
            phone_norm: Input phone norm parameter.

        Returns:
            str: Response payload or result."""
    return f"safety_contact_portal:otp:{contact_id}:{phone_norm}"


def _contact_attempts_key(contact_id: str, phone_norm: str) -> str:
    """Contact attempts key.

        Args:
            contact_id: Input contact id parameter.
            phone_norm: Input phone norm parameter.

        Returns:
            str: Response payload or result."""
    return f"safety_contact_portal:otp_attempts:{contact_id}:{phone_norm}"


def _contact_resend_key(contact_id: str, phone_norm: str) -> str:
    """Contact resend key.

        Args:
            contact_id: Input contact id parameter.
            phone_norm: Input phone norm parameter.

        Returns:
            str: Response payload or result."""
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
    """Sends a 6-digit OTP only if the phone matches this specific contact
    row - always responds the same way either way (anti-enumeration, same
    principle as request_portal_otp above).
    """
    _ = request
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
    """Executes verify contact portal otp operation.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            contact_id: Input contact id parameter.
            payload: Validated request body model containing parameters.

        Returns:
            SafetyContactPortalOtpVerifyResponse: Response payload or result."""
    _ = request
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
    """Executes get contact portal details operation.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            contact_id: Input contact id parameter.
            authorization: Bearer HTTP authorization header string containing Supabase JWT.

        Returns:
            SafetyContactPortalDetailsResponse: Response payload or result."""
    _ = request
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
    """Fire-and-forget: tells the original Nexus user across all three
    channels (push, SMS, email) that a trusted contact removed themselves -
    a single missed channel (e.g. notifications off) shouldn't mean they
    never find out their Meetup Safety coverage just changed.
    """
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
    """A trusted contact removing themselves at their own request. Permanent
    - see remove_safety_contact_self_service, which also blocks the same
    phone number from being silently re-added on a future sync.
    """
    _ = request
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

    # Idempotent by design: a contact re-opening/re-submitting an already-
    # used remove action still gets a success response - the state they
    # wanted (not listed) is true either way.
    return SafetyContactPortalRemoveResponse(removed=True)


@router.get("/api/v1/safety/portal/{session_id}")
@limiter.limit(settings.rate_limit_safety_portal)
async def portal_page(request: Request, session_id: str) -> HTMLResponse:
    """Serves the (static, session-id-agnostic) portal shell - all real
    session-scoped logic happens client-side against the JSON endpoints
    above, so this never touches the database.
    """
    _ = request
    _ = session_id
    return HTMLResponse(_PORTAL_PAGE_HTML)


_PORTAL_PAGE_HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nexus Meetup Safety</title>
<style>
  :root {
    --safety-blue: #0284C7;
    --safety-teal: #0D9488;
  }
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: #0F172A;
    color: #F1F5F9;
    margin: 0;
    min-height: 100vh;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: 32px 16px;
  }
  .card {
    width: 100%;
    max-width: 440px;
    background: rgba(255,255,255,0.04);
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 16px;
    padding: 28px 24px;
  }
  h1 {
    font-size: 20px;
    margin: 0 0 4px;
    background: linear-gradient(90deg, var(--safety-blue), var(--safety-teal));
    -webkit-background-clip: text;
    background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .subtitle { color: #94A3B8; font-size: 14px; margin: 0 0 24px; }
  label { display: block; font-size: 13px; color: #CBD5E1; margin-bottom: 6px; }
  input {
    width: 100%;
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 10px;
    padding: 12px 14px;
    color: #F1F5F9;
    font-size: 16px;
    margin-bottom: 12px;
  }
  input:focus {
    outline: none;
    border-color: var(--safety-teal);
    box-shadow: 0 0 0 3px rgba(13,148,136,0.25);
  }
  button {
    width: 100%;
    border: none;
    border-radius: 10px;
    padding: 13px 14px;
    font-size: 15px;
    font-weight: 600;
    color: white;
    background: linear-gradient(90deg, var(--safety-blue), var(--safety-teal));
    cursor: pointer;
  }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
  .link-btn {
    background: none;
    color: #94A3B8;
    font-weight: 400;
    font-size: 13px;
    width: auto;
    padding: 8px 0;
  }
  .error { color: #F87171; font-size: 13px; margin: -4px 0 12px; min-height: 16px; }
  .step { display: none; }
  .step.active { display: block; }
  .pill {
    display: inline-block;
    font-size: 12px;
    font-weight: 600;
    padding: 3px 10px;
    border-radius: 999px;
    background: rgba(13,148,136,0.18);
    color: #5EEAD4;
    margin-bottom: 16px;
  }
  .detail-row { margin-bottom: 16px; }
  .detail-row .label { font-size: 12px; color: #94A3B8; margin-bottom: 2px; }
  .detail-row .value { font-size: 15px; }
  .detail-row a { color: #5EEAD4; }
  .evidence-item {
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 10px;
    padding: 14px;
    margin-bottom: 10px;
  }
  .evidence-item .meta { font-size: 12px; color: #94A3B8; margin-bottom: 8px; }
  video, audio { width: 100%; border-radius: 8px; }
</style>
</head>
<body>
  <div class="card">
    <h1>Nexus Meetup Safety</h1>
    <p class="subtitle" id="subtitle">
      Someone listed you as a trusted contact. Verify your phone number to
      see their check-in details.
    </p>

    <div class="step active" id="step-phone">
      <label for="phone-input">Your phone number</label>
      <input id="phone-input" type="tel" placeholder="+91 98765 43210" autocomplete="tel">
      <div class="error" id="phone-error"></div>
      <button id="send-code-btn">Send code</button>
    </div>

    <div class="step" id="step-otp">
      <label for="otp-input">6-digit code</label>
      <input id="otp-input" type="tel" inputmode="numeric" maxlength="6" placeholder="000000">
      <div class="error" id="otp-error"></div>
      <button id="verify-code-btn">Verify</button>
      <button class="link-btn" id="resend-btn">Resend code</button>
    </div>

    <div class="step" id="step-details">
      <div id="details-content"></div>
    </div>
  </div>

<script>
(function () {
  var sessionId = window.location.pathname.split('/').filter(Boolean).pop();
  var apiBase = '/api/v1/safety/portal/' + sessionId;
  var phone = '';
  var portalToken = '';

  function show(stepId) {
    document.querySelectorAll('.step').forEach(function (el) {
      el.classList.toggle('active', el.id === stepId);
    });
  }

  function setError(elId, message) {
    document.getElementById(elId).textContent = message || '';
  }

  function bytesToBase64(bytes) {
    var bin = '';
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    return btoa(bin);
  }

  function base64ToBytes(b64) {
    var bin = atob(b64);
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
  }

  document.getElementById('send-code-btn').addEventListener('click', function () {
    phone = document.getElementById('phone-input').value.trim();
    setError('phone-error', '');
    if (phone.length < 6) {
      setError('phone-error', 'Enter a valid phone number.');
      return;
    }
    this.disabled = true;
    var btn = this;
    fetch(apiBase + '/otp/request', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Failed to send code.'); });
        show('step-otp');
      })
      .catch(function (e) { setError('phone-error', e.message); })
      .finally(function () { btn.disabled = false; });
  });

  document.getElementById('resend-btn').addEventListener('click', function () {
    setError('otp-error', '');
    fetch(apiBase + '/otp/request', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Could not resend code.'); });
        setError('otp-error', 'A new code was sent.');
      })
      .catch(function (e) { setError('otp-error', e.message); });
  });

  document.getElementById('verify-code-btn').addEventListener('click', function () {
    var code = document.getElementById('otp-input').value.trim();
    setError('otp-error', '');
    if (code.length < 4) {
      setError('otp-error', 'Enter the code you were texted.');
      return;
    }
    this.disabled = true;
    var btn = this;
    fetch(apiBase + '/otp/verify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone, code: code }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Verification failed.'); });
        return res.json();
      })
      .then(function (data) {
        portalToken = data.token;
        return loadDetails();
      })
      .catch(function (e) { setError('otp-error', e.message); })
      .finally(function () { btn.disabled = false; });
  });

  function loadDetails() {
    return fetch(apiBase + '/details', {
      headers: { 'Authorization': 'Bearer ' + portalToken },
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Could not load details.'); });
        return res.json();
      })
      .then(renderDetails);
  }

  function renderDetails(data) {
    var html = '';
    html += '<span class="pill">' + (data.status === 'active' ? 'Check-in active' : 'Check-in ended') + '</span>';
    html += '<div class="detail-row"><div class="label">Meetup</div><div class="value">' +
      escapeHtml(data.event_label || data.label || 'Not specified') + '</div></div>';
    if (data.last_location) {
      var mapsUrl = 'https://maps.google.com/?q=' + data.last_location.lat + ',' + data.last_location.lng;
      html += '<div class="detail-row"><div class="label">Last known location</div><div class="value">' +
        '<a href="' + mapsUrl + '" target="_blank" rel="noopener">Open in Maps</a></div></div>';
    } else {
      html += '<div class="detail-row"><div class="label">Last known location</div><div class="value">Not reported</div></div>';
    }

    if (data.evidence && data.evidence.length) {
      html += '<div class="detail-row"><div class="label">Evidence (' + data.evidence.length + ')</div></div>';
    }
    document.getElementById('details-content').innerHTML = html;

    (data.evidence || []).forEach(function (item, idx) {
      var wrap = document.createElement('div');
      wrap.className = 'evidence-item';
      var meta = document.createElement('div');
      meta.className = 'meta';
      meta.textContent = (item.content_type === 'video' ? 'Video' : 'Audio') +
        (item.duration_seconds ? ' · ' + Math.round(item.duration_seconds) + 's' : '');
      var btn = document.createElement('button');
      btn.textContent = 'Decrypt & play';
      btn.addEventListener('click', function () { decryptAndPlay(item, wrap, btn); });
      wrap.appendChild(meta);
      wrap.appendChild(btn);
      document.getElementById('details-content').appendChild(wrap);
    });

    show('step-details');
  }

  function escapeHtml(s) {
    var div = document.createElement('div');
    div.textContent = s;
    return div.innerHTML;
  }

  function decryptAndPlay(item, container, button) {
    button.disabled = true;
    button.textContent = 'Decrypting...';
    fetch(item.download_url)
      .then(function (res) { return res.arrayBuffer(); })
      .then(function (buf) {
        var bytes = new Uint8Array(buf);
        var nonce = bytes.slice(0, 12);
        var ciphertextAndTag = bytes.slice(12);
        return crypto.subtle.importKey('raw', base64ToBytes(item.media_key_base64), 'AES-GCM', false, ['decrypt'])
          .then(function (key) {
            return crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, key, ciphertextAndTag);
          });
      })
      .then(function (plaintext) {
        var mime = item.content_type === 'video' ? 'video/mp4' : 'audio/mp4';
        var blob = new Blob([plaintext], { type: mime });
        var url = URL.createObjectURL(blob);
        var el = document.createElement(item.content_type === 'video' ? 'video' : 'audio');
        el.src = url;
        el.controls = true;
        button.remove();
        container.appendChild(el);
      })
      .catch(function () {
        button.disabled = false;
        button.textContent = 'Failed to decrypt - try again';
      });
  }
})();
</script>
</body>
</html>"""


@router.get("/api/v1/safety/contact/{contact_id}")
@limiter.limit(settings.rate_limit_safety_portal)
async def contact_portal_page(request: Request, contact_id: str) -> HTMLResponse:
    """Serves the (static, contact-id-agnostic) self-removal portal shell -
    all real contact-scoped logic happens client-side against the JSON
    endpoints above, so this never touches the database, same as
    portal_page above.
    """
    _ = request
    _ = contact_id
    return HTMLResponse(_CONTACT_PORTAL_PAGE_HTML)


_CONTACT_PORTAL_PAGE_HTML = r"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nexus Meetup Safety</title>
<style>
  :root {
    --safety-blue: #0284C7;
    --safety-teal: #0D9488;
    --safety-red: #DC2626;
  }
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: #0F172A;
    color: #F1F5F9;
    margin: 0;
    min-height: 100vh;
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: 32px 16px;
  }
  .card {
    width: 100%;
    max-width: 440px;
    background: rgba(255,255,255,0.04);
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 16px;
    padding: 28px 24px;
  }
  h1 {
    font-size: 20px;
    margin: 0 0 4px;
    background: linear-gradient(90deg, var(--safety-blue), var(--safety-teal));
    -webkit-background-clip: text;
    background-clip: text;
    -webkit-text-fill-color: transparent;
  }
  .subtitle { color: #94A3B8; font-size: 14px; margin: 0 0 24px; }
  label { display: block; font-size: 13px; color: #CBD5E1; margin-bottom: 6px; }
  input {
    width: 100%;
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 10px;
    padding: 12px 14px;
    color: #F1F5F9;
    font-size: 16px;
    margin-bottom: 12px;
  }
  input:focus {
    outline: none;
    border-color: var(--safety-teal);
    box-shadow: 0 0 0 3px rgba(13,148,136,0.25);
  }
  button {
    width: 100%;
    border: none;
    border-radius: 10px;
    padding: 13px 14px;
    font-size: 15px;
    font-weight: 600;
    color: white;
    background: linear-gradient(90deg, var(--safety-blue), var(--safety-teal));
    cursor: pointer;
  }
  button.danger { background: var(--safety-red); }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
  .link-btn {
    background: none;
    color: #94A3B8;
    font-weight: 400;
    font-size: 13px;
    width: auto;
    padding: 8px 0;
  }
  .error { color: #F87171; font-size: 13px; margin: -4px 0 12px; min-height: 16px; }
  .step { display: none; }
  .step.active { display: block; }
  .avatar {
    width: 72px; height: 72px; border-radius: 50%; object-fit: cover;
    display: block; margin: 0 auto 16px; border: 2px solid rgba(255,255,255,0.12);
  }
  .detail-row { margin-bottom: 16px; text-align: center; }
  .detail-row .label { font-size: 12px; color: #94A3B8; margin-bottom: 2px; }
  .detail-row .value { font-size: 16px; font-weight: 600; }
  .fine-print { font-size: 12px; color: #64748B; line-height: 1.5; margin: 16px 0; }
</style>
</head>
<body>
  <div class="card">
    <h1>Nexus Meetup Safety</h1>
    <p class="subtitle" id="subtitle">
      Someone listed you as a trusted contact. Verify your phone number to
      manage this.
    </p>

    <div class="step active" id="step-phone">
      <label for="phone-input">Your phone number</label>
      <input id="phone-input" type="tel" placeholder="+91 98765 43210" autocomplete="tel">
      <div class="error" id="phone-error"></div>
      <button id="send-code-btn">Send code</button>
    </div>

    <div class="step" id="step-otp">
      <label for="otp-input">6-digit code</label>
      <input id="otp-input" type="tel" inputmode="numeric" maxlength="6" placeholder="000000">
      <div class="error" id="otp-error"></div>
      <button id="verify-code-btn">Verify</button>
      <button class="link-btn" id="resend-btn">Resend code</button>
    </div>

    <div class="step" id="step-details">
      <div id="details-content"></div>
      <button class="danger" id="remove-btn">Remove me as a trusted contact</button>
      <p class="fine-print">
        This stops all future check-in and SOS texts from Nexus on this
        person's behalf, and can't be undone from here.
      </p>
    </div>

    <div class="step" id="step-removed">
      <p style="text-align:center; color: #5EEAD4;">
        You've been removed. You won't receive any more messages from
        Nexus about this person.
      </p>
    </div>
  </div>

<script>
(function () {
  var contactId = window.location.pathname.split('/').filter(Boolean).pop();
  var apiBase = '/api/v1/safety/contact/' + contactId;
  var phone = '';
  var portalToken = '';

  function show(stepId) {
    document.querySelectorAll('.step').forEach(function (el) {
      el.classList.toggle('active', el.id === stepId);
    });
  }

  function setError(elId, message) {
    document.getElementById(elId).textContent = message || '';
  }

  function escapeHtml(s) {
    var div = document.createElement('div');
    div.textContent = s;
    return div.innerHTML;
  }

  document.getElementById('send-code-btn').addEventListener('click', function () {
    phone = document.getElementById('phone-input').value.trim();
    setError('phone-error', '');
    if (phone.length < 6) {
      setError('phone-error', 'Enter a valid phone number.');
      return;
    }
    this.disabled = true;
    var btn = this;
    fetch(apiBase + '/otp/request', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Failed to send code.'); });
        show('step-otp');
      })
      .catch(function (e) { setError('phone-error', e.message); })
      .finally(function () { btn.disabled = false; });
  });

  document.getElementById('resend-btn').addEventListener('click', function () {
    setError('otp-error', '');
    fetch(apiBase + '/otp/request', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Could not resend code.'); });
        setError('otp-error', 'A new code was sent.');
      })
      .catch(function (e) { setError('otp-error', e.message); });
  });

  document.getElementById('verify-code-btn').addEventListener('click', function () {
    var code = document.getElementById('otp-input').value.trim();
    setError('otp-error', '');
    if (code.length < 4) {
      setError('otp-error', 'Enter the code you were texted.');
      return;
    }
    this.disabled = true;
    var btn = this;
    fetch(apiBase + '/otp/verify', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone: phone, code: code }),
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Verification failed.'); });
        return res.json();
      })
      .then(function (data) {
        portalToken = data.token;
        return loadDetails();
      })
      .catch(function (e) { setError('otp-error', e.message); })
      .finally(function () { btn.disabled = false; });
  });

  function loadDetails() {
    return fetch(apiBase + '/details', {
      headers: { 'Authorization': 'Bearer ' + portalToken },
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Could not load details.'); });
        return res.json();
      })
      .then(renderDetails);
  }

  function renderDetails(data) {
    var html = '';
    if (data.profile_pic) {
      html += '<img class="avatar" src="' + data.profile_pic + '" alt="">';
    }
    html += '<div class="detail-row"><div class="label">Listed you as their trusted contact</div><div class="value">' +
      escapeHtml(data.user_name) + '</div></div>';
    if (data.hometown || data.current_place) {
      html += '<div class="detail-row"><div class="label">From / based in</div><div class="value">' +
        escapeHtml([data.hometown, data.current_place].filter(Boolean).join(' · ')) + '</div></div>';
    }
    document.getElementById('details-content').innerHTML = html;
    show('step-details');
  }

  document.getElementById('remove-btn').addEventListener('click', function () {
    this.disabled = true;
    var btn = this;
    fetch(apiBase + '/remove', {
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + portalToken },
    })
      .then(function (res) {
        if (!res.ok) return res.json().then(function (b) { throw new Error(b.detail || 'Could not remove you.'); });
        show('step-removed');
      })
      .catch(function () {
        btn.disabled = false;
      });
  });
})();
</script>
</body>
</html>"""
