import re
from typing import Any, cast
from urllib.parse import urlparse

from fastapi.testclient import TestClient
from httpx import Response

from app.main import app

client = cast(Any, TestClient(app))


def test_security_headers_present():
    response = cast(Response, client.get("/"))
    assert response.status_code == 200
    headers = response.headers

    assert "Content-Security-Policy" in headers
    assert "default-src 'self'" in headers["Content-Security-Policy"]
    assert headers.get("X-Content-Type-Options") == "nosniff"
    assert headers.get("X-Frame-Options") == "DENY"
    assert headers.get("X-XSS-Protection") == "1; mode=block"
    assert headers.get("Referrer-Policy") == "strict-origin-when-cross-origin"
    assert "Strict-Transport-Security" in headers
    assert "Permissions-Policy" in headers
    assert headers.get("Server") == "Nexus-Engine"


def test_favicon_and_manifest_routes():
    routes = [
        "/favicon.ico",
        "/favicon-16x16.png",
        "/favicon-32x32.png",
        "/apple-touch-icon.png",
        "/android-chrome-192x192.png",
        "/android-chrome-512x512.png",
        "/site.webmanifest",
        "/logo.png",
        "/logo-foreground.png",
        "/og-image.png",
        "/nexus-wide-logo.jpg",
        "/robots.txt",
        "/sitemap.xml",
    ]
    for r in routes:
        res = cast(Response, client.get(r))
        assert res.status_code == 200, f"Route {r} failed with status {res.status_code}"


def test_landing_page_html_accessibility_and_social():
    res = cast(Response, client.get("/"))
    assert res.status_code == 200
    html = res.text

    # Favicon and metadata check
    assert 'rel="icon"' in html
    assert 'href="/favicon.ico"' in html
    assert 'href="/site.webmanifest"' in html
    assert 'content="/nexus-wide-logo.jpg"' in html

    # Accessibility (a11y) check
    assert 'role="banner"' in html
    assert 'role="main"' in html
    assert 'role="contentinfo"' in html
    assert "Skip to main content" in html

    # Social media icons check
    href_values: list[str] = re.findall(r'href="([^"]+)"', html)
    external_hosts: set[str] = {
        host
        for href in href_values
        if href.startswith(("http://", "https://"))
        and (host := urlparse(href).hostname) is not None
    }
    expected_hosts = {
        "play.google.com",
        "devakesu.com",
    }
    assert expected_hosts.issubset(external_hosts)


def test_request_payload_size_limit():
    large_headers = {"Content-Length": str(15 * 1024 * 1024)}  # 15 MB
    res = cast(
        Response,
        client.post(
            "/api/v1/user/update",
            headers=large_headers,
            json={"test": "data"},
        ),
    )
    assert res.status_code == 413
    detail_content = cast(dict[str, Any], res.json())
    assert "Payload too large" in detail_content["detail"]


def test_request_streaming_payload_size_limit():
    # Large content > 10MB sent as body content
    large_data = "x" * (11 * 1024 * 1024)
    res = cast(
        Response,
        client.post(
            "/api/v1/user/update",
            content=large_data,
            headers={"Content-Type": "text/plain"},
        ),
    )
    assert res.status_code == 413
    detail_content = cast(dict[str, Any], res.json())
    assert "Payload too large" in detail_content["detail"]



def test_error_page_rendering():
    # HTML request to nonexistent endpoint (404)
    res_html = cast(
        Response,
        client.get("/nonexistent-page-url", headers={"Accept": "text/html"}),
    )
    assert res_html.status_code == 404
    assert "HTTP STATUS 404" in res_html.text
    assert "Signal Lost" in res_html.text

    # JSON request to nonexistent endpoint (404)
    res_json = cast(
        Response,
        client.get("/nonexistent-page-url", headers={"Accept": "application/json"}),
    )
    assert res_json.status_code == 404
    assert res_json.json()["detail"] == "Not Found"

    # Explicit /error route testing with custom parameters
    res_error = cast(
        Response,
        client.get("/error?code=500&message=Database+connection+failed"),
    )
    assert res_error.status_code == 500
    assert "HTTP STATUS 500" in res_error.text
    assert "Internal Anomaly" in res_error.text
    assert "Database connection failed" in res_error.text


def test_footers_and_active_page_bars():
    # 1. Home page must use main cosmic constellation footer and QR modal
    res_home = cast(Response, client.get("/"))
    assert res_home.status_code == 200
    assert 'id="qr-modal"' in res_home.text
    assert "footer-grid" in res_home.text

    # 2. Sub-pages must use secondary footer with active page highlight
    res_help = cast(Response, client.get("/help"))
    assert res_help.status_code == 200
    assert 'class="footer-link active"' in res_help.text
    assert 'href="/help" class="footer-link active"' in res_help.text

    res_legal = cast(Response, client.get("/legal"))
    assert res_legal.status_code == 200
    assert 'class="footer-link active"' in res_legal.text
    assert 'href="/legal" class="footer-link active"' in res_legal.text

    res_contact = cast(Response, client.get("/contact"))
    assert res_contact.status_code == 200
    assert 'class="footer-link active"' in res_contact.text
    assert 'href="/contact" class="footer-link active"' in res_contact.text

    res_delete = cast(Response, client.get("/delete-account"))
    assert res_delete.status_code == 200
    assert 'class="footer-link active"' in res_delete.text
    assert 'href="/delete-account" class="footer-link active"' in res_delete.text


def test_settings_twilio_signing_key_validation():
    import pytest
    from app.core.config import Settings

    # Setting Twilio without hmac_signing_key should raise ValueError
    with pytest.raises(ValueError, match="hmac_signing_key is required when Twilio SMS credentials are configured"):
        Settings(
            app_domain="test.example.com",
            debug=True,
            twilio_account_sid="AC1234567890",
            twilio_auth_token="auth_tok_123",
            twilio_from_number="+15555555555",
            hmac_signing_key="",
        )
