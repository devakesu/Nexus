"""FastAPI router for Meetup Safety, trusted contacts, emergency SOS, and evidence upload.

Handles user endpoints for managing trusted contact lists, creating safety check-ins,
triggering emergency SOS alerts (silent/loud), and uploading safety audio evidence.
"""

import asyncio
import html
import json
import logging
from typing import Any

import sentry_sdk
from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request
from fastapi.responses import HTMLResponse

from app.api.dependencies import (
    require_safety_consent,
    verify_app_check_with_replay_protection,
)
from app.core.config import settings
from app.core.infra.cache import redis_client
from app.core.infra.limiter import limiter
from app.core.infra.tasks import safe_create_task
from app.core.security.portal_auth import normalize_phone
from app.core.utils.sms import (
    compose_contact_added_message,
    compose_inform_message,
    compose_sos_message,
    make_contact_portal_token,
    sanitize_sms_text,
    send_sms,
    verify_escalation_cancel_token,
)
from app.db.client import DatabaseAccessError, utcnow
from app.db.safety import (
    EscalationInProgressError,
    cancel_safety_escalation,
    end_safety_session,
    fetch_contact_facing_profile_summary,
    fetch_safety_alert,
    fetch_safety_contacts,
    fetch_safety_contacts_with_id,
    fetch_safety_session,
    heartbeat_safety_session,
    record_safety_alert,
    register_safety_evidence,
    start_safety_session,
    sync_safety_contacts,
    update_alert_contacts_notified,
)
from app.models import (
    SafetyAlertRequest,
    SafetyAlertResponse,
    SafetyContactsSyncRequest,
    SafetyContactsSyncResponse,
    SafetyEvidenceRegisterRequest,
    SafetyEvidenceRegisterResponse,
    SafetySessionCheckinRequest,
    SafetySessionEndRequest,
    SafetySessionStartRequest,
    SafetySessionStartResponse,
)

router = APIRouter()
logger = logging.getLogger(__name__)


async def _notify_newly_added_contacts(
    user_id: str,
    newly_notified: list[dict[str, str]],
) -> None:
    """Fire-and-forget: sends the one-time "you were added" notice SMS
    (with the self-removal portal link) to each phone number seen for the
    first time in this sync. Runs after the sync itself so a slow/failed
    SMS never blocks the response.
    """
    if not newly_notified:
        return
    try:
        profile = await asyncio.to_thread(fetch_contact_facing_profile_summary, user_id)
        contacts = await asyncio.to_thread(fetch_safety_contacts_with_id, user_id)
    except DatabaseAccessError:
        logger.exception(
            "Failed to load context for trusted contact notice SMS",
            extra={"user_id": user_id},
        )
        return

    user_name = (profile or {}).get("name") or "A Nexus user"

    by_phone = {normalize_phone(str(c["phone"])): c for c in contacts}
    for n in newly_notified:
        contact = by_phone.get(normalize_phone(str(n.get("phone") or "")))
        if contact is None:
            continue
        manage_link = (
            f"{settings.backend_url}/api/v1/safety/contact/{make_contact_portal_token(contact['id'])}"
        )
        body = compose_contact_added_message(
            user_name=str(user_name), manage_link=manage_link,
        )
        await send_sms(str(n.get("phone") or ""), body)


