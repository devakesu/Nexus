from typing import Any, Literal, TypeAlias, cast

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DiscoveryTab: TypeAlias = Literal["Dating", "Friends", "Professional"]


class Settings(BaseSettings):
    """
    Application settings loaded from runtime-injected environment variables.

    Secrets are expected to be provided by an external secret manager
    such as Infisical rather than a local .env file.
    """

    # --- Required Configurations (No defaults) ---
    app_domain: str
    redis_url: str
    pii_encryption_key: str
    blind_index_key: str
    supabase_url: str
    supabase_service_role_key: str
    supabase_jwt_secret: str | dict[str, Any]

    # --- General / Application Settings ---
    app_name: str = "Nexus Orbit"
    debug: bool = False
    # Public scheme+host this API is reachable at, e.g. https://api.yourdomain.com.
    # Needed to build the trusted-contact escalation-cancel link sent by the
    # dead-man's-switch scheduler job, which has no incoming Request to derive
    # a base URL from (see app/services/reminder_scheduler.py).
    # Falls back to https://{app_domain} when unset.
    backend_url: str | None = None

    # --- Firebase / App Check ---
    firebase_service_account: dict[str, Any] | None = None
    enforce_app_check: bool = True
    enable_replay_protection: bool = True

    # --- Spotify OAuth ---
    spotify_client_id: str | None = None
    spotify_client_secret: str | None = None
    # Falls back to {backend_url}/api/v1/spotify/callback when unset.
    spotify_redirect_uri: str | None = None

    # --- Gated Signup & Authentication ---
    # Per-variant email domain allowlist for signup (JSON object in the env var).
    # Each key is a variant name, value is a list of allowed email domains.
    # Example env: ALLOWED_SIGNUP_DOMAINS={"nexus_mec":["mec.ac.in", "gmail.com"]}
    # Variants absent from this dict have no domain restriction.
    # The main 'nexus' variant should NOT be listed here.
    allowed_signup_domains: Any = {}

    # --- Email Providers & Support Routing ---
    brevo_api_key: str | None = None
    email_domain: str | None = None
    sendpulse_client_id: str | None = None
    sendpulse_client_secret: str | None = None
    # Falls back to admin@{app_domain} when unset (see app/core/email.py).
    feedback_notify_email: str | None = None

    # --- SMS / Twilio ---
    twilio_account_sid: str | None = None
    twilio_auth_token: str | None = None
    twilio_from_number: str | None = None

    # --- Legal & Compliance Pages ---
    current_terms_version: str = "1"
    # Same optional-no-import-failure style as the grievance officer block
    # above: unset renders a visible "not yet set" placeholder in the page
    # rather than failing, since these are launch-readiness values an ops
    # team fills in once, not runtime application config.
    legal_effective_date: str | None = None
    legal_governing_law_city: str | None = None

    # -- Grievance Officer / DPO contact (DPDP Act 2023 §13) --
    # Displayed on GET /legal/terms and /legal/privacy (app/api/legal.py),
    # read directly by the server-rendered page - no separate JSON API.
    grievance_officer_name: str | None = None
    grievance_officer_email: str | None = None
    grievance_officer_phone: str | None = None
    grievance_officer_website: str | None = None

    # --- CORS / Allowed Origins ---
    # Comma-separated list of allowed CORS origins.
    # The production origin (https://{app_domain}) is automatically
    # appended to this list when app_domain is set.
    allowed_origins: str = "http://localhost:3000,http://localhost:8080"

    # --- Rate Limiting ---
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
    rate_limit_data_export_otp: str = "5/hour"
    rate_limit_data_export: str = "3/day"

    # --- Account Deletion Lifecycle ---
    # See app/db/account_deletion.py. Tier 1: a request starts a recoverable
    # grace window; if not cancelled, the account is anonymized in place at
    # its end. Tier 2: a much later hard-delete of the (by then long-dormant)
    # anonymized shell, once its own retention window has passed.
    account_deletion_grace_period_days: int = 14
    account_deletion_blocklist_cooldown_days: int = 30
    account_deletion_long_tail_purge_days: int = 365 * 3

    # --- Meetup Safety Data Retention ---
    # Meetup Safety data retention (balances the investigative value of an
    # incident record against not hoarding highly sensitive data forever)
    # Digital Witness recordings (raw audio/video + escrowed decryption
    # keys) are the most invasive category here, so they're capped
    # regardless of account status - see purge_expired_safety_evidence in
    # app/db/safety.py. safety_alerts (lightweight metadata: type,
    # location, timestamp) are cheaper and more useful for trust & safety
    # pattern review, so they're kept indefinitely for *active* accounts
    # and only time-boxed once the account itself is gone - see
    # purge_safety_data_for_purged_accounts.
    safety_evidence_active_retention_days: int = 365
    safety_data_legal_hold_days: int = 180

    # --- Sentry (Error Monitoring) ---
    # Purely optional, no import-time failure if unset (unlike
    # enforce_app_check's hard-fail-if-misconfigured style) - see
    # app/main.py's gated sentry_sdk.init() call.
    sentry_backend_dsn: str | None = None
    sentry_environment: str | None = None
    sentry_traces_sample_rate: float = 0.0

    # --- Dev-Only Tooling ---
    # Dev-only tooling (see app/api/dev_temp.py, only mounted when debug=True)
    dev_allowed_email: str | None = None


    @property
    def is_jwks(self) -> bool:
        secret = self.supabase_jwt_secret
        return isinstance(secret, dict) or (
            secret.strip().startswith("{") and "keys" in secret
        )

    @field_validator("firebase_service_account", mode="before")
    @classmethod
    def parse_firebase_service_account(
        cls,
        v: Any,
    ) -> dict[str, Any] | None:
        import base64
        import json
        from contextlib import suppress

        if v is None:
            return None
        if isinstance(v, dict):
            return cast(dict[str, Any], v)
        if isinstance(v, str):
            stripped = v.strip()
            # If it is raw JSON string
            if stripped.startswith("{"):
                with suppress(json.JSONDecodeError):
                    return cast(dict[str, Any], json.loads(stripped))

            # Try Base64 decoding
            with suppress(Exception):
                decoded_bytes = base64.b64decode(stripped, validate=True)
                decoded_str = decoded_bytes.decode("utf-8")
                if decoded_str.strip().startswith("{"):
                    with suppress(json.JSONDecodeError):
                        return cast(dict[str, Any], json.loads(decoded_str))
        raise ValueError(
            "firebase_service_account must be a valid JSON dictionary "
            "or base64-encoded JSON string",
        )

    @field_validator("allowed_signup_domains", mode="before")
    @classmethod
    def parse_allowed_signup_domains(
        cls,
        v: Any,
    ) -> dict[str, list[str]]:
        import json
        from contextlib import suppress

        if v is None:
            return {}
        if isinstance(v, str):
            with suppress(json.JSONDecodeError):
                v = json.loads(v)
        if isinstance(v, dict):
            normalized: dict[str, list[str]] = {}
            dict_v = cast(dict[Any, Any], v)
            for variant, domains in dict_v.items():
                variant_str = str(variant)
                if isinstance(domains, str):
                    normalized[variant_str] = [
                        d.strip() for d in domains.split(",") if d.strip()
                    ]
                elif isinstance(domains, list):
                    list_domains = cast(list[Any], domains)
                    normalized[variant_str] = [str(d).strip() for d in list_domains]
                else:
                    normalized[variant_str] = [str(domains).strip()]
            return normalized
        raise ValueError(
            "allowed_signup_domains must be a JSON object or dictionary",
        )

    @model_validator(mode="after")
    def resolve_dynamic_defaults(self) -> "Settings":
        if self.app_domain:
            domain = self.app_domain.rstrip("/")
            # Set default backend public URL if not set
            if not self.backend_url:
                self.backend_url = f"https://{domain}"

            # Set default Spotify redirect URI if not set
            if not self.spotify_redirect_uri:
                self.spotify_redirect_uri = (
                    f"{self.backend_url}/api/v1/spotify/callback"
                )

            # Automatically append the production origin to allowed_origins
            production_origin = f"https://{domain}"
            existing = [o.strip() for o in self.allowed_origins.split(",") if o.strip()]
            if production_origin not in existing:
                existing.append(production_origin)
                self.allowed_origins = ",".join(existing)

        if not self.email_domain and self.app_domain:
            self.email_domain = self.app_domain
        return self

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
        "Command: infisical run --env=dev -- "
        "uvicorn app.main:app --reload --reload-dir app\n"
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
        "causes_supported": 2,
        "religious_beliefs": 3,
        "career_embedding": 2,
        "activities": 1,
        "artist_affinity": 1,
        "hometown": 1,
        "current_place": 1,
        "pets": 1,
        "age": 3,
        "tech_skills": 0,
        "complementary_roles": 0,
    },
    "Friends": {
        "activities": 3,
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
        "causes_supported": 1,
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
