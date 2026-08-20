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
async def test_auth_bootstrap_active_user_does_not_upsert() -> None:
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

        assert response.user_id == "active-user-111"
        assert response.is_active is True
        assert response.is_suspended is False
        assert response.newly_created is False
        mock_upsert.assert_not_called()


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
    ), patch("app.api.user.auth_otp.redis_client.set", AsyncMock(return_value=True)), patch(
        "app.api.user.auth_otp.send_bootstrap_welcome_email", AsyncMock(),
    ) as mock_welcome:
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


@pytest.mark.anyio
async def test_complete_onboarding_mismatched_app_variant_rejected() -> None:
    from app.api.user.auth_otp import complete_onboarding
    from app.models.user import NexusOnboardingRequest

    auth_user = {
        "id": "onboard-user-mec",
        "email": "student@mec.edu",
    }
    user_row = {
        "id": "onboard-user-mec",
        "is_active": True,
        "is_suspended": False,
        "accepted_terms_version": "1.0",
        "app_variant": "nexus_mec",
    }
    # Attempting to send NexusOnboardingRequest to a campus account
    payload = NexusOnboardingRequest(
        app_variant="nexus",
        name="Campus Student",
        age=35,
        demographic_bucket="M",
    )
    mock_request = MagicMock(spec=Request)

    with patch("app.api.user.auth_otp.fetch_public_user", return_value=user_row), patch(
        "app.api.user.auth_otp.fetch_profile", return_value=None,
    ):
        with pytest.raises(HTTPException) as exc_info:
            await complete_onboarding(
                request=mock_request,
                payload=payload,
                _device=None,
                auth_user=auth_user,
            )

        assert exc_info.value.status_code == status.HTTP_400_BAD_REQUEST
        assert "Invalid onboarding payload for account variant 'nexus_mec'" in exc_info.value.detail


