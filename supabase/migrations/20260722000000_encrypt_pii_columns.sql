-- ==========================================================
-- ENCRYPT PII COLUMNS (name/phone, current_location, email/mobile)
-- Alters these fields to BYTEA so they can store Fernet-encrypted bytes.
-- ==========================================================

BEGIN;

-- Drop unique constraint on users.email
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_email_key CASCADE;
DROP INDEX IF EXISTS public.users_email_unique_idx;


-- Alter users columns to BYTEA
ALTER TABLE public.users ALTER COLUMN email TYPE BYTEA USING email::bytea;
ALTER TABLE public.users ALTER COLUMN mobile TYPE BYTEA USING mobile::bytea;

-- Drop check constraints on safety_contacts before altering type
ALTER TABLE public.safety_contacts DROP CONSTRAINT IF EXISTS safety_contacts_name_length_check;
ALTER TABLE public.safety_contacts DROP CONSTRAINT IF EXISTS safety_contacts_phone_length_check;

-- Alter safety_contacts columns to BYTEA
ALTER TABLE public.safety_contacts ALTER COLUMN name TYPE BYTEA USING name::bytea;
ALTER TABLE public.safety_contacts ALTER COLUMN phone TYPE BYTEA USING phone::bytea;

-- Drop check constraint on safety_alerts location check
ALTER TABLE public.safety_alerts DROP CONSTRAINT IF EXISTS safety_alerts_location_object_check;

-- Alter safety_alerts column to BYTEA
ALTER TABLE public.safety_alerts ALTER COLUMN current_location TYPE BYTEA USING current_location::text::bytea;

-- Update column comments
COMMENT ON COLUMN public.users.email IS 'Encrypted email address.';
COMMENT ON COLUMN public.users.mobile IS 'Encrypted mobile number.';
COMMENT ON COLUMN public.safety_contacts.name IS 'Encrypted name.';
COMMENT ON COLUMN public.safety_contacts.phone IS 'Encrypted phone.';
COMMENT ON COLUMN public.safety_alerts.current_location IS 'Encrypted geolocation JSON object.';

COMMIT;
