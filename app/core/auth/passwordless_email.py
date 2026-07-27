"""Passwordless email OTP authentication utilities.

Provides scoped Supabase client instances for sending and verifying email OTPs
during login flows without mutating shared singleton session state.
"""

from supabase.lib.client_options import SyncClientOptions
from supabase_auth import AuthResponse

from app.core.config import settings
from supabase import Client, create_client


def _scoped_auth_client() -> Client:
    """Creates a throwaway Supabase client for isolated email-OTP send/verify calls.

    Uses `persist_session=False` and `auto_refresh_token=False` to avoid mutating
    shared application session state or starting unwanted background refresh timers.

    Returns:
        Client: Scoped Supabase client instance.
    """
    return create_client(
        settings.supabase_url,
        settings.supabase_service_role_key,
        options=SyncClientOptions(
            auto_refresh_token=False,
            persist_session=False,
        ),
    )


def send_login_email_otp(email: str) -> None:
    """Triggers Supabase email OTP authentication for existing accounts.

    `should_create_user=False` guarantees that no new user account is created if the
    email is not already registered.

    Args:
        email: Target user email address.
    """
    client = _scoped_auth_client()
    client.auth.sign_in_with_otp(
        {
            "email": email,
            "options": {"should_create_user": False},
        },
    )


def verify_login_email_otp(email: str, code: str) -> AuthResponse:
    """Verifies a 6-digit email OTP token with Supabase Auth.

    Args:
        email: Target user email address.
        code: 6-digit OTP token entered by the user.

    Returns:
        AuthResponse: Supabase AuthResponse object containing access and refresh tokens.

    Raises:
        AuthApiError: If the token is invalid, expired, or verification fails.
    """
    client = _scoped_auth_client()
    return client.auth.verify_otp(
        {
            "email": email,
            "token": code,
            "type": "email",
        },
    )

