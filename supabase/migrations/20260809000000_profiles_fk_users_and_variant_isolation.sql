-- migration: profiles_fk_users_and_variant_isolation
-- purpose: Clean up orphaned profiles and redirect profiles(id) to reference public.users(id) for referential integrity.

BEGIN;

-- 1. DELETE ORPHANED PROFILES (those with no corresponding public.users row)
DELETE FROM public.profiles
WHERE id NOT IN (SELECT id FROM public.users);

-- 2. REDIRECT THE FOREIGN KEY TO public.users
ALTER TABLE public.profiles
    DROP CONSTRAINT IF EXISTS profiles_id_fkey,
    ADD CONSTRAINT profiles_id_fkey
        FOREIGN KEY (id) REFERENCES public.users(id) ON DELETE CASCADE;

COMMIT;
