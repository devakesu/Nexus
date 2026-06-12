-- Migration: Add current_place column to profiles table.

ALTER TABLE public.profiles ADD COLUMN current_place BYTEA;

-- Update comments
COMMENT ON COLUMN public.profiles.current_place IS 'Encrypted Current Place of the user profile.';
