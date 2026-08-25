"""ProfileModel and profile update request/response Pydantic models."""

from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator

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
        """Executes validate avatar presence operation.

            Args:
                value: Input value parameter.

            Returns:
                str: Response payload or result."""
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
        if (
            ".." in stripped
            or "\\" in stripped
            or stripped.startswith("/")
            or "\x00" in stripped
        ):
            raise ValueError(
                "Validation Error: Profile picture path contains invalid characters or traversal sequences.",
            )
        return stripped

    @field_validator("normal_pics")
    @classmethod
    def validate_normal_pics_constraints(cls, value: list[str]) -> list[str]:
        """Executes validate normal pics constraints operation.

            Args:
                value: Input value parameter.

            Returns:
                list[str]: Response payload or result."""
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
            if (
                ".." in v
                or "\\" in v
                or v.startswith("/")
                or "\x00" in v
            ):
                raise ValueError(
                    "Validation Error: Gallery image path contains invalid characters or traversal sequences.",
                )
        return cleaned_list

    @field_validator("ai_vibe_tags")
    @classmethod
    def validate_vibe_tags_integrity(cls, value: list[str]) -> list[str]:
        """Executes validate vibe tags integrity operation.

            Args:
                value: Input value parameter.

            Returns:
                list[str]: Response payload or result."""
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
    """Profiledetailsupdate class representation."""
    name: str | None = Field(default=None, min_length=4, max_length=100)
    age: int | None = Field(default=None, ge=18, le=80)
    campus_branch: str | None = Field(default=None, max_length=100)
    campus_year: int | None = None
    campus_name: str | None = Field(default=None, max_length=150)
    display_gender: str | None = Field(default=None, max_length=50)
    display_sexuality: str | None = Field(default=None, max_length=50)
    pronouns: str | None = Field(default=None, max_length=50)
    bio: str | None = Field(default=None, max_length=1000)
    search_bucket: Literal["M", "F", "NB"] | None = None
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
        """Executes validate campus name operation.

            Args:
                value: Input value parameter.

            Returns:
                str | None: Response payload or result."""
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
        """Executes validate bio operation.

            Args:
                value: Input value parameter.

            Returns:
                str | None: Response payload or result."""
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
        """Executes check campus year needs name operation.

            Returns:
                'ProfileDetailsUpdate': Response payload or result."""
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
        """Executes validate drinking operation.

            Args:
                v: Input v parameter.

            Returns:
                str | None: Response payload or result."""
        if v is not None and v not in DRINKING_CHOICES:
            raise ValueError(f"drinking must be one of {DRINKING_CHOICES}")
        return v

    @field_validator("smoking")
    @classmethod
    def validate_smoking(cls, v: str | None) -> str | None:
        """Executes validate smoking operation.

            Args:
                v: Input v parameter.

            Returns:
                str | None: Response payload or result."""
        if v is not None and v not in SMOKING_CHOICES:
            raise ValueError(f"smoking must be one of {SMOKING_CHOICES}")
        return v

    @field_validator("children_plans")
    @classmethod
    def validate_children_plans(cls, v: str | None) -> str | None:
        """Executes validate children plans operation.

            Args:
                v: Input v parameter.

            Returns:
                str | None: Response payload or result."""
        if v is not None and v not in CHILDREN_PLANS_CHOICES:
            raise ValueError(f"children_plans must be one of {CHILDREN_PLANS_CHOICES}")
        return v

    @field_validator("religious_beliefs")
    @classmethod
    def validate_religious_beliefs(cls, v: str | None) -> str | None:
        """Executes validate religious beliefs operation.

            Args:
                v: Input v parameter.

            Returns:
                str | None: Response payload or result."""
        if v is not None and v not in RELIGIOUS_BELIEFS_CHOICES:
            raise ValueError(
                f"religious_beliefs must be one of {RELIGIOUS_BELIEFS_CHOICES}",
            )
        return v

    @field_validator("interests")
    @classmethod
    def validate_interests(cls, v: dict[str, int] | None) -> dict[str, int] | None:
        """Executes validate interests operation.

            Args:
                v: Input v parameter.

            Returns:
                dict[str, int] | None: Response payload or result."""
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
        """Executes validate sub interests operation.

            Args:
                v: Input v parameter.

            Returns:
                dict[str, list[str]] | None: Response payload or result."""
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
        """Executes validate display gender operation.

            Args:
                v: Input v parameter.

            Returns:
                str | None: Response payload or result."""
        if v is not None and v not in GENDER_CHOICES:
            raise ValueError(f"display_gender must be one of {GENDER_CHOICES}")
        return v

    @field_validator("display_sexuality")
    @classmethod
    def validate_display_sexuality(cls, v: str | None) -> str | None:
        """Executes validate display sexuality operation.

            Args:
                v: Input v parameter.

            Returns:
                str | None: Response payload or result."""
        if v is not None and v not in SEXUALITY_CHOICES:
            raise ValueError(f"display_sexuality must be one of {SEXUALITY_CHOICES}")
        return v

    @field_validator("pronouns")
    @classmethod
    def validate_pronouns(cls, v: str | None) -> str | None:
        """Executes validate pronouns operation.

            Args:
                v: Input v parameter.

            Returns:
                str | None: Response payload or result."""
        if v is not None and v not in PRONOUNS_CHOICES:
            raise ValueError(f"pronouns must be one of {PRONOUNS_CHOICES}")
        return v

    @field_validator("languages")
    @classmethod
    def validate_languages(cls, v: list[str] | None) -> list[str] | None:
        """Executes validate languages operation.

            Args:
                v: Input v parameter.

            Returns:
                list[str] | None: Response payload or result."""
        if v is not None:
            for lang in v:
                if lang not in LANGUAGES_CHOICES:
                    raise ValueError(f"Invalid language: {lang}")
        return v

    @field_validator("causes_supported")
    @classmethod
    def validate_causes_supported(cls, v: list[str] | None) -> list[str] | None:
        """Executes validate causes supported operation.

            Args:
                v: Input v parameter.

            Returns:
                list[str] | None: Response payload or result."""
        if v is not None:
            for cause in v:
                if cause not in CAUSES_SUPPORTED_CHOICES:
                    raise ValueError(f"Invalid cause: {cause}")
        return v

    @field_validator("pets")
    @classmethod
    def validate_pets(cls, v: list[str] | None) -> list[str] | None:
        """Executes validate pets operation.

            Args:
                v: Input v parameter.

            Returns:
                list[str] | None: Response payload or result."""
        if v is not None:
            for pet in v:
                if pet not in PETS_CHOICES:
                    raise ValueError(f"Invalid pet: {pet}")
        return v

    @field_validator("profile_pic")
    @classmethod
    def validate_profile_pic(cls, v: str | None) -> str | None:
        """Validates that profile picture path contains no traversal or forbidden characters."""
        if v is None:
            return v
        cleaned = v.strip()
        if not cleaned:
            return ""
        if len(cleaned) > 500:
            raise ValueError("Profile picture path must be less than 500 characters.")
        if (
            ".." in cleaned
            or "\\" in cleaned
            or cleaned.startswith("/")
            or "\x00" in cleaned
        ):
            raise ValueError(
                "Profile picture path contains invalid characters or traversal sequences.",
            )
        return cleaned

    @field_validator("normal_pics")
    @classmethod
    def validate_normal_pics(cls, v: list[str] | None) -> list[str] | None:
        """Validates that normal pics paths contain no traversal or forbidden characters."""
        if v is None:
            return v
        cleaned_list = [pic.strip() for pic in v if pic and pic.strip()]
        if len(cleaned_list) > 4:
            raise ValueError("A maximum of 4 gallery images can be registered.")
        for pic in cleaned_list:
            if len(pic) > 500:
                raise ValueError("Gallery image path must be less than 500 characters.")
            if (
                ".." in pic
                or "\\" in pic
                or pic.startswith("/")
                or "\x00" in pic
            ):
                raise ValueError(
                    "Gallery image path contains invalid characters or traversal sequences.",
                )
        return cleaned_list

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
    """Profiledetailsresponse class representation."""
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
    """Profileupdateresponse class representation."""
    status: str
    detail: str


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
        "children_plans",
    },
)


