# ruff: noqa: E501
import os

from fastapi import APIRouter
from fastapi.responses import FileResponse, HTMLResponse, PlainTextResponse, Response

from app.core.config import settings
from app.core.templates import render_contact, render_error, render_help, render_landing

router = APIRouter()

STATIC_DIR = os.path.join(os.path.dirname(__file__), "..", "static")


@router.get("/favicon.ico", include_in_schema=False)
async def favicon():
    return FileResponse(
        os.path.join(STATIC_DIR, "favicon.ico"),
        media_type="image/x-icon",
    )


@router.get("/favicon-16x16.png", include_in_schema=False)
async def favicon_16():
    return FileResponse(
        os.path.join(STATIC_DIR, "favicon-16x16.png"),
        media_type="image/png",
    )


@router.get("/favicon-32x32.png", include_in_schema=False)
async def favicon_32():
    return FileResponse(
        os.path.join(STATIC_DIR, "favicon-32x32.png"),
        media_type="image/png",
    )


@router.get("/apple-touch-icon.png", include_in_schema=False)
async def apple_touch_icon():
    return FileResponse(
        os.path.join(STATIC_DIR, "apple-touch-icon.png"),
        media_type="image/png",
    )


@router.get("/android-chrome-192x192.png", include_in_schema=False)
async def android_chrome_192():
    return FileResponse(
        os.path.join(STATIC_DIR, "android-chrome-192x192.png"),
        media_type="image/png",
    )


@router.get("/android-chrome-512x512.png", include_in_schema=False)
async def android_chrome_512():
    return FileResponse(
        os.path.join(STATIC_DIR, "android-chrome-512x512.png"),
        media_type="image/png",
    )


@router.get("/site.webmanifest", include_in_schema=False)
async def site_webmanifest():
    return FileResponse(
        os.path.join(STATIC_DIR, "site.webmanifest"),
        media_type="application/manifest+json",
    )


@router.get("/logo.png", include_in_schema=False)
async def logo_png():
    return FileResponse(
        os.path.join(STATIC_DIR, "logo.png"),
        media_type="image/png",
    )


@router.get("/logo-foreground.png", include_in_schema=False)
async def logo_foreground_png():
    return FileResponse(
        os.path.join(STATIC_DIR, "logo-foreground.png"),
        media_type="image/png",
    )


@router.get("/og-image.png", include_in_schema=False)
async def og_image_png():
    return FileResponse(
        os.path.join(STATIC_DIR, "og-image.png"),
        media_type="image/png",
    )


@router.get("/nexus-wide-logo.jpg", include_in_schema=False)
async def nexus_wide_logo():
    return FileResponse(
        os.path.join(STATIC_DIR, "nexus-wide-logo.jpg"),
        media_type="image/jpeg",
    )


@router.get("/robots.txt", include_in_schema=False)
async def robots_txt():
    content = f"User-agent: *\nAllow: /\nSitemap: {settings.backend_url}/sitemap.xml\n"
    return PlainTextResponse(content)


@router.get("/error", response_class=HTMLResponse, include_in_schema=False)
async def render_error_page(code: int = 404, message: str | None = None):
    """Renders a common error page inspired by Nexus backend root design system."""
    return HTMLResponse(render_error(code=code, message=message), status_code=code)


@router.get("/sitemap.xml", include_in_schema=False)
async def sitemap_xml():
    xml_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    <url>
        <loc>{settings.backend_url}/</loc>
        <changefreq>daily</changefreq>
        <priority>1.0</priority>
    </url>
    <url>
        <loc>{settings.backend_url}/legal</loc>
        <changefreq>monthly</changefreq>
        <priority>0.5</priority>
    </url>
    <url>
        <loc>{settings.backend_url}/contact</loc>
        <changefreq>monthly</changefreq>
        <priority>0.6</priority>
    </url>
    <url>
        <loc>{settings.backend_url}/help</loc>
        <changefreq>weekly</changefreq>
        <priority>0.8</priority>
    </url>
    <url>
        <loc>{settings.backend_url}/faq</loc>
        <changefreq>weekly</changefreq>
        <priority>0.8</priority>
    </url>
</urlset>"""
    return Response(content=xml_content, media_type="application/xml")


@router.get("/", response_class=HTMLResponse)
async def render_landing_page():
    turnstile_site_key = settings.turnstile_site_key or ""
    return HTMLResponse(
        render_landing(
            turnstile_site_key=turnstile_site_key,
            app_version=settings.app_version,
        )
    )


@router.get("/help", response_class=HTMLResponse)
@router.get("/faq", response_class=HTMLResponse)
async def render_help_page():
    return HTMLResponse(render_help())


@router.get("/contact", response_class=HTMLResponse)
async def render_contact_page():
    turnstile_site_key = settings.turnstile_site_key or ""
    return HTMLResponse(render_contact(turnstile_site_key=turnstile_site_key))


@router.get("/delete-account", response_class=HTMLResponse)
async def render_delete_account_page():
    return HTMLResponse(
        render_error(
            code=200,
            message="To delete your Nexus account, open the Nexus Mobile App and navigate to Settings → Delete Account. Account deletion is subject to a 14-day grace period.",
        )
    )
