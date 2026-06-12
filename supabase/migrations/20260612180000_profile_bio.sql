-- Migration: Add bio column + encrypt campus_branch/campus_name columns.

-- Bio: encrypted user self-description (BYTEA, same pattern as pronouns/lifestyle)
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS bio BYTEA;

COMMENT ON COLUMN public.profiles.bio IS 'Encrypted user bio/self-description, max 1000 characters.';

-- campus_branch: convert from plaintext TEXT to encrypted BYTEA.
-- Drop NOT NULL first (existing plaintext data cannot be automatically encrypted).
-- Existing values are nulled; users will re-save to trigger re-encryption.
ALTER TABLE public.profiles ALTER COLUMN campus_branch DROP NOT NULL;
ALTER TABLE public.profiles ALTER COLUMN campus_branch TYPE BYTEA USING NULL::BYTEA;

COMMENT ON COLUMN public.profiles.campus_branch IS 'Encrypted campus branch / major of the user. Blind index in campus_branch_blind_index.';

-- campus_name: convert from plaintext TEXT to encrypted BYTEA.
ALTER TABLE public.profiles ALTER COLUMN campus_name TYPE BYTEA USING NULL::BYTEA;

COMMENT ON COLUMN public.profiles.campus_name IS 'Encrypted campus/institute name of the user.';

