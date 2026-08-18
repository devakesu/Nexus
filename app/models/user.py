"""User authentication, onboarding, OTP, and account deletion Pydantic models."""

import re
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, Field, field_validator

from app.core.config import settings


def _validate_terms_version(value: str) -> str:
    """Validate terms version.

        Args:
            value: Input value parameter.

        Returns:
            str: Response payload or result."""
    cleaned = value.strip()
    try:
        float(cleaned)
    except ValueError as err:
        raise ValueError("accepted_terms_version must be a numeric string.") from err

    if cleaned != settings.current_terms_version.strip():
        raise ValueError("You must accept the current terms version.")
    return cleaned


class AuthBootstrapResponse(BaseModel):
    """User account bootstrap information response DTO."""

    user_id: str
    email: str | None = None
    is_active: bool
    is_suspended: bool
    moderation_status: str
    accepted_terms_version: str | None = None
    terms_accepted_at: datetime | None = None
    newly_created: bool
    mobile: str | None = None
    mobile_verified_at: datetime | None = None
    # Set when an account deletion request is pending. The client should
    # route to a Reactivate screen instead of the normal app when true - see
    # app/db/account_deletion.py and the bootstrap short-circuit in
    # app/api/user.py that skips assert_account_active for this case.
    deletion_pending: bool = False
    scheduled_purge_at: datetime | None = None
    # Itemized consent state - see 20260802000000_terms_consent_expansion.sql
    # and app/api/user.py's consent-recording endpoint. current_terms_version
    # is always populated (straight from settings), letting the client learn
    # the required version *before* it has accepted anything - the previous
    # gap that left brand-new users with no way to discover what version to
    # accept, and existing users with no way to discover a version bump.
    current_terms_version: str
    special_category_consent_version: str | None = None
    special_category_consent_at: datetime | None = None
    safety_data_consent_version: str | None = None
    safety_data_consent_at: datetime | None = None
    # True once the user has a profile (i.e. isn't still mid-onboarding) and
    # general consent is missing or stale relative to current_terms_version.
    # special_category consent is NOT a mandatory-consent input here (see
    # special_category_consent_granted below) - like safety-data consent, it
    # only gates a specific optional data category (sexual orientation /
    # religious belief profile fields), not general app access, since those
    # fields are themselves optional/skippable in the profile. The client
    # shows TermsConsentPage(isVersionBump: true) when this is true for an
    # already-onboarded user, and TermsConsentPage(isVersionBump: false)
    # right after onboarding completes for a first-time user.
    mandatory_consent_required: bool = False
    # True only when special_category_consent_version is set AND not stale
    # relative to current_terms_version - precomputed the same way as
    # safety_data_consent_granted below, so the client can gate the
    # sexuality/religious-belief profile fields without re-deriving
    # version-staleness comparison logic itself.
    special_category_consent_granted: bool = False
    # True only when safety_data_consent_version is set AND not stale
    # relative to current_terms_version - the exact same check
    # assert_safety_consent runs server-side, precomputed here so the
    # client never has to re-derive version-staleness comparison logic
    # itself just to decide whether to show the Safety Center / event
    # check-in toggle as locked.
    safety_data_consent_granted: bool = False


class BaseOnboardingRequest(BaseModel):
    """
    Minimal common fields shared by all onboarding variants.

    Only `age` is universal. All other fields (name, branch, year) are
    variant-specific. Terms/consent is deliberately NOT collected here -
    onboarding creates the profile only; consent is a separate step (see
    TermsConsentPage / the consent-recording endpoint in app/api/user.py),
    so a bad/rejected consent choice never has to be untangled from profile
    creation.
    """

    age: int = Field(..., ge=18, le=27)


