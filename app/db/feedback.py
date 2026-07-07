import logging
from typing import Any, cast

from postgrest.exceptions import APIError

from app.db.client import DatabaseAccessError, supabase_client

logger = logging.getLogger(__name__)

_INSERT_RETURN_COLS = "id, status, created_at"


def _build_feedback_payload(
    user_id: str,
    query_type: str,
    subject: str,
    message: str,
    contact_email: str | None,
    github_issue_url: str | None,
    attachment_paths: list[str] | None,
    app_version: str | None,
    platform: str | None,
    device_info: dict[str, Any] | None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "user_id": user_id,
        "query_type": query_type,
        "subject": subject.strip(),
        "message": message.strip(),
    }
    optional_fields: dict[str, Any] = {
        "contact_email": contact_email.strip().lower() if contact_email else None,
        "github_issue_url": github_issue_url.strip() if github_issue_url else None,
        "attachment_paths": attachment_paths or None,
        "app_version": app_version.strip() if app_version else None,
        "platform": platform or None,
        "device_info": device_info or None,
    }
    payload.update({k: v for k, v in optional_fields.items() if v is not None})
    return payload


def record_feedback_submission(
    user_id: str,
    query_type: str,
    subject: str,
    message: str,
    contact_email: str | None = None,
    github_issue_url: str | None = None,
    attachment_paths: list[str] | None = None,
    app_version: str | None = None,
    platform: str | None = None,
    device_info: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Insert a Help, Feedback & Bug Report ticket.

    The initial status-history row is populated automatically by the
    log_feedback_reports_status_change trigger (see migration
    20260714000000_feedback_reports.sql).
    """
    payload = _build_feedback_payload(
        user_id=user_id,
        query_type=query_type,
        subject=subject,
        message=message,
        contact_email=contact_email,
        github_issue_url=github_issue_url,
        attachment_paths=attachment_paths,
        app_version=app_version,
        platform=platform,
        device_info=device_info,
    )

    try:
        res = (
            supabase_client.table("feedback_reports")
            .insert(payload)
            .select(_INSERT_RETURN_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            raise DatabaseAccessError("Feedback insert returned no row")
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to insert feedback report",
            extra={"user_id": user_id, "query_type": query_type},
        )
        raise DatabaseAccessError("Failed to insert feedback report") from e


def fetch_user_email(user_id: str) -> str | None:
    """Look up the account email of record from public.users.

    users.email is NOT NULL in the schema, so this should always resolve
    for a real account; None only on lookup failure.
    """
    try:
        res = (
            supabase_client.table("users")
            .select("email")
            .eq("id", user_id)
            .maybe_single()
            .execute()
        )
        if res and res.data:
            return cast(dict[str, Any], res.data).get("email")
        return None
    except APIError:
        logger.exception("Failed to fetch user email", extra={"user_id": user_id})
        return None
