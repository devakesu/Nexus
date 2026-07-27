"""Meetup Safety, safety portal, and trusted-contact portal Pydantic models."""

import re
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
        """Executes strip and require non blank operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v

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
    lat: float
    lng: float


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


class SafetyEvidenceRegisterResponse(BaseModel):
    """Safetyevidenceregisterresponse class representation."""
    id: str


class SafetySessionStartRequest(BaseModel):
    """Safetysessionstartrequest class representation."""
    interval_seconds: int = Field(..., gt=0, le=86400)
    label: str | None = Field(default=None, max_length=200)
    event_label: str | None = Field(default=None, max_length=200)
    next_checkin_at: datetime
    battery_percent: int | None = Field(default=None, ge=0, le=100)
    connection_type: Literal["wifi", "cellular", "offline"] | None = None


class SafetySessionStartResponse(BaseModel):
    """Safetysessionstartresponse class representation."""
    id: str


class SafetySessionCheckinRequest(BaseModel):
    """Safetysessioncheckinrequest class representation."""
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
    """Safetycontactportaldetailsresponse class representation."""
    user_name: str
    profile_pic: str | None = None
    hometown: str | None = None
    current_place: str | None = None


class SafetyContactPortalRemoveResponse(BaseModel):
    """Safetycontactportalremoveresponse class representation."""
    removed: bool = True
