-- Migration to support phone authentication (email nullable)
BEGIN;

-- 1. Make email column nullable in public.users
ALTER TABLE public.users ALTER COLUMN email DROP NOT NULL;

-- 2. Drop the existing unique constraint/index on email if they exist
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_email_key;
DROP INDEX IF EXISTS public.users_email_idx;

-- 3. Create a unique partial index for email when it is present
CREATE UNIQUE INDEX IF NOT EXISTS users_email_unique_idx ON public.users (LOWER(email)) WHERE email IS NOT NULL AND email != '';

-- 4. Update handle_new_auth_user function to support both email and phone
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  raw_email text;
  raw_phone text;
BEGIN
  raw_email := NULLIF(LOWER(NEW.email), '');
  raw_phone := NULLIF(NEW.phone, '');

  INSERT INTO public.users (
    id,
    email,
    mobile,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    raw_email,
    raw_phone,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE
  SET
    email = EXCLUDED.email,
    mobile = EXCLUDED.mobile,
    updated_at = NOW();

  RETURN NEW;
END;
$$;

-- 5. Update sync_user_email_from_auth function to safely handle nullable email
CREATE OR REPLACE FUNCTION public.sync_user_email_from_auth()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  raw_email text;
  raw_phone text;
BEGIN
  raw_email := NULLIF(LOWER(NEW.email), '');
  raw_phone := NULLIF(NEW.phone, '');

  UPDATE public.users
  SET
    email = raw_email,
    mobile = raw_phone,
    updated_at = NOW()
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

COMMIT;
