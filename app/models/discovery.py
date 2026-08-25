"""Discovery filters, action requests, orbit card, and viewport Pydantic models."""

import re
from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator

from app.core.config import DiscoveryTab


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
        """Executes validate age range operation.

            Returns:
                'DiscoveryFilters': Response payload or result."""
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


ReportReason = Literal[
    "scam",
    "bot",
    "harassment",
    "inappropriate",
    "spam",
    "underage",
    "other",
]


class BaseActionRequest(BaseModel):
    """Standardized action and moderation envelope shared across discovery and match contexts."""

    target_id: str = Field(
        ...,
        min_length=1,
        description="Profile id of the candidate the action applies to.",
    )
    tab: DiscoveryTab | None = Field(
        default=None,
        description="Discovery tab context when action is scoped to a specific surface.",
    )
    conversation_id: str | None = Field(
        default=None,
        description="Optional conversation id if the action is linked to a chat.",
    )
    reason: ReportReason | None = Field(
        default=None,
        description="Reason code; required when action is report.",
    )
    reason_detail: str | None = Field(
        default=None,
        max_length=500,
        description="Free-text elaboration; required when reason is other.",
    )
    evidence: list[dict[str, Any]] | None = Field(
        default=None,
        description="Optional structured report evidence (e.g. client-decrypted transcripts/franking).",
    )

    @field_validator("target_id")
    @classmethod
    def validate_target_id_uuid(cls, v: str) -> str:
        """Validates that target_id is a valid UUID."""
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("target_id must be a valid UUID") from e
        return v

    @field_validator("conversation_id")
    @classmethod
    def validate_conversation_id_uuid(cls, v: str | None) -> str | None:
        """Validates that conversation_id is a valid UUID if provided."""
        if v is None:
            return None
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("conversation_id must be a valid UUID") from e
        return v

    def validate_report_invariants(self, action: str) -> None:
        """Validates reporting requirements if action is 'report'."""
        if action == "report":
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


class DiscoveryActionRequest(BaseActionRequest):
    """
    Request payload for applying a discovery action to a target profile.
    """

    # Supported actions, including reversal operations.
    action: Literal[
        "pass",
        "hide",
        "like",
        "superlike",
        "block",
        "report",
        "unpass",
        "unhide",
        "unblock",
    ] = Field(
        ...,
        description="Discovery action or reversal action to apply.",
    )

    @model_validator(mode="after")
    def validate_tab_requirements(self) -> "DiscoveryActionRequest":
        """Executes validate tab requirements operation.

            Returns:
                'DiscoveryActionRequest': Response payload or result."""
        # Actions scoped to a discovery tab must include tab context.
        tab_required_actions = {
            "pass",
            "hide",
            "like",
            "superlike",
            "unpass",
            "unhide",
        }

        if self.action in tab_required_actions and self.tab is None:
            raise ValueError("tab is required for this action")

        self.validate_report_invariants(self.action)
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
    """Orbitnodedetailrequest class representation."""
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
        """Executes validate uuids operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError(f"Value must be a valid UUID: {v}") from e
        return v


class OrbitNodeDetailBaseOut(BaseModel):
    """Orbitnodedetailbaseout class representation."""
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
    """Orbitnodedetaildatingout class representation."""
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
    """Orbitnodedetailfriendsout class representation."""
    display_sexuality: str | None = None
    drinking: str | None = None
    smoking: str | None = None
    lifestyle: str | None = None
    religious_beliefs: str | None = None
    normal_pics: list[str] = Field(default_factory=list)
    top_artists: list[str] = Field(default_factory=list)
    pets: list[str] = Field(default_factory=list)


class OrbitNodeDetailProfessionalOut(OrbitNodeDetailBaseOut):
    """Orbitnodedetailprofessionalout class representation."""
    activities: list[str] = Field(default_factory=list)
    looking_for: list[str] = Field(default_factory=list)
    tech_skills: list[str] = Field(default_factory=list)


OrbitNodeDetailResponse = (
    OrbitNodeDetailDatingOut
    | OrbitNodeDetailFriendsOut
    | OrbitNodeDetailProfessionalOut
)


class DiscoveryViewportRequest(BaseModel):
    """Discoveryviewportrequest class representation."""
    tab: DiscoveryTab = Field(
        ...,
        description="Target matching pipeline matrix ('Dating', 'Friends', or 'Professional').",
    )
    session_id: str = Field(..., min_length=1)
    center_x: float = Field(..., ge=-5000.0, le=5000.0)
    center_y: float = Field(..., ge=-5000.0, le=5000.0)
    radius: float = Field(..., gt=0.0, le=2000.0)

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


class DiscoveryViewportResponse(BaseModel):
    """Discoveryviewportresponse class representation."""
    session_id: str
    expires_at: datetime
    total_nodes: int = 0
    nodes: list[OrbitNodeOut]


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
    """Likeslistresponse class representation."""
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
        """Executes validate uuids operation.

            Args:
                v: Input v parameter.

            Returns:
                list[str]: Response payload or result."""
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
        """Executes validate target id uuid operation.

            Args:
                v: Input v parameter.

            Returns:
                str: Response payload or result."""
        import uuid

        try:
            uuid.UUID(v)
        except ValueError as e:
            raise ValueError("target_id must be a valid UUID") from e
        return v


class LikeActionRequest(BaseActionRequest):
    """Record an action from the likes inbox (no session required)."""

    action: Literal["like", "superlike", "pass", "hide", "block", "report"]
    tab: DiscoveryTab | None = None

    @model_validator(mode="after")
    def validate_report_fields(self) -> "LikeActionRequest":
        """Executes validate report fields operation.

            Returns:
                'LikeActionRequest': Response payload or result."""
        if self.action not in ("block", "report") and self.tab is None:
            raise ValueError("tab is required for this action")
        self.validate_report_invariants(self.action)
        return self


class LikeActionResponse(BaseModel):
    """Likeactionresponse class representation."""
    success: bool = True
    matched: bool = False
    match_id: str | None = None


class MatchItem(BaseModel):
    """Matchitem class representation."""
    match_id: str
    matched_user_id: str
    name: str | None = None
    age: int | None = None
    profile_pic: str | None = None
    matched_at: datetime


class MatchesListResponse(BaseModel):
    """Matcheslistresponse class representation."""
    matches: list[MatchItem]


class MatchActionRequest(BaseActionRequest):
    """Record an action on an active match (unmatch, block, or report)."""

    action: Literal["unmatch", "block", "report"]

    @model_validator(mode="after")
    def validate_action_fields(self) -> "MatchActionRequest":
        """Executes validate action fields operation.

            Returns:
                'MatchActionRequest': Response payload or result."""
        if self.action == "unmatch" and self.tab is None:
            raise ValueError("tab is required for unmatch")
        self.validate_report_invariants(self.action)
        return self


class MatchActionResponse(BaseModel):
    """Matchactionresponse class representation."""
    success: bool = True
