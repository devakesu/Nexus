from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from fastapi import HTTPException, Request, status

from app.api.user.auth_otp import auth_bootstrap
from app.models import AuthBootstrapResponse


@pytest.mark.anyio
async def test_auth_bootstrap_suspended_user_does_not_upsert() -> None:
    auth_user = {
        "id": "banned-user-123",
        "email": "user@example.com",
        "app_metadata": {"app_variant": "nexus"},
    }
    existing_row = {
        "id": "banned-user-123",
        "is_active": True,
        "is_suspended": True,
        "moderation_status": "suspended",
        "accepted_terms_version": "1.0",
        "purged_at": None,
    }

    mock_request = MagicMock(spec=Request)
    mock_upsert = MagicMock()

    with patch("app.api.user.auth_otp.fetch_public_user", return_value=existing_row), patch(
        "app.api.user.auth_otp.upsert_public_user", mock_upsert,
    ), patch("app.api.user.auth_otp.fetch_profile", return_value=None), patch(
        "app.api.user.auth_otp.is_allowed_email", return_value=True,
    ):
        response: AuthBootstrapResponse = await auth_bootstrap(
            request=mock_request,
            _device=None,
            auth_user=auth_user,
        )

        assert response.user_id == "banned-user-123"
        assert response.is_suspended is True
        assert response.newly_created is False
        mock_upsert.assert_not_called()


@pytest.mark.anyio
async def test_auth_bootstrap_inactive_user_does_not_upsert() -> None:
    auth_user = {
        "id": "inactive-user-456",
        "email": "user@example.com",
        "app_metadata": {"app_variant": "nexus"},
    }
    existing_row = {
        "id": "inactive-user-456",
        "is_active": False,
        "is_suspended": False,
        "moderation_status": "approved",
        "purged_at": None,
    }

    mock_request = MagicMock(spec=Request)
    mock_upsert = MagicMock()

    with patch("app.api.user.auth_otp.fetch_public_user", return_value=existing_row), patch(
        "app.api.user.auth_otp.upsert_public_user", mock_upsert,
    ), patch("app.api.user.auth_otp.fetch_profile", return_value=None), patch(
        "app.api.user.auth_otp.is_allowed_email", return_value=True,
    ):
        response: AuthBootstrapResponse = await auth_bootstrap(
            request=mock_request,
            _device=None,
            auth_user=auth_user,
        )

        assert response.user_id == "inactive-user-456"
        assert response.is_active is False
        assert response.newly_created is False
        mock_upsert.assert_not_called()


@pytest.mark.anyio
async def test_auth_bootstrap_purged_user_does_not_upsert() -> None:
    auth_user = {
        "id": "purged-user-789",
        "email": "user@example.com",
        "app_metadata": {"app_variant": "nexus"},
    }
    existing_row = {
        "id": "purged-user-789",
        "is_active": False,
        "is_suspended": False,
        "moderation_status": "approved",
        "purged_at": "2026-08-01T12:00:00+00:00",
    }

    mock_request = MagicMock(spec=Request)
    mock_upsert = MagicMock()

    with patch("app.api.user.auth_otp.fetch_public_user", return_value=existing_row), patch(
        "app.api.user.auth_otp.upsert_public_user", mock_upsert,
    ), patch("app.api.user.auth_otp.fetch_profile", return_value=None), patch(
        "app.api.user.auth_otp.is_allowed_email", return_value=True,
    ):
        response: AuthBootstrapResponse = await auth_bootstrap(
            request=mock_request,
            _device=None,
            auth_user=auth_user,
        )

        assert response.user_id == "purged-user-789"
        assert response.newly_created is False
        mock_upsert.assert_not_called()


