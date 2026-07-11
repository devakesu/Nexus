BEGIN;

-- Orphaned trigger functions from the pre-backend-bootstrap era. Their
-- triggers (on_auth_user_created, on_auth_user_updated_sync_email) were
-- dropped in 20260605124755_auth_refine.sql and never reattached, but the
-- functions were re-created (unused) by 20260607100000_phone_auth.sql and
-- still write into the columns being dropped below with stale, unencrypted
-- logic. Clean them up.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_updated_sync_email ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_auth_user();
DROP FUNCTION IF EXISTS public.sync_user_email_from_auth();

-- email/mobile are duplicated copies of auth.users.email / auth.users.phone.
-- auth.users (Supabase Auth) is the single source of truth going forward;
-- the one real reader (feedback confirmation email) now calls
-- auth.admin.get_user_by_id() instead of reading this table.
ALTER TABLE public.users DROP COLUMN IF EXISTS email;
ALTER TABLE public.users DROP COLUMN IF EXISTS mobile;

COMMIT;

-- Down-path (destructive, NOT implemented — documented only):
--   Historical values are unrecoverable; email could be backfilled
--   unencrypted from auth.users, but mobile's original ciphertext could
--   never be restored.
