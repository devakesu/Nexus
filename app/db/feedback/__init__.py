"""Database user feedback, ticketing, and status tracking package."""

from app.db.feedback.feedback import (
    add_ticket_comment,
    close_ticket,
    fetch_ticket_comments,
    fetch_ticket_report,
    fetch_ticket_status_history,
    fetch_user_email,
    fetch_user_tickets,
    record_feedback_submission,
)

__all__ = [
    "add_ticket_comment",
    "close_ticket",
    "fetch_ticket_comments",
    "fetch_ticket_report",
    "fetch_ticket_status_history",
    "fetch_user_email",
    "fetch_user_tickets",
    "record_feedback_submission",
]