@pytest.mark.anyio
async def test_auth_bootstrap_active_user_calls_upsert() -> None:
    auth_user = {
        "id": "active-user-111",
        "email": "user@example.com",
        "app_metadata": {"app_variant": "nexus"},
    }
    existing_row = {
        "id": "active-user-111",
        "is_active": True,
        "is_suspended": False,
        "moderation_status": "approved",
        "purged_at": None,
    }
    upserted_row = {
        "id": "active-user-111",
        "is_active": True,
        "is_suspended": False,
        "moderation_status": "approved",
        "purged_at": None,
    }

    mock_request = MagicMock(spec=Request)
    mock_upsert = MagicMock(return_value=(upserted_row, False))

    with patch("app.api.user.auth_otp.fetch_public_user", return_value=existing_row), patch(
        "app.api.user.auth_otp.upsert_public_user", mock_upsert,
    ), patch("app.api.user.auth_otp.fetch_profile", return_value=None), patch(
        "app.api.user.auth_otp.is_allowed_email", return_value=True,
    ):
        response: AuthBootstrapResponse = await auth_bootstrap(
            request=mock_request,
            _device=None,
            auth_user=auth_user,
        )

        assert response.user_id == "active-user-111"
        assert response.is_active is True
        assert response.is_suspended is False
        mock_upsert.assert_called_once_with("active-user-111", "nexus")


@pytest.mark.anyio
async def test_auth_bootstrap_new_user_calls_upsert() -> None:
    auth_user = {
        "id": "new-user-222",
        "email": "newuser@example.com",
        "app_metadata": {"app_variant": "nexus"},
    }
    upserted_row = {
        "id": "new-user-222",
        "is_active": True,
        "is_suspended": False,
        "moderation_status": "approved",
        "purged_at": None,
    }

    mock_request = MagicMock(spec=Request)
    mock_upsert = MagicMock(return_value=(upserted_row, True))

    with patch("app.api.user.auth_otp.fetch_public_user", return_value=None), patch(
        "app.api.user.auth_otp.upsert_public_user", mock_upsert,
    ), patch("app.api.user.auth_otp.fetch_profile", return_value=None), patch(
        "app.api.user.auth_otp.is_allowed_email", return_value=True,
    ), patch("app.api.user.auth_otp.send_bootstrap_welcome_email", AsyncMock()) as mock_welcome:
        response: AuthBootstrapResponse = await auth_bootstrap(
            request=mock_request,
            _device=None,
            auth_user=auth_user,
        )

        assert response.user_id == "new-user-222"
        assert response.newly_created is True
        mock_upsert.assert_called_once_with("new-user-222", "nexus")
        mock_welcome.assert_called_once()


@pytest.mark.anyio
async def test_auth_bootstrap_phone_only_on_restricted_variant_blocked() -> None:
    auth_user = {
        "id": "phone-user-333",
        "phone": "+15551234567",
        "app_metadata": {"app_variant": "nexus_mec"},
    }

    mock_request = MagicMock(spec=Request)

    with patch(
        "app.api.user.auth_otp.settings.allowed_signup_domains",
        {"nexus_mec": ["mec.ac.in"]},
    ):
        with pytest.raises(HTTPException) as exc_info:
            await auth_bootstrap(
                request=mock_request,
                _device=None,
                auth_user=auth_user,
            )

        assert exc_info.value.status_code == status.HTTP_400_BAD_REQUEST
        assert "Email authentication is required for nexus_mec registration" in exc_info.value.detail


@pytest.mark.anyio
async def test_auth_bootstrap_phone_only_on_unrestricted_variant_allowed() -> None:
    auth_user = {
        "id": "phone-user-444",
        "phone": "+15551234567",
        "app_metadata": {"app_variant": "nexus"},
    }
    upserted_row = {
        "id": "phone-user-444",
        "is_active": True,
        "is_suspended": False,
        "moderation_status": "approved",
        "purged_at": None,
    }

    mock_request = MagicMock(spec=Request)
    mock_upsert = MagicMock(return_value=(upserted_row, True))

    with patch("app.api.user.auth_otp.fetch_public_user", return_value=None), patch(
        "app.api.user.auth_otp.upsert_public_user", mock_upsert,
    ), patch("app.api.user.auth_otp.fetch_profile", return_value=None):
        response: AuthBootstrapResponse = await auth_bootstrap(
            request=mock_request,
            _device=None,
            auth_user=auth_user,
        )

        assert response.user_id == "phone-user-444"
        assert response.newly_created is True
        mock_upsert.assert_called_once_with("phone-user-444", "nexus")


