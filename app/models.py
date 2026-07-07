import re
from datetime import datetime
from typing import Annotated, Any, Literal

from pydantic import Base64Bytes, BaseModel, Field, field_validator, model_validator

from app.core.choices import (
    CAUSES_SUPPORTED_CHOICES,
    CHILDREN_PLANS_CHOICES,
    DRINKING_CHOICES,
    GENDER_CHOICES,
    LANGUAGES_CHOICES,
    PETS_CHOICES,
    PRONOUNS_CHOICES,
    RELIGIOUS_BELIEFS_CHOICES,
    SEXUALITY_CHOICES,
    SMOKING_CHOICES,
    VALID_INTERESTS,
)
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
    search_bucket: str = "NB"
    dating_target_buckets: list[str] = Field(default_factory=list)
    friends_target_buckets: list[str] = Field(default_factory=list)
    professional_target_buckets: list[str] = Field(default_factory=list)

    # Optional decrypted scalar attributes.
    display_gender: str | None = None
    display_sexuality: str | None = None
    pronouns: str | None = None
    drinking: str | None = None
    smoking: str | None = None
    role_at: str | None = None
    hometown: str | None = None
    current_place: str | None = None
    children_plans: str | None = None
    religious_beliefs: str | None = None
    profile_pic: str | None = None

    # Optional decrypted list attributes.
    partner_values: list[str] = Field(default_factory=list)
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
# Onboarding - Polymorphic models
# ---------------------------------------------------------------------------


