"""FastAPI router for user discovery, orbits, likes, and passes."""

from fastapi import APIRouter

from app.api.discovery.endpoints import router as discovery_endpoints_router
from app.api.discovery.likes import router as likes_router

router = APIRouter()

router.include_router(discovery_endpoints_router)
router.include_router(likes_router)

__all__ = ["router"]
