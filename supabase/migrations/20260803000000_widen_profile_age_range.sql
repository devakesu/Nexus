-- ==========================================================
-- AGE RANGE DIFFERENTIATION BY VARIANT
--
-- public.profiles.age has been CHECK-constrained to 18-27 for every app
-- variant since the original migration (20260604180435_initial.sql) - this
-- never actually matched the app-layer intent: NexusOnboardingRequest
-- (app/models.py) has always allowed 18-80 for the main 'nexus' variant,
-- while MECOnboardingRequest correctly stays 18-27. The DB constraint
-- silently overrode that for 'nexus' - any onboarding/profile-edit
-- submission above 27 would DB-reject regardless of app_variant.
--
-- profiles has no app_variant column of its own (that lives on the
-- sibling public.users table, both keyed 1:1 off auth.users(id) - see
-- 20260608100000_move_app_variant.sql), so a plain CHECK constraint can't
-- express "18-80 for nexus, 18-27 for everything else" on its own. This
-- migration widens the CHECK to the union range (so the DB no longer
-- silently overrides the app-layer intent for 'nexus') and adds a trigger
-- for the actual per-variant enforcement as a DB-level backstop behind the
-- FastAPI-layer check added in app/api/user.py's update_profile_details -
-- matching this codebase's established pattern of DB triggers backing up
-- application-layer authorization (e.g. guard_service_fields()).
--
-- Safe ordering: public.users rows are always created (via auth/bootstrap)
-- before their public.profiles row (created during onboarding), so the
-- app_variant lookup below never races against a not-yet-existing users row.
-- ==========================================================

BEGIN;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_age_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_age_check
    CHECK (age BETWEEN 18 AND 80);

CREATE OR REPLACE FUNCTION public.enforce_variant_age_range()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_variant TEXT;
BEGIN
    SELECT app_variant INTO v_variant FROM public.users WHERE id = NEW.id;

    IF v_variant IS DISTINCT FROM 'nexus' AND NEW.age > 27 THEN
        RAISE EXCEPTION 'age_out_of_range_for_variant' USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_variant_age_range ON public.profiles;
CREATE TRIGGER trg_enforce_variant_age_range
    BEFORE INSERT OR UPDATE OF age ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.enforce_variant_age_range();

COMMENT ON FUNCTION public.enforce_variant_age_range() IS
    'DB-level backstop for the 18-80 (nexus) / 18-27 (every other variant) age split - the FastAPI layer (app/api/user.py::update_profile_details) is the primary enforcement point, this trigger catches anything that bypasses it.';

REVOKE ALL ON FUNCTION public.enforce_variant_age_range() FROM PUBLIC, anon, authenticated;

COMMIT;
