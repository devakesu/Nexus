from supabase.lib.client_options import SyncClientOptions
from supabase_auth import AuthResponse

from app.core.config import settings
from supabase import Client, create_client


def _scoped_auth_client() -> Client:
    """A throwaway Supabase client for a single email-OTP send/verify call.

    app/db/client.py's module-level `supabase_client` is a shared singleton
    used by every request in this process. GoTrue's sign_in_with_otp/
    verify_otp calls mutate the calling client's *own* in-memory session
    state (_save_session/_remove_session) - calling them on the shared
    singleton would leak one request's session into every other concurrent
    request. persist_session=False keeps that state in-memory only (never
    touches disk/storage, which wouldn't make sense server-side anyway) and
    auto_refresh_token=False stops it from starting a background refresh
    timer for a client instance that's discarded the moment this request
    finishes.
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
    """Triggers Supabase's normal email OTP send for an existing account
    only (should_create_user=False - this is a login path, not signup; if
    the looked-up email were ever wrong, the last thing we want is to
    silently create a new account for it).
    """
    client = _scoped_auth_client()
    client.auth.sign_in_with_otp(
        {
            "email": email,
            "options": {"should_create_user": False},
        },
    )


def verify_login_email_otp(email: str, code: str) -> AuthResponse:
    """Verifies the code Supabase emailed and returns the resulting
    AuthResponse (.session.access_token/.refresh_token) - the caller hands
    the refresh_token back to the mobile client, which adopts it locally
    via `Supabase.instance.client.auth.setSession(refreshToken)`. Raises
    whatever GoTrue raises (AuthApiError) on an invalid/expired code; the
    endpoint layer is responsible for turning that into a generic message.
    """
    client = _scoped_auth_client()
    return client.auth.verify_otp(
        {
            "email": email,
            "token": code,
            "type": "email",
        },
    )
