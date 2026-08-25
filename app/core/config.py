"""Application configuration settings management via Pydantic BaseSettings.

Defines environment variables, runtime secret validation, feature flags, discovery tab enums,
and rate-limiting configuration loaded dynamically from Infisical or environment variables.
"""

from typing import Any, Literal, TypeAlias, cast

from pydantic import field_validator, model_validator
from pydantic.fields import FieldInfo
from pydantic_settings import (
    BaseSettings,
    PydanticBaseSettingsSource,
    SettingsConfigDict,
)

# Keys that must NOT be loaded from .env/statically under any circumstances.
# They are only allowed to be loaded from the runtime environment.
BLOCKED_DOTENV_KEYS: set[str] = {
    "redis_url",
    "pii_encryption_key",
    "blind_index_key",
    "hmac_signing_key",
    "admin_api_key",
    "supabase_service_role_key",
    "supabase_jwt_secret",
    "firebase_service_account",
    "spotify_client_secret",
    "brevo_api_key",
    "sendpulse_client_id",
    "sendpulse_client_secret",
    "twilio_account_sid",
    "twilio_auth_token",
    "twilio_from_number",
    "sentry_backend_dsn",
    "enable_rate_limiting",
    "enable_replay_protection",
    "enforce_app_check",
    "rate_limit_account_deletion",
    "rate_limit_account_deletion_otp",
    "rate_limit_account_phone_otp",
    "rate_limit_auth",
    "rate_limit_data_export",
    "rate_limit_data_export_otp",
    "rate_limit_discover",
    "rate_limit_feedback",
    "rate_limit_health",
    "rate_limit_login_by_phone",
    "rate_limit_safety",
    "rate_limit_safety_heartbeat",
    "rate_limit_safety_portal",
    "rate_limit_spotify",
    "rate_limit_spotify_resync",
}

DiscoveryTab: TypeAlias = Literal["Dating", "Friends", "Professional"]


def is_valid_app_domain(domain: str) -> bool:
    """Validates if a domain string is a valid FQDN suitable for email domain resolution.

    Args:
        domain: Input domain string.

    Returns:
        bool: True if domain is valid FQDN, False otherwise.
    """
    if not domain:
        return False
    import ipaddress

    try:
        ipaddress.ip_address(domain)
        return False  # IP address is considered invalid for email domain
    except ValueError:
        pass

    d_lower = domain.lower()
    if (
        d_lower in ("localhost", "local")
        or d_lower.endswith(".local")
        or d_lower.endswith(".internal")
        or d_lower.endswith(".test")
        or d_lower.endswith(".example")
        or d_lower.endswith(".invalid")
        or d_lower.endswith(".localhost")
    ):
        return False

    # Simple domain structure check (must contain dot and valid characters)
    return bool(
        "." in domain
        and all((part and part.isalnum()) or "-" in part for part in domain.split(".")),
    )


