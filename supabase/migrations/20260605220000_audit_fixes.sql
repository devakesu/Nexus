-- Migration: audit_fixes
-- Purpose: Apply database-level fixes for C-4, H-6, M-5, M-6, and L-8.

BEGIN;

-- C-4: Seed existing NULL values and add NOT NULL / DEFAULT constraints to spatial columns
UPDATE public.discovery_session_items SET x = 0.0 WHERE x IS NULL;
UPDATE public.discovery_session_items SET y = 0.0 WHERE y IS NULL;
UPDATE public.discovery_session_items SET orbit_tier = 0 WHERE orbit_tier IS NULL;

ALTER TABLE public.discovery_session_items
  ALTER COLUMN x SET DEFAULT 0.0,
  ALTER COLUMN x SET NOT NULL,
  ALTER COLUMN y SET DEFAULT 0.0,
  ALTER COLUMN y SET NOT NULL,
  ALTER COLUMN orbit_tier SET DEFAULT 0,
  ALTER COLUMN orbit_tier SET NOT NULL;

-- H-6 & M-6: Drop permissive client-facing INSERT policy and set restrictive UPDATE policy on discovery_session_items
DROP POLICY IF EXISTS "Users can insert own discovery session items" ON public.discovery_session_items;
DROP POLICY IF EXISTS "Users can update own discovery session items" ON public.discovery_session_items;

CREATE POLICY "Users can update own discovery session items"
    ON public.discovery_session_items
    FOR UPDATE
    USING (false)
    WITH CHECK (false);

-- M-5: Redefine trigger function set_updated_at to use UTC timestamp explicitly
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = timezone('utc'::text, now());
  RETURN NEW;
END;
$$;

-- L-8: Affirm default function privilege revoke order (already overrides remote_schema.sql)
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM authenticated;

COMMIT;
