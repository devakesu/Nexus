import html
import re
import unicodedata
import urllib.parse
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator


class SafetyContactIn(BaseModel):
    """Safetycontactin class representation."""
    name: str = Field(..., min_length=1, max_length=100)
    phone: str = Field(..., min_length=8, max_length=20)

    @field_validator("name")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
        """Sanitizes contact name by stripping control characters, newlines, and excess whitespace."""
        from app.core.utils.sms import sanitize_sms_text

        cleaned = sanitize_sms_text(v, max_length=100)
        if not cleaned:
            raise ValueError("must not be blank")
        return cleaned

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
        """Executes validate phone operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        cleaned = v.strip()
        if not re.match(r"^\+[1-9]\d{7,14}$", cleaned):
            raise ValueError(
                "Invalid phone number format. "
                "Must start with '+' followed by 8-15 digits (E.164 format).",
            )
        return cleaned


class SafetyContactsSyncRequest(BaseModel):
    """Replaces the caller's full trusted-contact list. The list is always
    small (device caps it at 3), so a replace-all sync is simpler than
    per-contact add/remove endpoints and can't drift out of order.
    """

    contacts: list[SafetyContactIn] = Field(..., max_length=3)


class SafetyContactsSyncResponse(BaseModel):
    """blocked names submitted contacts that were NOT synced because that
    phone number previously removed itself via the self-service portal -
    see app/db/safety.py::sync_safety_contacts. The client should surface
    why rather than silently dropping them.
    """

    count: int
    blocked: list[str] = []


class SafetyLocation(BaseModel):
    """Safetylocation class representation."""
    lat: float = Field(..., ge=-90.0, le=90.0)
    lng: float = Field(..., ge=-180.0, le=180.0)


class SafetyAlertRequest(BaseModel):
    """Safetyalertrequest class representation."""
    alert_type: Literal["sos_silent", "sos_loud", "inform"]
    session_id: str | None = None

    @field_validator("session_id")
    @classmethod
    def validate_session_id_uuid(cls, v: str | None) -> str | None:
        """Executes validate session id uuid operation.

            Args:
                v: Input v parameter.

            Returns:
                str | None: Response payload or result."""
        if v is None:
            return None
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("session_id must be a valid UUID") from e
        return v

    session_label: str | None = Field(default=None, max_length=200)
    event_label: str | None = Field(default=None, max_length=200)
    current_location: SafetyLocation | None = None

    @field_validator("session_label", "event_label")
    @classmethod
    def sanitize_label_text(cls, v: str | None) -> str | None:
        if v is None:
            return None
        from app.core.utils.sms import sanitize_sms_text

        return sanitize_sms_text(v, max_length=200)


class SafetyAlertResponse(BaseModel):
    """Safetyalertresponse class representation."""
    id: str
    contacts_notified: int
    contacts_total: int


class SafetyEvidenceRegisterRequest(BaseModel):
    """Safetyevidenceregisterrequest class representation."""
    alert_id: str
    storage_path: str = Field(..., max_length=500)
    media_key_base64: str = Field(..., max_length=500)
    content_type: Literal["video", "audio"]
    duration_seconds: float | None = None

    @field_validator("storage_path")
    @classmethod
    def validate_storage_path(cls, value: str) -> str:
        """Validates that storage_path does not contain traversal, backslashes, leading slashes, null bytes, or URL-encoded escapes."""
        if not value or not value.strip():
            raise ValueError("storage_path is mandatory.")
        stripped = value.strip()
        if len(stripped) > 500:
            raise ValueError("storage_path must be less than 500 characters.")

        # URL decode and NFKC normalize
        decoded = urllib.parse.unquote(stripped)
        normalized = unicodedata.normalize("NFKC", decoded).strip()

        if (
            "\x00" in normalized
            or "\\" in normalized
            or normalized.startswith("/")
            or ".." in normalized
        ):
            raise ValueError("storage_path contains invalid characters or traversal sequences.")

        parts = normalized.split("/")
        if len(parts) < 2:
            raise ValueError("storage_path must contain at least user_id and filename.")
        for segment in parts:
            if not segment or segment in (".", "..") or ".." in segment:
                raise ValueError("storage_path contains invalid path segments.")
        return normalized


class SafetyEvidenceRegisterResponse(BaseModel):
    """Safetyevidenceregisterresponse class representation."""
    id: str


class SafetySessionStartRequest(BaseModel):
    """Request model to initiate a Meetup Safety check-in loop.

    Requires interval_seconds between 300 (5 min) and 86400 (24h).
    next_checkin_at must be in the future, bounded within max(interval_seconds * 2, 3600s)
    to prevent zombie sessions and ensure alignment with the escalation scheduler.
    """
    interval_seconds: int = Field(..., ge=300, le=86400)
    label: str | None = Field(default=None, max_length=200)
    event_label: str | None = Field(default=None, max_length=200)
    next_checkin_at: datetime
    battery_percent: int | None = Field(default=None, ge=0, le=100)
    connection_type: Literal["wifi", "cellular", "offline"] | None = None

    @field_validator("label", "event_label")
    @classmethod
    def sanitize_label_text(cls, v: str | None) -> str | None:
        if v is None:
            return None
        from app.core.utils.sms import sanitize_sms_text

        return sanitize_sms_text(v, max_length=200)


class SafetySessionStartResponse(BaseModel):
    """Safetysessionstartresponse class representation."""
    id: str


class SafetySessionCheckinRequest(BaseModel):
    """Request model for active safety session heartbeat check-in.

    next_checkin_at must be strictly in the future and bounded within a maximum window
    of 2 days to prevent arbitrary future scheduling.
    """
    session_id: str = Field(..., min_length=1)

    @field_validator("session_id")
    @classmethod
    def validate_session_id_uuid(cls, v: str) -> str:
        """Executes validate session id uuid operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("session_id must be a valid UUID") from e
        return v

    next_checkin_at: datetime
    battery_percent: int | None = Field(default=None, ge=0, le=100)
    connection_type: Literal["wifi", "cellular", "offline"] | None = None


