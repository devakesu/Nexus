from typing import Any, Literal, TypeAlias

from pydantic_settings import BaseSettings, SettingsConfigDict

DiscoveryTab: TypeAlias = Literal["Dating", "Friends", "Professional"]


class Settings(BaseSettings):
    """
    Application settings loaded from runtime-injected environment variables.

    Secrets are expected to be provided by an external secret manager
    such as Infisical rather than a local .env file.
    """

    # --- Core backend secrets ---
    supabase_url: str
    supabase_service_role_key: str
    supabase_jwt_secret: str | dict[str, Any]
    """
    Supabase JWT secret used for decoding access tokens.
    Can be a symmetric secret key string (for HS256/HS384/HS512) or
    a JWKS (JSON Web Key Set) dictionary containing public key specs (for ES256).
    """

    # --- Firebase / App Check ---
    firebase_service_account_path: str | None = None
    enforce_app_check: bool = True
    enable_replay_protection: bool = True

    # --- Rate limiting / network policy ---
    enable_rate_limiting: bool = True
    rate_limit_health: str = "15/minute"
    rate_limit_discover: str = "10/minute"
    rate_limit_auth: str = "5/minute"
    allowed_origins: str = "*"

    # --- Infrastructure / crypto ---
    redis_url: str
    pii_encryption_key: str
    blind_index_key: str

    # -- Auth --
    # Per-variant email domain allowlist (JSON object in the env var).
    # Each key is a variant name, value is the required email domain.
    # Example env: ALLOWED_EMAIL_DOMAINS={"nexus_mec":"mec.edu.in"}
    # Variants absent from this dict have no domain restriction.
    # The main 'nexus' variant should NOT be listed here.
    allowed_email_domains: dict[str, str] = {}

    # -- Legal --
    current_terms_version: str = "1"

    # -- Email Providers --
    brevo_api_key: str | None = None
    sendpulse_client_id: str | None = None
    sendpulse_client_secret: str | None = None
    app_domain: str
    app_name: str = "Nexus Orbit"

    model_config = SettingsConfigDict(
        env_file=None,
        extra="ignore",
    )


try:
    # Settings are validated at import time so the application fails fast
    # when required secrets are missing or malformed.
    settings = Settings()  # type: ignore[call-arg]
except Exception as e:
    raise RuntimeError(
        "CRITICAL: Failed to validate application secrets block.\n"
        "Ensure you are running the application wrapped inside the "
        "Infisical CLI tool.\n"
        "Command: infisical run --env=dev -- uvicorn app.main:app --reload\n"
        f"Error Details: {e}",
    ) from e


# ---------------------------------------------------------------------------
# Matchmaking constants
# ---------------------------------------------------------------------------

# Reward candidates from a different academic branch when the scoring engine
# determines that cross-branch diversity should receive a small boost.
CROSS_BRANCH_BONUS: float = 5.0

# Blend weights used by the ranking engine for anchor vs ambient scoring.
TIER_WEIGHTS: dict[DiscoveryTab, dict[str, float]] = {
    "Dating": {"anchor": 0.80, "ambient": 0.20},
    "Friends": {"anchor": 0.60, "ambient": 0.40},
    "Professional": {"anchor": 0.90, "ambient": 0.10},
}

# Multiplier applied when a soft dealbreaker is detected.
DEALBREAKER_PENALTY: float = 0.10

# Attributes treated as hard incompatibilities per tab.
HARD_DEALBREAKERS: dict[DiscoveryTab, list[str]] = {
    "Dating": ["smoking", "drinking"],
    "Friends": [],
    "Professional": [],
}

# Orientation-specific feature weight adjustments used by the ranking engine.
ORIENTATION_WEIGHT_MODIFIERS: dict[str, dict[str, float]] = {
    "Asexual": {
        "ai_vibe_tags": 0.3,
        "drinking": 0.5,
        "smoking": 0.5,
        "interests": 1.5,
        "causes_supported": 1.3,
    },
    "Demisexual": {
        "ai_vibe_tags": 0.5,
        "top_artists": 0.8,
        "interests": 1.3,
        "value_dimensions": 1.2,
    },
}

# Per-tab feature masks used to weight ranking signals.
TAB_MASKS: dict[DiscoveryTab, dict[str, int]] = {
    "Dating": {
        "value_dimensions": 5,
        "partner_values": 5,
        "interests": 5,
        "dating_for": 4,
        "drinking": 4,
        "smoking": 4,
        "bio_embedding": 4,
        "identity_embedding": 3,
        "ai_vibe_tags": 3,
        "children_plans": 4,
        "causes_supported": 3,
        "religious_beliefs": 3,
        "career_embedding": 2,
        "activities": 2,
        "top_artists": 1,
        "hometown": 1,
        "current_place": 1,
        "pets": 1,
        "age": 3,
        "tech_skills": 0,
        "complementary_roles": 0,
    },
    "Friends": {
        "activities": 5,
        "interests": 5,
        "top_artists": 5,
        "ai_vibe_tags": 3,
        "bio_embedding": 3,
        "identity_embedding": 3,
        "hometown": 3,
        "current_place": 3,
        "pets": 3,
        "drinking": 2,
        "smoking": 2,
        "causes_supported": 2,
        "lifestyle": 2,
        "languages": 2,
        "value_dimensions": 2,
        "career_embedding": 1,
        "religious_beliefs": 1,
        "children_plans": 0,
        "partner_values": 0,
        "tech_skills": 0,
        "complementary_roles": 0,
    },
    "Professional": {
        "identity_embedding": 5,
        "career_embedding": 5,
        "complementary_roles": 4,
        "activities": 3,
        "interests": 3,
        "tech_skills": 4,
        "causes_supported": 3,
        "bio_embedding": 3,
        "languages": 1,
        "ai_vibe_tags": 1,
        "hometown": 0,
        "current_place": 0,
        "pets": 0,
        "children_plans": 0,
        "drinking": 0,
        "smoking": 0,
        "partner_values": 0,
        "value_dimensions": 1,
        "top_artists": 0,
    },
}

# Similarity thresholds used by fuzzy-matching helpers.
FUZZY_THRESHOLDS: dict[str, float] = {
    "hometown": 0.70,
    "current_place": 0.70,
    "default": 0.85,
}
