"""Database Meetup Safety, trusted contacts, check-ins, and emergency alert state persistence layer.

Provides database interaction methods for managing trusted contacts, scheduling safety check-ins,
storing safety session audio/location evidence, and processing emergency SOS escalations.
"""

import contextlib
import json
import logging
from datetime import timedelta
from typing import Any, cast

from postgrest.exceptions import APIError
from storage3.utils import StorageException

from app.core.config import settings
from app.core.crypto import (
    DecryptFailedError,
    compute_blind_index,
    decrypt_pii,
    encrypt_to_hex,
)
from app.core.portal_auth import normalize_phone
from app.db.client import DatabaseAccessError, supabase_client, utcnow
from app.db.profiles import (
    decrypt_profile_record,
    sanitize_decrypted_profile,
    sign_profile_media,
)

logger = logging.getLogger(__name__)


_ALERT_INSERT_COLS = "id, created_at"
_EVIDENCE_INSERT_COLS = "id"
_SESSION_COLS = (
    "id, user_id, label, interval_seconds, next_checkin_at, event_context, "
    "status, battery_percent, connection_type, escalations_sent, "
    "last_escalated_at"
)


def _phone_blind_index(phone: str) -> str:
    """Phone blind index.

        Args:
            phone: phone blind index.

        Returns:
            str: Result value.
        """
    return compute_blind_index(normalize_phone(phone))