class NexusOnboardingRequest(BaseOnboardingRequest):
    """
    Onboarding payload for the main Nexus (personal) flavor.

    - Name is collected from the user.
    - Age is collected.
    - Demographic bucket (M/F/NB) is collected for relevance-ranked discovery.
    """

    app_variant: Literal["nexus"] = "nexus"
    name: str = Field(..., min_length=4, max_length=100)
    age: int = Field(..., ge=18, le=80)
    demographic_bucket: Literal["M", "F", "NB"] = Field(
        ...,
        description="Which demographic bucket the user primarily identifies as.",
    )

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        """Executes validate name operation.

            Args:
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
        cleaned = value.strip()
        if len(cleaned) < 4:
            raise ValueError("Name must be at least 4 characters.")
        if not re.match(r"^[a-zA-Z\s\.]+$", cleaned):
            raise ValueError(
                "Name can only contain letters, spaces, and dots.",
            )
        if ".." in cleaned:
            raise ValueError("Name cannot contain consecutive dots.")
        if len(re.findall(r"[a-zA-Z]", cleaned)) < 2:
            raise ValueError("Name must contain actual letters.")
        return cleaned


class MECOnboardingRequest(BaseOnboardingRequest):
    """
    Onboarding payload for the Nexus-MEC (college) flavor.

    - Name is NOT in the payload; derived server-side.
    - Branch and year are REQUIRED.
    - Age is collected.
    """

    app_variant: Literal["nexus_mec"] = "nexus_mec"
    campus_branch: str = Field(..., min_length=1, max_length=100)
    campus_year: int = Field(..., ge=1, le=4)
    campus_name: str | None = Field(default=None, max_length=150)

    @field_validator("campus_branch")
    @classmethod
    def validate_branch(cls, value: str) -> str:
        """Executes validate branch operation.

            Args:
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("Branch is required for NEXUS_MEC profiles.")
        return cleaned

    @field_validator("campus_name")
    @classmethod
    def validate_campus_name(cls, value: str | None) -> str | None:
        """Executes validate campus name operation.

            Args:
                value: Input value parameter.

            Returns:
                str | None: Response payload or result."""
        if not value or not value.strip():
            raise ValueError("Institute name is required.")
        cleaned = value.strip()
        if sum(c.isalpha() for c in cleaned) < 3:
            raise ValueError("Institute name must contain at least three letters.")
        return cleaned


# Discriminated union resolved by the `app_variant` field.
# FastAPI will automatically pick the correct model based on the payload.
OnboardingPayload = Annotated[
    NexusOnboardingRequest | MECOnboardingRequest,
    Field(discriminator="app_variant"),
]


class CompleteOnboardingResponse(BaseModel):
    """Completeonboardingresponse class representation."""
    user_id: str
    profile_created: bool
    profile: dict[str, object] = Field(exclude=True)


class ExportCodeResponse(BaseModel):
    """
    Returned to a flavor-variant user after generating a one-time export code.
    The code is valid for 15 minutes and can be entered on the main Nexus app.
    """

    code: str = Field(..., min_length=6, max_length=6)
    expires_at: datetime


class ImportRequest(BaseModel):
    """Payload sent by the main Nexus user to consume a flavor export code."""

    sync_code: str = Field(..., min_length=6, max_length=6)

    @field_validator("sync_code")
    @classmethod
    def validate_code_format(cls, value: str) -> str:
        """Executes validate code format operation.

            Args:
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
        cleaned = value.strip().upper()
        if not cleaned.isalnum():
            raise ValueError("sync_code must be alphanumeric.")
        return cleaned


class ImportResponse(BaseModel):
    """Result of a successful cross-flavor import handshake."""

    success: bool = True
    imported_fields: list[str] = Field(default_factory=list)


class ConsentUpdateRequest(BaseModel):
    """Records one or more of the three itemized consents (see
    20260802000000_terms_consent_expansion.sql). general_accepted is the
    only mandatory one - it must be true for the request to succeed, but a
    false submission is still logged to terms_consent_log (as a decline)
    before the 400 is raised, so decline events are auditable too.
    special_category_accepted and safety_data_accepted are both optional
    and independently togglable, same shape: None means "leave this
    category unchanged" rather than "decline it" - e.g. a general-consent
    submission shouldn't silently revoke a previously-granted special-
    category or safety consent.
    """

    terms_version: str
    general_accepted: bool
    special_category_accepted: bool | None = None
    safety_data_accepted: bool | None = None

    @field_validator("terms_version")
    @classmethod
    def validate_terms_version(cls, value: str) -> str:
        """Executes validate terms version operation.

            Args:
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
        return _validate_terms_version(value)


class ConsentUpdateResponse(BaseModel):
    """Consentupdateresponse class representation."""
    user_id: str
    accepted_terms_version: str | None = None
    terms_accepted_at: datetime | None = None
    special_category_consent_version: str | None = None
    special_category_consent_at: datetime | None = None
    safety_data_consent_version: str | None = None
    safety_data_consent_at: datetime | None = None


