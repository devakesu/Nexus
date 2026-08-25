from datetime import datetime, timedelta, timezone
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
        import hashlib
        invld_hash = hashlib.sha256(b"INVLD1").hexdigest()[:16]
        mock_redis.incr.assert_any_call(f"import:code_attempts:{invld_hash}")


@pytest.mark.anyio
async def test_import_from_flavor_reaching_max_attempts_raises_429() -> None:
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
    mock_redis.get.return_value = "4"
    mock_redis.incr.return_value = 5

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

        assert exc_info.value.status_code == status.HTTP_429_TOO_MANY_REQUESTS
        assert "Too many failed import attempts" in exc_info.value.detail



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


def test_execute_import_reencrypts_encrypted_fields() -> None:
    from app.db.users.import_export import execute_import

    source_profile = {
        "id": "flavor-user-10",
        "app_variant": "nexus_mec",
        "campus_branch": "CSE",
        "lifestyle": "\\x6f6c64636970686572",
        "search_bucket": "M",
        "import_sync_expires_at": (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat(),
    }
    target_profile = {
        "id": "main-user-10",
        "app_variant": "nexus",
        "campus_branch": "CSE",
        "lifestyle": None,
    }
    source_user_row = {
        "id": "flavor-user-10",
        "app_variant": "nexus_mec",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": None,
    }

    with patch(
        "app.db.users.import_export._fetch_import_profiles",
        return_value=(source_profile, target_profile),
    ), patch(
        "app.db.users.import_export.fetch_public_user",
        return_value=source_user_row,
    ), patch(
        "app.db.users.import_export.decrypt_pii",
        return_value="Active gym goer",
    ) as mock_decrypt, patch(
        "app.db.users.import_export.encrypt_to_hex",
        return_value="\\x6e6577636970686572",
    ) as mock_encrypt, patch(
        "app.db.users.import_export.supabase_client.table",
    ) as mock_table:
        # Mock CAS nullify and target update
        mock_builder = MagicMock()
        mock_builder.update.return_value = mock_builder
        mock_builder.eq.return_value = mock_builder
        mock_builder.execute.return_value = MagicMock(data=[{"id": "flavor-user-10"}])
        mock_table.return_value = mock_builder

        copied = execute_import(target_user_id="main-user-10", sync_code="XYZ789")

        assert "lifestyle" in copied
        assert "search_bucket" in copied

        mock_decrypt.assert_called_once_with("\\x6f6c64636970686572", category="profile")
        mock_encrypt.assert_called_once_with("Active gym goer", category="profile")


def test_execute_import_undecryptable_field_fails_409() -> None:
    from app.core.security.crypto import DecryptFailedError
    from app.db.users.import_export import execute_import

    source_profile = {
        "id": "flavor-user-10",
        "app_variant": "nexus_mec",
        "campus_branch": "CSE",
        "lifestyle": "\\xdeadbeef",
        "import_sync_expires_at": (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat(),
    }
    target_profile = {
        "id": "main-user-10",
        "app_variant": "nexus",
        "campus_branch": "CSE",
    }
    source_user_row = {
        "id": "flavor-user-10",
        "app_variant": "nexus_mec",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": None,
    }

    with patch(
        "app.db.users.import_export._fetch_import_profiles",
        return_value=(source_profile, target_profile),
    ), patch(
        "app.db.users.import_export.fetch_public_user",
        return_value=source_user_row,
    ), patch(
        "app.db.users.import_export.decrypt_pii",
        side_effect=DecryptFailedError("Corrupted or wrong rotation key"),
    ):
        with pytest.raises(HTTPException) as exc_info:
            execute_import(target_user_id="main-user-10", sync_code="XYZ789")

        assert exc_info.value.status_code == status.HTTP_409_CONFLICT
        assert "corrupted or undecryptable data in field 'lifestyle'" in exc_info.value.detail


def test_execute_import_concurrent_claim_fails_409() -> None:
    from app.db.users.import_export import execute_import

    source_profile = {
        "id": "flavor-user-11",
        "app_variant": "nexus_mec",
        "campus_branch": "CSE",
        "import_sync_expires_at": (datetime.now(timezone.utc) + timedelta(minutes=10)).isoformat(),
    }
    target_profile = {
        "id": "main-user-11",
        "app_variant": "nexus",
        "campus_branch": "CSE",
    }
    source_user_row = {
        "id": "flavor-user-11",
        "app_variant": "nexus_mec",
        "is_active": True,
        "is_suspended": False,
        "deletion_requested_at": None,
    }

    with patch(
        "app.db.users.import_export._fetch_import_profiles",
        return_value=(source_profile, target_profile),
    ), patch(
        "app.db.users.import_export.fetch_public_user",
        return_value=source_user_row,
    ), patch(
        "app.db.users.import_export.supabase_client.table",
    ) as mock_table:
        # CAS nullify returns empty data (already claimed concurrently)
        mock_builder = MagicMock()
        mock_builder.update.return_value = mock_builder
        mock_builder.eq.return_value = mock_builder
        mock_builder.execute.return_value = MagicMock(data=[])
        mock_table.return_value = mock_builder

        with pytest.raises(HTTPException) as exc_info:
            execute_import(target_user_id="main-user-11", sync_code="RACE99")

        assert exc_info.value.status_code == status.HTTP_409_CONFLICT
        assert "Export code was already claimed" in exc_info.value.detail


@pytest.mark.anyio
async def test_generate_export_code_deletes_both_old_code_and_user_attempts_in_redis() -> None:
    """generate_export_code removes both old code attempts and per-user attempts from Redis."""
    import hashlib
    from app.db.users.import_export import generate_export_code

    mock_redis = AsyncMock()
    mock_redis.delete.return_value = True

    with patch("app.db.users.import_export.supabase_client.table") as mock_table, \
         patch("app.db.users.import_export.redis_client", mock_redis):
        mock_builder = MagicMock()
        mock_builder.select.return_value = mock_builder
        mock_builder.eq.return_value = mock_builder
        mock_builder.maybe_single.return_value = mock_builder
        mock_builder.execute.return_value = MagicMock(data={"import_sync_code": "OLD123"})
        mock_builder.update.return_value = mock_builder
        mock_table.return_value = mock_builder

        code, expires_at = await generate_export_code("user-reset-test")

        assert len(code) == 6
        assert isinstance(expires_at, datetime)
        expected_hash = hashlib.sha256(b"OLD123").hexdigest()[:16]
        mock_redis.delete.assert_any_call(f"import:code_attempts:{expected_hash}")
        mock_redis.delete.assert_any_call("import:attempts:user-reset-test")


@pytest.mark.anyio
async def test_import_from_flavor_hashes_sync_code_in_redis_key() -> None:
    """import_from_flavor checks and records code attempts using sha256 hash."""
    import hashlib

    auth_user = {"id": "main-user-hash-test"}
    mock_user_row = {"id": "main-user-hash-test", "app_variant": "nexus", "is_active": True}
    mock_redis = AsyncMock()
    mock_redis.get.return_value = None

    sync_code = "SEC999"
    expected_hash = hashlib.sha256(b"SEC999").hexdigest()[:16]

    with patch("app.api.user.sync.redis_client", mock_redis), \
         patch("app.api.user.sync.fetch_public_user", return_value=mock_user_row), \
         patch("app.api.user.sync.execute_import", return_value=["display_gender"]):
        req = MagicMock(spec=Request)
        res = await import_from_flavor(
            request=req,
            payload=ImportRequest(sync_code=sync_code),
            _device=None,
            auth_user=auth_user,
        )

        assert res.success is True
        mock_redis.get.assert_any_call(f"import:code_attempts:{expected_hash}")
