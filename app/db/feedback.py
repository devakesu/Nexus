"""Database user feedback, support ticket, and administrative comment persistence layer.

Provides database interaction methods for submitting feedback inquiries, retrieving ticket histories,
adding comments, updating ticket statuses, and querying administrative ticket views.
"""

import logging
from typing import Any, cast

from postgrest.exceptions import APIError

from app.db.client import DatabaseAccessError, supabase_client, utcnow

logger = logging.getLogger(__name__)

_INSERT_RETURN_COLS = "id, status, created_at"
_LIST_COLS = "id, query_type, subject, status, created_at, updated_at"
_DETAIL_COLS = (
    "id, query_type, subject, message, github_issue_url, attachment_paths, "
    "app_version, platform, status, created_at, updated_at"
)

# open/in_progress sort ahead of resolved/closed; created_at desc within each group.
_STATUS_SORT_PRIORITY = {"open": 0, "in_progress": 0, "resolved": 1, "closed": 1}


def _build_feedback_payload(
    user_id: str | None,
    query_type: str,
    subject: str,
    message: str,
    github_issue_url: str | None,
    attachment_paths: list[str] | None,
    app_version: str | None,
    platform: str | None,
    device_info: dict[str, Any] | None,
    contact_email: str | None = None,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Build feedback payload.

        Args:
            user_id: build feedback payload.
            query_type: build feedback payload.
            subject: build feedback payload.
            message: build feedback payload.
            github_issue_url: build feedback payload.
            attachment_paths: build feedback payload.
            app_version: build feedback payload.
            platform: build feedback payload.
            device_info: build feedback payload.
            contact_email: build feedback payload.
            metadata: build feedback payload.

        Returns:
            dict[str, Any]: Result value.
        """
    final_metadata = dict(metadata or {})
    if contact_email:
        final_metadata["contact_email"] = contact_email.strip().lower()

    payload: dict[str, Any] = {
        "user_id": user_id,
        "query_type": query_type,
        "subject": subject.strip(),
        "message": message.strip(),
    }
    optional_fields: dict[str, Any] = {
        "github_issue_url": github_issue_url.strip() if github_issue_url else None,
        "attachment_paths": attachment_paths or None,
        "app_version": app_version.strip() if app_version else None,
        "platform": platform or None,
        "device_info": device_info or None,
        "metadata": final_metadata or None,
    }
    payload.update({k: v for k, v in optional_fields.items() if v is not None})
    return payload


def record_feedback_submission(
    user_id: str | None = None,
    query_type: str = "help",
    subject: str = "",
    message: str = "",
    github_issue_url: str | None = None,
    attachment_paths: list[str] | None = None,
    app_version: str | None = None,
    platform: str | None = None,
    device_info: dict[str, Any] | None = None,
    contact_email: str | None = None,
    metadata: dict[str, Any] | None = None,
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
        github_issue_url=github_issue_url,
        attachment_paths=attachment_paths,
        app_version=app_version,
        platform=platform,
        device_info=device_info,
        contact_email=contact_email,
        metadata=metadata,
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
    """Look up the account email of record from Supabase Auth (auth.users),
    which is the single source of truth for account email.
    """
    try:
        response = supabase_client.auth.admin.get_user_by_id(user_id)
    except Exception:
        logger.exception(
            "Failed to fetch user email via admin API",
            extra={"user_id": user_id},
        )
        return None

    user = getattr(response, "user", None)
    email = getattr(user, "email", None) if user is not None else None
    return email.strip().lower() if isinstance(email, str) and email else None


def fetch_user_tickets(
    user_id: str,
    limit: int | None = None,
    offset: int = 0,
) -> list[dict[str, Any]]:
    """List a user's own tickets, open/in_progress first, newest first within
    each group.

    Sorting is done in Python rather than SQL since a per-user ticket count
    is always small and this keeps the query itself trivial.
    """
    try:
        res = (
            supabase_client.table("feedback_reports")
            .select(_LIST_COLS)
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .execute()
        )
        rows = cast(list[dict[str, Any]], res.data or [])
    except APIError as e:
        logger.exception("Failed to fetch user tickets", extra={"user_id": user_id})
        raise DatabaseAccessError("Failed to fetch tickets") from e

    rows.sort(key=lambda r: _STATUS_SORT_PRIORITY.get(str(r.get("status")), 2))
    sliced = rows[offset:]
    return sliced[:limit] if limit is not None else sliced


def fetch_ticket_report(user_id: str, report_id: str) -> dict[str, Any] | None:
    """Fetch a single ticket, scoped to its owner. None if missing or not owned."""
    try:
        res = (
            supabase_client.table("feedback_reports")
            .select(_DETAIL_COLS)
            .eq("id", report_id)
            .eq("user_id", user_id)
            .maybe_single()
            .execute()
        )
        if res and res.data:
            return cast(dict[str, Any], res.data)
        return None
    except APIError as e:
        logger.exception(
            "Failed to fetch ticket",
            extra={"user_id": user_id, "report_id": report_id},
        )
        raise DatabaseAccessError("Failed to fetch ticket") from e


def fetch_ticket_status_history(report_id: str) -> list[dict[str, Any]]:
    """Fetch ticket status history.

        Args:
            report_id: fetch ticket status history.

        Returns:
            list[dict[str, Any]]: Result value.
        """
    try:
        res = (
            supabase_client.table("feedback_report_status_history")
            .select("status, note, changed_by, created_at")
            .eq("report_id", report_id)
            .order("created_at")
            .execute()
        )
        return cast(list[dict[str, Any]], res.data or [])
    except APIError as e:
        logger.exception(
            "Failed to fetch ticket status history",
            extra={"report_id": report_id},
        )
        raise DatabaseAccessError("Failed to fetch ticket status history") from e


def fetch_ticket_comments(report_id: str) -> list[dict[str, Any]]:
    """Fetch ticket comments.

        Args:
            report_id: fetch ticket comments.

        Returns:
            list[dict[str, Any]]: Result value.
        """
    try:
        res = (
            supabase_client.table("feedback_report_comments")
            .select("id, author_id, body, created_at")
            .eq("report_id", report_id)
            .order("created_at")
            .execute()
        )
        return cast(list[dict[str, Any]], res.data or [])
    except APIError as e:
        logger.exception(
            "Failed to fetch ticket comments",
            extra={"report_id": report_id},
        )
        raise DatabaseAccessError("Failed to fetch ticket comments") from e


def add_ticket_comment(report_id: str, author_id: str, body: str) -> dict[str, Any]:
    """Add ticket comment.

        Args:
            report_id: add ticket comment.
            author_id: add ticket comment.
            body: add ticket comment.

        Returns:
            dict[str, Any]: Result value.
        """
    try:
        comment_payload = {
            "report_id": report_id,
            "author_id": author_id,
            "body": body.strip(),
        }
        res = (
            supabase_client.table("feedback_report_comments")
            .insert(comment_payload)
            .select("id, author_id, body, created_at")
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            raise DatabaseAccessError("Comment insert returned no row")
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to insert ticket comment",
            extra={"report_id": report_id, "author_id": author_id},
        )
        raise DatabaseAccessError("Failed to insert ticket comment") from e


def close_ticket(user_id: str, report_id: str, reason: str) -> dict[str, Any] | None:
    """Close a ticket the caller owns, recording the reason.

    Returns None if the ticket doesn't exist, isn't owned by user_id, or is
    already closed (scoped directly into the update's filter so this is a
    single atomic check-and-set rather than fetch-then-update).
    """
    try:
        res = (
            supabase_client.table("feedback_reports")
            .update(
                {
                    "status": "closed",
                    "reviewed_by": user_id,
                    "reviewed_at": utcnow().isoformat(),
                    "reviewer_notes": reason.strip(),
                },
            )
            .eq("id", report_id)
            .eq("user_id", user_id)
            .neq("status", "closed")
            .select(_DETAIL_COLS)
            .execute()
        )
        rows = cast(list[Any], res.data or [])
        if not rows or not isinstance(rows[0], dict):
            return None
        return cast(dict[str, Any], rows[0])
    except APIError as e:
        logger.exception(
            "Failed to close ticket",
            extra={"user_id": user_id, "report_id": report_id},
        )
        raise DatabaseAccessError("Failed to close ticket") from e
