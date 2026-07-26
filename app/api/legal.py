import logging

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from app.core.config import settings
from app.core.limiter import limiter
from app.core.templates import render_legal

logger = logging.getLogger(__name__)

router = APIRouter()


def _field_or(value: str | None, missing_label: str) -> str:
    """Renders a real config value verbatim, or a visibly-flagged
    placeholder chip if it hasn't been set yet.
    """
    if value:
        return value
    return f'<span class="field">{missing_label}</span>'


def _placeholder_banner(missing: list[str]) -> str:
    """Renders banner when launch-readiness config values are missing."""
    if not missing:
        return ""
    items = "; ".join(missing)
    return f"""
    <div class="placeholder-banner">
      <span class="tag">Before publish</span>
      <span>Still needs a real value: {items}.</span>
    </div>
    """


def render_legal_page(*, is_embed: bool = False) -> str:
    """Renders the legal.html template with variables filled in."""
    domain = settings.email_domain or ""
    terms_version = settings.current_terms_version.strip()

    missing: list[str] = []
    if not settings.legal_effective_date:
        missing.append("effective date (LEGAL_EFFECTIVE_DATE)")
    if not settings.legal_governing_law_city:
        missing.append("governing-law city (LEGAL_GOVERNING_LAW_CITY)")
    if not settings.grievance_officer_name:
        missing.append(
            "Grievance Officer name/contact (grievance_officer_* settings)",
        )

    effective_date = _field_or(settings.legal_effective_date, "not yet set")
    city = _field_or(settings.legal_governing_law_city, "not yet set")
    grievance_name = _field_or(settings.grievance_officer_name, "not yet designated")
    grievance_email = _field_or(settings.grievance_officer_email, "not yet set")
    grievance_phone = _field_or(settings.grievance_officer_phone, "not yet set")
    grievance_website = _field_or(settings.grievance_officer_website, "not yet set")

    return render_legal(
        effective_date=effective_date,
        terms_version=terms_version,
        domain=domain,
        city=city,
        grievance_name=grievance_name,
        grievance_email=grievance_email,
        grievance_phone=grievance_phone,
        grievance_website=grievance_website,
        placeholder_banner=_placeholder_banner(missing),
        is_embed=is_embed,
    )


@router.get("/legal")
@limiter.limit(settings.rate_limit_health)
def legal_terms_page(request: Request, embed: bool = False) -> HTMLResponse:
    """Public, unauthenticated - reachable before signup/login, and this is
    the URL the Flutter app's WebView (legal_terms_page.dart) points at.
    When embed=true (or embed=1), header and footer are omitted for clean in-app rendering.
    """
    is_embed = embed or request.query_params.get("embed") in ("1", "true")
    return HTMLResponse(render_legal_page(is_embed=is_embed))


@router.get("/legal/privacy")
@limiter.limit(settings.rate_limit_health)
def legal_privacy_page(request: Request) -> RedirectResponse:
    """Privacy Policy canonical URL redirecting into the /legal#privacy fragment."""
    _ = request
    return RedirectResponse(url="/legal#privacy", status_code=302)
