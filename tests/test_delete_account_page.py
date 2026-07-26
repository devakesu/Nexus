from typing import Any, cast

from fastapi.testclient import TestClient
from httpx import Response

from app.main import app

client = cast(Any, TestClient(app))


def test_delete_account_page_normal_renders_header_and_footer() -> None:
    response = cast(Response, client.get("/delete-account"))
    assert response.status_code == 200
    text = response.text
    assert 'role="banner"' in text or "<header" in text
    assert "Delete Account" in text or "<footer" in text
    assert "Account Deletion &amp; Data Rights" in text
    assert "Backup Your Account Data" in text
    assert "Export My Data" in text
    assert "DELETE" in text
    assert "otp-modal" in text
    assert "user-email-input" in text
    assert "otp-code-input" in text
    assert "/api/v1/account/export/otp/request" in text
    assert "/api/v1/account/deletion/request" in text


def test_delete_account_page_embed_hides_header_and_footer() -> None:
    response = cast(Response, client.get("/delete-account?embed=true"))
    assert response.status_code == 200
    text = response.text
    assert 'role="banner"' not in text
    assert "<footer" not in text
    assert "Account Deletion &amp; Data Rights" in text
    assert "Grace Period" in text


def test_account_deletion_otp_request_missing_email_returns_400() -> None:
    response = cast(
        Response, client.post("/api/v1/account/deletion/otp/request", json={}),
    )
    assert response.status_code == 400


def test_account_export_otp_request_missing_email_returns_400() -> None:
    response = cast(
        Response, client.post("/api/v1/account/export/otp/request", json={}),
    )
    assert response.status_code == 400
