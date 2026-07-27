"""Trusted contact portal authentication and safety alert management endpoints package.

Refactored from monolithic safety_portal.py to support modular HTML templates and endpoints.
Exposes the unified router symbol for mounting in the main application.
"""

from app.api.safety_portal.endpoints import router

__all__ = [
    "router",
]
