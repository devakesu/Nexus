"""Request/response Pydantic models for web contact forms and OTP verification."""

from pydantic import BaseModel, Field, field_validator


class ContactOtpRequest(BaseModel):
    """Payload for requesting a contact form OTP verification code."""

    email: str = Field(..., max_length=255, description="Submitter email address.")
    turnstile_token: str | None = Field(
        default=None, max_length=2048, description="Optional Cloudflare Turnstile token.",
    )


class ContactSubmitRequest(BaseModel):
    """Payload for submitting a web contact form ticket after OTP verification."""

    email: str = Field(..., max_length=255, description="Submitter email address.")
    otp_code: str = Field(..., min_length=6, max_length=6, description="6-digit verification OTP code.")
    query_type: str = Field(default="help", max_length=32, description="Inquiry category.")
    subject: str = Field(..., min_length=3, max_length=255, description="Brief inquiry title.")
    message: str = Field(..., min_length=10, max_length=10000, description="Detailed inquiry message body.")
    name: str | None = Field(default=None, max_length=120, description="Optional submitter name.")
    account_id_or_phone: str | None = Field(
        default=None, max_length=120, description="Optional phone or account identifier.",
    )
    github_issue_url: str | None = Field(default=None, max_length=500, description="Optional related GitHub issue URL.")
    attachment_paths: list[str] = Field(
        default_factory=list, description="Optional uploaded attachment storage paths.",
    )
    turnstile_token: str | None = Field(
        default=None, max_length=2048, description="Optional Cloudflare Turnstile token.",
    )

    @field_validator("query_type")
    @classmethod
    def sanitize_query_type(cls, val: str) -> str:
        """Sanitizes query type string."""
        return val.strip().lower()
