import re
from datetime import datetime
from typing import Annotated, Literal

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

    @field_validator("campus_name")
    @classmethod
    def validate_campus_name(cls, value: str | None) -> str | None:
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
    user_id: str
    profile_created: bool
    profile: dict[str, object] = Field(exclude=True)


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
            if self.reason == "other":
                detail = self.reason_detail or ""
                alpha_chars = re.sub(r"[^a-zA-Z]", "", detail)
                if len(alpha_chars) < 5:
                    raise ValueError(
                        "reason_detail must contain at least 5 alphabetic "
                        "characters when reason is other",
                    )

        return self


class DiscoveryActionResponse(BaseModel):
    """
    Minimal success response for discovery action mutations.
    """

    success: bool = True


class OrbitNodeOut(BaseModel):
    """
    Lightweight node payload for rendering a profile on the orbit canvas.

    Carries just enough to identify a node at a glance (name, thumbnail);
    full profile details are still fetched only when the user taps a node.
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

    @field_validator("session_id", "candidate_id")
    @classmethod
    def validate_uuids(cls, v: str) -> str:
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError(f"Value must be a valid UUID: {v}") from e
        return v


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
    interests: dict[str, int] = Field(default_factory=dict)
    sub_interests: dict[str, list[str]] = Field(default_factory=dict)
    ai_vibe_tags: list[str] = Field(default_factory=list)

    music_match_grade: int | None = None
    viewer_spotify_connected: bool = False
    candidate_spotify_connected: bool = False


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
# Spotify - owner-only playlist detail. Never returned from any peer-facing
# endpoint (Orbit, likes inbox, discovery) - only from the owner-scoped
# routes in app/api/spotify.py. artist_affinity itself (the matching-engine
# signal) has no Pydantic model at all - it's never serialized in an API
# response, only read internally by app/db/profiles.py for scoring.
# ---------------------------------------------------------------------------


class SpotifyTrackOut(BaseModel):
    spotify_track_id: str | None = None
    name: str
    artists: list[str] = Field(default_factory=list)


class SpotifyPlaylistOut(BaseModel):
    id: str
    spotify_playlist_id: str
    name: str
    is_collaborative: bool
    track_count: int
    tracks: list[SpotifyTrackOut] = []
    synced_at: datetime | None = None
    spotify_url: str


class SpotifyPlaylistsResponse(BaseModel):
    connected: bool
    last_synced_at: datetime | None = None
    playlists: list[SpotifyPlaylistOut] = []


class SpotifyStatusResponse(BaseModel):
    connected: bool
    last_synced_at: datetime | None = None
    playlist_count: int = 0


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

    actor_ids: list[str] = Field(default_factory=list, max_length=1000)
    mark_all: bool = False
    tab: DiscoveryTab | None = None

    @field_validator("actor_ids")
    @classmethod
    def validate_uuids(cls, v: list[str]) -> list[str]:
        import uuid

        for x in v:
            try:
                uuid.UUID(x)
            except ValueError as e:
                raise ValueError(f"Invalid UUID: {x}") from e
        return v


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
    tab: DiscoveryTab
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
            if self.reason == "other":
                detail = self.reason_detail or ""
                alpha_chars = re.sub(r"[^a-zA-Z]", "", detail)
                if len(alpha_chars) < 5:
                    raise ValueError(
                        "reason_detail must contain at least 5 alphabetic "
                        "characters when reason is other",
                    )
        return self


class LikeActionResponse(BaseModel):
    success: bool = True
    matched: bool = False
    match_id: str | None = None


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
    tab: DiscoveryTab
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
            if self.reason == "other":
                detail = self.reason_detail or ""
                alpha_chars = re.sub(r"[^a-zA-Z]", "", detail)
                if len(alpha_chars) < 5:
                    raise ValueError(
                        "reason_detail must contain at least 5 alphabetic "
                        "characters when reason is other",
                    )
        return self


class MatchActionResponse(BaseModel):
    success: bool = True


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
    ciphertext_metadata: dict[str, str | int | bool | None] = Field(
        default_factory=dict,
        max_length=20,
        description="Bounded Signal protocol metadata (string/int/bool values only).",
    )

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
    ciphertext_metadata: dict[str, str | int | bool | None] = Field(
        default_factory=dict,
        max_length=20,
        description="Bounded Signal protocol metadata (string/int/bool values only).",
    )
    # Meetup Safety auto-configure (Milestone F) - personal to whichever
    # participant creates the event, not shared conversation state.
    safety_enabled: bool = False
    safety_interval_seconds: int | None = Field(default=None, gt=0, le=86400)

    @field_validator("ciphertext")
    @classmethod
    def validate_base64(cls, v: str) -> str:
        import base64

        try:
            base64.b64decode(v, validate=True)
        except Exception as e:
            raise ValueError("ciphertext must be valid base64") from e
        return v

    @model_validator(mode="after")
    def validate_safety_interval(self) -> "CreateEventRequest":
        if self.safety_enabled and self.safety_interval_seconds is None:
            raise ValueError(
                "safety_interval_seconds is required when safety_enabled is set",
            )
        return self


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
    safety_enabled: bool = False
    safety_interval_seconds: int | None = None


class UpdateEventStatusRequest(BaseModel):
    status: Literal["confirmed", "cancelled"]


class DiscoveryViewportRequest(BaseModel):
    session_id: str = Field(..., min_length=1)
    center_x: float
    center_y: float
    radius: float = Field(..., gt=0.0, le=2000.0)

    @field_validator("session_id")
    @classmethod
    def validate_session_id_uuid(cls, v: str) -> str:
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("session_id must be a valid UUID") from e
        return v


class DiscoveryViewportResponse(BaseModel):
    session_id: str
    expires_at: datetime
    total_nodes: int
    nodes: list[OrbitNodeOut]


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
        return _validate_terms_version(value)


class ConsentUpdateResponse(BaseModel):
    user_id: str
    accepted_terms_version: str | None = None
    terms_accepted_at: datetime | None = None
    special_category_consent_version: str | None = None
    special_category_consent_at: datetime | None = None
    safety_data_consent_version: str | None = None
    safety_data_consent_at: datetime | None = None


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
        # Allow empty normal_pics (e.g. when only avatar is set)
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

        # Prevent injection attempts inside strings and enforce individual
        # tag length constraints.
        for tag in cleaned_tags:
            if len(tag) > 30:
                raise ValueError(
                    f"Validation Error: Vibe tag expression exceeds maximum safety "
                    f"limit of 30 characters: '{tag}'",
                )
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

    @field_validator("campus_name")
    @classmethod
    def validate_campus_name(cls, value: str | None) -> str | None:
        if value is None:
            return value
        cleaned = value.strip()
        if not cleaned:
            return ""
        if sum(c.isalpha() for c in cleaned) < 3:
            raise ValueError("Institute name must contain at least three letters.")
        return cleaned

    @field_validator("bio")
    @classmethod
    def validate_bio(cls, value: str | None) -> str | None:
        if value is None:
            return value
        cleaned = value.strip()
        if not cleaned:
            return ""
        if sum(c.isalpha() for c in cleaned) < 3:
            raise ValueError("Bio must contain at least three alphabetic characters.")
        return cleaned

    @model_validator(mode="after")
    def check_campus_year_needs_name(self) -> "ProfileDetailsUpdate":
        if (
            self.campus_year is not None
            and self.campus_name is not None
            and not self.campus_name.strip()
        ):
            raise ValueError("Cannot select a campus year when institute is empty.")
        return self

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


class ProfileDetailsResponse(BaseModel):
    name: str | None = None
    age: int | None = None
    campus_year: int | None = None
    campus_branch: str | None = None
    campus_name: str | None = None
    display_gender: str | None = None
    display_sexuality: str | None = None
    pronouns: str | None = None
    bio: str = ""
    search_bucket: str = "NB"
    hometown: str | None = None
    current_place: str | None = None
    partner_values: list[str] = Field(default_factory=list)
    children_plans: str | None = None
    religious_beliefs: str | None = None
    lifestyle: str | None = None
    drinking: str | None = None
    smoking: str | None = None
    role_at: str | None = None
    role_type: list[str] = Field(default_factory=list)
    dating_target_buckets: list[str] = Field(default_factory=list)
    dating_for: list[str] = Field(default_factory=list)
    friends_target_buckets: list[str] = Field(default_factory=list)
    professional_target_buckets: list[str] = Field(default_factory=list)
    looking_for: list[str] = Field(default_factory=list)
    activities: list[str] = Field(default_factory=list)
    causes_supported: list[str] = Field(default_factory=list)
    top_artists: list[str] = Field(default_factory=list)
    tech_skills: list[str] = Field(default_factory=list)
    languages: list[str] = Field(default_factory=list)
    pets: list[str] = Field(default_factory=list)
    interests: dict[str, int] = Field(default_factory=dict)
    sub_interests: dict[str, list[str]] = Field(default_factory=dict)
    ordered_images: list[str] = Field(default_factory=list)
    ai_vibe_tags: list[str] = Field(default_factory=list)
    is_dating_active: bool = False
    is_friends_active: bool = False
    is_professional_active: bool = False
    age_changes_used_in_window: int = 0
    age_change_eligible: bool = True
    age_next_eligible_at: str | None = None
    name_changes_used_in_window: int = 0
    name_change_eligible: bool = True
    name_next_eligible_at: str | None = None


class ProfileUpdateResponse(BaseModel):
    status: str
    detail: str


class ModerationSubjectItem(BaseModel):
    id: str
    name: str | None = None
    age: int | None = None
    campus_year: int | None = None
    campus_name: str | None = None
    campus_branch: str | None = None
    hometown: str | None = None
    current_place: str | None = None
    profile_pic: str | None = None


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
    device_info: dict[str, str | int | bool | None] = Field(
        default_factory=dict,
        max_length=30,
    )

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


# ---------------------------------------------------------------------------
# Meetup Safety
# ---------------------------------------------------------------------------


class SafetyContactIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    phone: str = Field(..., min_length=8, max_length=20)

    @field_validator("name")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v

    @field_validator("phone")
    @classmethod
    def validate_phone(cls, v: str) -> str:
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
    lat: float
    lng: float


class SafetyAlertRequest(BaseModel):
    alert_type: Literal["sos_silent", "sos_loud", "inform"]
    session_id: str | None = None

    @field_validator("session_id")
    @classmethod
    def validate_session_id_uuid(cls, v: str | None) -> str | None:
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
    id: str
    contacts_notified: int
    contacts_total: int


class SafetyEvidenceRegisterRequest(BaseModel):
    alert_id: str
    storage_path: str = Field(..., max_length=500)
    media_key_base64: str = Field(..., max_length=500)
    content_type: Literal["video", "audio"]
    duration_seconds: float | None = None


class SafetyEvidenceRegisterResponse(BaseModel):
    id: str


# ---------------------------------------------------------------------------
# Meetup Safety - recurring session mirror (Milestone D: dead-man's-switch)
# ---------------------------------------------------------------------------


class SafetySessionStartRequest(BaseModel):
    interval_seconds: int = Field(..., gt=0, le=86400)
    label: str | None = Field(default=None, max_length=200)
    event_label: str | None = Field(default=None, max_length=200)
    next_checkin_at: datetime
    battery_percent: int | None = Field(default=None, ge=0, le=100)
    connection_type: Literal["wifi", "cellular", "offline"] | None = None


class SafetySessionStartResponse(BaseModel):
    id: str


class SafetySessionCheckinRequest(BaseModel):
    session_id: str = Field(..., min_length=1)

    @field_validator("session_id")
    @classmethod
    def validate_session_id_uuid(cls, v: str) -> str:
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
    session_id: str = Field(..., min_length=1)

    @field_validator("session_id")
    @classmethod
    def validate_session_id_uuid(cls, v: str) -> str:
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("session_id must be a valid UUID") from e
        return v


# ---------------------------------------------------------------------------
# Account phone verification - independent of Supabase Auth's Phone provider
# (disabled, since it doubled as a login credential with no way to keep
# verification without also keeping phone-based sign-in). See
# app/core/account_phone_otp.py.
# ---------------------------------------------------------------------------


class AccountPhoneOtpRequestRequest(BaseModel):
    phone: str = Field(..., min_length=8, max_length=20)

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


class AccountPhoneOtpRequestResponse(BaseModel):
    sent: bool = True


class AccountPhoneOtpVerifyRequest(BaseModel):
    phone: str = Field(..., min_length=8, max_length=20)
    # Exactly 6 digits, matching generate_otp_code() - rejecting malformed
    # input here (a 422) rather than letting it consume one of the 5
    # precious verify attempts against a code that could never have matched.
    code: str = Field(..., pattern=r"^\d{6}$")

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


class AccountPhoneOtpVerifyResponse(BaseModel):
    verified: bool = True
    mobile: str
    mobile_verified_at: datetime


# ---------------------------------------------------------------------------
# Phone-as-username login - phone number is only ever a lookup key here.
# The OTP itself always goes to the resolved account's verified EMAIL, never
# SMS, so this doesn't reintroduce the phone-as-login-credential surface the
# Phone auth provider was disabled to close. Unauthenticated (this IS the
# sign-in flow - there's no session yet), gated by App Check instead.
# ---------------------------------------------------------------------------


class LoginByPhoneRequestRequest(BaseModel):
    phone: str = Field(..., min_length=8, max_length=20)

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


class LoginByPhoneRequestResponse(BaseModel):
    """Always {"sent": true} regardless of whether the phone actually
    matched an account - same anti-enumeration principle as
    SafetyPortalOtpRequestResponse.
    """

    sent: bool = True


class LoginByPhoneVerifyRequest(BaseModel):
    phone: str = Field(..., min_length=8, max_length=20)
    code: str = Field(..., min_length=4, max_length=10)

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


class LoginByPhoneVerifyResponse(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int


# ---------------------------------------------------------------------------
# Account deletion (self-serve). Reauth (email OTP) is a dedicated step,
# separate from the deletion request itself - see app/api/account_deletion.py
# and app/db/account_deletion.py.
# ---------------------------------------------------------------------------


class AccountDeletionSettingsResponse(BaseModel):
    grace_period_days: int
    blocklist_cooldown_days: int
    long_tail_purge_days: int
    safety_evidence_active_retention_days: int
    safety_data_legal_hold_days: int


class AccountDeletionOtpRequestResponse(BaseModel):
    sent: bool = True


class AccountDeletionOtpVerifyRequest(BaseModel):
    # Rides Supabase's native email OTP (AppConfig.otpLength on the client),
    # not the 6-digit SMS-based account_phone_otp system - see
    # app/core/passwordless_email.py.
    code: str = Field(..., min_length=4, max_length=10)


class AccountDeletionOtpVerifyResponse(BaseModel):
    verified: bool = True


class AccountDeletionRequestRequest(BaseModel):
    confirmation_text: str = Field(..., max_length=50)


class AccountDeletionRequestResponse(BaseModel):
    scheduled_purge_at: datetime


class AccountDeletionCancelResponse(BaseModel):
    reactivated: bool = True


# ---------------------------------------------------------------------------
# Personal data export (DPDP §11 / GDPR Art 20) - same OTP-reauth pattern as
# account deletion, since dumping all of a user's PII is comparably
# sensitive. See app/db/export.py.
# ---------------------------------------------------------------------------


class DataExportOtpRequestResponse(BaseModel):
    sent: bool = True


class DataExportOtpVerifyRequest(BaseModel):
    code: str = Field(..., min_length=4, max_length=10)


class DataExportOtpVerifyResponse(BaseModel):
    verified: bool = True


# ---------------------------------------------------------------------------
# Meetup Safety - OTP-gated trusted-contact web portal (Milestone E)
# ---------------------------------------------------------------------------


class SafetyPortalOtpRequestRequest(BaseModel):
    phone: str = Field(..., min_length=6, max_length=20)

    @field_validator("phone")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
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
    phone: str = Field(..., min_length=6, max_length=20)
    # Exactly 6 digits, matching generate_otp_code() - rejecting malformed
    # input here (a 422) rather than letting it consume one of the 5
    # precious verify attempts against a code that could never have matched.
    code: str = Field(..., pattern=r"^\d{6}$")

    @field_validator("phone")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v


class SafetyPortalOtpVerifyResponse(BaseModel):
    token: str
    expires_in: int


class SafetyPortalEvidenceItem(BaseModel):
    id: str
    content_type: Literal["video", "audio"]
    duration_seconds: float | None = None
    download_url: str
    media_key_base64: str
    created_at: datetime


class SafetyPortalDetailsResponse(BaseModel):
    label: str | None = None
    event_label: str | None = None
    status: Literal["active", "ended"]
    last_location: SafetyLocation | None = None
    last_location_at: datetime | None = None
    evidence: list[SafetyPortalEvidenceItem] = []


# ---------------------------------------------------------------------------
# Trusted-contact self-removal portal - a trusted contact has no Nexus
# account (same "no auth dependency stack, OTP + rate limiting is the
# actual boundary" posture as the SOS portal above), reached from the
# one-time notice SMS sent the first time their number is synced. See
# app/api/safety_portal.py and app/db/safety.py.
# ---------------------------------------------------------------------------


class SafetyContactPortalOtpRequestRequest(BaseModel):
    phone: str = Field(..., min_length=6, max_length=20)

    @field_validator("phone")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
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
    phone: str = Field(..., min_length=6, max_length=20)
    code: str = Field(..., pattern=r"^\d{6}$")

    @field_validator("phone")
    @classmethod
    def strip_and_require_non_blank(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("must not be blank")
        return v


class SafetyContactPortalOtpVerifyResponse(BaseModel):
    token: str
    expires_in: int


class SafetyContactPortalDetailsResponse(BaseModel):
    user_name: str
    profile_pic: str | None = None
    hometown: str | None = None
    current_place: str | None = None


class SafetyContactPortalRemoveResponse(BaseModel):
    removed: bool = True
