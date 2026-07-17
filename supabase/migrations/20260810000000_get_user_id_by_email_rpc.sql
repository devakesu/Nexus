-- migration: get_user_id_by_email_rpc
-- purpose: Expose a helper function to resolve a user UUID from auth.users by email.
-- Since auth.users is in a separate schema and restricted, this SECURITY DEFINER function provides safe access to the backend role.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_user_id_by_email(email_addr text)
RETURNS uuid
SECURITY DEFINER
SET search_path = public, auth
LANGUAGE plpgsql
AS $$
DECLARE
    user_id uuid;
BEGIN
    SELECT id INTO user_id FROM auth.users WHERE email = LOWER(email_addr) LIMIT 1;
    RETURN user_id;
END;
$$;

COMMENT ON FUNCTION public.get_user_id_by_email(text)
    IS 'Resolves a user UUID from auth.users by email. SECURITY DEFINER to bypass schema permissions.';

COMMIT;
