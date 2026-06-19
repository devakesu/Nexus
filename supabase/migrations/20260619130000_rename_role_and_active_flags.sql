-- ==========================================================
-- NEXUS FIELD RENAMES
-- role → role_at (stores company/institute name, not a job title)
-- is_*_complete → is_*_active (flags control discovery visibility)
-- ==========================================================

ALTER TABLE public.profiles
    RENAME COLUMN role TO role_at;

ALTER TABLE public.profiles
    RENAME COLUMN is_friends_complete TO is_friends_active;

ALTER TABLE public.profiles
    RENAME COLUMN is_professional_complete TO is_professional_active;

ALTER TABLE public.profiles
    RENAME COLUMN is_dating_complete TO is_dating_active;

-- Update column comments.
COMMENT ON COLUMN public.profiles.role_at
    IS 'Encrypted company or institute name for professional context.';

COMMENT ON COLUMN public.profiles.is_friends_active
    IS 'Server-maintained flag: profile is active in Friends discovery.';

COMMENT ON COLUMN public.profiles.is_professional_active
    IS 'Server-maintained flag: profile is active in Professional discovery.';

COMMENT ON COLUMN public.profiles.is_dating_active
    IS 'Server-maintained flag: profile is active in Dating discovery.';

-- Drop and recreate partial eligibility indexes with updated column names.
DROP INDEX IF EXISTS public.idx_profiles_friends_eligibility;
DROP INDEX IF EXISTS public.idx_profiles_professional_eligibility;
DROP INDEX IF EXISTS public.idx_profiles_dating_eligibility;

CREATE INDEX idx_profiles_friends_eligibility
    ON public.profiles (id)
    WHERE is_friends_active = TRUE AND is_deactivated = FALSE;

CREATE INDEX idx_profiles_professional_eligibility
    ON public.profiles (id)
    WHERE is_professional_active = TRUE AND is_deactivated = FALSE;

CREATE INDEX idx_profiles_dating_eligibility
    ON public.profiles (id)
    WHERE is_dating_active = TRUE AND is_deactivated = FALSE;

-- Recreate the service-field guard trigger with updated column names.
CREATE OR REPLACE FUNCTION public.guard_service_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        IF NEW.is_deactivated IS DISTINCT FROM OLD.is_deactivated OR
           NEW.deactivated_at IS DISTINCT FROM OLD.deactivated_at THEN
            RAISE EXCEPTION 'permission denied: profile deactivation states are server-side only';
        END IF;

        IF NEW.is_friends_active IS DISTINCT FROM OLD.is_friends_active OR
           NEW.is_professional_active IS DISTINCT FROM OLD.is_professional_active OR
           NEW.is_dating_active IS DISTINCT FROM OLD.is_dating_active THEN
            RAISE EXCEPTION 'permission denied: profile active flags are server-side only';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_service_fields()
    IS 'SECURITY DEFINER trigger function that blocks non-service callers from changing server-owned profile lifecycle and tab-active fields.';
