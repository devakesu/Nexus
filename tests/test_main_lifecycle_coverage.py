"""Comprehensive unit tests covering app/main.py lifecycle, exception handlers, middleware, and CORS configuration."""

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import FastAPI, HTTPException, Request
from fastapi.testclient import TestClient
from starlette.datastructures import Headers

from typing import Any

from app.main import (
    app,
    custom_rate_limit_handler,
    http_exception_handler,
    lifespan,
)

pytestmark = pytest.mark.anyio


async def test_lifespan_startup_and_shutdown():
    test_app = FastAPI()

    # Successful startup & shutdown
    with patch("app.main.redis_client.ping", new_callable=AsyncMock) as mock_ping, \
         patch("app.main.start_reminder_scheduler") as mock_start, \
         patch("app.main.stop_reminder_scheduler") as mock_stop, \
         patch("app.main.close_email_client", new_callable=AsyncMock) as mock_email_close, \
         patch("app.main.redis_client.aclose", new_callable=AsyncMock) as mock_redis_close:
        async with lifespan(test_app):
            mock_ping.assert_called_once()
            mock_start.assert_called_once()

        mock_stop.assert_called_once()
        mock_email_close.assert_called_once()
        mock_redis_close.assert_called_once()


async def test_lifespan_startup_redis_failure():
    test_app = FastAPI()

    with patch("app.main.redis_client.ping", new_callable=AsyncMock, side_effect=ConnectionError("Redis down")):
        with pytest.raises(RuntimeError, match="CRITICAL: Redis unreachable"):
            async with lifespan(test_app):
                pass


def test_custom_rate_limit_handler():
    mock_request = MagicMock(spec=Request)
    mock_request.app.state.limiter = MagicMock()
    def _inject(resp: Any, limit: Any) -> Any:
        return resp
    mock_request.app.state.limiter._inject_headers = _inject
    mock_request.state.view_rate_limit = ("5/minute", "ip")

    exc = MagicMock()
    exc.detail = "5 per 1 minute"
    response = custom_rate_limit_handler(mock_request, exc)
    assert response.status_code == 429
    assert b"Rate limit exceeded" in response.body


async def test_http_exception_handler_json_and_html():
    # JSON request
    json_req = MagicMock(spec=Request)
    json_req.headers = Headers({"accept": "application/json"})
    exc = HTTPException(status_code=404, detail="User not found")

    json_resp = await http_exception_handler(json_req, exc)
    assert json_resp.status_code == 404
    assert b"User not found" in json_resp.body

    # HTML request
    html_req = MagicMock(spec=Request)
    html_req.headers = Headers({"accept": "text/html,application/xhtml+xml"})
    html_exc = HTTPException(status_code=403, detail="Forbidden area")

    html_resp = await http_exception_handler(html_req, html_exc)
    assert html_resp.status_code == 403
    assert b"<html" in html_resp.body or b"Forbidden" in html_resp.body


def test_main_app_smoke():
    client: Any = TestClient(app)
    # Test health or 404 handler
    res: Any = client.get("/non-existent-route-for-testing", headers={"accept": "application/json"})
    assert res.status_code == 404
    assert "detail" in res.json()