@pytest.mark.anyio
async def test_complete_onboarding_campus_age_validation() -> None:
    from pydantic import ValidationError

    from app.models.user import MECOnboardingRequest

    # Pydantic schema validation rejects age > 27 for MECOnboardingRequest
    with pytest.raises(ValidationError):
        MECOnboardingRequest(
            app_variant="nexus_mec",
            campus_branch="CS",
            campus_year=3,
            campus_name="Model Engineering College",
            age=28,
        )


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

    with patch("app.db.users.auth.fetch_public_user", return_value=None), patch(
        "app.db.users.auth.supabase_client.table", return_value=mock_builder,
    ), patch(
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

    with patch("app.db.users.auth.fetch_public_user", return_value=None), patch(
        "app.db.users.auth.supabase_client.table", return_value=mock_builder,
    ), patch(
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

    with patch("app.db.users.auth.fetch_public_user", return_value=None), patch(
        "app.db.users.auth.supabase_client.table", return_value=mock_builder,
    ), patch(
        "app.db.users.auth.invalidate_user_status_cache",
    ):
        row, newly_created = upsert_public_user("new-user-2", "nexus")
        assert newly_created is True
        assert row["id"] == "new-user-2"


def test_upsert_public_user_existing_user_preserves_row() -> None:
    from app.db.users.auth import upsert_public_user

    existing_row = {
        "id": "existing-user-2",
        "app_variant": "nexus_mec",
        "is_active": True,
        "is_suspended": False,
    }

    with patch("app.db.users.auth.fetch_public_user", return_value=existing_row), patch(
        "app.db.users.auth.supabase_client.table",
    ) as mock_table:
        row, newly_created = upsert_public_user("existing-user-2", "nexus")
        assert newly_created is False
        assert row["id"] == "existing-user-2"
        assert row["app_variant"] == "nexus_mec"
        mock_table.assert_not_called()


@pytest.mark.anyio
async def test_auth_bootstrap_ignores_user_metadata_app_variant() -> None:
    """Verifies that client-supplied user_metadata.app_variant is ignored in favor of server-set app_metadata."""
    auth_user = {
        "id": "flavor-user-999",
        "email": "user@example.com",
        "user_metadata": {"app_variant": "nexus"},  # Client-crafted
        "app_metadata": {"app_variant": "nexus_mec"},  # Server-set
    }
    upserted_row = {
        "id": "flavor-user-999",
        "app_variant": "nexus_mec",
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
    ), patch("app.api.user.auth_otp.redis_client.set", AsyncMock(return_value=True)), patch(
        "app.api.user.auth_otp.send_bootstrap_welcome_email", AsyncMock(),
    ) as mock_welcome:
        response: AuthBootstrapResponse = await auth_bootstrap(
            request=mock_request,
            _device=None,
            auth_user=auth_user,
        )

        assert response.user_id == "flavor-user-999"
        mock_upsert.assert_called_once_with("flavor-user-999", "nexus_mec")
        mock_welcome.assert_called_once_with(
            email="user@example.com",
            auth_user=auth_user,
            app_variant="nexus_mec",
        )


@pytest.mark.anyio
async def test_auth_bootstrap_defaults_to_nexus_when_app_metadata_missing_even_if_user_metadata_set() -> None:
    """Verifies that if app_metadata has no app_variant, it defaults to 'nexus' and ignores user_metadata."""
    auth_user = {
        "id": "untrusted-user-111",
        "email": "user@example.com",
        "user_metadata": {"app_variant": "nexus_mec"},  # Client-injected variant attempt
        "app_metadata": {},  # No server-set app_variant
    }
    upserted_row = {
        "id": "untrusted-user-111",
        "app_variant": "nexus",
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
    ), patch("app.api.user.auth_otp.redis_client.set", AsyncMock(return_value=True)), patch(
        "app.api.user.auth_otp.send_bootstrap_welcome_email", AsyncMock(),
    ) as mock_welcome:
        response: AuthBootstrapResponse = await auth_bootstrap(
            request=mock_request,
            _device=None,
            auth_user=auth_user,
        )

        assert response.user_id == "untrusted-user-111"
        mock_upsert.assert_called_once_with("untrusted-user-111", "nexus")
        mock_welcome.assert_called_once_with(
            email="user@example.com",
            auth_user=auth_user,
            app_variant="nexus",
        )


@pytest.mark.anyio
async def test_auth_bootstrap_welcome_email_deduplication_via_redis() -> None:
    """Verifies that concurrent bootstrap calls do not duplicate welcome emails."""
    auth_user = {
        "id": "new-user-888",
        "email": "newuser@example.com",
        "app_metadata": {"app_variant": "nexus"},
    }
    upserted_row = {
        "id": "new-user-888",
        "is_active": True,
        "is_suspended": False,
        "moderation_status": "approved",
        "purged_at": None,
    }

    mock_request = MagicMock(spec=Request)
    mock_upsert = MagicMock(return_value=(upserted_row, True))
    mock_welcome = AsyncMock()

    # Case 1: First call acquires lock -> sends email
    with patch("app.api.user.auth_otp.fetch_public_user", return_value=None), patch(
        "app.api.user.auth_otp.upsert_public_user", mock_upsert,
    ), patch("app.api.user.auth_otp.fetch_profile", return_value=None), patch(
        "app.api.user.auth_otp.is_allowed_email", return_value=True,
    ), patch("app.api.user.auth_otp.redis_client.set", AsyncMock(return_value=True)), patch(
        "app.api.user.auth_otp.send_bootstrap_welcome_email", mock_welcome,
    ):
        await auth_bootstrap(request=mock_request, _device=None, auth_user=auth_user)
        assert mock_welcome.call_count == 1

    # Case 2: Concurrent/duplicate call fails to acquire lock -> skips email
    with patch("app.api.user.auth_otp.fetch_public_user", return_value=None), patch(
        "app.api.user.auth_otp.upsert_public_user", mock_upsert,
    ), patch("app.api.user.auth_otp.fetch_profile", return_value=None), patch(
        "app.api.user.auth_otp.is_allowed_email", return_value=True,
    ), patch("app.api.user.auth_otp.redis_client.set", AsyncMock(return_value=None)), patch(
        "app.api.user.auth_otp.send_bootstrap_welcome_email", mock_welcome,
    ):
        await auth_bootstrap(request=mock_request, _device=None, auth_user=auth_user)
        # Call count remains 1 (did not increment)
        assert mock_welcome.call_count == 1


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


@pytest.mark.anyio
async def test_auth_bootstrap_returns_masked_mobile_number() -> None:
    """Verify that auth_bootstrap returns a masked phone number in AuthBootstrapResponse."""
    auth_user = {
        "id": "user-mobile-123",
        "email": "user@example.com",
        "app_metadata": {"app_variant": "nexus"},
    }
    existing_row = {
        "id": "user-mobile-123",
        "is_active": True,
        "is_suspended": False,
        "moderation_status": "approved",
        "accepted_terms_version": "1.0",
        "purged_at": None,
        "mobile": "+919876543210",
        "mobile_verified_at": "2026-08-01T12:00:00+00:00",
    }

    mock_request = MagicMock(spec=Request)

    with patch("app.api.user.auth_otp.fetch_public_user", return_value=existing_row), \
         patch("app.api.user.auth_otp.fetch_profile", return_value=None), \
         patch("app.api.user.auth_otp.is_allowed_email", return_value=True):
        response: AuthBootstrapResponse = await auth_bootstrap(
            request=mock_request,
            _device=None,
            auth_user=auth_user,
        )

        assert response.user_id == "user-mobile-123"
        assert response.mobile == "+91******3210"
        assert response.mobile != "+919876543210"
        assert response.mobile_verified_at is not None


@pytest.mark.anyio
async def test_revoke_all_sessions_executes_global_signout_and_fcm_deactivation() -> None:
    """Verify that revoke_all_sessions triggers Supabase admin global sign-out, FCM token deactivation, and Redis cache clearing."""
    from app.api.user.auth_otp import revoke_all_sessions

    mock_request = MagicMock(spec=Request)
    mock_sign_out = MagicMock()
    mock_devices_table = MagicMock()
    mock_redis = AsyncMock()

    with patch("app.api.user.auth_otp.supabase_client.auth.admin.sign_out", mock_sign_out), \
         patch("app.api.user.auth_otp.supabase_client.table", return_value=mock_devices_table), \
         patch("app.api.user.auth_otp.redis_client", mock_redis):

        response = await revoke_all_sessions(
            request=mock_request,
            _device=None,
            user_id="user-revoke-123",
        )

        assert response == {"success": True}
        mock_sign_out.assert_called_once_with("user-revoke-123", "global")
        mock_devices_table.update.assert_called_once_with({"is_active": False})
        mock_devices_table.update().eq.assert_called_once_with("user_id", "user-revoke-123")
        assert mock_redis.delete.call_count == 2



