-- Add role_type (encrypted JSON array, multi-select professional role categories)
-- and repurpose the existing `role` column as company/institute (display text only).
-- role_type is filtered post-fetch via list-overlap, same pattern as looking_for/tech_skills.

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS role_type BYTEA;

ALTER TABLE public.profiles
    DROP COLUMN IF EXISTS role_blind_index;

COMMENT ON COLUMN public.profiles.role IS
    'Encrypted free-text company or institute name (display only).';

COMMENT ON COLUMN public.profiles.role_type IS
    'Encrypted JSON array of predefined role-type tags (e.g. Founder, Engineer). '
    'Filtered post-fetch via list-overlap; no blind index needed.';
