from typing import Any, cast

from fastapi.testclient import TestClient
from httpx import Response

from app.main import app

client = TestClient(app)


def test_legal_page_normal_renders_header_and_footer() -> None:
    response = cast(Response, cast(Any, client).get("/legal"))
    assert response.status_code == 200
    text = str(response.text)
    assert 'role="banner"' in text or "<header" in text
    assert "Privacy & Terms" in text or "<footer" in text


def test_legal_page_embed_hides_header_and_footer() -> None:
    response = cast(Response, cast(Any, client).get("/legal?embed=true"))
    assert response.status_code == 200
    text = str(response.text)
    assert 'role="banner"' not in text
    assert "<footer" not in text
    assert "Terms of Service" in text or "Legal & Privacy" in text
