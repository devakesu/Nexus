-- ==========================================================
-- DATABASE HARDENING AND SECURITY POLICIES
-- ==========================================================

BEGIN;

-- DB-1: Revoke users_update_own update policy and column-level grants.
-- This ensures all public.users table mutations go through the backend service role.
DROP POLICY IF EXISTS "users_update_own" ON public.users;
REVOKE UPDATE ON TABLE public.users FROM authenticated;


-- DB-2: search_path Convention Documentation
--
-- Convention: SECURITY DEFINER functions must lock down search_path to prevent hijacking.
-- 1. Functions performing writes to public tables from system auth triggers (e.g., handle_new_auth_user,
--    sync_user_email_from_auth) use `SET search_path = ''`. This requires fully qualified table references
--    (e.g., public.users) and is the most secure posture.
-- 2. Trigger functions executing in user-facing contexts (e.g., guard_service_fields, set_updated_at)
--    use `SET search_path = public, pg_temp` to allow referencing public tables without schema qualification,
--    while preventing temporary schema injection/hijacking.


-- DB-3: Composite index on matches(liker_id, liked_back_id) for unmatch lookups
CREATE INDEX IF NOT EXISTS idx_matches_liker_liked_back
    ON public.matches (liker_id, liked_back_id);


-- DB-6: Composite unique constraint preventing duplicate active likes or superlikes
CREATE UNIQUE INDEX IF NOT EXISTS uq_profile_discovery_actions_active_like_or_superlike
    ON public.profile_discovery_actions (actor_id, target_id, tab)
    WHERE action IN ('like', 'superlike') AND revoked_at IS NULL;

COMMIT;
