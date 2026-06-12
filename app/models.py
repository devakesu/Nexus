from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from app.core.config import DiscoveryTab, settings


class AuthBootstrapResponse(BaseModel):
    user_id: str
    email: str | None = None
    is_active: bool
    is_suspended: bool
    moderation_status: str
    accepted_terms_version: str | None = None
    terms_accepted_at: datetime | None = None
    newly_created: bool


class ProfileModel(BaseModel):
    """
    Canonical in-memory profile shape used by the discovery pipeline.

    This model includes core identity fields, tab-specific target buckets,
    decrypted optional scalar attributes, structured preference payloads,
    and optional embedding vectors used by ranking.
    """

    # Core identity fields.
    id: str
    name: str
    campus_branch: str
    campus_year: int | None = None
    age: int
    campus_name: str | None = None

    # Search and targeting bucket configuration.
    search_buckets: list[str] = Field(default_factory=list)
    dating_target_buckets: list[str] = Field(default_factory=list)
    friends_target_buckets: list[str] = Field(default_factory=list)
    professional_target_buckets: list[str] = Field(default_factory=list)

    # Optional decrypted scalar attributes.
    display_gender: str | None = None
    display_sexuality: str | None = None
    pronouns: str | None = None
    drinking: str | None = None
    smoking: str | None = None
    role: str | None = None
    hometown: str | None = None
    current_place: str | None = None
    partner_values: str | None = None
    children_plans: str | None = None
    religious_beliefs: str | None = None
    profile_pic: str | None = None

    # Optional decrypted list attributes.
    activities: list[str] = Field(default_factory=list)
    looking_for: list[str] = Field(default_factory=list)
    causes_supported: list[str] = Field(default_factory=list)
    top_artists: list[str] = Field(default_factory=list)
    tech_skills: list[str] = Field(default_factory=list)
    languages: list[str] = Field(default_factory=list)
    ai_vibe_tags: list[str] = Field(default_factory=list)
    pets: list[str] = Field(default_factory=list)
    normal_pics: list[str] = Field(default_factory=list)

    # Optional decrypted structured payloads.
    interests: dict[str, int] = Field(default_factory=dict)
    sub_interests: dict[str, list[str]] = Field(default_factory=dict)
    value_dimensions: dict[str, float] = Field(default_factory=dict)

    # Optional vector embeddings used by the ranking engine.
    identity_embedding: list[float] | None = None
    career_embedding: list[float] | None = None
    bio_embedding: list[float] | None = None


# ---------------------------------------------------------------------------
# Onboarding — Polymorphic models
# ---------------------------------------------------------------------------

class BaseOnboardingRequest(BaseModel):
    """
    Minimal common fields shared by all onboarding variants.

    Only `age` and `accepted_terms_version` are universal.
    All other fields (name, branch, year) are variant-specific.
    """

    age: int = Field(..., ge=18, le=27)
    accepted_terms_version: str
    phone: str = Field(..., min_length=8, max_length=20)

    @field_validator("accepted_terms_version")
    @classmethod
    def validate_terms_version(cls, value: str) -> str:
        cleaned = value.strip()
        try:
            val_float = float(cleaned)
            curr_float = float(settings.current_terms_version)
            if val_float != curr_float:
                raise ValueError("You must accept the current terms version.")
        except ValueError as err:
            raise ValueError("You must accept the current terms version.") from err
        return cleaned

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value: str) -> str:
        import re
        cleaned = value.strip()
        if not re.match(r"^\+?[1-9]\d{7,14}$", cleaned):
            raise ValueError(
                "Invalid phone number format. "
                "Must start with optional '+' followed by 8-15 digits.",
            )
        return cleaned



class NexusOnboardingRequest(BaseOnboardingRequest):
    """
    Onboarding payload for the main Nexus (personal) flavor.

    - Name is collected from the user.
    - Age is collected.
    - Lifestyle is collected.
    """

    app_variant: Literal["nexus"] = "nexus"
    name: str = Field(..., min_length=4, max_length=100)
    lifestyle: str = Field(..., min_length=1)

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
        import re
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
        cleaned = value.strip()
        if not cleaned:
            raise ValueError("Branch is required for MEC profiles.")
        return cleaned


