import logging

from fastapi import APIRouter, Request

from app.core.config import settings
from app.core.limiter import limiter
from app.models import GrievanceContactResponse

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/api/v1/legal/contact", response_model=GrievanceContactResponse)
@limiter.limit(settings.rate_limit_health)
def grievance_contact(request: Request) -> GrievanceContactResponse:
    """Public Grievance Officer / DPO contact (DPDP Act 2023 §13) - no auth,
    no App Check, so it's reachable before signup/login too. Fields are
    null until the corresponding env vars are set; the display surface
    (privacy policy page) is a separate, later step.
    """
    _ = request
    return GrievanceContactResponse(
        name=settings.grievance_officer_name,
        email=settings.grievance_officer_email,
        phone=settings.grievance_officer_phone,
        website=settings.grievance_officer_website,
    )