@pytest.mark.anyio
async def test_complete_onboarding_without_accepted_terms_fails() -> None:
    from app.api.user.auth_otp import complete_onboarding
    from app.models.user import NexusOnboardingRequest

    auth_user = {
        "id": "onboard-user-1",
        "email": "test@example.com",
    }
    user_row = {
        "id": "onboard-user-1",
        "is_active": True,
        "is_suspended": False,
        "accepted_terms_version": None,
    }
    payload = NexusOnboardingRequest(
        app_variant="nexus",
        name="Alex River",
        age=24,
        demographic_bucket="NB",
    )
    mock_request = MagicMock(spec=Request)

    with patch("app.api.user.auth_otp.fetch_public_user", return_value=user_row):
        with pytest.raises(HTTPException) as exc_info:
            await complete_onboarding(
                request=mock_request,
                payload=payload,
                _device=None,
                auth_user=auth_user,
            )

        assert exc_info.value.status_code == status.HTTP_400_BAD_REQUEST
        assert exc_info.value.detail == "Accept terms before completing onboarding."


@pytest.mark.anyio
async def test_complete_onboarding_with_accepted_terms_succeeds() -> None:
    from app.api.user.auth_otp import complete_onboarding
    from app.models.user import NexusOnboardingRequest

    auth_user = {
        "id": "onboard-user-2",
        "email": "test2@example.com",
    }
    user_row = {
        "id": "onboard-user-2",
        "is_active": True,
        "is_suspended": False,
        "accepted_terms_version": "1.0",
    }
    payload = NexusOnboardingRequest(
        app_variant="nexus",
        name="Alex River",
        age=24,
        demographic_bucket="NB",
    )
    mock_request = MagicMock(spec=Request)
    mock_upsert_profile = MagicMock(return_value=({"id": "onboard-user-2"}, True))

    with patch("app.api.user.auth_otp.fetch_public_user", return_value=user_row), patch(
        "app.api.user.auth_otp.fetch_profile", return_value=None,
    ), patch(
        "app.api.user.auth_otp.upsert_profile_variant", mock_upsert_profile,
    ):
        response = await complete_onboarding(
            request=mock_request,
            payload=payload,
            _device=None,
            auth_user=auth_user,
        )

        assert response.user_id == "onboard-user-2"
        assert response.profile_created is True
        mock_upsert_profile.assert_called_once()


def test_upsert_public_user_with_xmax_zero() -> None:
    from app.db.users.auth import upsert_public_user

    mock_builder = MagicMock()
    mock_builder.upsert.return_value = mock_builder
    mock_builder.select.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(
        data=[
            {
                "id": "new-user-1",
                "app_variant": "nexus",
                "is_active": True,
                "is_suspended": False,
                "xmax": "0",
            },
        ],
    )

    with patch("app.db.users.auth.supabase_client.table", return_value=mock_builder), patch(
        "app.db.users.auth.invalidate_user_status_cache",
    ):
        row, newly_created = upsert_public_user("new-user-1", "nexus")
        assert newly_created is True
        assert row["id"] == "new-user-1"
        assert "xmax" not in row


def test_upsert_public_user_with_xmax_nonzero() -> None:
    from app.db.users.auth import upsert_public_user

    mock_builder = MagicMock()
    mock_builder.upsert.return_value = mock_builder
    mock_builder.select.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(
        data=[
            {
                "id": "existing-user-1",
                "app_variant": "nexus",
                "is_active": True,
                "is_suspended": False,
                "xmax": "99999",
            },
        ],
    )

    with patch("app.db.users.auth.supabase_client.table", return_value=mock_builder), patch(
        "app.db.users.auth.invalidate_user_status_cache",
    ):
        row, newly_created = upsert_public_user("existing-user-1", "nexus")
        assert newly_created is False
        assert row["id"] == "existing-user-1"


