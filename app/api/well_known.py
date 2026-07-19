import logging

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from app.core.config import settings

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/.well-known/apple-app-site-association")
def apple_app_site_association(request: Request) -> JSONResponse:
    _ = request
    content = {
        "applinks": {
            "apps": [],
            "details": [
                {
                    "appID": f"{settings.apple_team_id}.com.devakesu.apps.nexus",
                    "paths": ["*"],
                },
                {
                    "appID": f"{settings.apple_team_id}.com.devakesu.apps.nexus.mec",
                    "paths": ["*"],
                },
            ],
        },
    }
    return JSONResponse(content=content)


@router.get("/.well-known/assetlinks.json")
def assetlinks(request: Request) -> JSONResponse:
    _ = request
    content = [
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "com.devakesu.apps.nexus",
                "sha256_cert_fingerprints": [settings.android_sha256_fingerprint],
            },
        },
        {
            "relation": ["delegate_permission/common.handle_all_urls"],
            "target": {
                "namespace": "android_app",
                "package_name": "com.devakesu.apps.nexus.mec",
                "sha256_cert_fingerprints": [settings.android_sha256_fingerprint],
            },
        },
    ]
    return JSONResponse(content=content)
