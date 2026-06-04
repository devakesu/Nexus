from typing import Dict, List, Literal, Optional
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
    search_buckets: List[str] = Field(default_factory=list)
    dating_target_buckets: List[str] = Field(default_factory=list)
    friends_target_buckets: List[str] = Field(default_factory=list)
    professional_target_buckets: List[str] = Field(default_factory=list)

    # Optional decrypted scalar attributes.
    display_gender: Optional[str] = None
    display_sexuality: Optional[str] = None
    drinking: Optional[str] = None
    smoking: Optional[str] = None
    role: Optional[str] = None
    hometown: Optional[str] = None
    partner_values: Optional[str] = None
    children_plans: Optional[str] = None
    religious_beliefs: Optional[str] = None
    lifestyle: Optional[str] = None

    # Optional decrypted list attributes.
    activities: List[str] = Field(default_factory=list)
    looking_for: List[str] = Field(default_factory=list)
    causes_supported: List[str] = Field(default_factory=list)
    top_artists: List[str] = Field(default_factory=list)
    tech_skills: List[str] = Field(default_factory=list)
    languages: List[str] = Field(default_factory=list)
    ai_vibe_tags: List[str] = Field(default_factory=list)
    pets: List[str] = Field(default_factory=list)

    # Optional decrypted structured payloads.
    interests: Dict[str, int] = Field(default_factory=dict)
    sub_interests: Dict[str, List[str]] = Field(default_factory=dict)
    value_dimensions: Dict[str, float] = Field(default_factory=dict)

    # Optional vector embeddings used by the ranking engine.
    identity_embedding: Optional[List[float]] = None
    career_embedding: Optional[List[float]] = None
    bio_embedding: Optional[List[float]] = None


class DiscoveryFilters(BaseModel):
    """
    Structured filter payload for discovery candidate narrowing.

    This model constrains optional filter inputs and validates age bounds
    before any database filtering is executed.
    """

    # Optional categorical filters.
    years: Optional[List[int]] = Field(
        default=None,
        description="Array of target campus academic years.",
    )
    drinking: Optional[List[str]] = Field(
        default=None,
        description="Target drinking lifestyle profiles.",
    )
    smoking: Optional[List[str]] = Field(
        default=None,
        description="Target smoking lifestyle profiles.",
    )
    branches: Optional[List[str]] = Field(
        default=None,
        description="Target engineering branch categories.",
    )
    role: Optional[str] = Field(
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
    Request payload for the discovery feed endpoint.

    A new discovery session is created when session_id is omitted.
    When session_id is provided, the request continues pagination
    within the same frozen ranked snapshot.
    """

    # Active discovery tab controls the matching pipeline branch.
    tab: DiscoveryTab = Field(
        ...,
        description="Target matching pipeline matrix.",
    )

    # Optional filters default to an empty object for unfiltered discovery.
    filters: DiscoveryFilters = Field(
        default_factory=DiscoveryFilters,
        description="Dynamic compound filter parameters configuration.",
    )

    # limit controls page size only, not ranking depth.
    limit: int = Field(
        default=20,
        ge=1,
        le=20,
        description="Maximum number of ranked profiles to return in one page.",
    )

    # session_id is reused to continue pagination inside a frozen snapshot.
    session_id: Optional[str] = Field(
        default=None,
        description="Server-issued discovery session identifier for stable pagination across an existing ranked snapshot.",
    )

    # cursor is the zero-based continuation offset in the session snapshot.
    cursor: int = Field(
        default=0,
        ge=0,
        description="Zero-based continuation offset within the current discovery session snapshot.",
    )


class FeedItemOut(BaseModel):
    """
    Sanitized discovery-card payload returned to the client.

    This model exposes only the minimal fields needed to render a feed card.
    """

    # Stable profile identifier used for rendering and follow-up actions.
    id: Optional[str] = None

    # Basic card identity fields.
    name: Optional[str] = None
    branch: Optional[str] = None
    year: Optional[int] = None

    # Optional display metadata.
    display_gender: Optional[str] = None
    display_sexuality: Optional[str] = None
    role: Optional[str] = None

    # Frozen ranking score captured when the session was created.
    score: Optional[float] = None


class DiscoverResponse(BaseModel):
    """
    Paginated discovery feed response.

    Returns the current page plus the session identifier and
    continuation metadata needed for the next request.
    """

    # Session identifier reused by the client for stable pagination.
    session_id: str = Field(
        ...,
        description="Server-issued identifier for the current discovery session snapshot.",
    )

    # Feed payload for the current page.
    feed: List[FeedItemOut] = Field(default_factory=list)

    # True when additional results remain in the same session.
    has_more: bool = Field(
        ...,
        description="Whether more ranked results are available after this page within the same discovery session.",
    )

    # Continuation cursor for the next page; null when exhausted.
    next_cursor: Optional[int] = Field(
        default=None,
        description="Zero-based continuation offset to request the next page from the same discovery session.",
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


class DiscoveryActionResponse(BaseModel):
    """
    Minimal success response for discovery action mutations.
    """

    success: bool = True