-- ==========================================================
-- SET SEARCH PATH FOR create_discovery_session_with_items
-- Hardens the SECURITY DEFINER function by setting search_path.
-- ==========================================================

BEGIN;

ALTER FUNCTION public.create_discovery_session_with_items(UUID, TEXT, JSONB, TIMESTAMPTZ, JSONB)
    SET search_path = public, pg_temp;

COMMIT;
