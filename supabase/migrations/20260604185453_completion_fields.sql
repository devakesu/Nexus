-- ==========================================================
-- NEXUS COMPLETENESS FLAGS
-- Replace coarse profile completeness with tab-specific readiness flags
-- ==========================================================

-- These flags are computed by trusted backend code after decrypting and validating
-- profile data in application memory. They are not derived in SQL because some
-- required source fields are encrypted BYTEA payloads.

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS is_friends_complete BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_professional_complete BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS is_dating_complete BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.profiles.is_friends_complete
    IS 'Server-maintained eligibility flag for Friends discovery. Computed in backend from decrypted profile readiness rules.';

COMMENT ON COLUMN public.profiles.is_professional_complete
    IS 'Server-maintained eligibility flag for Professional discovery. Computed in backend from decrypted profile readiness rules.';

COMMENT ON COLUMN public.profiles.is_dating_complete
    IS 'Server-maintained eligibility flag for Dating discovery. Computed in backend from decrypted profile readiness rules.';


-- Drop legacy coarse eligibility index before removing its backing column.
DROP INDEX IF EXISTS public.idx_profiles_matching_eligibility;

-- Remove redundant umbrella completeness flag.
ALTER TABLE public.profiles
    DROP COLUMN IF EXISTS is_profile_complete;

-- Add tab-specific partial indexes for fast eligibility filtering.
CREATE INDEX IF NOT EXISTS idx_profiles_friends_eligibility
    ON public.profiles (id)
    WHERE is_friends_complete = TRUE AND is_deactivated = FALSE;

CREATE INDEX IF NOT EXISTS idx_profiles_professional_eligibility
    ON public.profiles (id)
    WHERE is_professional_complete = TRUE AND is_deactivated = FALSE;

CREATE INDEX IF NOT EXISTS idx_profiles_dating_eligibility
    ON public.profiles (id)
    WHERE is_dating_complete = TRUE AND is_deactivated = FALSE;


-- Update server-side field guard to reflect the new completion model.
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

        IF NEW.is_friends_complete IS DISTINCT FROM OLD.is_friends_complete OR
           NEW.is_professional_complete IS DISTINCT FROM OLD.is_professional_complete OR
           NEW.is_dating_complete IS DISTINCT FROM OLD.is_dating_complete THEN
            RAISE EXCEPTION 'permission denied: profile completion flags are server-side only';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_service_fields()
    IS 'SECURITY DEFINER trigger function that blocks non-service callers from changing server-owned profile lifecycle and tab-completion fields.';