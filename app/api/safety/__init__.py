"""FastAPI router for trust and safety, user reporting, and safety portal endpoints."""

from fastapi import APIRouter

from app.api.safety.endpoints import router as safety_endpoints_router
from app.api.safety.portal import router as safety_portal_router

router = APIRouter()

router.include_router(safety_endpoints_router)
router.include_router(safety_portal_router)

__all__ = ["router"]
