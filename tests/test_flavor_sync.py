from datetime import datetime, timezone
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request, status

from app.api.user.sync import create_export_code, import_from_flavor
from app.models import ImportRequest


@pytest.mark.anyio
async def test_create_export_code_rejected_when_deletion_pending() -> None:
    auth_user = {
        "id": "flavor-user-1",
        "email": "student@mec.ac.in",
    }
    mock_profile = {"id": "flavor-user-1", "name": "Student"}
    mock_user_row = {
        "id": "flavor-user-1",
        "app_variant": "nexus_mec",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": "2026-08-01T12:00:00+00:00",
    }

    mock_request = MagicMock(spec=Request)

    with patch("app.api.user.sync.fetch_profile", return_value=mock_profile), patch(
        "app.api.user.sync.fetch_public_user", return_value=mock_user_row,
    ):
        with pytest.raises(HTTPException) as exc_info:
            await create_export_code(
                request=mock_request,
                _device=None,
                auth_user=auth_user,
            )

        assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
        assert "Account is pending deletion" in exc_info.value.detail


@pytest.mark.anyio
async def test_create_export_code_succeeds_when_active_and_flavor_variant() -> None:
    auth_user = {
        "id": "flavor-user-2",
        "email": "student2@mec.ac.in",
    }
    mock_profile = {"id": "flavor-user-2", "name": "Student 2"}
    mock_user_row = {
        "id": "flavor-user-2",
        "app_variant": "nexus_mec",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": None,
    }
    mock_exp = datetime(2026, 8, 13, 20, 0, 0, tzinfo=timezone.utc)

    mock_request = MagicMock(spec=Request)

    with patch("app.api.user.sync.fetch_profile", return_value=mock_profile), patch(
        "app.api.user.sync.fetch_public_user", return_value=mock_user_row,
    ), patch("app.api.user.sync.generate_export_code", AsyncMock(return_value=("ABC123", mock_exp))):
        response = await create_export_code(
            request=mock_request,
            _device=None,
            auth_user=auth_user,
        )

        assert response.code == "ABC123"
        assert response.expires_at == mock_exp


@pytest.mark.anyio
async def test_import_from_flavor_rejected_when_deletion_pending() -> None:
    auth_user = {
        "id": "main-user-1",
        "email": "main@example.com",
    }
    mock_user_row = {
        "id": "main-user-1",
        "app_variant": "nexus",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": "2026-08-01T12:00:00+00:00",
    }

    mock_request = MagicMock(spec=Request)
    payload = ImportRequest(sync_code="ABC123")

    with patch("app.api.user.sync.fetch_public_user", return_value=mock_user_row), patch(
        "app.api.user.sync.redis_client.get", AsyncMock(return_value=None),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await import_from_flavor(
                request=mock_request,
                payload=payload,
                _device=None,
                auth_user=auth_user,
            )

        assert exc_info.value.status_code == status.HTTP_403_FORBIDDEN
        assert "Account is pending deletion" in exc_info.value.detail


@pytest.mark.anyio
async def test_import_from_flavor_invalid_code_increments_attempts() -> None:
    auth_user = {
        "id": "main-user-2",
        "email": "main2@example.com",
    }
    mock_user_row = {
        "id": "main-user-2",
        "app_variant": "nexus",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": None,
    }
    mock_request = MagicMock(spec=Request)
    payload = ImportRequest(sync_code="INVLD1")

    mock_redis = AsyncMock()
    mock_redis.get.return_value = None

    with patch("app.api.user.sync.fetch_public_user", return_value=mock_user_row), patch(
        "app.api.user.sync.redis_client", mock_redis,
    ), patch(
        "app.api.user.sync.execute_import",
        side_effect=HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or already-used export code."),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await import_from_flavor(
                request=mock_request,
                payload=payload,
                _device=None,
                auth_user=auth_user,
            )

        assert exc_info.value.status_code == status.HTTP_400_BAD_REQUEST
        mock_redis.incr.assert_any_call("import:attempts:main-user-2")
        mock_redis.incr.assert_any_call("import:code_attempts:INVLD1")


@pytest.mark.anyio
async def test_import_from_flavor_other_error_does_not_increment_attempts() -> None:
    auth_user = {
        "id": "main-user-3",
        "email": "main3@example.com",
    }
    mock_user_row = {
        "id": "main-user-3",
        "app_variant": "nexus",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": None,
    }
    mock_request = MagicMock(spec=Request)
    payload = ImportRequest(sync_code="EXPIR1")

    mock_redis = AsyncMock()
    mock_redis.get.return_value = None

    with patch("app.api.user.sync.fetch_public_user", return_value=mock_user_row), patch(
        "app.api.user.sync.redis_client", mock_redis,
    ), patch(
        "app.api.user.sync.execute_import",
        side_effect=HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Export code has expired. Please generate a new one from the flavor app."),
    ):
        with pytest.raises(HTTPException) as exc_info:
            await import_from_flavor(
                request=mock_request,
                payload=payload,
                _device=None,
                auth_user=auth_user,
            )

        assert exc_info.value.status_code == status.HTTP_400_BAD_REQUEST
        mock_redis.incr.assert_not_called()