def _validate_terms_version(value: str) -> str:
    cleaned = value.strip()
    try:
        float(cleaned)
    except ValueError as err:
        raise ValueError("accepted_terms_version must be a numeric string.") from err

    if cleaned != settings.current_terms_version.strip():
        raise ValueError("You must accept the current terms version.")
    return cleaned


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
        return _validate_terms_version(value)

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, value: str) -> str:
        cleaned = value.strip()
        if not re.match(r"^\+[1-9]\d{7,14}$", cleaned):
            raise ValueError(
                "Invalid phone number format. "
                "Must start with '+' followed by 8-15 digits (E.164 format).",
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
    age: int = Field(..., ge=18, le=80)
    lifestyle: str = Field(..., min_length=1)

    @field_validator("name")
    @classmethod
    def validate_name(cls, value: str) -> str:
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
    # DB-level blind index filters (new columns)
    children_plans: list[str] | None = Field(
        default=None,
        description=(
            "Acceptable children-plans values (multi-select; IN on HMAC blind index)."
        ),
    )
    religious_beliefs: list[str] | None = Field(
        default=None,
        description=(
            "Acceptable religious-belief values (multi-select; IN on HMAC blind index)."
        ),
    )

    # DB-level unencrypted filters
    dating_for: list[str] | None = Field(
        default=None,
        description=(
            "Target dating intent codes (GIN overlap on dating_for TEXT[] column)."
        ),
    )
    search_bucket_filter: list[str] | None = Field(
        default=None,
        description="Restrict candidates to specific search_bucket values (M/F/NB).",
    )

    # Post-fetch in-memory filters (encrypted fields - no blind indexes)
    languages: list[str] | None = Field(
        default=None,
        description="Candidate must speak at least one of these languages.",
    )
    sub_interests: list[str] | None = Field(
        default=None,
        description=(
            "Flat list of sub-interest values; candidate must have at least one."
        ),
    )
    role_type: list[str] | None = Field(
        default=None,
        description="Professional tab: candidate role_type must overlap.",
    )
    looking_for: list[str] | None = Field(
        default=None,
        description="Professional tab: candidate looking_for must overlap.",
    )
    causes_supported: list[str] | None = Field(
        default=None,
        description="Professional tab: candidate causes_supported must overlap.",
    )
    tech_skills: list[str] | None = Field(
        default=None,
        description="Professional tab: candidate tech_skills must overlap.",
    )
    partner_values: list[str] | None = Field(
        default=None,
        description=(
            "Dating tab: applied only when 'partner_values' is in dealbreaker_fields."
        ),
    )

    # Dealbreaker gate - hard-filter only when the field name is listed here
    dealbreaker_fields: list[str] | None = Field(
        default=None,
        description="Names of filter fields to enforce as strict dealbreakers.",
    )

    # Inclusive age bounds.
    # Upper bound is 80 to support the main variant's wider age range.
    min_age: int = Field(
        default=18,
        ge=18,
        le=80,
        description="Minimum age constraint boundary.",
    )
    max_age: int = Field(
        default=27,
        ge=18,
        le=80,
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

    @field_validator("target_id")
    @classmethod
    def validate_target_id_uuid(cls, v: str) -> str:
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("target_id must be a valid UUID") from e
        return v

    # Supported actions, including reversal operations.
    action: Literal[
        "pass",
        "hide",
        "like",
        "superlike",
        "block",
        "report",
        "unhide",
        "unlike",
        "unsuperlike",
        "unblock",
    ] = Field(
        ...,
        description="Discovery action or reversal action to apply.",
    )

    # Tab is required for tab-scoped actions and forbidden for block/report/unblock.
    tab: DiscoveryTab | None = Field(
        default=None,
        description=(
            "Required for tab-scoped actions; must be omitted for block/report/unblock."
        ),
    )

    # Report-specific fields - only valid when action == "report".
    reason: (
        Literal[
            "scam",
            "bot",
            "harassment",
            "inappropriate",
            "spam",
            "underage",
            "other",
        ]
        | None
    ) = Field(
        default=None,
        description="Reason code; required when action is report.",
    )

    reason_detail: str | None = Field(
        default=None,
        max_length=500,
        description="Free-text elaboration; required when reason is other.",
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

        # Global actions must not include tab context.
        tab_forbidden_actions = {"block", "unblock"}

        if self.action in tab_required_actions and self.tab is None:
            raise ValueError("tab is required for this action")

        if self.action in tab_forbidden_actions and self.tab is not None:
            raise ValueError("tab must be omitted for block/unblock")

        if self.action == "report":
            if self.reason is None:
                raise ValueError("reason is required for report")
            if self.reason == "other" and not (self.reason_detail or "").strip():
                raise ValueError("reason_detail is required when reason is other")

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
    profile_pic: str | None = None
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
    role_at: str | None = None

    score: float = 0.0
    x: float = 0.0
    y: float = 0.0
    orbit_tier: int = 0
    profile_pic: str | None = None

    # Common fields (all tabs)
    bio: str | None = None
    pronouns: str | None = None
    display_gender: str | None = None
    hometown: str | None = None
    current_place: str | None = None
    languages: list[str] = Field(default_factory=list)
    causes_supported: list[str] = Field(default_factory=list)
    interests: dict[str, Any] = Field(default_factory=dict)
    sub_interests: dict[str, Any] = Field(default_factory=dict)
    ai_vibe_tags: list[str] = Field(default_factory=list)


class OrbitNodeDetailDatingOut(OrbitNodeDetailBaseOut):
    display_sexuality: str | None = None
    drinking: str | None = None
    smoking: str | None = None
    lifestyle: str | None = None
    religious_beliefs: str | None = None
    partner_values: list[str] = Field(default_factory=list)
    children_plans: str | None = None
    dating_for: list[str] = Field(default_factory=list)
    normal_pics: list[str] = Field(default_factory=list)
    top_artists: list[str] = Field(default_factory=list)
    pets: list[str] = Field(default_factory=list)


class OrbitNodeDetailFriendsOut(OrbitNodeDetailBaseOut):
    display_sexuality: str | None = None
    drinking: str | None = None
    smoking: str | None = None
    lifestyle: str | None = None
    religious_beliefs: str | None = None
    normal_pics: list[str] = Field(default_factory=list)
    top_artists: list[str] = Field(default_factory=list)
    pets: list[str] = Field(default_factory=list)


class OrbitNodeDetailProfessionalOut(OrbitNodeDetailBaseOut):
    activities: list[str] = Field(default_factory=list)
    looking_for: list[str] = Field(default_factory=list)
    tech_skills: list[str] = Field(default_factory=list)


OrbitNodeDetailResponse = (
    OrbitNodeDetailDatingOut
    | OrbitNodeDetailFriendsOut
    | OrbitNodeDetailProfessionalOut
)


# ---------------------------------------------------------------------------
# Likes inbox
# ---------------------------------------------------------------------------


class LikeListItem(BaseModel):
    """One entry in the likes inbox - who liked the viewer and when."""

    actor_id: str
    action: Literal["like", "superlike"]
    created_at: datetime
    seen_at: datetime | None = None
    name: str | None = None
    age: int | None = None
    profile_pic: str | None = None


class LikesListResponse(BaseModel):
    likes: list[LikeListItem]
    unseen_count: int


class MarkLikesSeenRequest(BaseModel):
    """
    Mark one or more likes as seen.
    Set mark_all=True to mark every unseen like for the authenticated user.
    Otherwise supply a list of actor_ids to mark selectively.
    """

    actor_ids: list[str] = Field(default_factory=list)
    mark_all: bool = False
    tab: DiscoveryTab | None = None


class PeerProfileRequest(BaseModel):
    """
    Fetch the full profile detail for a specific user (e.g., from the likes inbox).
    """

    target_id: str = Field(..., min_length=1)
    tab: DiscoveryTab

    @field_validator("target_id")
    @classmethod
    def validate_target_id_uuid(cls, v: str) -> str:
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("target_id must be a valid UUID") from e
        return v


class LikeActionRequest(BaseModel):
    """Record an action from the likes inbox (no session required)."""

    target_id: str = Field(..., min_length=1)

    @field_validator("target_id")
    @classmethod
    def validate_target_id_uuid(cls, v: str) -> str:
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("target_id must be a valid UUID") from e
        return v

    action: Literal["like", "superlike", "pass", "hide", "block", "report"]
    tab: DiscoveryTab = "Dating"
    reason: (
        Literal[
            "scam",
            "bot",
            "harassment",
            "inappropriate",
            "spam",
            "underage",
            "other",
        ]
        | None
    ) = Field(
        default=None,
        description="Reason code; required when action is report.",
    )
    reason_detail: str | None = Field(
        default=None,
        max_length=500,
        description="Free-text elaboration; required when reason is other.",
    )

    @model_validator(mode="after")
    def validate_report_fields(self) -> "LikeActionRequest":
        if self.action == "report":
            if self.reason is None:
                raise ValueError("reason is required for report")
            if self.reason == "other" and not (self.reason_detail or "").strip():
                raise ValueError("reason_detail is required when reason is other")
        return self


# Matches
# ---------------------------------------------------------------------------


class MatchItem(BaseModel):
    match_id: str
    matched_user_id: str
    name: str | None = None
    age: int | None = None
    profile_pic: str | None = None
    matched_at: datetime


class MatchesListResponse(BaseModel):
    matches: list[MatchItem]


class MatchActionRequest(BaseModel):
    """Record an action on an active match (unmatch, block, or report)."""

    target_id: str = Field(..., min_length=1)

    @field_validator("target_id")
    @classmethod
    def validate_target_id_uuid(cls, v: str) -> str:
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("target_id must be a valid UUID") from e
        return v

    action: Literal["unmatch", "block", "report"]
    tab: DiscoveryTab = "Dating"
    reason: (
        Literal[
            "scam",
            "bot",
            "harassment",
            "inappropriate",
            "spam",
            "underage",
            "other",
        ]
        | None
    ) = Field(
        default=None,
        description="Reason code; required when action is report.",
    )
    reason_detail: str | None = Field(
        default=None,
        max_length=500,
        description="Free-text elaboration; required when reason is other.",
    )

    @model_validator(mode="after")
    def validate_report_fields(self) -> "MatchActionRequest":
        if self.action == "report":
            if self.reason is None:
                raise ValueError("reason is required for report")
            if self.reason == "other" and not (self.reason_detail or "").strip():
                raise ValueError("reason_detail is required when reason is other")
        return self


# Chats
# ---------------------------------------------------------------------------


class ChatConversationItem(BaseModel):
    conversation_id: str
    matched_user_id: str
    name: str | None = None
    age: int | None = None
    profile_pic: str | None = None
    last_message_at: datetime


class ChatsListResponse(BaseModel):
    conversations: list[ChatConversationItem]


class ChatCandidateItem(BaseModel):
    """A match with no conversation started yet - shown in the New Chat picker."""

    match_id: str
    matched_user_id: str
    name: str | None = None
    age: int | None = None
    profile_pic: str | None = None
    matched_at: datetime


class ChatCandidatesResponse(BaseModel):
    candidates: list[ChatCandidateItem]


class CreateChatRequest(BaseModel):
    match_id: str = Field(..., min_length=1)

    @field_validator("match_id")
    @classmethod
    def validate_match_id_uuid(cls, v: str) -> str:
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("match_id must be a valid UUID") from e
        return v


class CreateChatResponse(BaseModel):
    conversation_id: str
    matched_user_id: str
    tab: DiscoveryTab


# Signal Protocol key material
# ---------------------------------------------------------------------------


class UploadIdentityKeyRequest(BaseModel):
    identity_public_key: Base64Bytes
    registration_id: int = Field(..., ge=1, le=0x7FFFFFFF)


class UploadSignedPrekeyRequest(BaseModel):
    key_id: int = Field(..., ge=0)
    public_key: Base64Bytes
    signature: Base64Bytes


class OneTimePrekeyItem(BaseModel):
    key_id: int = Field(..., ge=0)
    public_key: Base64Bytes


class UploadOneTimePrekeysRequest(BaseModel):
    prekeys: list[OneTimePrekeyItem] = Field(..., min_length=1, max_length=200)


class OneTimePrekeyCountResponse(BaseModel):
    count: int


class KeyBundleResponse(BaseModel):
    user_id: str
    identity_public_key: Base64Bytes
    registration_id: int
    signed_prekey_id: int
    signed_prekey_public: Base64Bytes
    signed_prekey_signature: Base64Bytes
    one_time_prekey_id: int | None = None
    one_time_prekey_public: Base64Bytes | None = None


class EstablishSessionRequest(BaseModel):
    conversation_id: str = Field(..., min_length=1)

    @field_validator("conversation_id")
    @classmethod
    def validate_conversation_id_uuid(cls, v: str) -> str:
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("conversation_id must be a valid UUID") from e
        return v


# Chat messages
# ---------------------------------------------------------------------------


class SendMessageRequest(BaseModel):
    """A ciphertext envelope - the server never sees plaintext or keys."""

    message_type: Literal["text", "image", "voice", "event", "location"] = "text"
    ciphertext: str = Field(..., min_length=1, max_length=200_000)
    ciphertext_metadata: dict[str, Any] = Field(default_factory=dict)

    @field_validator("ciphertext")
    @classmethod
    def validate_base64(cls, v: str) -> str:
        import base64

        try:
            base64.b64decode(v, validate=True)
        except Exception as e:
            raise ValueError("ciphertext must be valid base64") from e
        return v


class SendMessageResponse(BaseModel):
    message_id: str
    created_at: datetime


# Presence & read receipts
# ---------------------------------------------------------------------------


class PresenceHeartbeatRequest(BaseModel):
    is_online: bool = True


class PresenceResponse(BaseModel):
    """is_online/last_active_at are both null if the peer has Active Status
    off, has no active match with the caller, or has never been active -
    these cases are deliberately indistinguishable from the outside."""

    is_online: bool | None = None
    last_active_at: datetime | None = None


class MarkMessagesReadResponse(BaseModel):
    marked_count: int


# Chat events (date/plan proposals)
# ---------------------------------------------------------------------------


class CreateEventRequest(BaseModel):
    """
    Balanced storage: event_time/location are plaintext (needed for
    reminder scheduling); title/notes travel as a ratchet-encrypted
    ciphertext envelope, identical to a normal text message.
    """

    event_time: datetime
    location_lat: float | None = Field(default=None, ge=-90, le=90)
    location_lng: float | None = Field(default=None, ge=-180, le=180)
    location_label: str | None = Field(default=None, max_length=200)
    ciphertext: str = Field(..., min_length=1, max_length=200_000)
    ciphertext_metadata: dict[str, Any] = Field(default_factory=dict)

    @field_validator("ciphertext")
    @classmethod
    def validate_base64(cls, v: str) -> str:
        import base64

        try:
            base64.b64decode(v, validate=True)
        except Exception as e:
            raise ValueError("ciphertext must be valid base64") from e
        return v


class EventResponse(BaseModel):
    event_id: str
    message_id: str
    conversation_id: str
    event_time: datetime
    location_lat: float | None = None
    location_lng: float | None = None
    location_label: str | None = None
    status: Literal["proposed", "confirmed", "cancelled"]
    created_at: datetime


class UpdateEventStatusRequest(BaseModel):
    status: Literal["confirmed", "cancelled"]


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
        return _validate_terms_version(value)


class AcceptTermsResponse(BaseModel):
    user_id: str
    accepted_terms_version: str
    terms_accepted_at: datetime
    terms_recorded: bool


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
        max_length=4,
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
        stripped = value.strip()
        if len(stripped) > 500:
            raise ValueError(
                "Validation Error: Profile picture path must be "
                "less than 500 characters.",
            )
        return stripped

    @field_validator("normal_pics")
    @classmethod
    def validate_normal_pics_constraints(cls, value: list[str]) -> list[str]:
        cleaned_list = [v.strip() for v in value if v and v.strip()]
        total_count = len(cleaned_list)

        if total_count < 1:
            raise ValueError(
                "Validation Error: At least one normal gallery image path is required.",
            )
        if total_count > 4:
            raise ValueError(
                "Validation Error: A maximum of 4 gallery images can be registered.",
            )
        for v in cleaned_list:
            if len(v) > 500:
                raise ValueError(
                    "Validation Error: Gallery image path must be "
                    "less than 500 characters.",
                )
        return cleaned_list

    @field_validator("ai_vibe_tags")
    @classmethod
    def validate_vibe_tags_integrity(cls, value: list[str]) -> list[str]:
        # Defensive cleanup: strip whitespaces, convert to lowercase, remove duplicates
        cleaned_tags = list(set([t.strip().lower() for t in value if t and t.strip()]))

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


class ProfileDetailsUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=4, max_length=100)
    age: int | None = Field(default=None, ge=18, le=80)
    campus_branch: str | None = Field(default=None, max_length=100)
    campus_year: int | None = None
    campus_name: str | None = Field(default=None, max_length=150)
    display_gender: str | None = Field(default=None, max_length=50)
    display_sexuality: str | None = Field(default=None, max_length=50)
    pronouns: str | None = Field(default=None, max_length=50)
    bio: str | None = Field(default=None, max_length=1000)
    search_bucket: Literal["M", "F", "NB", "Q"] | None = None
    hometown: str | None = Field(default=None, max_length=100)
    current_place: str | None = Field(default=None, max_length=100)
    partner_values: list[str] | None = Field(default=None)
    children_plans: str | None = Field(default=None, max_length=100)
    religious_beliefs: str | None = Field(default=None, max_length=100)
    lifestyle: str | None = Field(default=None, max_length=200)
    drinking: str | None = Field(default=None, max_length=50)
    smoking: str | None = Field(default=None, max_length=50)

    @field_validator("drinking")
    @classmethod
    def validate_drinking(cls, v: str | None) -> str | None:
        if v is not None and v not in DRINKING_CHOICES:
            raise ValueError(f"drinking must be one of {DRINKING_CHOICES}")
        return v

    @field_validator("smoking")
    @classmethod
    def validate_smoking(cls, v: str | None) -> str | None:
        if v is not None and v not in SMOKING_CHOICES:
            raise ValueError(f"smoking must be one of {SMOKING_CHOICES}")
        return v

    @field_validator("children_plans")
    @classmethod
    def validate_children_plans(cls, v: str | None) -> str | None:
        if v is not None and v not in CHILDREN_PLANS_CHOICES:
            raise ValueError(f"children_plans must be one of {CHILDREN_PLANS_CHOICES}")
        return v

    @field_validator("religious_beliefs")
    @classmethod
    def validate_religious_beliefs(cls, v: str | None) -> str | None:
        if v is not None and v not in RELIGIOUS_BELIEFS_CHOICES:
            raise ValueError(
                f"religious_beliefs must be one of {RELIGIOUS_BELIEFS_CHOICES}",
            )
        return v

    @field_validator("interests")
    @classmethod
    def validate_interests(cls, v: dict[str, int] | None) -> dict[str, int] | None:
        if v is None:
            return v
        for k, val in v.items():
            if k not in VALID_INTERESTS:
                raise ValueError(f"Invalid interest: {k}")
            if val < 1 or val > 5:
                raise ValueError(
                    f"Interest level for {k} must be an integer between 1 and 5",
                )
        return v

    @field_validator("sub_interests")
    @classmethod
    def validate_sub_interests(
        cls,
        v: dict[str, list[str]] | None,
    ) -> dict[str, list[str]] | None:
        if v is None:
            return v
        for k, subs in v.items():
            if k not in VALID_INTERESTS:
                raise ValueError(f"Invalid parent interest: {k}")
            allowed_subs = VALID_INTERESTS[k]
            for s in subs:
                if s not in allowed_subs:
                    raise ValueError(
                        f"Invalid sub-interest '{s}' for parent interest '{k}'",
                    )
        return v

    @field_validator("display_gender")
    @classmethod
    def validate_display_gender(cls, v: str | None) -> str | None:
        if v is not None and v not in GENDER_CHOICES:
            raise ValueError(f"display_gender must be one of {GENDER_CHOICES}")
        return v

    @field_validator("display_sexuality")
    @classmethod
    def validate_display_sexuality(cls, v: str | None) -> str | None:
        if v is not None and v not in SEXUALITY_CHOICES:
            raise ValueError(f"display_sexuality must be one of {SEXUALITY_CHOICES}")
        return v

    @field_validator("pronouns")
    @classmethod
    def validate_pronouns(cls, v: str | None) -> str | None:
        if v is not None and v not in PRONOUNS_CHOICES:
            raise ValueError(f"pronouns must be one of {PRONOUNS_CHOICES}")
        return v

    @field_validator("languages")
    @classmethod
    def validate_languages(cls, v: list[str] | None) -> list[str] | None:
        if v is not None:
            for lang in v:
                if lang not in LANGUAGES_CHOICES:
                    raise ValueError(f"Invalid language: {lang}")
        return v

    @field_validator("causes_supported")
    @classmethod
    def validate_causes_supported(cls, v: list[str] | None) -> list[str] | None:
        if v is not None:
            for cause in v:
                if cause not in CAUSES_SUPPORTED_CHOICES:
                    raise ValueError(f"Invalid cause: {cause}")
        return v

    @field_validator("pets")
    @classmethod
    def validate_pets(cls, v: list[str] | None) -> list[str] | None:
        if v is not None:
            for pet in v:
                if pet not in PETS_CHOICES:
                    raise ValueError(f"Invalid pet: {pet}")
        return v

    role_at: str | None = Field(default=None, max_length=150)
    profile_pic: str | None = Field(default=None, max_length=255)
    normal_pics: list[str] | None = None
    role_type: list[str] | None = None
    dating_target_buckets: list[str] | None = None
    dating_for: list[str] | None = None
    friends_target_buckets: list[str] | None = None
    professional_target_buckets: list[str] | None = None
    looking_for: list[str] | None = None
    activities: list[str] | None = None
    causes_supported: list[str] | None = None
    top_artists: list[str] | None = None
    tech_skills: list[str] | None = None
    languages: list[str] | None = None
    pets: list[str] | None = None
    interests: dict[str, int] | None = None
    sub_interests: dict[str, list[str]] | None = None
    is_dating_active: bool | None = None
    is_friends_active: bool | None = None
    is_professional_active: bool | None = None


class ModerationSubjectsRequest(BaseModel):
    target_ids: list[str] = Field(..., min_length=1, max_length=50)


# ---------------------------------------------------------------------------
# Profile field visibility / privacy settings
# ---------------------------------------------------------------------------

ALLOWED_HIDDEN_FIELDS: frozenset[str] = frozenset(
    {
        "display_gender",
        "display_sexuality",
        "pronouns",
        "current_place",
        "campus_branch",
        "religious_beliefs",
        "pets",
        "top_artists",
        "causes_supported",
        "hometown",
    },
)


class PrivacySettingsResponse(BaseModel):
    hidden_fields: list[str]
    share_active_status: bool
    share_read_receipts: bool


class PrivacySettingsUpdate(BaseModel):
    """All fields optional - PATCH only touches the ones provided."""

    hidden_fields: list[str] | None = None
    share_active_status: bool | None = None
    share_read_receipts: bool | None = None

    @field_validator("hidden_fields")
    @classmethod
    def validate_hidden_fields(cls, v: list[str] | None) -> list[str] | None:
        if v is None:
            return None
        for field in v:
            if field not in ALLOWED_HIDDEN_FIELDS:
                raise ValueError(
                    f"'{field}' is not a hideable field. "
                    f"Allowed: {sorted(ALLOWED_HIDDEN_FIELDS)}",
                )
        return list(set(v))


# ---------------------------------------------------------------------------
# Email notification preferences
# ---------------------------------------------------------------------------


class EmailNotificationSettingsResponse(BaseModel):
    email_notify_matches: bool
    email_notify_messages: bool
    email_notify_digest: bool
    email_notify_product_updates: bool
    email_notify_promotions: bool


class EmailNotificationSettingsUpdate(BaseModel):
    """All fields optional - PATCH only touches the ones provided."""

    email_notify_matches: bool | None = None
    email_notify_messages: bool | None = None
    email_notify_digest: bool | None = None
    email_notify_product_updates: bool | None = None
    email_notify_promotions: bool | None = None


# ---------------------------------------------------------------------------
# Device / push notification token registration
# ---------------------------------------------------------------------------


class RegisterDeviceRequest(BaseModel):
    """Register or refresh an FCM push token for the authenticated user's device."""

    fcm_token: str = Field(..., min_length=1)
    platform: Literal["android", "ios"] = "android"
    device_id: str | None = Field(
        default=None,
        description="Client-supplied stable device identifier (optional).",
    )


# ---------------------------------------------------------------------------
# Help, Feedback & Bug Report
# ---------------------------------------------------------------------------

_GITHUB_ISSUE_URL_RE = re.compile(r"^https://github\.com/[^/\s]+/[^/\s]+/issues/\d+/?$")


class FeedbackSubmitRequest(BaseModel):
    """Submit a Help, Feedback & Bug Report ticket."""

    query_type: Literal["help", "feedback", "bug_report"]
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
    device_info: dict[str, Any] = Field(default_factory=dict)

    @field_validator("subject", "message")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v

    @field_validator("github_issue_url")
    @classmethod
    def validate_github_issue_url(cls, v: str | None) -> str | None:
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
        if len(v) > 5:
            raise ValueError("attachment_paths supports at most 5 files")
        return v

    @model_validator(mode="after")
    def validate_github_url_scope(self) -> "FeedbackSubmitRequest":
        if self.github_issue_url and self.query_type != "bug_report":
            raise ValueError(
                "github_issue_url is only applicable to bug_report tickets",
            )
        return self


class FeedbackSubmitResponse(BaseModel):
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
    status: str
    note: str | None = None
    changed_by: str | None = None
    created_at: datetime


class FeedbackCommentEntry(BaseModel):
    id: str
    author_id: str
    body: str
    created_at: datetime
    is_own: bool


class FeedbackTicketDetail(BaseModel):
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
    body: str = Field(..., min_length=1, max_length=3000)

    @field_validator("body")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v


class FeedbackCloseRequest(BaseModel):
    reason: str = Field(..., min_length=3, max_length=1000)

    @field_validator("reason")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v
