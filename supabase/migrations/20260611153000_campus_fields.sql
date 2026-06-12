-- Migration: Rename branch -> campus_branch, year -> campus_year, add campus_name, and rename blind index.

ALTER TABLE public.profiles RENAME COLUMN branch TO campus_branch;
ALTER TABLE public.profiles RENAME COLUMN year TO campus_year;
ALTER TABLE public.profiles RENAME COLUMN branch_blind_index TO campus_branch_blind_index;

ALTER TABLE public.profiles ADD COLUMN campus_name TEXT;

-- Rename indexes for consistency
ALTER INDEX IF EXISTS public.idx_profiles_year RENAME TO idx_profiles_campus_year;
ALTER INDEX IF EXISTS public.idx_profiles_branch_blind RENAME TO idx_profiles_campus_branch_blind;

-- Update comments
COMMENT ON COLUMN public.profiles.campus_branch_blind_index IS 'HMAC-SHA256 deterministic blind hash for encrypted campus branch queries.';
COMMENT ON COLUMN public.profiles.campus_name IS 'Campus name of the user profile.';
