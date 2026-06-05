/*
  migration: drop auth.users sync triggers and functions

  purpose:
    - stop auto-creating public.users rows from auth.users
    - stop auto-syncing auth.users.email into public.users
    - move public.users creation to the backend bootstrap endpoint

  notes:
    - auth.users remains the identity source managed by Supabase Auth
    - public.users becomes an app-admission table managed by backend verification
    - user rows will now be inserted only after backend validation succeeds
*/

BEGIN;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_updated_sync_email ON auth.users;

DROP FUNCTION IF EXISTS public.handle_new_auth_user();
DROP FUNCTION IF EXISTS public.sync_user_email_from_auth();

COMMIT;