# Discriminated union resolved by the `app_variant` field.
# FastAPI will automatically pick the correct model based on the payload.
OnboardingPayload = Annotated[
    NexusOnboardingRequest | MECOnboardingRequest,
    Field(discriminator="app_variant"),
]


# Kept for backwards-compatibility; new code should use OnboardingPayload.
CompleteOnboardingRequest = BaseOnboardingRequest


class CompleteOnboardingResponse(BaseModel):
    user_id: str
    profile_created: bool
    terms_recorded: bool
    accepted_terms_version: str
    terms_accepted_at: datetime
    profile: dict[str, object]


# ---------------------------------------------------------------------------
# Cross-flavor import / export handshake
# ---------------------------------------------------------------------------

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
        cleaned = value.strip().upper()
        if not cleaned.isalnum():
            raise ValueError("sync_code must be alphanumeric.")
        return cleaned


class ImportResponse(BaseModel):
    """Result of a successful cross-flavor import handshake."""

    success: bool = True
    imported_fields: list[str] = Field(default_factory=list)


class DiscoveryFilters(BaseModel):
    """
    Structured filter payload for discovery candidate pool narrowing.

    This model constrains optional filter inputs and validates age bounds
    before any database filtering is executed.
    """

    # Optional categorical filters.
    campus_years: list[int] | None = Field(
        default=None,
        description="Array of target campus academic years.",
    )
    drinking: list[str] | None = Field(
        default=None,
        description="Target drinking lifestyle profiles.",
    )
    smoking: list[str] | None = Field(
        default=None,
        description="Target smoking lifestyle profiles.",
    )
    campus_branches: list[str] | None = Field(
        default=None,
        description="Target engineering branch categories.",
    )
    role: str | None = Field(
        default=None,
        max_length=100,
        description="Target professional role designation.",
    )

    @field_validator("role")
    @classmethod
    def validate_role(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return value.strip().lower()

    # Inclusive age bounds.
    min_age: int = Field(
        default=18,
        ge=18,
        le=27,
        description="Minimum age constraint boundary.",
    )
    max_age: int = Field(
        default=27,
        ge=18,
        le=27,
        description="Maximum age constraint boundary.",
    )

    @model_validator(mode="after")
    def validate_age_range(self) -> "DiscoveryFilters":
        # Cross-field validation belongs at the model level in Pydantic v2.
        if self.min_age > self.max_age:
            raise ValueError("min_age cannot be greater than max_age")
        return self


class DiscoveryRequest(BaseModel):
    """
    Request payload for orbit-based discovery bootstrap.

    A new discovery session is created when session_id is omitted.
    When session_id is provided, the request resumes the same frozen session.
    """

    tab: DiscoveryTab = Field(
        ...,
        description="Target matching pipeline matrix.",
    )

    filters: DiscoveryFilters = Field(
        default_factory=DiscoveryFilters,
        description="Dynamic compound filter parameters configuration.",
    )

    session_id: str | None = Field(
        default=None,
        description=(
            "Server-issued discovery session identifier for orbit-session reuse."
        ),
    )


class DiscoveryActionRequest(BaseModel):
    """
    Request payload for applying a discovery action to a target profile.
    """

    # Candidate profile receiving the action.
    target_id: str = Field(
        ...,
        description="Profile id of the candidate the action applies to.",
    )

    # Supported actions, including reversal operations.
    action: Literal[
        "pass",
        "hide",
        "like",
        "superlike",
        "block",
        "unhide",
        "unlike",
        "unsuperlike",
        "unblock",
    ] = Field(
        ...,
        description="Discovery action or reversal action to apply.",
    )

    # Tab is required for tab-scoped actions and forbidden for block/unblock.
    tab: DiscoveryTab | None = Field(
        default=None,
        description=(
            "Required for tab-scoped actions; must be omitted for block/unblock."
        ),
    )

    @model_validator(mode="after")
    def validate_tab_requirements(self) -> "DiscoveryActionRequest":
        # Actions scoped to a discovery tab must include tab context.
        tab_required_actions = {
            "pass",
            "hide",
            "like",
            "superlike",
            "unhide",
            "unlike",
            "unsuperlike",
        }

        # Global block actions must not include tab context.
        tab_forbidden_actions = {"block", "unblock"}

        if self.action in tab_required_actions and self.tab is None:
            raise ValueError("tab is required for this action")

        if self.action in tab_forbidden_actions and self.tab is not None:
            raise ValueError("tab must be omitted for block/unblock")

        return self


class DiscoveryActionResponse(BaseModel):
    """
    Minimal success response for discovery action mutations.
    """

    success: bool = True


class OrbitNodeOut(BaseModel):
    """
    Lightweight node payload for rendering a profile on the orbit canvas.

    Full profile details are intentionally excluded and should be fetched
    only when the user taps a node.
    """

    id: str
    name: str | None = None
    score: float
    x: float
    y: float
    orbit_tier: int


class OrbitDiscoverResponse(BaseModel):
    """
    Initial discovery bootstrap payload for the orbit-based UI.

    Returns the discovery session identifier plus the first visible set
    of nodes around the origin for immediate rendering.
    """

    session_id: str
    expires_at: datetime
    total_nodes: int = 0
    nodes: list[OrbitNodeOut] = []


class OrbitNodeDetailRequest(BaseModel):
    session_id: str = Field(
        ...,
        description="Server-issued discovery session identifier.",
    )
    candidate_id: str = Field(
        ...,
        description="Profile id of the clicked orbit node.",
    )


class OrbitNodeDetailBaseOut(BaseModel):
    tab: DiscoveryTab
    id: str
    name: str | None = None
    age: int | None = None
    campus_branch: str | None = None
    campus_year: int | None = None
    campus_name: str | None = None
    role: str | None = None

    score: float = 0.0
    x: float = 0.0
    y: float = 0.0
    orbit_tier: int = 0
    profile_pic: str | None = None
    normal_pics: list[str] = Field(default_factory=list)


class OrbitNodeDetailDatingOut(OrbitNodeDetailBaseOut):
    display_gender: str | None = None
    display_sexuality: str | None = None
    pronouns: str | None = None
    drinking: str | None = None
    smoking: str | None = None
    hometown: str | None = None
    current_place: str | None = None
    partner_values: str | None = None
    children_plans: str | None = None
    religious_beliefs: str | None = None
    lifestyle: str | None = None

    activities: list[str] = Field(default_factory=list)
    looking_for: list[str] = Field(default_factory=list)
    causes_supported: list[str] = Field(default_factory=list)
    top_artists: list[str] = Field(default_factory=list)
    tech_skills: list[str] = Field(default_factory=list)
    languages: list[str] = Field(default_factory=list)
    ai_vibe_tags: list[str] = Field(default_factory=list)
    pets: list[str] = Field(default_factory=list)


class OrbitNodeDetailFriendsOut(OrbitNodeDetailBaseOut):
    hometown: str | None = None
    current_place: str | None = None
    pronouns: str | None = None
    lifestyle: str | None = None
    activities: list[str] = Field(default_factory=list)
    causes_supported: list[str] = Field(default_factory=list)
    top_artists: list[str] = Field(default_factory=list)
    languages: list[str] = Field(default_factory=list)
    ai_vibe_tags: list[str] = Field(default_factory=list)
    pets: list[str] = Field(default_factory=list)


class OrbitNodeDetailProfessionalOut(OrbitNodeDetailBaseOut):
    hometown: str | None = None
    current_place: str | None = None
    pronouns: str | None = None
    tech_skills: list[str] = Field(default_factory=list)
    languages: list[str] = Field(default_factory=list)
    causes_supported: list[str] = Field(default_factory=list)


OrbitNodeDetailResponse = (
    OrbitNodeDetailDatingOut
    | OrbitNodeDetailFriendsOut
    | OrbitNodeDetailProfessionalOut
)


class DiscoveryViewportRequest(BaseModel):
    session_id: str = Field(..., min_length=1)
    center_x: float
    center_y: float
    radius: float = Field(..., gt=0.0, le=2000.0)


class DiscoveryViewportResponse(BaseModel):
    session_id: str
    expires_at: datetime
    total_nodes: int
    nodes: list[OrbitNodeOut]


class AcceptTermsRequest(BaseModel):
    accepted_terms_version: str

    @field_validator("accepted_terms_version")
    @classmethod
    def validate_terms_version(cls, value: str) -> str:
        cleaned = value.strip()
        try:
            val_float = float(cleaned)
            curr_float = float(settings.current_terms_version)
            if val_float != curr_float:
                raise ValueError("You must accept the current terms version.")
        except ValueError as err:
            raise ValueError("You must accept the current terms version.") from err
        return cleaned


class AcceptTermsResponse(BaseModel):
    user_id: str
    accepted_terms_version: str
    terms_accepted_at: datetime
    terms_recorded: bool


class ProfileImagesUpdate(BaseModel):
    """
    Enforces structural client contract boundaries for media updates.
    Expects clean plaintext file paths within the secure bucket before
    backend processing.
    """
    profile_pic: str = Field(
        ...,
        description="Mandatory relative path to user avatar storage.",
    )
    normal_pics: list[str] = Field(
        ...,
        description="Array of normal gallery images.",
    )

    @field_validator("profile_pic")
    @classmethod
    def validate_avatar_presence(cls, value: str) -> str:
        if not value or not value.strip():
            raise ValueError(
                "Validation Error: Profile picture path is a mandatory "
                "onboarding field.",
            )
        return value.strip()

    @field_validator("normal_pics")
    @classmethod
    def validate_normal_pics_constraints(cls, value: list[str]) -> list[str]:
        cleaned_list = [v.strip() for v in value if v and v.strip()]
        total_count = len(cleaned_list)

        # Enforce your strict multi-photo design constraints
        if total_count < 1:
            raise ValueError(
                "Validation Error: At least one normal picture must be "
                "uploaded alongside your avatar.",
            )
        if total_count > 4:
            raise ValueError(
                "Validation Error: Up to 4 secondary gallery images are "
                "allowed inside this asset track.",
            )

        return cleaned_list


class ProfileImagesAndTagsUpdate(BaseModel):
    """
    Client contract model for on-device edge AI calculations.
    Ingests storage asset paths and computed text arrays directly.
    """
    profile_pic: str = Field(
        ...,
        description="Mandatory relative storage path to the user avatar image.",
    )
    normal_pics: list[str] = Field(
        ...,
        description="Array of up to 4 secondary gallery storage paths.",
    )
    ai_vibe_tags: list[str] = Field(
        ...,
        description="List of aesthetic tags extracted locally by on-device AI.",
    )

    @field_validator("profile_pic")
    @classmethod
    def validate_avatar_presence(cls, value: str) -> str:
        if not value or not value.strip():
            raise ValueError(
                "Validation Error: Profile picture storage location is mandatory.",
            )
        return value.strip()

    @field_validator("normal_pics")
    @classmethod
    def validate_normal_pics_constraints(cls, value: list[str]) -> list[str]:
        cleaned_list = [v.strip() for v in value if v and v.strip()]
        total_count = len(cleaned_list)

        if total_count < 1:
            raise ValueError(
                "Validation Error: At least one normal gallery image path "
                "is required.",
            )
        if total_count > 4:
            raise ValueError(
                "Validation Error: A maximum of 4 gallery images can be "
                "registered.",
            )
        return cleaned_list

    @field_validator("ai_vibe_tags")
    @classmethod
    def validate_vibe_tags_integrity(cls, value: list[str]) -> list[str]:
        # Defensive cleanup: strip whitespaces, convert to lowercase, remove duplicates
        cleaned_tags = list(set([
            t.strip().lower() for t in value if t and t.strip()
        ]))

        if len(cleaned_tags) < 1:
            raise ValueError(
                "Validation Error: On-device inference output must yield at "
                "least one valid vibe tag.",
            )
        if len(cleaned_tags) > 15:
            raise ValueError(
                "Validation Error: System safety bound exceeded. Maximum 15 "
                "vibe tags allowed.",
            )

        # Prevent injection attempts inside strings
        for tag in cleaned_tags:
            if not tag.isalnum() and "-" not in tag and "_" not in tag:
                raise ValueError(
                    f"Validation Error: Malformed characters detected in tag "
                    f"expression: '{tag}'",
                )

        return cleaned_tags