class Settings(BaseSettings):
    """
    Application settings loaded from runtime-injected environment variables.

    Secrets are expected to be provided by an external secret manager
    such as Infisical rather than a local .env file.
    """

    # --- Required Configurations (No defaults) ---
    app_domain: str = ""
    redis_url: str = ""
    pii_encryption_key: str = ""
    pii_profile_key: str = ""
    pii_contact_key: str = ""
    pii_media_escrow_key: str = ""
    pii_oauth_token_key: str = ""
    pii_chat_key: str = ""
    blind_index_key: str = ""
    hmac_signing_key: str = ""
    supabase_url: str = ""
    supabase_service_role_key: str = ""
    supabase_jwt_secret: str | dict[str, Any] = ""
    admin_api_key: str | None = None

    # --- General / Application Settings ---
    app_name: str = "Nexus Orbit"
    app_version: str = "1.0.0"
    app_commit_sha: str = "dev"
    engine_commit_sha: str = ""
    build_timestamp: str = ""
    github_run_id: str = ""
    github_run_number: str = ""
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
    spotify_allowed_redirect_uris: list[str] = [
        "com.devakesu.apps.nexus://callback",
    ]

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

    # --- Cloudflare Turnstile ---
    turnstile_site_key: str | None = None
    turnstile_secret_key: str | None = None

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
    # Displayed on GET /legal and /legal/privacy (app/api/legal.py),
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
    rate_limit_chat: str = "60/minute"
    rate_limit_read_receipts: str = "120/minute"
    rate_limit_auth: str = "5/minute"
    rate_limit_feedback: str = "5/hour"
    rate_limit_safety: str = "20/hour"
    rate_limit_safety_contacts_sync: str = "5/hour"
    rate_limit_safety_alert: str = "5/hour"
    rate_limit_safety_session: str = "30/hour"
    rate_limit_safety_heartbeat: str = "120/hour"
    rate_limit_safety_portal: str = "10/hour"
    rate_limit_safety_escalation_cancel: str = "10/hour"
    rate_limit_account_phone_otp: str = "10/hour"
    rate_limit_login_by_phone: str = "10/hour"
    rate_limit_spotify: str = "10/minute"
    rate_limit_spotify_resync: str = "3/hour"
    rate_limit_account_deletion_otp: str = "5/hour"
    rate_limit_account_deletion: str = "5/hour"
    rate_limit_data_export_otp: str = "5/hour"
    rate_limit_data_export: str = "3/day"

    # --- Reverse Proxy / Forwarded Headers ---
    # Comma-separated list of trusted proxy IP addresses or CIDRs.
    # Set to "*" to trust all proxies (common in Docker/Kubernetes ingress setups).
    # When enabled, ProxyHeadersMiddleware / Uvicorn parses X-Forwarded-For to derive client IP.
    proxy_headers: bool = True
    forwarded_allow_ips: str = "*"

    # --- App Link / Universal Link verification ---
    apple_team_id: str | None = None
    android_sha256_fingerprint: str | None = None

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
    max_safety_escalations: int = 3

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
        """Executes is jwks operation.

            Returns:
                bool: Response payload or result."""
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
        """Executes parse firebase service account operation.

            Args:
                v: Input v parameter.

            Returns:
                dict[str, Any] | None: Response payload or result."""
        import base64
        import binascii
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
            with suppress(binascii.Error, UnicodeDecodeError, ValueError):
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
        """Executes parse allowed signup domains operation.

            Args:
                v: Input v parameter.

            Returns:
                dict[str, list[str]]: Response payload or result."""
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
    def resolve_dynamic_defaults(self) -> "Settings":  # noqa: C901
        """Executes resolve dynamic defaults operation.

            Returns:
                'Settings': Response payload or result."""
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

        # Resolve email_domain based on validity of app_domain
        app_domain_clean = self.app_domain.strip().rstrip("/") if self.app_domain else ""
        # Remove protocol if user included it
        if "://" in app_domain_clean:
            app_domain_clean = app_domain_clean.split("://", 1)[1]
        if ":" in app_domain_clean:
            app_domain_clean = app_domain_clean.split(":", 1)[0]

        if is_valid_app_domain(app_domain_clean):
            self.email_domain = app_domain_clean
        elif self.debug:
            if self.email_domain:
                self.email_domain = self.email_domain.strip().rstrip("/")
            else:
                self.email_domain = app_domain_clean
        else:
            raise ValueError(
                f"Invalid app_domain '{self.app_domain}' in production mode (debug=False). "
                "Production requires a valid domain name for email resolution.",
            )

        # Validate that if Twilio SMS credentials are set, HMAC signing key is present
        has_twilio_creds = bool(
            self.twilio_account_sid
            and self.twilio_auth_token
            and self.twilio_from_number
        )
        if has_twilio_creds and not self.hmac_signing_key:
            raise ValueError(
                "hmac_signing_key is required when Twilio SMS credentials are configured to sign escalation cancel and portal tokens.",
            )

        # Enforce that backend_url starts with https:// in production
        if self.backend_url:
            clean_backend_url = self.backend_url.strip().rstrip("/")
            self.backend_url = clean_backend_url
            if not self.debug and not clean_backend_url.startswith("https://"):
                raise ValueError(
                    "backend_url must start with 'https://' in production.",
                )

        return self

    model_config = SettingsConfigDict(
        env_file=".env",
        extra="ignore",
    )

    @classmethod
    def settings_customise_sources(
        cls,
        settings_cls: type[BaseSettings],
        init_settings: PydanticBaseSettingsSource,
        env_settings: PydanticBaseSettingsSource,
        dotenv_settings: PydanticBaseSettingsSource,
        file_secret_settings: PydanticBaseSettingsSource,
    ) -> tuple[PydanticBaseSettingsSource, ...]:
        """Executes settings customise sources operation.

            Args:
                settings_cls: Input settings cls parameter.
                init_settings: Input init settings parameter.
                env_settings: Input env settings parameter.
                dotenv_settings: Input dotenv settings parameter.
                file_secret_settings: Input file secret settings parameter.

            Returns:
                tuple[PydanticBaseSettingsSource, ...]: Response payload or result."""
        class FilteredDotenvSource(PydanticBaseSettingsSource):
            """Filtereddotenvsource class representation."""
            def get_field_value(
                self,
                field: FieldInfo,
                field_name: str,
            ) -> tuple[Any, str, bool]:
                """Executes get field value operation.

                    Args:
                        field: Input field parameter.
                        field_name: Input field name parameter.

                    Returns:
                        tuple[Any, str, bool]: Response payload or result."""
                if field_name in BLOCKED_DOTENV_KEYS:
                    return None, field_name, False
                return dotenv_settings.get_field_value(field, field_name)

            def __call__(self) -> dict[str, Any]:
                """Executes call   operation.

                    Returns:
                        dict[str, Any]: Response payload or result."""
                raw_data = dotenv_settings()
                return {
                    k: v for k, v in raw_data.items()
                    if k not in BLOCKED_DOTENV_KEYS
                }

        return (
            init_settings,
            env_settings,
            FilteredDotenvSource(settings_cls),
            file_secret_settings,
        )


try:
    # Settings are validated at import time so the application fails fast
    # when required secrets are missing or malformed.
    settings = Settings()
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
