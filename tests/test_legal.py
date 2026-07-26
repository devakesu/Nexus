from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_legal_page_normal_renders_header_and_footer() -> None:
    response = client.get("/legal")  # type: ignore[no-untyped-call, no-any-return, type-arg]
    assert response.status_code == 200  # type: ignore[attr-defined]
    text = str(response.text)  # type: ignore[attr-defined]
    assert 'role="banner"' in text or "<header" in text
    assert "Privacy & Terms" in text or "<footer" in text


def test_legal_page_embed_hides_header_and_footer() -> None:
    response = client.get("/legal?embed=true")  # type: ignore[no-untyped-call, no-any-return, type-arg]
    assert response.status_code == 200  # type: ignore[attr-defined]
    text = str(response.text)  # type: ignore[attr-defined]
    assert 'role="banner"' not in text
    assert "<footer" not in text
    assert "Terms of Service" in text or "Legal & Privacy" in text
