import json
import jwt
import firebase_admin
from firebase_admin import credentials
from fastapi import FastAPI, HTTPException, Body, Depends, Header, Request
from fastapi.middleware.cors import CORSMiddleware
from typing import Optional
from starlette.responses import Response
from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePublicKey
from contextlib import asynccontextmanager

from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from slowapi.middleware import SlowAPIMiddleware

from Nexus_Engine import engine
from app.check import verify_app_check_token
from app.config import settings  
from app.database import fetch_stage_1_candidates
from app.models import DiscoveryFilters, DiscoveryRequest
from app.cache import redis_client
import logging  

logger = logging.getLogger(__name__)

# ==========================================================
# FIREBASE ADMIN INITIALIZATION
# ==========================================================
if settings.enforce_app_check:
    if not settings.firebase_service_account_path:
        raise RuntimeError("CRITICAL: Firebase service account path unpopulated. Required when ENFORCE_APP_CHECK is true.")

    if not firebase_admin._apps:
        try:
            cred = credentials.Certificate(settings.firebase_service_account_path)
            firebase_admin.initialize_app(cred)
        except Exception:
            logger.critical("Firebase SDK initialization failed", exc_info=True)
            raise RuntimeError("CRITICAL: Firebase SDK initialization failed. Check logs for details.")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup
    if settings.enable_replay_protection:
        try:
            await redis_client.ping()
            logger.info("[STARTUP] Redis connection established.")
        except Exception:
            logger.critical("[STARTUP] Redis is unreachable. Replay protection will fail.")
            raise RuntimeError(
                "CRITICAL: Redis unreachable. Cannot start with replay protection enabled."
            )

    yield

    # shutdown
    try:
        await redis_client.aclose()
    except Exception:
        logger.warning("[SHUTDOWN] Redis client close failed.", exc_info=False)

# ==========================================================
# APP SETUP & MIDDLEWARE
# ==========================================================
app = FastAPI(
    title="Nexus MEC Matchmaking Engine",
    version="1.4.0",
    docs_url="/api/v1/docs",
    redoc_url=None
)
origins = [o.strip() for o in settings.allowed_origins.split(",") if o.strip()]
if "*" in origins and len(origins) > 1:
    raise RuntimeError("CRITICAL: Wildcard origin cannot be mixed with specific origins.")

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["POST", "GET", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Firebase-AppCheck"],
)     

# ==========================================================
# RATE LIMITING MANAGER
# ==========================================================

limiter = Limiter(key_func=get_remote_address, enabled=settings.enable_rate_limiting)
app.state.limiter = limiter

def custom_rate_limit_handler(request: Request, exc: Exception) -> Response:
    if isinstance(exc, RateLimitExceeded):
        return _rate_limit_exceeded_handler(request, exc)
    raise exc

app.add_exception_handler(RateLimitExceeded, custom_rate_limit_handler)
app.add_middleware(SlowAPIMiddleware)

# ==========================================================
# SECURITY GUARDS (AUTH & HARDWARE ATTESTATION)
# ==========================================================
    
def load_supabase_public_key() -> EllipticCurvePublicKey:
    jwk_data = settings.supabase_jwt_secret

    if isinstance(jwk_data, str):
        try:
            jwk_data = json.loads(jwk_data)
        except json.JSONDecodeError:
            raise RuntimeError("CRITICAL: Supabase JWK is not valid JSON.")

    if isinstance(jwk_data, dict) and "keys" in jwk_data:
        keys = jwk_data.get("keys", [])
        if not keys:
            raise RuntimeError("CRITICAL: Supabase JWKS contains no keys.")
        jwk_data = keys[0]

    if not isinstance(jwk_data, dict):
        raise RuntimeError("CRITICAL: Invalid Supabase JWK format.")

    try:
        key = jwt.PyJWK(jwk_data).key

        if not isinstance(key, EllipticCurvePublicKey):
            raise RuntimeError("CRITICAL: Supabase JWK did not produce an EC public key for ES256.")

        return key
    except Exception as e:
        raise RuntimeError(f"CRITICAL: Failed to build Supabase public key: {e}")
    
SUPABASE_PUBLIC_KEY = load_supabase_public_key()

def get_authenticated_user_id(authorization: Optional[str] = Header(None)) -> str:
    """
    Cryptographically verifies the Supabase session token passed down from Flutter.
    Natively parses the asymmetric JWK object frame using the ES256 algorithm protocol.
    Type-guarded to satisfy strict PyJWT JWKDict static parameter requirements.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401,
            detail="Missing or malformed Authorization header credentials."
        )

    token = authorization.split(" ")[1]

    try:
        payload = jwt.decode(
            token,
            SUPABASE_PUBLIC_KEY,
            algorithms=["ES256"],
            audience="authenticated"
        )

        user_uuid: Optional[str] = payload.get("sub")
        if not user_uuid:
            raise HTTPException(status_code=401, detail="Invalid token: Sub claim missing.")
        return user_uuid

    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Authentication session expired.")
    except jwt.InvalidTokenError:
        logger.warning("[AUTH] JWT validation failed — token rejected", exc_info=False)
        raise HTTPException(status_code=401, detail="Cryptographic signature verification failed.")


# ==========================================================
# CORE ROUTING LAYER
# ==========================================================
@app.get("/health")
@limiter.limit(settings.rate_limit_health)
def health_check(request: Request):
    """System health check endpoint."""
    _ = request 
    return {"status": "healthy"}


@app.post("/api/v1/discover")
@limiter.limit(settings.rate_limit_discover)
def get_recommendations(
    request: Request,
    payload: DiscoveryRequest = Body(...),
    _device: None = Depends(verify_app_check_token),
    user_id: str = Depends(get_authenticated_user_id)
):
    """
    Dual-Lock Protected Discovery Engine Entrypoint.
    Requires an authentic Supabase signature AND an unaltered, hardware-verified mobile binary footprint.
    """
    _ = request
    active_tab = payload.tab
    filters = payload.filters or DiscoveryFilters()
    
    # STAGE 1: Candidate Retrieval
    # SECURITY INVARIANT: user_id is always sourced from the verified JWT sub claim.
    # fetch_stage_1_candidates must never accept a caller-supplied user identity.
    viewer, candidate_pool = fetch_stage_1_candidates(user_id, active_tab, filters)
    if not viewer or not isinstance(viewer, dict):
        raise HTTPException(status_code=404, detail="Target user profile unpopulated.")
        
    # STAGE 2: Matrix Re-ranking
    feed_results = engine.discover_feed(viewer, active_tab, candidate_pool, feed_limit=20)
    
    # STAGE 3: Data Minimization
    sanitized_feed = []
    for item in feed_results:
        profile = item.get("profile", {})
        if not profile: 
            continue

        # DATA MINIMIZATION SEAL: This allowlist is intentional and security-critical.
        # Do NOT replace with **profile spread. Any new fields require explicit review.            
        sanitized_feed.append({
            "id": profile.get("id"),
            "name": profile.get("name"),
            "branch": profile.get("branch"),
            "year": profile.get("year"),
            "display_gender": profile.get("display_gender"),
            "display_sexuality": profile.get("display_sexuality"),
            "role": profile.get("role"),
            "score": item.get("score")
        })
        
    return {"feed": sanitized_feed}