class PrivacySettingsResponse(BaseModel):
    """Privacysettingsresponse class representation."""
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
        """Executes validate hidden fields operation.

            Args:
                v: Input v parameter.

            Returns:
                list[str] | None: Response payload or result."""
        if v is None:
            return None
        for field in v:
            if field not in ALLOWED_HIDDEN_FIELDS:
                raise ValueError(
                    f"'{field}' is not a hideable field. "
                    f"Allowed: {sorted(ALLOWED_HIDDEN_FIELDS)}",
                )
        return list(set(v))


class EmailNotificationSettingsResponse(BaseModel):
    """Emailnotificationsettingsresponse class representation."""
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


class RegisterDeviceRequest(BaseModel):
    """Register or refresh an FCM push token for the authenticated user's device."""

    fcm_token: str = Field(..., min_length=1, max_length=4096)
    platform: Literal["android", "ios"] = "android"
    device_id: str | None = Field(
        default=None,
        max_length=256,
        description="Client-supplied stable device identifier (optional).",
    )

    @field_validator("fcm_token")
    @classmethod
    def validate_fcm_token_format(cls, v: str) -> str:
        from app.db.client import validate_fcm_token
        return validate_fcm_token(v)

    @field_validator("device_id")
    @classmethod
    def validate_device_id_format(cls, v: str | None) -> str | None:
        if v is None:
            return None
        from app.db.client import validate_device_id
        return validate_device_id(v)


class ModerationSubjectItem(BaseModel):
    """Moderationsubjectitem class representation."""
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
    """Moderationsubjectsrequest class representation."""
    target_ids: list[str] = Field(..., min_length=1, max_length=50)

    @field_validator("target_ids")
    @classmethod
    def validate_target_ids(cls, v: list[str]) -> list[str]:
        if not v:
            raise ValueError("target_ids cannot be empty.")
        if len(v) > 50:
            raise ValueError("target_ids cannot contain more than 50 items.")
        from app.db.client import normalize_uuid
        return list(dict.fromkeys(normalize_uuid(tid) for tid in v))


class ProfileDerivedSignalsResponse(BaseModel):
    """Transparency model detailing derived algorithmic signals, embeddings, and scoring profiles for GDPR compliance."""
    user_id: str
    ai_vibe_tags: list[str] = Field(default_factory=list)
    artist_affinity: dict[str, float] = Field(default_factory=dict)
    genre_affinity: dict[str, float] = Field(default_factory=dict)
    embedding_signals: dict[str, Any] = Field(default_factory=dict)
    orientation_weight_profile: str
    active_scoring_weights: dict[str, dict[str, float]] = Field(default_factory=dict)
    hidden_profile_fields: list[str] = Field(default_factory=list)
    transparency_notice: str

