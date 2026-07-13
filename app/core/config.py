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

    # --- Firebase / App Check ---
    firebase_service_account_path: str | None = None
    enforce_app_check: bool = True
    enable_replay_protection: bool = True

    # --- Spotify OAuth ---
    spotify_client_id: str | None = None
    spotify_client_secret: str | None = None
    spotify_redirect_uri: str

    # --- Rate limiting / network policy ---
    enable_rate_limiting: bool = True
    rate_limit_health: str = "15/minute"
    rate_limit_discover: str = "10/minute"
    rate_limit_auth: str = "5/minute"
    rate_limit_feedback: str = "5/hour"
    rate_limit_safety: str = "20/hour"
    rate_limit_safety_portal: str = "10/hour"
    rate_limit_account_phone_otp: str = "10/hour"
    rate_limit_login_by_phone: str = "10/hour"
    rate_limit_spotify: str = "10/minute"
    rate_limit_spotify_resync: str = "3/hour"
    rate_limit_account_deletion_otp: str = "5/hour"
    rate_limit_account_deletion: str = "5/hour"
    allowed_origins: str = "http://localhost:3000,http://localhost:8080"

    # -- Account deletion lifecycle --
    # See app/db/account_deletion.py. Tier 1: a request starts a recoverable
    # grace window; if not cancelled, the account is anonymized in place at
    # its end. Tier 2: a much later hard-delete of the (by then long-dormant)
    # anonymized shell, once its own retention window has passed.
    account_deletion_grace_period_days: int = 14
    account_deletion_blocklist_cooldown_days: int = 30
    account_deletion_long_tail_purge_days: int = 365 * 3

    # --- Infrastructure / crypto ---
    redis_url: str
    pii_encryption_key: str
    blind_index_key: str

    # -- Auth --
    # Per-variant email domain allowlist (JSON object in the env var).
    # Each key is a variant name, value is the required email domain.
    # Example env: ALLOWED_EMAIL_DOMAINS={"nexus_mec":"mec.ac.in"}
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

    # -- SMS / Twilio --
    twilio_account_sid: str | None = None
    twilio_auth_token: str | None = None
    twilio_from_number: str | None = None
    # Public scheme+host this API is reachable at, e.g. https://api.yourdomain.com.
    # Needed to build the trusted-contact escalation-cancel link sent by the
    # dead-man's-switch scheduler job, which has no incoming Request to derive
    # a base URL from (see app/services/reminder_scheduler.py).
    backend_public_url: str = ""
    app_name: str = "Nexus Orbit"
    debug: bool = False

    # -- Support / feedback routing --
    # Falls back to admin@{app_domain} when unset (see app/core/email.py).
    feedback_notify_email: str | None = None

    # -- Dev-only tooling (see app/api/dev_temp.py, only mounted when debug=True) --
    dev_allowed_email: str | None = None

    @property
    def is_jwks(self) -> bool:
        secret = self.supabase_jwt_secret
        return isinstance(secret, dict) or (
            secret.strip().startswith("{") and "keys" in secret
        )

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

# Blend weights for merging Spotify's algorithmic /me/top/artists ranking
# with owned/collaborative-playlist track frequency into a single
# artist_affinity signal (see app/services/spotify_sync.py:blend_artist_affinity).
# Must sum to 1.0; tunable independently of the per-tab TAB_MASKS weight below.
SPOTIFY_AFFINITY_NATIVE_WEIGHT: float = 0.55
SPOTIFY_AFFINITY_PLAYLIST_WEIGHT: float = 0.45

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
        "artist_affinity": 0.8,
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
        "artist_affinity": 1,
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
        "artist_affinity": 5,
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
        "artist_affinity": 0,
    },
}

# Similarity thresholds used by fuzzy-matching helpers.
FUZZY_THRESHOLDS: dict[str, float] = {
    "hometown": 0.70,
    "current_place": 0.70,
    "default": 0.85,
}
