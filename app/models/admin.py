"""Admin, feedback ticket, and Help/Support Pydantic models."""

import re
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

_GITHUB_ISSUE_URL_RE = re.compile(r"^https://github\.com/[^/\s]+/[^/\s]+/issues/\d+/?$")


class FeedbackSubmitRequest(BaseModel):
    """Submit a Help, Feedback & Bug Report ticket."""

    query_type: Literal[
        "help",
        "feedback",
        "bug_report",
        "suspended",
        "security",
        "legal_grievance",
        "grievance",
        "other",
    ]
    subject: str = Field(..., min_length=3, max_length=150)
    message: str = Field(..., min_length=10, max_length=5000)
    github_issue_url: str | None = Field(
        default=None,
        max_length=500,
        description="Optional linked GitHub issue; only valid for bug_report tickets.",
    )
    attachment_paths: list[str] = Field(
        default_factory=list,
        description=(
            "Object paths already uploaded to the private 'feedback_attachments' "
            "storage bucket, e.g. '<user_id>/<uuid>.jpg'."
        ),
    )
    app_version: str | None = Field(default=None, max_length=32)
    platform: Literal["android", "ios"] | None = None
    device_info: dict[str, str | int | bool | None] = Field(
        default_factory=dict,
        max_length=30,
    )

    @field_validator("subject", "message")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
        """Executes strip and require non blank operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v

    @field_validator("github_issue_url")
    @classmethod
    def validate_github_issue_url(cls, v: str | None) -> str | None:
        """Executes validate github issue url operation.

            Args:
                v: Input v parameter.

            Returns:
                str | None: Response payload or result."""
        if v is None:
            return None
        v = v.strip()
        if not v:
            return None
        if not _GITHUB_ISSUE_URL_RE.match(v):
            raise ValueError(
                "github_issue_url must look like "
                "https://github.com/<org>/<repo>/issues/<number>",
            )
        return v

    @field_validator("attachment_paths")
    @classmethod
    def validate_attachment_paths(cls, v: list[str]) -> list[str]:
        """Executes validate attachment paths operation.

            Args:
                v: Input v parameter.

            Returns:
                list[str]: Response payload or result."""
        if len(v) > 5:
            raise ValueError("attachment_paths supports at most 5 files")
        return v

    @model_validator(mode="after")
    def validate_github_url_scope(self) -> "FeedbackSubmitRequest":
        """Executes validate github url scope operation.

            Returns:
                'FeedbackSubmitRequest': Response payload or result."""
        if self.github_issue_url and self.query_type != "bug_report":
            raise ValueError(
                "github_issue_url is only applicable to bug_report tickets",
            )
        return self


class FeedbackSubmitResponse(BaseModel):
    """Feedbacksubmitresponse class representation."""
    id: str
    status: str
    created_at: datetime


class FeedbackTicketSummary(BaseModel):
    """Compact ticket row for the "My Tickets" list."""

    id: str
    query_type: str
    subject: str
    status: str
    created_at: datetime
    updated_at: datetime


class FeedbackStatusHistoryEntry(BaseModel):
    """Feedbackstatushistoryentry class representation."""
    status: str
    note: str | None = None
    changed_by: str | None = None
    created_at: datetime


class FeedbackCommentEntry(BaseModel):
    """Feedbackcommententry class representation."""
    id: str
    author_id: str
    body: str
    created_at: datetime
    is_own: bool


class FeedbackTicketDetail(BaseModel):
    """Feedbackticketdetail class representation."""
    id: str
    query_type: str
    subject: str
    message: str
    github_issue_url: str | None = None
    attachment_paths: list[str]
    app_version: str | None = None
    platform: str | None = None
    status: str
    created_at: datetime
    updated_at: datetime
    status_history: list[FeedbackStatusHistoryEntry]
    comments: list[FeedbackCommentEntry]


class FeedbackCommentRequest(BaseModel):
    """Feedbackcommentrequest class representation."""
    body: str = Field(..., min_length=1, max_length=3000)

    @field_validator("body")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
        """Executes strip and require non blank operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v


class FeedbackCloseRequest(BaseModel):
    """Feedbackcloserequest class representation."""
    reason: str = Field(..., min_length=3, max_length=1000)

    @field_validator("reason")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
        """Executes strip and require non blank operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v
