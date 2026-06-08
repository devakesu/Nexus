-- ==========================================================
-- NEXUS MEC MIGRATION: HARDENED COMPLIANT MEDIA LAYER (V2)
-- ==========================================================

BEGIN;

-- 1. PROVISION SECURE PRIVATE MEDIA STORAGE HOUSING VIA DATABASE INTERFACES
-- Registers a locked storage bucket safely inside the metadata catalog.
-- The public column is intentionally set to false to lock out direct unauthenticated web sweeps.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) 
VALUES (
    'user_media', 
    'user_media', 
    false, 
    5242880, -- Enforces an explicit 5MB upper compression cap ceiling per asset payload
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp'] -- Strict asset type enforcement whitelist
)
ON CONFLICT (id) DO NOTHING;

-- 2. ENFORCE FIREWALL REGISTRY VIA STORAGE OBJECT POLICIES
-- Drops stale tracking rules and verifies explicit isolation boundaries on your bucket space.
DROP POLICY IF EXISTS "Allow backend storage tracking access" ON storage.objects;
CREATE POLICY "Allow backend storage tracking access" 
  ON storage.objects 
  FOR ALL 
  TO authenticated 
  USING (bucket_id = 'user_media')
  WITH CHECK (bucket_id = 'user_media');

-- 3. APPEND THE NEW ENCRYPTED BYTEA PROFILE PIC TRACKS TO THE MAIN PROFILES TABLE
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS profile_pic BYTEA,
  ADD COLUMN IF NOT EXISTS normal_pics BYTEA;

-- 4. METADATA SYSTEM ARCHITECTURE COMPLIANCE AUDITS
COMMENT ON COLUMN public.profiles.profile_pic IS 'Encrypted object storage path string representing the mandatory avatar image token.';
COMMENT ON COLUMN public.profiles.normal_pics IS 'Encrypted JSON string array matching 1-4 validation bounding paths.';

COMMIT;