class AccountPhoneOtpRequestRequest(BaseModel):
    """Accountphoneotprequestrequest class representation."""
    phone: str = Field(..., min_length=8, max_length=20)

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value: str) -> str:
        """Executes validate phone operation.

            Args:
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
        cleaned = value.strip()
        if not re.match(r"^\+[1-9]\d{7,14}$", cleaned):
            raise ValueError(
                "Invalid phone number format. "
                "Must start with '+' followed by 8-15 digits (E.164 format).",
            )
        return cleaned


class AccountPhoneOtpRequestResponse(BaseModel):
    """Accountphoneotprequestresponse class representation."""
    sent: bool = True


class AccountPhoneOtpVerifyRequest(BaseModel):
    """Accountphoneotpverifyrequest class representation."""
    phone: str = Field(..., min_length=8, max_length=20)
    # Exactly 6 digits, matching generate_otp_code() - rejecting malformed
    # input here (a 422) rather than letting it consume one of the 5
    # precious verify attempts against a code that could never have matched.
    code: str = Field(..., pattern=r"^\d{6}$")

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value: str) -> str:
        """Executes validate phone operation.

            Args:
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
        cleaned = value.strip()
        if not re.match(r"^\+[1-9]\d{7,14}$", cleaned):
            raise ValueError(
                "Invalid phone number format. "
                "Must start with '+' followed by 8-15 digits (E.164 format).",
            )
        return cleaned


class AccountPhoneOtpVerifyResponse(BaseModel):
    """Accountphoneotpverifyresponse class representation."""
    verified: bool = True
    mobile: str
    mobile_verified_at: datetime


class LoginByPhoneRequestRequest(BaseModel):
    """Loginbyphonerequestrequest class representation."""
    phone: str = Field(..., min_length=8, max_length=20)

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value: str) -> str:
        """Executes validate phone operation.

            Args:
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
        cleaned = value.strip()
        if not re.match(r"^\+[1-9]\d{7,14}$", cleaned):
            raise ValueError(
                "Invalid phone number format. "
                "Must start with '+' followed by 8-15 digits (E.164 format).",
            )
        return cleaned


class LoginByPhoneRequestResponse(BaseModel):
    """Always {"sent": true} regardless of whether the phone actually
    matched an account - same anti-enumeration principle as
    SafetyPortalOtpRequestResponse.
    """

    sent: bool = True


class LoginByPhoneVerifyRequest(BaseModel):
    """Loginbyphoneverifyrequest class representation."""
    phone: str = Field(..., min_length=8, max_length=20)
    code: str = Field(..., min_length=4, max_length=10)

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value: str) -> str:
        """Executes validate phone operation.

            Args:
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
        cleaned = value.strip()
        if not re.match(r"^\+[1-9]\d{7,14}$", cleaned):
            raise ValueError(
                "Invalid phone number format. "
                "Must start with '+' followed by 8-15 digits (E.164 format).",
            )
        return cleaned


class LoginByPhoneVerifyResponse(BaseModel):
    """Loginbyphoneverifyresponse class representation."""
    refresh_token: str


class AccountDeletionSettingsResponse(BaseModel):
    """Accountdeletionsettingsresponse class representation."""
    grace_period_days: int
    blocklist_cooldown_days: int
    long_tail_purge_days: int
    safety_evidence_active_retention_days: int
    safety_data_legal_hold_days: int


class AccountDeletionOtpRequestRequest(BaseModel):
    """Accountdeletionotprequestrequest class representation."""
    email: str | None = Field(default=None, max_length=255)


class AccountDeletionOtpRequestResponse(BaseModel):
    """Accountdeletionotprequestresponse class representation."""
    sent: bool = True


class AccountDeletionOtpVerifyRequest(BaseModel):
    """Accountdeletionotpverifyrequest class representation."""
    code: str = Field(..., min_length=4, max_length=10)
    email: str | None = Field(default=None, max_length=255)


class AccountDeletionOtpVerifyResponse(BaseModel):
    """Accountdeletionotpverifyresponse class representation."""
    verified: bool = True


class AccountDeletionRequestRequest(BaseModel):
    """Accountdeletionrequestrequest class representation."""
    confirmation_text: str = Field(..., max_length=50)
    email: str | None = Field(default=None, max_length=255)


class AccountDeletionRequestResponse(BaseModel):
    """Accountdeletionrequestresponse class representation."""
    scheduled_purge_at: datetime


class AccountDeletionCancelResponse(BaseModel):
    """Accountdeletioncancelresponse class representation."""
    reactivated: bool = True


class DataExportOtpRequestRequest(BaseModel):
    """Dataexportotprequestrequest class representation."""
    email: str | None = Field(default=None, max_length=255)


class DataExportOtpRequestResponse(BaseModel):
    """Dataexportotprequestresponse class representation."""
    sent: bool = True


class DataExportOtpVerifyRequest(BaseModel):
    """Dataexportotpverifyrequest class representation."""
    code: str = Field(..., min_length=4, max_length=10)
    email: str | None = Field(default=None, max_length=255)


class DataExportOtpVerifyResponse(BaseModel):
    """Dataexportotpverifyresponse class representation."""
    verified: bool = True


class DataExportRequestRequest(BaseModel):
    """Dataexportrequestrequest class representation."""
    email: str | None = Field(default=None, max_length=255)
