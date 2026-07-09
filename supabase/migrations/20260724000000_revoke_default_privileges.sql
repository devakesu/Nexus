-- ==========================================================
-- REVOKE DEFAULT PRIVILEGES ON TABLES/SEQUENCES FOR anon/authenticated
-- Hardens the default baseline so any new table created without RLS
-- is not automatically accessible to public/anonymous roles.
-- ==========================================================

BEGIN;

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM anon, authenticated;

COMMIT;
