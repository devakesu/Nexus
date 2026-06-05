from datetime import datetime
from typing import Literal, Union
from pydantic import BaseModel, Field, model_validator

from app.config import DiscoveryTab


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
    branch: str
    year: int
    age: int

    # Search and targeting bucket configuration.
    search_buckets: list[str] = Field(default_factory=list)
    dating_target_buckets: list[str] = Field(default_factory=list)
    friends_target_buckets: list[str] = Field(default_factory=list)
    professional_target_buckets: list[str] = Field(default_factory=list)

    # Optional decrypted scalar attributes.
    display_gender: str | None = None
    display_sexuality: str | None = None
    drinking: str | None = None
    smoking: str | None = None
    role: str | None = None
    hometown: str | None = None
    partner_values: str | None = None
    children_plans: str | None = None
    religious_beliefs: str | None = None
    lifestyle: str | None = None

    # Optional decrypted list attributes.
    activities: list[str] = Field(default_factory=list)
    looking_for: list[str] = Field(default_factory=list)
    causes_supported: list[str] = Field(default_factory=list)
    top_artists: list[str] = Field(default_factory=list)
    tech_skills: list[str] = Field(default_factory=list)
    languages: list[str] = Field(default_factory=list)
    ai_vibe_tags: list[str] = Field(default_factory=list)
    pets: list[str] = Field(default_factory=list)

    # Optional decrypted structured payloads.
    interests: dict[str, int] = Field(default_factory=dict)
    sub_interests: dict[str, list[str]] = Field(default_factory=dict)
    value_dimensions: dict[str, float] = Field(default_factory=dict)

    # Optional vector embeddings used by the ranking engine.
    identity_embedding: list[float] | None = None
    career_embedding: list[float] | None = None
    bio_embedding: list[float] | None = None


class DiscoveryFilters(BaseModel):
    """
    Structured filter payload for discovery candidate pool narrowing.

    This model constrains optional filter inputs and validates age bounds
    before any database filtering is executed.
    """

    # Optional categorical filters.
    years: list[int] | None = Field(
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
    branches: list[str] | None = Field(
        default=None,
        description="Target engineering branch categories.",
    )
    role: str | None = Field(
        default=None,
        max_length=100,
        description="Target professional role designation.",
    )

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
        description="Server-issued discovery session identifier for orbit-session reuse.",
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
        description="Required for tab-scoped actions; must be omitted for block/unblock.",
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
    nodes: list[OrbitNodeOut] = Field(default_factory=list)
    

class OrbitNodeDetailRequest(BaseModel):
    session_id: str = Field(..., description="Server-issued discovery session identifier.")
    candidate_id: str = Field(..., description="Profile id of the clicked orbit node.")


class OrbitNodeDetailBaseOut(BaseModel):
    tab: DiscoveryTab
    id: str
    name: str | None = None
    age: int | None = None
    branch: str | None = None
    year: int | None = None
    role: str | None = None

    score: float = 0.0
    x: float = 0.0
    y: float = 0.0
    orbit_tier: int = 0


class OrbitNodeDetailDatingOut(OrbitNodeDetailBaseOut):
    display_gender: str | None = None
    display_sexuality: str | None = None
    drinking: str | None = None
    smoking: str | None = None
    hometown: str | None = None
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
    lifestyle: str | None = None
    activities: list[str] = Field(default_factory=list)
    causes_supported: list[str] = Field(default_factory=list)
    top_artists: list[str] = Field(default_factory=list)
    languages: list[str] = Field(default_factory=list)
    ai_vibe_tags: list[str] = Field(default_factory=list)
    pets: list[str] = Field(default_factory=list)


class OrbitNodeDetailProfessionalOut(OrbitNodeDetailBaseOut):
    hometown: str | None = None
    tech_skills: list[str] = Field(default_factory=list)
    languages: list[str] = Field(default_factory=list)
    causes_supported: list[str] = Field(default_factory=list)

OrbitNodeDetailResponse = Union[
    OrbitNodeDetailDatingOut,
    OrbitNodeDetailFriendsOut,
    OrbitNodeDetailProfessionalOut,
]

class DiscoveryActionResponse(BaseModel):
    """
    Minimal success response for discovery action mutations.
    """

    success: bool = True