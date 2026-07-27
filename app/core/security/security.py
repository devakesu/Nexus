"""Security headers and HTTP request size protection middleware.

Enforces HTTP Security Headers (CSP, HSTS, X-Frame-Options, Permissions-Policy)
and enforces a 10MB payload size limit on incoming request bodies to prevent Denial-of-Service.
"""

import logging
from typing import ClassVar

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.responses import JSONResponse

logger = logging.getLogger(__name__)

# 10 MB maximum request payload size limit
MAX_REQUEST_BODY_SIZE = 10 * 1024 * 1024


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    """Middleware that attaches strict security headers and dynamic cache-control policies."""

    STATIC_ROUTES: ClassVar[set[str]] = {
        "/favicon.ico",
        "/favicon-16x16.png",
        "/favicon-32x32.png",
        "/apple-touch-icon.png",
        "/android-chrome-192x192.png",
        "/android-chrome-512x512.png",
        "/logo.png",
        "/logo-foreground.png",
        "/og-image.png",
        "/nexus-wide-logo.jpg",
        "/site.webmanifest",
        "/robots.txt",
        "/sitemap.xml",
    }

    async def dispatch(
        self,
        request: Request,
        call_next: RequestResponseEndpoint,
    ) -> Response:
        """Processes request and attaches security and cache control headers to response.

        Args:
            request: Incoming HTTP Request instance.
            call_next: Next request endpoint handler.

        Returns:
            Response: HTTP response with added security headers.
        """
        response = await call_next(request)

        # Security Headers
        headers = response.headers
        headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self' 'unsafe-inline' "
            "https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://unpkg.com; "
            "style-src 'self' 'unsafe-inline' "
            "https://fonts.googleapis.com https://cdn.jsdelivr.net "
            "https://cdnjs.cloudflare.com https://unpkg.com; "
            "font-src 'self' https://fonts.gstatic.com "
            "https://cdnjs.cloudflare.com data:; "
            "img-src 'self' data: https: blob:; "
            "connect-src 'self' https: wss:; "
            "frame-ancestors 'none'; "
            "form-action 'self'; "
            "base-uri 'self'; "
            "object-src 'none'; "
            "upgrade-insecure-requests;"
        )
        headers["X-Content-Type-Options"] = "nosniff"
        headers["X-Frame-Options"] = "DENY"
        headers["X-XSS-Protection"] = "1; mode=block"
        headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        headers["Permissions-Policy"] = (
            "camera=(), microphone=(), geolocation=(), payment=(), "
            "usb=(), display-capture=(), accelerometer=(), gyroscope=()"
        )
        headers["Strict-Transport-Security"] = (
            "max-age=31536000; includeSubDomains; preload"
        )
        headers["X-Permitted-Cross-Domain-Policies"] = "none"
        headers["Cross-Origin-Opener-Policy"] = "same-origin"

        path = request.url.path
        if path.startswith("/static/") or path in self.STATIC_ROUTES:
            headers["Cross-Origin-Resource-Policy"] = "cross-origin"
            headers["Cache-Control"] = (
                "public, max-age=86400, stale-while-revalidate=604800"
            )
        else:
            headers["Cross-Origin-Resource-Policy"] = "same-origin"
            if path.startswith("/api/"):
                headers["Cache-Control"] = "no-store, max-age=0"

        headers["Server"] = "Nexus-Engine"
        return response


class RequestSizeLimitMiddleware(BaseHTTPMiddleware):
    """Middleware preventing payload size abuse by rejecting bodies > 10MB."""

    async def dispatch(
        self,
        request: Request,
        call_next: RequestResponseEndpoint,
    ) -> Response:
        """Enforces Content-Length limits on incoming request payloads.

        Args:
            request: Incoming HTTP Request instance.
            call_next: Next request handler endpoint.

        Returns:
            Response: 413 JSONResponse if payload exceeds limit, or downstream Response.
        """
        content_length = request.headers.get("content-length")
        if content_length:
            try:
                if int(content_length) > MAX_REQUEST_BODY_SIZE:
                    logger.warning(
                        "Request payload exceeded max size: %s bytes",
                        content_length,
                    )
                    return JSONResponse(
                        status_code=413,
                        content={
                            "detail": (
                                "Payload too large. "
                                "Maximum allowed request payload is 10MB."
                            ),
                        },
                    )
            except ValueError:
                pass

        return await call_next(request)

