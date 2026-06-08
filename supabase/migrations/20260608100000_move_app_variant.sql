-- migration: move_app_variant
-- purpose: Move app_variant column from public.profiles to public.users for secure server-side control and clean moderation context.

BEGIN;

-- 1. ADD COLUMN TO public.users
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS app_variant TEXT NOT NULL DEFAULT 'nexus'
        CHECK (app_variant IN ('nexus', 'nexus_mec'));

-- 2. MIGRATE EXISTING DATA
UPDATE public.users u
SET app_variant = p.app_variant
FROM public.profiles p
WHERE u.id = p.id;

-- 3. DROP INDEX AND COLUMN FROM public.profiles
DROP INDEX IF EXISTS public.idx_profiles_app_variant;

ALTER TABLE public.profiles
    DROP COLUMN IF EXISTS app_variant;

-- 4. CREATE INDEX ON public.users FOR app_variant
CREATE INDEX IF NOT EXISTS idx_users_app_variant
    ON public.users (app_variant);

-- 5. COMMENTS
COMMENT ON COLUMN public.users.app_variant
    IS 'Flavor identifier for this account. Controls which variant-specific UI and onboarding fields apply. Maintained by the backend and not editable by the client.';

COMMIT;
