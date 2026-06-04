from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional, Union, Dict, Any

class Settings(BaseSettings):
    """
    Expects runtime secret injection from an external provider (Infisical).
    """
    supabase_url: str
    supabase_service_role_key: str
    supabase_jwt_secret: Union[str, Dict[str, Any]] 

    firebase_service_account_path: Optional[str] = None
    enforce_app_check: bool = True
    enable_replay_protection: bool = True

    enable_rate_limiting: bool = True
    rate_limit_health: str = "15/minute"
    rate_limit_discover: str = "10/minute"
    allowed_origins: str = "*"

    redis_url: str

    model_config = SettingsConfigDict(
        env_file=None,
        extra="ignore"
    )

try:
    settings = Settings()  # type: ignore[call-arg]
except Exception as e:
    raise RuntimeError(
        f"CRITICAL: Failed to validate application secrets block.\n"
        f"Ensure you are running the application wrapped inside the Infisical CLI tool.\n"
        f"Command: infisical run --env=dev -- uvicorn app.main:app --reload\n"
        f"Error Details: {e}"
    )

# --- MATCHMAKING CONSTANTS & MASKS ---
CROSS_BRANCH_BONUS = 5.0  

TIER_WEIGHTS = {
    "Dating":       {"anchor": 0.80, "ambient": 0.20},
    "Friends":      {"anchor": 0.60, "ambient": 0.40},
    "Professional": {"anchor": 0.90, "ambient": 0.10}
}

DEALBREAKER_PENALTY = 0.10

HARD_DEALBREAKERS = {
    "Dating": ["smoking", "drinking"], 
    "Friends": [],
    "Professional": []
}

ORIENTATION_WEIGHT_MODIFIERS = {
    "Asexual":    {"ai_vibe_tags": 0.3, "drinking": 0.5, "smoking": 0.5, "interests": 1.5, "causes_supported": 1.3},
    "Demisexual": {"ai_vibe_tags": 0.5, "top_artists": 0.8, "interests": 1.3, "value_dimensions": 1.2},
}

TAB_MASKS = {
    "Dating": {
        "value_dimensions": 5, "partner_values": 5, "interests": 5,
        "drinking": 4, "smoking": 4, "bio_embedding": 4,
        "identity_embedding": 3, "ai_vibe_tags": 3, "children_plans": 4, "causes_supported": 3,
        "religious_beliefs": 3, "career_embedding": 2, "activities": 2, 
        "top_artists": 1, "hometown": 1, "pets": 1, "age": 3,
        "tech_skills": 0, "complementary_roles": 0 
    },
    "Friends": {
        "activities": 5, "interests": 5, "top_artists": 5, 
        "ai_vibe_tags": 3, "bio_embedding": 3, "identity_embedding": 3, "hometown": 3, "pets": 3, 
        "drinking": 2, "smoking": 2, "causes_supported": 2, "lifestyle": 2, "languages": 2, 
        "value_dimensions": 2, "career_embedding": 1, "religious_beliefs": 1, 
        "children_plans": 0, "partner_values": 0, "tech_skills": 0, "complementary_roles": 0
    },
    "Professional": {
        "identity_embedding": 5, "career_embedding": 5, "complementary_roles": 4, 
        "activities": 3, "interests": 3, "tech_skills": 4, "causes_supported": 3, "bio_embedding": 3,
        "languages": 1, "ai_vibe_tags": 1, "hometown": 0, "pets": 0, 
        "children_plans": 0, "drinking": 0, "smoking": 0, "partner_values": 0, 
        "value_dimensions": 1, "top_artists": 0 
    }
}

FUZZY_THRESHOLDS = { "hometown": 0.70, "default": 0.85 }