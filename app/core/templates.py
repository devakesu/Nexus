from pathlib import Path
from typing import Any, Dict, Optional
from jinja2 import Environment, FileSystemLoader, select_autoescape

# Path to the templates directory (app/templates)
TEMPLATES_DIR = Path(__file__).parent.parent / "templates"

# Jinja2 Environment initialization
jinja_env = Environment(
    loader=FileSystemLoader(str(TEMPLATES_DIR)),
    autoescape=select_autoescape(["html", "xml"]),
    trim_blocks=True,
    lstrip_blocks=True,
)


def render_template(template_name: str, context: Optional[Dict[str, Any]] = None) -> str:
    """Renders a Jinja2 template with the given context dictionary."""
    if context is None:
        context = {}
    template = jinja_env.get_template(template_name)
    return template.render(**context)


def render_landing(turnstile_site_key: Optional[str] = None, app_version: str = "1.0.0") -> str:
    """Renders the main landing page template."""
    return render_template(
        "pages/landing.html",
        {
            "turnstile_site_key": turnstile_site_key,
            "app_version": app_version,
            "footer_type": "main",
            "header_mode": "main",
            "active_page": "home",
        },
    )


def render_contact(turnstile_site_key: Optional[str] = None) -> str:
    """Renders the support and contact page template."""
    return render_template(
        "pages/contact.html",
        {
            "turnstile_site_key": turnstile_site_key,
            "footer_type": "secondary",
            "header_mode": "secondary",
            "active_page": "contact",
            "brand_subtitle": "Contact Us",
        },
    )


def render_help() -> str:
    """Renders the Help Center and FAQ page template."""
    return render_template(
        "pages/help.html",
        {
            "footer_type": "secondary",
            "header_mode": "secondary",
            "active_page": "help",
            "brand_subtitle": "Help Center",
        },
    )


def render_legal(
    effective_date: str = "July 26, 2026",
    terms_version: str = "1.0.0",
    domain: str = "nexus.devakesu.com",
    city: str = "Bengaluru",
    grievance_name: str = "Nexus Grievance Officer",
    grievance_email: str = "grievance@devakesu.com",
    grievance_phone: str = "+91-80-45678900",
    grievance_website: str = "https://nexus.devakesu.com",
    placeholder_banner: str = "",
    is_embed: bool = False,
) -> str:
    """Renders the Legal & Privacy Policy page template."""
    return render_template(
        "pages/legal.html",
        {
            "effective_date": effective_date,
            "terms_version": terms_version,
            "domain": domain,
            "city": city,
            "grievance_name": grievance_name,
            "grievance_email": grievance_email,
            "grievance_phone": grievance_phone,
            "grievance_website": grievance_website,
            "placeholder_banner": placeholder_banner,
            "is_embed": is_embed,
            "footer_type": "secondary",
            "header_mode": "secondary",
            "active_page": "legal",
            "brand_subtitle": "Terms & Privacy",
        },
    )


def render_delete_account(
    grace_period_days: int = 14,
    blocklist_cooldown_days: int = 30,
    long_tail_purge_days: int = 1095,
    safety_evidence_active_retention_days: int = 365,
    safety_data_legal_hold_days: int = 180,
    domain: str = "nexus.devakesu.com",
    effective_date: str = "July 26, 2026",
    is_embed: bool = False,
) -> str:
    """Renders the Delete Account & Data Export page template."""
    if long_tail_purge_days % 365 == 0:
        years = long_tail_purge_days // 365
        purge_fmt = f"{years} year{'s' if years != 1 else ''}"
    else:
        purge_fmt = f"{long_tail_purge_days} days"

    return render_template(
        "pages/delete_account.html",
        {
            "grace_period_days": grace_period_days,
            "blocklist_cooldown_days": blocklist_cooldown_days,
            "long_tail_purge_days": long_tail_purge_days,
            "long_tail_purge_formatted": purge_fmt,
            "safety_evidence_active_retention_days": safety_evidence_active_retention_days,
            "safety_data_legal_hold_days": safety_data_legal_hold_days,
            "domain": domain,
            "effective_date": effective_date,
            "is_embed": is_embed,
            "footer_type": "secondary",
            "header_mode": "secondary",
            "active_page": "delete_account",
            "brand_subtitle": "Account Rights",
        },
    )




def render_error(code: int = 404, message: Optional[str] = None) -> str:
    """Renders a unified error page template."""
    error_titles = {
        400: ("400", "Bad Request", "The request payload or parameters were invalid or corrupted.", "var(--nova)"),
        401: ("401", "Unauthorized", "Authentication credentials were missing or invalid.", "var(--nova)"),
        403: ("403", "Access Forbidden", "You do not have authorization to access this deep-space node.", "var(--pulsar)"),
        404: ("404", "Signal Lost", "The node or signal frequency requested could not be located in orbit.", "var(--starlight)"),
        429: ("429", "Rate Limit Exceeded", "Too many requests. Please throttle your pulse rate before reconnecting.", "var(--nova)"),
        500: ("500", "Internal Anomaly", "An unexpected void anomaly occurred within our core engine cluster.", "var(--pulsar)"),
        502: ("502", "Bad Gateway", "The upstream gateway engine returned an invalid response.", "var(--nebula)"),
        503: ("503", "Service Unavailable", "System maintenance or temporary overload in progress. Re-orbiting soon.", "var(--nova)"),
    }

    code_str, default_title, default_desc, signal_color = error_titles.get(
        code,
        (str(code), "HTTP Error", "An error occurred while processing your request.", "var(--starlight)"),
    )

    display_title = default_title
    display_desc = message if message else default_desc

    return render_template(
        "pages/error.html",
        {
            "code_str": code_str,
            "display_title": display_title,
            "display_desc": display_desc,
            "signal_color": signal_color,
            "footer_type": "secondary",
            "header_mode": "secondary",
            "active_page": "error",
            "brand_subtitle": "Error",
        },
    )
