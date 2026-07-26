"""FastAPI router for serving iOS Universal Links and Android App Links configuration files.

Provides endpoints for `apple-app-site-association` and `assetlinks.json`.
"""

import logging

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from app.core.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()



@router.get("/.well-known/apple-app-site-association")
def apple_app_site_association(request: Request) -> JSONResponse:
    """Returns Apple Universal Links app site association configuration JSON.

    Args:
        request: Incoming HTTP request instance.

    Returns:
        JSONResponse: AASA configuration object.
    """
    _ = request
    team_id = settings.apple_team_id
    if not team_id:
        return JSONResponse(content={"applinks": {"apps": [], "details": []}})
    content = {
        "applinks": {
            "apps": [],
            "details": [
                {
                    "appID": f"{team_id}.com.devakesu.apps.nexus",
                    "paths": ["*"],
                },
                {
                    "appID": f"{team_id}.com.devakesu.apps.nexus.mec",
                    "paths": ["*"],
                },
            ],
        },
    }
    return JSONResponse(content=content)


@router.get("/.well-known/assetlinks.json")
def assetlinks(request: Request) -> JSONResponse:
    """Returns Android App Links asset links configuration JSON.

    Args:
        request: Incoming HTTP request instance.

    Returns:
        JSONResponse: Assetlinks configuration list.
    """
    _ = request
    fingerprint = settings.android_sha256_fingerprint
    if not fingerprint:
        return JSONResponse(content=[])
    content = [
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "com.devakesu.apps.nexus",
                "sha256_cert_fingerprints": [fingerprint],
            },
        },
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "com.devakesu.apps.nexus.mec",
                "sha256_cert_fingerprints": [fingerprint],
            },
        },
    ]
    return JSONResponse(content=content)

