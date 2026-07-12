-- ==========================================================
-- AGE CHANGE: MOVE TO THE SAME ROLLING 2x/YEAR MODEL AS NAME
--
-- Supersedes the "1 change per 365-day cooldown since age_updated_at"
-- model from 20260728000000_profile_identity_change_limits.sql. The
-- correct rule is: age may change twice within a rolling 365-day window,
-- with registration (onboarding) counting as the first change - identical
-- semantics to profile_name_change_log / apply_name_change.
--
-- profiles.age_updated_at is kept as a convenience "last changed at"
-- marker (still stamped on every successful change) but is no longer the
-- source of eligibility truth - profile_age_change_log is.
-- ==========================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.profile_age_change_log (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_profile_age_change_log_user_changed_at
    ON public.profile_age_change_log (user_id, changed_at DESC);

COMMENT ON TABLE public.profile_age_change_log IS
    'Append-only log of age changes, one row per change. Rolling-window eligibility = count of rows with changed_at > now() - interval ''365 days'' < 2. Deny-all client RLS - service_role backend access only, same pattern as profile_name_change_log.';

ALTER TABLE public.profile_age_change_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_age_change_log FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Deny all client-side age change log access" ON public.profile_age_change_log;
CREATE POLICY "Deny all client-side age change log access"
    ON public.profile_age_change_log
    FOR ALL
    USING (false)
    WITH CHECK (false);

COMMENT ON POLICY "Deny all client-side age change log access" ON public.profile_age_change_log
    IS 'Explicit deny-all for anon/authenticated; only the backend service_role client reads/writes. No GRANT issued - see 20260724000000_revoke_default_privileges.sql.';

-- Backfill: registration counts as change #1 for existing profiles.
-- age_updated_at was already backfilled to created_at in
-- 20260728000000, so reuse it (falling back to created_at if somehow null).
INSERT INTO public.profile_age_change_log (user_id, changed_at)
SELECT p.id, COALESCE(p.age_updated_at, p.created_at)
FROM public.profiles p
WHERE NOT EXISTS (
    SELECT 1 FROM public.profile_age_change_log l WHERE l.user_id = p.id
);

-- Replaces the previous single-cooldown apply_age_change with the
-- rolling-count version (mirrors apply_name_change exactly). The old
-- 3-arg signature is dropped explicitly - CREATE OR REPLACE does not
-- overwrite it since the parameter list is changing (Postgres treats a
-- different signature as a distinct overload, which would otherwise leave
-- the old 3-arg function callable side-by-side with the new one).
DROP FUNCTION IF EXISTS public.apply_age_change(UUID, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.apply_age_change(
    p_user_id UUID,
    p_new_age INTEGER,
    p_min_interval_days INTEGER DEFAULT 365,
    p_max_changes INTEGER DEFAULT 2
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_count INTEGER;
BEGIN
    PERFORM 1 FROM public.profiles WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'profile_not_found' USING ERRCODE = 'P0002';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.profile_age_change_log
    WHERE user_id = p_user_id
      AND changed_at > v_now - (p_min_interval_days || ' days')::interval;

    IF v_count >= p_max_changes THEN
        RAISE EXCEPTION 'age_change_limit_reached' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.profiles
    SET age = p_new_age, age_updated_at = v_now, updated_at = v_now
    WHERE id = p_user_id;
    INSERT INTO public.profile_age_change_log (user_id, changed_at) VALUES (p_user_id, v_now);

    RETURN v_now;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_age_change(UUID, INTEGER, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;

COMMIT;
