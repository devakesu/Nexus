-- ==========================================================
-- PROFILE IDENTITY CHANGE RATE LIMITS (age + name)
--
-- Age: at most 1 change per rolling 365 days (profiles.age_updated_at).
-- Name: at most 2 changes per rolling 365-day sliding window
--   (profile_name_change_log, one row per change).
--
-- Onboarding counts as change #1 for both: complete_onboarding /
-- upsert_profile_variant (app/db/users.py) now stamps age_updated_at and
-- inserts the first profile_name_change_log row at onboarding time. This
-- migration backfills that retroactively for already-onboarded profiles,
-- using profiles.created_at as the best-available historical timestamp.
--
-- Writes are guarded+applied atomically via apply_age_change/
-- apply_name_change RPCs (see app/api/user.py::update_profile_details),
-- matching the existing check+write RPC pattern (upsert_signed_prekey,
-- sync_safety_contacts) rather than sequential unguarded Python calls -
-- SELECT ... FOR UPDATE inside each function serializes concurrent
-- duplicate submits against the same row, closing the TOCTOU race a plain
-- Python read-then-write would leave open.
-- ==========================================================

BEGIN;

-- 1. profiles: rolling-window marker for age
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS age_updated_at TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.age_updated_at IS
    'UTC timestamp of the most recent age change. Age may only change again 365 days after this. Set at onboarding (first value counts as change #1) and by apply_age_change(). Never client-writable - the profiles UPDATE RLS policy was already dropped (20260620000000_rls_rationalize.sql), so this column is backend/service_role-only by inheritance.';

-- 2. profile_name_change_log: one row per historical name change
CREATE TABLE IF NOT EXISTS public.profile_name_change_log (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_profile_name_change_log_user_changed_at
    ON public.profile_name_change_log (user_id, changed_at DESC);

COMMENT ON TABLE public.profile_name_change_log IS
    'Append-only log of display-name changes, one row per change. Rolling-window eligibility = count of rows with changed_at > now() - interval ''365 days'' < 2. Deny-all client RLS - service_role backend access only, same pattern as spotify_connections.';

ALTER TABLE public.profile_name_change_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_name_change_log FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Deny all client-side name change log access" ON public.profile_name_change_log;
CREATE POLICY "Deny all client-side name change log access"
    ON public.profile_name_change_log
    FOR ALL
    USING (false)
    WITH CHECK (false);

COMMENT ON POLICY "Deny all client-side name change log access" ON public.profile_name_change_log
    IS 'Explicit deny-all for anon/authenticated; only the backend service_role client reads/writes. No GRANT issued - see 20260724000000_revoke_default_privileges.sql.';

-- 3. Backfill: onboarding counts as change #1 for existing profiles
UPDATE public.profiles
SET age_updated_at = created_at
WHERE age_updated_at IS NULL;

INSERT INTO public.profile_name_change_log (user_id, changed_at)
SELECT p.id, p.created_at
FROM public.profiles p
WHERE NOT EXISTS (
    SELECT 1 FROM public.profile_name_change_log l WHERE l.user_id = p.id
);

-- 4. apply_age_change: atomic guarded read-check-write (closes TOCTOU race)
CREATE OR REPLACE FUNCTION public.apply_age_change(
    p_user_id UUID,
    p_new_age INTEGER,
    p_min_interval_days INTEGER DEFAULT 365
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_last_change TIMESTAMPTZ;
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
BEGIN
    SELECT age_updated_at INTO v_last_change
    FROM public.profiles WHERE id = p_user_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'profile_not_found' USING ERRCODE = 'P0002';
    END IF;

    IF v_last_change IS NOT NULL
       AND v_last_change > v_now - (p_min_interval_days || ' days')::interval THEN
        RAISE EXCEPTION 'age_change_too_soon' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.profiles
    SET age = p_new_age, age_updated_at = v_now, updated_at = v_now
    WHERE id = p_user_id;

    RETURN v_now;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_age_change(UUID, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;

-- 5. apply_name_change: atomic guarded count-check + write + log insert
CREATE OR REPLACE FUNCTION public.apply_name_change(
    p_user_id UUID,
    p_new_name TEXT,
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
    FROM public.profile_name_change_log
    WHERE user_id = p_user_id
      AND changed_at > v_now - (p_min_interval_days || ' days')::interval;

    IF v_count >= p_max_changes THEN
        RAISE EXCEPTION 'name_change_limit_reached' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.profiles SET name = p_new_name, updated_at = v_now WHERE id = p_user_id;
    INSERT INTO public.profile_name_change_log (user_id, changed_at) VALUES (p_user_id, v_now);

    RETURN v_now;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_name_change(UUID, TEXT, INTEGER, INTEGER) FROM PUBLIC, anon, authenticated;

COMMIT;
