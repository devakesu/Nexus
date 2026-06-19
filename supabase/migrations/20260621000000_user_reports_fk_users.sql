-- ==========================================================
-- ALTER USER REPORTS FOREIGN KEYS TO REFERENCE USERS(ID)
-- Redirects reporter_id and target_id references from public.profiles
-- to public.users for more stable identity tracking.
-- ==========================================================

BEGIN;

-- Drop inline-generated foreign key constraints from the profiles reference
ALTER TABLE public.user_reports
    DROP CONSTRAINT IF EXISTS user_reports_reporter_id_fkey,
    DROP CONSTRAINT IF EXISTS user_reports_target_id_fkey;

-- Add updated foreign key constraints pointing to public.users(id)
ALTER TABLE public.user_reports
    ADD CONSTRAINT user_reports_reporter_id_fkey
        FOREIGN KEY (reporter_id) REFERENCES public.users(id) ON DELETE CASCADE,
    ADD CONSTRAINT user_reports_target_id_fkey
        FOREIGN KEY (target_id) REFERENCES public.users(id) ON DELETE CASCADE;

COMMIT;