def test_upsert_public_user_fallback_no_xmax_new_user() -> None:
    from app.db.users.auth import upsert_public_user

    mock_builder = MagicMock()
    mock_builder.upsert.return_value = mock_builder
    mock_builder.select.return_value = mock_builder
    # result.data has no xmax
    mock_builder.execute.return_value = MagicMock(
        data=[
            {
                "id": "new-user-2",
                "app_variant": "nexus",
                "is_active": True,
                "is_suspended": False,
                "accepted_terms_version": None,
                "terms_accepted_at": None,
                "special_category_consent_version": None,
                "deletion_requested_at": None,
                "xmax": None,
            },
        ],
    )

    with patch("app.db.users.auth.supabase_client.table", return_value=mock_builder), patch(
        "app.db.users.auth.invalidate_user_status_cache",
    ):
        row, newly_created = upsert_public_user("new-user-2", "nexus")
        assert newly_created is True
        assert row["id"] == "new-user-2"


def test_upsert_public_user_fallback_no_xmax_existing_user() -> None:
    from app.db.users.auth import upsert_public_user

    mock_builder = MagicMock()
    mock_builder.upsert.return_value = mock_builder
    mock_builder.select.return_value = mock_builder
    mock_builder.execute.return_value = MagicMock(
        data=[
            {
                "id": "existing-user-2",
                "app_variant": "nexus",
                "is_active": True,
                "is_suspended": False,
                "accepted_terms_version": "1.0",
                "terms_accepted_at": "2026-08-01T00:00:00Z",
                "xmax": None,
            },
        ],
    )

    with patch("app.db.users.auth.supabase_client.table", return_value=mock_builder), patch(
        "app.db.users.auth.invalidate_user_status_cache",
    ):
        row, newly_created = upsert_public_user("existing-user-2", "nexus")
        assert newly_created is False
        assert row["id"] == "existing-user-2"


def test_decrypt_mobile_handles_decryption_failure_with_error_log() -> None:
    from app.core.security.crypto import DecryptFailedError
    from app.db.users.auth import _decrypt_mobile

    row = {"id": "user-corrupted", "mobile": "bad-ciphertext"}
    with patch("app.db.users.auth.decrypt_pii", side_effect=DecryptFailedError("Corrupted PII")), patch(
        "app.db.users.auth.logger.error",
    ) as mock_log_error:
        res = _decrypt_mobile(row)
        assert res["mobile"] is None
        mock_log_error.assert_called_once()
        assert "Failed to decrypt mobile for user" in mock_log_error.call_args[0][0]


def test_get_user_id_by_email_guards_and_success() -> None:
    from app.db.users.auth import get_user_id_by_email

    # Invalid / empty
    assert get_user_id_by_email("") is None
    # No @
    assert get_user_id_by_email("invalid-email-address") is None
    # Starts with @
    assert get_user_id_by_email("@domain.com") is None
    # Ends with @
    assert get_user_id_by_email("user@") is None
    # Oversized (>254 chars)
    assert get_user_id_by_email("a" * 250 + "@example.com") is None

    # Valid lookup via RPC
    mock_rpc = MagicMock()
    mock_rpc.execute.return_value = MagicMock(data="user-found-uuid")
    with patch("app.db.users.auth.supabase_client.rpc", return_value=mock_rpc) as mock_supabase_rpc:
        user_id = get_user_id_by_email("  Valid.User@Example.Com  ")
        assert user_id == "user-found-uuid"
        mock_supabase_rpc.assert_called_once_with(
            "get_user_id_by_email",
            {"email_addr": "valid.user@example.com"},
        )