@router.put("/api/v1/safety/contacts", response_model=SafetyContactsSyncResponse)
@limiter.limit(settings.rate_limit_safety)
async def put_safety_contacts(
    request: Request,
    payload: SafetyContactsSyncRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(require_safety_consent),
) -> SafetyContactsSyncResponse:
    """Updates the caller's trusted contact list for Meetup Safety monitoring."""
    _ = request
    try:
        blocked, newly_notified = await asyncio.to_thread(
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

    safe_create_task(_notify_newly_added_contacts(user_id, newly_notified))

    return SafetyContactsSyncResponse(
        count=len(payload.contacts) - len(blocked),
        blocked=[str(c.get("name") or "") for c in blocked],
    )


async def _check_cached_sos_alert(
    idempotency_key: str,
    user_id: str,
    session_id: str | None,
) -> SafetyAlertResponse | None:
    try:
        cached_val = await redis_client.get(idempotency_key)
        if cached_val:
            try:
                cached_data = json.loads(cached_val)
                logger.info(
                    "Skipping duplicate safety alert: already sent in last 60s",
                    extra={"user_id": user_id, "session_id": session_id},
                )
                return SafetyAlertResponse(
                    id=cached_data["id"],
                    contacts_notified=cached_data["contacts_notified"],
                    contacts_total=cached_data["contacts_total"],
                )
            except (json.JSONDecodeError, KeyError, TypeError, ValueError) as parse_err:
                logger.debug("Failed to parse cached SOS idempotency: %s", parse_err)
    except Exception as err:
        logger.warning("Failed to check SOS idempotency in Redis", exc_info=err)
    return None


async def _send_alert_sms_to_contacts(
    contacts: list[dict[str, Any]],
    body: str,
    user_id: str,
    alert_type: str,
) -> int:
    notified = 0
    for contact in contacts:
        result = await send_sms(contact["phone"], body)
        if result.success:
            notified += 1
        else:
            logger.warning(
                "Failed to notify a trusted contact",
                extra={"user_id": user_id, "alert_type": alert_type},
            )
    return notified


async def _record_safety_alert_response(
    user_id: str,
    payload: SafetyAlertRequest,
    location: dict[str, Any] | None,
    notified: int,
    contacts_total: int,
) -> SafetyAlertResponse:
    try:
        row = await asyncio.to_thread(
            record_safety_alert,
            user_id,
            payload.alert_type,
            location,
            payload.session_id,
        )
        await asyncio.to_thread(
            update_alert_contacts_notified,
            str(row["id"]),
            notified,
        )
        return SafetyAlertResponse(
            id=str(row["id"]),
            contacts_notified=notified,
            contacts_total=contacts_total,
        )
    except DatabaseAccessError as err:
        sentry_sdk.capture_exception(err)
        logger.exception(
            "Database error recording safety alert after SMS delivery",
            extra={"user_id": user_id, "alert_type": payload.alert_type, "notified": notified},
        )
        if notified > 0:
            import uuid
            return SafetyAlertResponse(
                id=f"temp-{uuid.uuid4()}",
                contacts_notified=notified,
                contacts_total=contacts_total,
            )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err


async def _cache_sos_alert(idempotency_key: str, response: SafetyAlertResponse) -> None:
    try:
        await redis_client.set(
            idempotency_key,
            json.dumps({
                "id": response.id,
                "contacts_notified": response.contacts_notified,
                "contacts_total": response.contacts_total,
            }),
            ex=60,
        )
    except Exception as err:
        logger.warning("Failed to set SOS idempotency in Redis", exc_info=err)


@router.post("/api/v1/safety/alert", response_model=SafetyAlertResponse)
@limiter.limit(settings.rate_limit_safety)
async def send_safety_alert(
    request: Request,
    payload: SafetyAlertRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(require_safety_consent),
) -> SafetyAlertResponse:
    """Composes and sends the SOS/inform SMS to every trusted contact on
    file, then logs the alert (and how many contacts were actually reached)
    for audit purposes. Notifying remaining contacts continues even if one
    send fails - a partial alert is far better than none.
    """
    _ = request

    idempotency_key = f"safety:sos:idempotency:{user_id}:{payload.session_id or 'none'}"
    cached_response = await _check_cached_sos_alert(idempotency_key, user_id, payload.session_id)
    if cached_response is not None:
        return cached_response

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

    display_name = sanitize_sms_text(payload.session_label, max_length=50) or "A Nexus user"
    clean_event_label = sanitize_sms_text(payload.event_label, max_length=100)
    location = (
        payload.current_location.model_dump()
        if payload.current_location is not None
        else None
    )

    if payload.alert_type == "inform":
        body = compose_inform_message(
            name=display_name,
            location=location,
            event_label=clean_event_label,
        )
    else:
        body = compose_sos_message(
            name=display_name,
            silent=payload.alert_type == "sos_silent",
            location=location,
            event_label=clean_event_label,
        )

    notified = await _send_alert_sms_to_contacts(contacts, body, user_id, payload.alert_type)
    response = await _record_safety_alert_response(user_id, payload, location, notified, len(contacts))
    await _cache_sos_alert(idempotency_key, response)
    return response


@router.post(
    "/api/v1/safety/evidence",
    response_model=SafetyEvidenceRegisterResponse,
)
@limiter.limit(settings.rate_limit_safety)
async def register_evidence(
    request: Request,
    payload: SafetyEvidenceRegisterRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(require_safety_consent),
) -> SafetyEvidenceRegisterResponse:
    """Registers a Digital Witness (Silent SOS) evidence segment already
    uploaded (as ciphertext) to the safety_evidence storage bucket. The
    decryption key is escrowed here for a future OTP-authenticated
    trusted-contact portal - see the safety_evidence table comment.
    """
    _ = request

    own_prefix = f"{user_id}/"
    if not payload.storage_path.startswith(own_prefix) or ".." in payload.storage_path:
        raise HTTPException(
            status_code=422,
            detail="storage_path may only reference your own uploads.",
        )

    try:
        alert = await asyncio.to_thread(fetch_safety_alert, payload.alert_id)
    except DatabaseAccessError as err:
        logger.exception(
            "Database error looking up safety alert for evidence registration",
            extra={"user_id": user_id, "alert_id": payload.alert_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err
    if alert is None or str(alert.get("user_id")) != user_id:
        raise HTTPException(
            status_code=404,
            detail="No matching alert found for this account.",
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


@router.post(
    "/api/v1/safety/session/start",
    response_model=SafetySessionStartResponse,
)
@limiter.limit(settings.rate_limit_safety)
async def start_session(
    request: Request,
    payload: SafetySessionStartRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(require_safety_consent),
) -> SafetySessionStartResponse:
    """Mirrors a freshly-started check-in loop server-side so the dead-man's
    -switch scheduler has something to poll. The event label (if any) is
    stashed in event_context so an escalation SMS sent hours later can still
    say which meetup this was.
    """
    _ = request

    event_context = {"label": payload.event_label} if payload.event_label else None

    if payload.next_checkin_at <= utcnow():
        raise HTTPException(
            status_code=400,
            detail="next_checkin_at must be in the future.",
        )

    try:
        row = await asyncio.to_thread(
            start_safety_session,
            user_id,
            payload.label,
            payload.interval_seconds,
            payload.next_checkin_at.isoformat(),
            event_context,
            payload.battery_percent,
            payload.connection_type,
        )
    except EscalationInProgressError as err:
        raise HTTPException(
            status_code=400,
            detail="Cannot start a new safety session while an active session is currently escalating.",
        ) from err
    except DatabaseAccessError as err:
        logger.exception(
            "Database error starting safety session",
            extra={"user_id": user_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    return SafetySessionStartResponse(id=str(row["id"]))


@router.post("/api/v1/safety/session/checkin")
@limiter.limit(settings.rate_limit_safety)
async def checkin_session(
    request: Request,
    payload: SafetySessionCheckinRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(require_safety_consent),
) -> dict[str, bool]:
    """A successful "I'm Safe" check-in - proves the device is fine and
    resets the escalation counter, exactly like the local exact-alarm
    reschedule this mirrors.
    """
    _ = request

    if payload.next_checkin_at <= utcnow():
        raise HTTPException(
            status_code=400,
            detail="next_checkin_at must be in the future.",
        )

    try:
        row = await asyncio.to_thread(
            heartbeat_safety_session,
            user_id,
            payload.session_id,
            payload.next_checkin_at.isoformat(),
            payload.battery_percent,
            payload.connection_type,
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error checking in safety session",
            extra={"user_id": user_id, "session_id": payload.session_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    if row is None:
        raise HTTPException(
            status_code=404,
            detail="No active safety session with that id.",
        )
    return {"ok": True}


@router.post("/api/v1/safety/session/end")
@limiter.limit(settings.rate_limit_safety)
async def end_session(
    request: Request,
    payload: SafetySessionEndRequest = Body(...),
    _device: None = Depends(verify_app_check_with_replay_protection),
    user_id: str = Depends(require_safety_consent),
) -> dict[str, bool]:
    """Concludes an active Meetup Safety check-in monitoring session.

        Args:
            request: FastAPI HTTP request object used for rate limiting and connection state.
            payload: Validated request body model containing parameters.
            _device: App Check attestation token dependency guard.
            user_id: Unique UUID string of the authenticated user.

        Returns:
            dict[str, bool]: Response payload or result."""
    _ = request
    try:
        await asyncio.to_thread(end_safety_session, user_id, payload.session_id)
    except DatabaseAccessError as err:
        logger.exception(
            "Database error ending safety session",
            extra={"user_id": user_id, "session_id": payload.session_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err
    return {"ok": True}


@router.get("/api/v1/safety/escalation/{session_id}/cancel")
@limiter.limit(settings.rate_limit_safety)
async def cancel_escalation(
    request: Request,
    session_id: str,
    token: str = Query(...),
    reason: str = Query(...),
    note: str | None = Query(default=None, max_length=500),
) -> HTMLResponse:
    """Lets a trusted contact stop further "device unreachable" alerts from
    a plain link in the SMS - they have no Nexus account, so a signed token
    in the URL stands in for auth instead of the usual dependency stack.
    """
    _ = request
    if reason not in ("safe", "other"):
        return HTMLResponse(
            _escalation_page("That link looks malformed."),
            status_code=400,
        )

    token_escalation_num = verify_escalation_cancel_token(session_id, token)
    if token_escalation_num is None:
        return HTMLResponse(
            _escalation_page("That link is invalid or has expired."),
            status_code=403,
        )

    try:
        session = await asyncio.to_thread(fetch_safety_session, session_id)
        if session is None:
            return HTMLResponse(
                _escalation_page("This safety session no longer exists."),
                status_code=404,
            )

        # Pause the current burst only, if it is already cancelled, acknowledge it
        if session.get("escalation_cancelled_at") is not None:
            return HTMLResponse(
                _escalation_page("This safety alert has already been cancelled."),
                status_code=200,
            )

        # Only allow cancellation if it matches the current active escalation attempt
        if int(session.get("escalations_sent") or 0) != token_escalation_num:
            return HTMLResponse(
                _escalation_page("That link is no longer valid for this safety alert."),
                status_code=400,
            )

        user_id = session.get("user_id")
        if not user_id:
            return HTMLResponse(
                _escalation_page("This safety session no longer exists."),
                status_code=404,
            )

        await asyncio.to_thread(
            cancel_safety_escalation,
            user_id,
            session_id,
            reason,
            note,
        )
    except DatabaseAccessError as err:
        logger.exception(
            "Database error cancelling safety escalation",
            extra={"session_id": session_id},
        )
        raise HTTPException(
            status_code=503,
            detail="Service temporarily unavailable.",
        ) from err

    return HTMLResponse(
        _escalation_page(
            "Thanks for letting us know. You won't get any more alerts for "
            "this check-in."
            if reason == "safe"
            else "Got it - further alerts for this check-in are now stopped.",
        ),
    )


def _escalation_page(message: str) -> str:
    """A minimal, dependency-free confirmation page - the recipient is a
    trusted contact with no app or account, just a browser tab from an SMS
    link, so this intentionally skips any frontend build step.
    """
    escaped_message = html.escape(message)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nexus Meetup Safety</title>
<style>
  body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: #0F172A; color: #F1F5F9; display: flex; align-items: center;
    justify-content: center; min-height: 100vh; margin: 0; padding: 24px; }}
  .card {{ max-width: 420px; text-align: center; }}
  h1 {{ font-size: 20px; margin-bottom: 12px; }}
  p {{ color: #CBD5E1; line-height: 1.5; }}
</style>
</head>
<body>
  <div class="card">
    <h1>Nexus Meetup Safety</h1>
    <p>{escaped_message}</p>
  </div>
</body>
</html>"""
