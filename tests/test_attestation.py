from typing import Any, cast
from unittest.mock import MagicMock, patch

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

from app.api.dependencies import verify_and_get_app_check_claims
from app.api.user.auth_otp import get_attestation_status
from app.main import app
from app.models import AttestationResponse


def test_verify_and_get_app_check_claims_valid():
    mock_claims = {
        "app_id": "1:10892348:android:nexus",
        "sub": "1:10892348:android:nexus",
        "iss": "https://firebaseappcheck.googleapis.com/10892348",
        "iat": 1700000000,
        "exp": 1700003600,
        "aud": ["projects/10892348"],
    }
    with patch("app.api.dependencies.app_check.verify_token", return_value=mock_claims):
        claims = verify_and_get_app_check_claims(x_firebase_appcheck="valid_token_123")
        assert claims == mock_claims


def test_verify_and_get_app_check_claims_invalid_raises_403():
    with patch(
        "app.api.dependencies.app_check.verify_token",
        side_effect=Exception("Invalid token signature"),
    ):
        with pytest.raises(HTTPException) as exc_info:
            verify_and_get_app_check_claims(x_firebase_appcheck="invalid_token")
        assert exc_info.value.status_code == 403
        assert "integrity check failed" in exc_info.value.detail.lower()


def test_verify_and_get_app_check_claims_missing_enforced_raises_401():
    with patch("app.api.dependencies.settings.enforce_app_check", True):
        with pytest.raises(HTTPException) as exc_info:
            verify_and_get_app_check_claims(x_firebase_appcheck=None)
        assert exc_info.value.status_code == 401
        assert "Missing device attestation credentials" in exc_info.value.detail


def test_verify_and_get_app_check_claims_missing_unenforced_returns_none():
    with patch("app.api.dependencies.settings.enforce_app_check", False):
        claims = verify_and_get_app_check_claims(x_firebase_appcheck=None)
        assert claims is None


@pytest.mark.anyio
async def test_get_attestation_status_with_valid_claims():
    mock_request = MagicMock()
    mock_claims = {
        "app_id": "1:10892348:android:nexus",
        "sub": "1:10892348:android:nexus",
        "iss": "https://firebaseappcheck.googleapis.com/10892348",
        "iat": 1700000000,
        "exp": 1700003600,
    }
    response: AttestationResponse = await get_attestation_status(
        request=mock_request,
        claims=mock_claims,
    )
    assert response.verified is True
    assert response.appCheck is True
    assert response.appId == "1:10892348:android:nexus"
    assert response.details["provider"] == "Play Integrity / App Attest"
    assert response.details["issuer"] == "https://firebaseappcheck.googleapis.com/10892348"
    assert response.details["iat"] == 1700000000
    assert response.details["exp"] == 1700003600


@pytest.mark.anyio
async def test_get_attestation_status_debug_claims():
    mock_request = MagicMock()
    mock_claims = {
        "app_id": "1:10892348:android:nexus",
        "sub": "1:10892348:android:nexus",
        "iss": "https://firebaseappcheck.googleapis.com/debug/10892348",
        "iat": 1700000000,
        "exp": 1700003600,
    }
    response: AttestationResponse = await get_attestation_status(
        request=mock_request,
        claims=mock_claims,
    )
    assert response.verified is True
    assert response.appCheck is True
    assert response.details["provider"] == "debug"


@pytest.mark.anyio
async def test_get_attestation_status_unenforced_no_claims():
    mock_request = MagicMock()
    with patch("app.api.user.auth_otp.settings.debug", True):
        response: AttestationResponse = await get_attestation_status(
            request=mock_request,
            claims=None,
        )
        assert response.verified is True
        assert response.appCheck is False
        assert response.appId is None
        assert response.details["provider"] == "development"
        assert response.details["enforced"] is False


def test_attestation_endpoint_http_valid():
    client = cast(Any, TestClient(app))
    mock_claims = {
        "app_id": "1:10892348:android:nexus",
        "sub": "1:10892348:android:nexus",
        "iss": "https://firebaseappcheck.googleapis.com/10892348",
        "iat": 1700000000,
        "exp": 1700003600,
    }
    with patch("app.api.dependencies.app_check.verify_token", return_value=mock_claims):
        resp = client.get(
            "/api/v1/auth/attestation",
            headers={"X-Firebase-AppCheck": "valid_token"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["verified"] is True
        assert data["appCheck"] is True
        assert data["appId"] == "1:10892348:android:nexus"
        assert data["details"]["provider"] == "Play Integrity / App Attest"


def test_attestation_endpoint_http_invalid_token():
    client = cast(Any, TestClient(app))
    with patch(
        "app.api.dependencies.app_check.verify_token",
        side_effect=Exception("Invalid signature"),
    ):
        resp = client.get(
            "/api/v1/auth/attestation",
            headers={"X-Firebase-AppCheck": "bad_token"},
        )
        assert resp.status_code == 403


def test_attestation_endpoint_http_missing_token_enforced():
    client = cast(Any, TestClient(app))
    with patch("app.api.dependencies.settings.enforce_app_check", True):
        resp = client.get("/api/v1/auth/attestation")
        assert resp.status_code == 401


def test_attestation_endpoint_http_missing_token_unenforced():
    client = cast(Any, TestClient(app))
    with patch("app.api.dependencies.settings.enforce_app_check", False):
        resp = client.get("/api/v1/auth/attestation")
        assert resp.status_code == 200
        data = resp.json()
        assert data["verified"] is True
        assert data["appCheck"] is False
