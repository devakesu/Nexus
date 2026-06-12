-- Migration: Add pronouns column to profiles table.

ALTER TABLE public.profiles ADD COLUMN pronouns BYTEA;

-- Update comments
COMMENT ON COLUMN public.profiles.pronouns IS 'Encrypted pronouns of the user profile.';