def sync_safety_contacts(
    user_id: str,
    contacts: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Replaces the caller's full trusted-contact mirror atomically using an
    RPC, after filtering out any phone number that previously self-removed
    (see safety_contact_notices) - a self-removal must stick even though
    the device is the "primary copy" of this list and doesn't know about it.

    Returns (blocked, newly_notified): blocked contacts were dropped from
    the sync entirely (the caller should tell the user why); newly_notified
    contacts are ones seen for the first time ever for this user, and the
    caller is responsible for sending them the one-time notice SMS.
    """
    try:
        notices_res = (
            supabase_client.table("safety_contact_notices")
            .select("phone_blind_index, self_removed_at")
            .eq("user_id", user_id)
            .execute()
        )
    except APIError as e:
        logger.exception(
            "Failed to fetch safety contact notices", extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to sync safety contacts") from e

    notices = {
        str(row["phone_blind_index"]): row
        for row in cast(list[dict[str, Any]], notices_res.data or [])
    }

    allowed: list[dict[str, Any]] = []
    blocked: list[dict[str, Any]] = []
    newly_notified: list[dict[str, Any]] = []
    for c in contacts:
        phone = str(c.get("phone") or "")
        blind_index = _phone_blind_index(phone)
        notice = notices.get(blind_index)
        if notice is not None and notice.get("self_removed_at"):
            blocked.append(c)
            continue
        allowed.append(c)
        if notice is None:
            newly_notified.append({**c, "blind_index": blind_index})

    encrypted: list[dict[str, Any]] = [
        {
            "name": encrypt_to_hex(c.get("name")),
            "phone": encrypt_to_hex(c.get("phone")),
        }
        for c in allowed
    ]
    try:
        supabase_client.rpc(
            "sync_safety_contacts",
            {"p_user_id": user_id, "p_contacts": encrypted},
        ).execute()
    except APIError as e:
        logger.exception("Failed to sync safety contacts", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to sync safety contacts") from e

    if newly_notified:
        try:
            supabase_client.table("safety_contact_notices").upsert(
                [
                    {
                        "user_id": user_id,
                        "phone_blind_index": n["blind_index"],
                    }
                    for n in newly_notified
                ],
                on_conflict="user_id,phone_blind_index",
            ).execute()
        except APIError:
            logger.exception(
                "Failed to record safety contact notices", extra={"user_id": user_id},
            )

    return blocked, newly_notified


def fetch_safety_contacts(user_id: str) -> list[dict[str, Any]]:
    """Fetch safety contacts.

        Args:
            user_id: fetch safety contacts.

        Returns:
            list[dict[str, Any]]: Result value.
        """
    try:
        res = (
            supabase_client.table("safety_contacts")
            .select("name, phone")
            .eq("user_id", user_id)
            .execute()
        )
        data = cast(list[dict[str, Any]], res.data or [])
        for row in data:
            row["name"] = decrypt_pii(row.get("name"))
            row["phone"] = decrypt_pii(row.get("phone"))
        return data
    except APIError as e:
        logger.exception(
            "Failed to fetch safety contacts",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to fetch safety contacts") from e


def fetch_safety_contacts_with_id(user_id: str) -> list[dict[str, Any]]:
    """Same as fetch_safety_contacts, but includes each row's (post-resync)
    id - needed to build a per-contact portal link right after a sync, since
    the plain name/phone fetch above doesn't carry it.
    """
    try:
        res = (
            supabase_client.table("safety_contacts")
            .select("id, name, phone")
            .eq("user_id", user_id)
            .execute()
        )
        data = cast(list[dict[str, Any]], res.data or [])
        for row in data:
            row["name"] = decrypt_pii(row.get("name"))
            row["phone"] = decrypt_pii(row.get("phone"))
        return data
    except APIError as e:
        logger.exception(
            "Failed to fetch safety contacts with id",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to fetch safety contacts") from e


# ---------------------------------------------------------------------------
# Trusted-contact self-removal portal
# ---------------------------------------------------------------------------


def fetch_safety_contact_by_id(contact_id: str) -> dict[str, Any] | None:
    """Fetch safety contact by id.

        Args:
            contact_id: fetch safety contact by id.

        Returns:
            dict[str, Any] | None: Result value.
        """
    try:
        res = (
            supabase_client.table("safety_contacts")
            .select("id, user_id, name, phone")
            .eq("id", contact_id)
            .maybe_single()
            .execute()
        )
        if not res or not res.data:
            return None
        row = cast(dict[str, Any], res.data)
    except APIError as e:
        logger.exception(
            "Failed to fetch safety contact by id", extra={"contact_id": contact_id},
        )
        raise DatabaseAccessError("Failed to fetch safety contact") from e
    row["name"] = decrypt_pii(row.get("name"))
    row["phone"] = decrypt_pii(row.get("phone"))
    return row


def remove_safety_contact_self_service(contact_id: str) -> dict[str, Any] | None:
    """Permanently removes a trusted contact at their own request: deletes
    the safety_contacts mirror row and marks the durable notice record so a
    later sync_safety_contacts call can't silently re-add the same phone
    number. Returns the removed contact's {user_id, name, phone} (decrypted)
    for the caller to notify the original user with, or None if the contact
    no longer exists (already removed, or the user deleted their account).
    """
    contact = fetch_safety_contact_by_id(contact_id)
    if contact is None:
        return None

    try:
        supabase_client.table("safety_contacts").delete().eq(
            "id", contact_id,
        ).execute()
    except APIError as e:
        logger.exception(
            "Failed to delete self-removed safety contact",
            extra={"contact_id": contact_id},
        )
        raise DatabaseAccessError("Failed to remove trusted contact") from e

    blind_index = _phone_blind_index(str(contact.get("phone") or ""))
    now = utcnow().isoformat()
    try:
        supabase_client.table("safety_contact_notices").upsert(
            {
                "user_id": contact["user_id"],
                "phone_blind_index": blind_index,
                "self_removed_at": now,
            },
            on_conflict="user_id,phone_blind_index",
        ).execute()
    except APIError:
        logger.exception(
            "Failed to record self-removal notice", extra={"contact_id": contact_id},
        )

    return contact


def fetch_contact_facing_profile_summary(user_id: str) -> dict[str, Any] | None:
    """The minimal, deliberately narrow profile view shown to a trusted
    contact on the self-removal portal - just enough to confirm who listed
    them (name, photo, hometown, current place), nothing from the dating/
    matching surface.
    """
    try:
        res = (
            supabase_client.table("profiles")
            .select("name, profile_pic, hometown, current_place")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        if not res or not res.data:
            return None
        row = cast(dict[str, Any], res.data)
    except APIError as e:
        logger.exception(
            "Failed to fetch profile summary for contact portal",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to fetch profile summary") from e

    try:
        decrypted = sanitize_decrypted_profile(decrypt_profile_record(row))
    except DecryptFailedError:
        logger.exception(
            "Failed to decrypt profile summary for contact portal",
            extra={"user_id": user_id},
        )
        return None
    return sign_profile_media(decrypted)


def record_safety_alert(
    user_id: str,
    alert_type: str,
    current_location: dict[str, float] | None,
    session_id: str | None = None,
) -> dict[str, Any]:
    """Record safety alert.

        Args:
            user_id: record safety alert.
            alert_type: record safety alert.
            current_location: record safety alert.
            session_id: record safety alert.

        Returns:
            dict[str, Any]: Result value.
        """
    payload: dict[str, Any] = {"user_id": user_id, "alert_type": alert_type}
    if current_location is not None:
        payload["current_location"] = encrypt_to_hex(json.dumps(current_location))
    if session_id is not None:
        payload["session_id"] = session_id

    try:
        res = (
            supabase_client.table("safety_alerts")
            .insert(payload)
            .select(_ALERT_INSERT_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            raise DatabaseAccessError("Safety alert insert returned no row")
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to insert safety alert",
            extra={"user_id": user_id, "alert_type": alert_type},
        )
        raise DatabaseAccessError("Failed to insert safety alert") from e


def fetch_safety_alert(alert_id: str) -> dict[str, Any] | None:
    """Fetch safety alert.

        Args:
            alert_id: fetch safety alert.

        Returns:
            dict[str, Any] | None: Result value.
        """
    try:
        res = (
            supabase_client.table("safety_alerts")
            .select("id, user_id")
            .eq("id", alert_id)
            .maybe_single()
            .execute()
        )
        if res and res.data:
            return cast(dict[str, Any], res.data)
        return None
    except APIError as e:
        logger.exception("Failed to fetch safety alert", extra={"alert_id": alert_id})
        raise DatabaseAccessError("Failed to fetch safety alert") from e


def update_alert_contacts_notified(alert_id: str, count: int) -> None:
    """Update alert contacts notified.

        Args:
            alert_id: update alert contacts notified.
            count: update alert contacts notified.

        Returns:
            None: Result value.
        """
    try:
        supabase_client.table("safety_alerts").update(
            {"contacts_notified": count},
        ).eq("id", alert_id).execute()
    except APIError as e:
        logger.exception(
            "Failed to update safety alert notified count",
            extra={"alert_id": alert_id},
        )
        raise DatabaseAccessError(
            "Failed to update safety alert notified count",
        ) from e


def register_safety_evidence(
    user_id: str,
    alert_id: str,
    storage_path: str,
    media_key_base64: str,
    content_type: str,
    duration_seconds: float | None,
) -> dict[str, Any]:
    """Register safety evidence.

        Args:
            user_id: register safety evidence.
            alert_id: register safety evidence.
            storage_path: register safety evidence.
            media_key_base64: register safety evidence.
            content_type: register safety evidence.
            duration_seconds: register safety evidence.

        Returns:
            dict[str, Any]: Result value.
        """
    # media_key_base64 (the per-file AES-GCM decryption key) is
    # Fernet-encrypted at rest, same pattern already used for
    # safety_contacts.name/phone and safety_alerts.current_location in this
    # file - closes the plaintext-key-escrow risk previously flagged here,
    # while keeping trusted-contact decryption working without the
    # reporting user's device needing to be online (fetch_evidence_for_alert_ids
    # decrypts it back server-side before the portal ever sees it).
    payload: dict[str, Any] = {
        "user_id": user_id,
        "alert_id": alert_id,
        "storage_path": storage_path,
        "media_key_base64": encrypt_to_hex(media_key_base64),
        "content_type": content_type,
    }
    if duration_seconds is not None:
        payload["duration_seconds"] = duration_seconds

    try:
        res = (
            supabase_client.table("safety_evidence")
            .insert(payload)
            .select(_EVIDENCE_INSERT_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            raise DatabaseAccessError("Safety evidence insert returned no row")
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to register safety evidence",
            extra={"user_id": user_id, "alert_id": alert_id},
        )
        raise DatabaseAccessError("Failed to register safety evidence") from e


# ---------------------------------------------------------------------------
# Recurring check-in session mirror (Milestone D: dead-man's-switch)
# ---------------------------------------------------------------------------


def start_safety_session(
    user_id: str,
    label: str | None,
    interval_seconds: int,
    next_checkin_at: str,
    event_context: dict[str, Any] | None,
    battery_percent: int | None,
    connection_type: str | None,
) -> dict[str, Any]:
    """Ends any stale active session for this user (defensive - the device
    should have already ended its previous session) and starts a new one.
    """
    try:
        supabase_client.table("safety_sessions").update({"status": "ended"}).eq(
            "user_id",
            user_id,
        ).eq("status", "active").execute()

        payload: dict[str, Any] = {
            "user_id": user_id,
            "label": label,
            "interval_seconds": interval_seconds,
            "next_checkin_at": next_checkin_at,
            "event_context": event_context or {},
            "last_heartbeat_at": utcnow().isoformat(),
            "battery_percent": battery_percent,
            "connection_type": connection_type,
        }
        res = (
            supabase_client.table("safety_sessions")
            .insert(payload)
            .select(_SESSION_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            raise DatabaseAccessError("Safety session insert returned no row")
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to start safety session",
            extra={"user_id": user_id},
        )
        raise DatabaseAccessError("Failed to start safety session") from e


def heartbeat_safety_session(
    user_id: str,
    session_id: str,
    next_checkin_at: str,
    battery_percent: int | None,
    connection_type: str | None,
) -> dict[str, Any] | None:
    """A successful check-in (or a fresh start) proves the device is fine,
    so this always resets escalations_sent back to 0. It also clears any
    earlier escalation_cancelled_at from a *previous* missed-checkin streak
    - that cancellation was scoped to the incident a trusted contact
    dismissed, not a permanent opt-out, so a fresh miss later in the same
    session must still be able to escalate again.
    """
    try:
        res = (
            supabase_client.table("safety_sessions")
            .update(
                {
                    "next_checkin_at": next_checkin_at,
                    "last_heartbeat_at": utcnow().isoformat(),
                    "battery_percent": battery_percent,
                    "connection_type": connection_type,
                    "escalations_sent": 0,
                    "last_escalated_at": None,
                    "escalation_cancelled_at": None,
                    "escalation_cancel_reason": None,
                    "escalation_cancel_note": None,
                },
            )
            .eq("id", session_id)
            .eq("user_id", user_id)
            .eq("status", "active")
            .select(_SESSION_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            return None
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to heartbeat safety session",
            extra={"user_id": user_id, "session_id": session_id},
        )
        raise DatabaseAccessError("Failed to heartbeat safety session") from e


def end_safety_session(user_id: str, session_id: str) -> None:
    """End safety session.

        Args:
            user_id: end safety session.
            session_id: end safety session.

        Returns:
            None: Result value.
        """
    try:
        supabase_client.table("safety_sessions").update(
            {"status": "ended"},
        ).eq("id", session_id).eq("user_id", user_id).execute()
    except APIError as e:
        logger.exception(
            "Failed to end safety session",
            extra={"user_id": user_id, "session_id": session_id},
        )
        raise DatabaseAccessError("Failed to end safety session") from e


def fetch_overdue_safety_sessions(grace_seconds: int) -> list[dict[str, Any]]:
    """Candidate sessions that have missed at least one check-in and haven't
    exhausted their 3 escalation attempts. The precise "is the *next*
    escalation actually due yet" check (which depends on escalations_sent,
    not just next_checkin_at) is done in Python by the caller, same as
    fetch_user_tickets sorts in Python rather than SQL.
    """
    try:
        cutoff = (utcnow() - timedelta(seconds=grace_seconds)).isoformat()
        res = (
            supabase_client.table("safety_sessions")
            .select(_SESSION_COLS)
            .eq("status", "active")
            .is_("escalation_cancelled_at", "null")
            .lt("escalations_sent", 3)
            .lt("next_checkin_at", cutoff)
            .execute()
        )
        return cast(list[dict[str, Any]], res.data or [])
    except APIError as e:
        logger.exception("Failed to fetch overdue safety sessions")
        raise DatabaseAccessError("Failed to fetch overdue safety sessions") from e


def record_safety_escalation_sent(session_id: str, new_count: int) -> None:
    """Record safety escalation sent.

        Args:
            session_id: record safety escalation sent.
            new_count: record safety escalation sent.

        Returns:
            None: Result value.
        """
    try:
        supabase_client.table("safety_sessions").update(
            {
                "escalations_sent": new_count,
                "last_escalated_at": utcnow().isoformat(),
            },
        ).eq("id", session_id).execute()
    except APIError as e:
        logger.exception(
            "Failed to record safety escalation",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to record safety escalation") from e


def fetch_safety_session(session_id: str) -> dict[str, Any] | None:
    """Fetch safety session.

        Args:
            session_id: fetch safety session.

        Returns:
            dict[str, Any] | None: Result value.
        """
    try:
        res = (
            supabase_client.table("safety_sessions")
            .select(_SESSION_COLS)
            .eq("id", session_id)
            .maybe_single()
            .execute()
        )
        if res and res.data:
            return cast(dict[str, Any], res.data)
        return None
    except APIError as e:
        logger.exception(
            "Failed to fetch safety session",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to fetch safety session") from e


def cancel_safety_escalation(
    session_id: str,
    reason: str,
    note: str | None,
) -> dict[str, Any] | None:
    """Idempotent: only takes effect the first time (escalation_cancelled_at
    IS NULL), so a trusted contact double-tapping the link (or the link
    being opened twice) doesn't overwrite an earlier reason/note.
    """
    try:
        res = (
            supabase_client.table("safety_sessions")
            .update(
                {
                    "escalation_cancelled_at": utcnow().isoformat(),
                    "escalation_cancel_reason": reason,
                    "escalation_cancel_note": note,
                },
            )
            .eq("id", session_id)
            .is_("escalation_cancelled_at", "null")
            .select(_SESSION_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            return None
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to cancel safety escalation",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to cancel safety escalation") from e


# ---------------------------------------------------------------------------
# Trusted-contact web portal (Milestone E)
# ---------------------------------------------------------------------------

_PORTAL_ALERT_COLS = "id, alert_type, current_location, created_at"
_PORTAL_EVIDENCE_COLS = (
    "id, alert_id, storage_path, media_key_base64, content_type, "
    "duration_seconds, created_at"
)


def fetch_alerts_for_session(session_id: str) -> list[dict[str, Any]]:
    """Newest first, so the portal's "last known location" is simply the
    first row with a non-null current_location.
    """
    try:
        res = (
            supabase_client.table("safety_alerts")
            .select(_PORTAL_ALERT_COLS)
            .eq("session_id", session_id)
            .order("created_at", desc=True)
            .execute()
        )
        alerts = cast(list[dict[str, Any]], res.data or [])
        for a in alerts:
            loc = a.get("current_location")
            if loc:
                with contextlib.suppress(Exception):
                    dec = decrypt_pii(loc)
                    a["current_location"] = json.loads(dec) if dec else None
        return alerts
    except APIError as e:
        logger.exception(
            "Failed to fetch alerts for safety session",
            extra={"session_id": session_id},
        )
        raise DatabaseAccessError("Failed to fetch alerts for safety session") from e


def fetch_evidence_for_alert_ids(alert_ids: list[str]) -> list[dict[str, Any]]:
    """Fetch evidence for alert ids.

        Args:
            alert_ids: fetch evidence for alert ids.

        Returns:
            list[dict[str, Any]]: Result value.
        """
    if not alert_ids:
        return []
    try:
        res = (
            supabase_client.table("safety_evidence")
            .select(_PORTAL_EVIDENCE_COLS)
            .in_("alert_id", alert_ids)
            .order("created_at", desc=False)
            .execute()
        )
        rows = cast(list[dict[str, Any]], res.data or [])
        for row in rows:
            key = row.get("media_key_base64")
            if key:
                # Fail-soft: rows written before this encryption was added
                # hold real plaintext base64, which isn't a valid Fernet
                # token - decrypt_pii raises on those, so leave the raw
                # value as-is rather than breaking their playback.
                with contextlib.suppress(Exception):
                    row["media_key_base64"] = decrypt_pii(key)
        return rows
    except APIError as e:
        logger.exception(
            "Failed to fetch evidence for safety alerts",
            extra={"alert_id_count": len(alert_ids)},
        )
        raise DatabaseAccessError("Failed to fetch evidence for safety alerts") from e


def create_evidence_download_url(storage_path: str, expires_in: int) -> str | None:
    """A fresh, short-lived signed URL into the private safety_evidence
    bucket - generated on demand rather than stored, so it's never sitting
    around valid longer than a single portal page load needs it.
    """
    try:
        result = supabase_client.storage.from_("safety_evidence").create_signed_url(
            storage_path,
            expires_in,
        )
        return result.get("signedURL")
    except StorageException:
        logger.exception(
            "Failed to create signed URL for safety evidence",
            extra={"storage_path": storage_path},
        )
        return None


# ---------------------------------------------------------------------------
# Retention / deletion policy
#
# Digital Witness recordings (safety_evidence: raw audio/video plus the
# escrowed AES-GCM key) are the most invasive data this feature holds, so
# they're capped by age regardless of account status. safety_alerts rows
# (lightweight metadata - type, encrypted location, timestamp, contact
# count) are cheaper and stay useful for trust & safety pattern review, so
# they're only time-boxed once the owning account itself is gone - see
# app/db/account_deletion.py's module docstring for why purged_at (Tier-1
# anonymization) rather than account deletion request time is the anchor.
# Both run daily from app/services/reminder_scheduler.py.
# ---------------------------------------------------------------------------


def purge_expired_safety_evidence() -> None:
    """Hard-deletes safety_evidence rows (and their storage objects) older
    than settings.safety_evidence_active_retention_days, for every account
    - active or deleted alike. Per-row failures are logged and skipped
    rather than aborting the whole batch, same pattern as
    account_deletion.py's purge jobs.
    """
    cutoff = (
        utcnow() - timedelta(days=settings.safety_evidence_active_retention_days)
    ).isoformat()
    try:
        res = (
            supabase_client.table("safety_evidence")
            .select("id, storage_path")
            .lt("created_at", cutoff)
            .execute()
        )
    except APIError:
        logger.exception("Failed to fetch expired safety evidence")
        return

    rows = cast(list[dict[str, Any]], res.data or [])
    if not rows:
        return

    paths = [str(r["storage_path"]) for r in rows if r.get("storage_path")]
    if paths:
        try:
            supabase_client.storage.from_("safety_evidence").remove(paths)
        except Exception:
            logger.exception(
                "Failed to remove expired safety evidence storage objects",
            )

    ids = [str(r["id"]) for r in rows if r.get("id")]
    try:
        supabase_client.table("safety_evidence").delete().in_("id", ids).execute()
    except APIError:
        logger.exception("Failed to delete expired safety evidence rows")


def purge_safety_data_for_purged_accounts() -> None:
    """Hard-deletes any remaining safety_alerts/safety_evidence belonging to
    accounts that finished Tier-1 anonymization (users.purged_at) more than
    settings.safety_data_legal_hold_days ago - long enough to cover a
    realistic law-enforcement or internal trust & safety follow-up window
    on an incident from that account, short enough not to hoard it
    indefinitely once the account is gone for good.
    """
    cutoff = (
        utcnow() - timedelta(days=settings.safety_data_legal_hold_days)
    ).isoformat()
    try:
        res = (
            supabase_client.table("users")
            .select("id")
            .not_.is_("purged_at", "null")
            .lte("purged_at", cutoff)
            .execute()
        )
    except APIError:
        logger.exception("Failed to fetch accounts due for safety data purge")
        return

    user_ids = [
        str(r["id"]) for r in cast(list[dict[str, Any]], res.data or []) if r.get("id")
    ]
    if not user_ids:
        return

    try:
        evidence_res = (
            supabase_client.table("safety_evidence")
            .select("id, storage_path")
            .in_("user_id", user_ids)
            .execute()
        )
        evidence_rows = cast(list[dict[str, Any]], evidence_res.data or [])
        paths = [
            str(r["storage_path"]) for r in evidence_rows if r.get("storage_path")
        ]
        if paths:
            with contextlib.suppress(Exception):
                supabase_client.storage.from_("safety_evidence").remove(paths)
        supabase_client.table("safety_evidence").delete().in_(
            "user_id", user_ids,
        ).execute()
    except APIError:
        logger.exception(
            "Failed to purge safety_evidence for purged accounts",
        )

    try:
        supabase_client.table("safety_alerts").delete().in_(
            "user_id", user_ids,
        ).execute()
    except APIError:
        logger.exception("Failed to purge safety_alerts for purged accounts")
