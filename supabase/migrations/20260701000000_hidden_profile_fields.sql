-- ==========================================================
-- PROFILE FIELD VISIBILITY PREFERENCES
-- ==========================================================
-- Stores which profile fields the owner wants hidden from
-- other users' views. The server still uses all fields for
-- match scoring; only the presentation layer suppresses them.
-- ==========================================================

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS hidden_profile_fields TEXT[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.profiles.hidden_profile_fields IS
  'Fields the profile owner has chosen to hide from other users. '
  'Used only for presentation; scoring uses the full profile.';

COMMIT;