class SafetySessionEndRequest(BaseModel):
    """Safetysessionendrequest class representation."""
    session_id: str = Field(..., min_length=1)

    @field_validator("session_id")
    @classmethod
    def validate_session_id_uuid(cls, v: str) -> str:
        """Executes validate session id uuid operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("session_id must be a valid UUID") from e
        return v


class EscalationCancelRequest(BaseModel):
    """Request model for POST-based escalation cancellation."""
    token: str = Field(..., min_length=1)
    reason: Literal["safe", "other"]
    note: str | None = Field(default=None, max_length=500)

    @field_validator("note")
    @classmethod
    def sanitize_note(cls, v: str | None) -> str | None:
        if v is None:
            return None
        cleaned = html.escape(v.strip())[:500]
        return cleaned or None


class SafetyPortalOtpRequestRequest(BaseModel):
    """Safetyportalotprequestrequest class representation."""
    phone: str = Field(..., min_length=6, max_length=20)

    @field_validator("phone")
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


class SafetyPortalOtpRequestResponse(BaseModel):
    """Always {"sent": true} regardless of whether the phone actually
    matched a trusted contact - the portal deliberately doesn't reveal
    that, same anti-enumeration principle as a password-reset endpoint.
    """

    sent: bool = True


class SafetyPortalOtpVerifyRequest(BaseModel):
    """Safetyportalotpverifyrequest class representation."""
    phone: str = Field(..., min_length=6, max_length=20)
    # Exactly 6 digits, matching generate_otp_code() - rejecting malformed
    # input here (a 422) rather than letting it consume one of the 5
    # precious verify attempts against a code that could never have matched.
    code: str = Field(..., pattern=r"^\d{6}$")

    @field_validator("phone")
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


class SafetyPortalOtpVerifyResponse(BaseModel):
    """Safetyportalotpverifyresponse class representation."""
    token: str
    expires_in: int


class SafetyPortalEvidenceItem(BaseModel):
    """Safetyportalevidenceitem class representation."""
    id: str
    content_type: Literal["video", "audio"]
    duration_seconds: float | None = None
    download_url: str
    media_key_base64: str
    created_at: datetime


class SafetyPortalDetailsResponse(BaseModel):
    """Safetyportaldetailsresponse class representation."""
    label: str | None = None
    event_label: str | None = None
    status: Literal["active", "ended"]
    last_location: SafetyLocation | None = None
    last_location_at: datetime | None = None
    evidence: list[SafetyPortalEvidenceItem] = []


class SafetyContactPortalOtpRequestRequest(BaseModel):
    """Safetycontactportalotprequestrequest class representation."""
    phone: str = Field(..., min_length=6, max_length=20)

    @field_validator("phone")
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


class SafetyContactPortalOtpRequestResponse(BaseModel):
    """Always {"sent": true} regardless of whether the phone actually
    matches this contact_id - same anti-enumeration principle as
    SafetyPortalOtpRequestResponse.
    """

    sent: bool = True


class SafetyContactPortalOtpVerifyRequest(BaseModel):
    """Safetycontactportalotpverifyrequest class representation."""
    phone: str = Field(..., min_length=6, max_length=20)
    code: str = Field(..., pattern=r"^\d{6}$")

    @field_validator("phone")
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


class SafetyContactPortalOtpVerifyResponse(BaseModel):
    """Safetycontactportalotpverifyresponse class representation."""
    token: str
    expires_in: int


class SafetyContactPortalDetailsResponse(BaseModel):
    """Minimal contact-facing profile summary for trusted contact self-removal portal.

    Authorizes and returns only recognizing identifiers (display name, profile photo,
    and home/current city) to allow an authenticated contact to verify who designated
    them before deciding to opt out. Excludes sensitive profile PII (bio, DOB, full address,
    email, phone, orientation, religion).
    """
    user_name: str
    profile_pic: str | None = None
    hometown: str | None = None
    current_place: str | None = None


class SafetyContactPortalRemoveResponse(BaseModel):
    """Safetycontactportalremoveresponse class representation."""
    removed: bool = True
