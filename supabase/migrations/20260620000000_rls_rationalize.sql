-- ==========================================================
-- RLS RATIONALIZATION
--
-- All profile and discovery writes go exclusively through the
-- FastAPI backend (service_role), which bypasses RLS entirely.
-- The write policies below were never triggered and are dead code.
-- Removing them prevents misleading future maintainers into
-- thinking client-side writes are possible or guarded at the DB level.
--
-- Authorization is enforced at the FastAPI layer:
--   - ES256 JWT verification via Supabase JWKS
--   - user_id scoping on every query
--   - Account status checks (suspension, deactivation)
--   - Firebase App Check on sensitive routes
--
-- SELECT policies and the profiles INSERT policy are retained as
-- forward-guards. The guard_service_fields() trigger is the
-- authoritative DB-level backstop for server-owned columns.
-- ==========================================================

-- ----------------------------------------------------------
-- profiles: remove dead UPDATE policy
-- ----------------------------------------------------------
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;

-- ----------------------------------------------------------
-- profile_discovery_actions: remove dead write policies
-- All actions (pass, like, superlike, hide, block, report) are
-- written via the backend's record_discovery_action() function.
-- ----------------------------------------------------------
DROP POLICY IF EXISTS "Users can insert own discovery actions" ON public.profile_discovery_actions;
DROP POLICY IF EXISTS "Users can update own discovery actions" ON public.profile_discovery_actions;
DROP POLICY IF EXISTS "Users can delete own discovery actions" ON public.profile_discovery_actions;

-- ----------------------------------------------------------
-- discovery_sessions: remove dead write policies
-- Session creation and snapshotting are backend-only operations.
-- ----------------------------------------------------------
DROP POLICY IF EXISTS "Users can insert own discovery sessions" ON public.discovery_sessions;
DROP POLICY IF EXISTS "Users can update own discovery sessions" ON public.discovery_sessions;
DROP POLICY IF EXISTS "Users can delete own discovery sessions" ON public.discovery_sessions;

-- ----------------------------------------------------------
-- discovery_session_items: remove dead DELETE policy
-- INSERT was already removed in 20260605220000_audit_fixes.sql.
-- UPDATE (deny) policy was set in that same migration — keep it.
-- ----------------------------------------------------------
DROP POLICY IF EXISTS "Users can delete own discovery session items" ON public.discovery_session_items;

-- ==========================================================
-- EXTEND guard_service_fields() TO COVER IMPORT SYNC FIELDS
--
-- The import sync fields (has_imported_data, import_sync_code,
-- import_sync_expires_at) are set exclusively by the backend
-- during profile export/import. Add them to the service-field
-- guard as a backstop against misconfiguration.
-- ==========================================================

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

        IF NEW.has_imported_data IS DISTINCT FROM OLD.has_imported_data OR
           NEW.import_sync_code IS DISTINCT FROM OLD.import_sync_code OR
           NEW.import_sync_expires_at IS DISTINCT FROM OLD.import_sync_expires_at THEN
            RAISE EXCEPTION 'permission denied: import sync fields are server-side only';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.guard_service_fields()
    IS 'SECURITY DEFINER trigger blocking non-service writes to server-governed profile fields: deactivation state, tab-active flags, and import sync fields.';

-- ==========================================================
-- PARTIAL UNIQUE INDEX: prevent duplicate pending reports
--
-- One pending report per reporter→target pair. Protects against
-- rapid duplicate submissions even if the backend is called
-- concurrently or retried.
-- ==========================================================

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_reports_pending
    ON public.user_reports (reporter_id, target_id)
    WHERE review_status = 'pending';

-- ==========================================================
-- TABLE COMMENTS: document security model for future maintainers
-- ==========================================================

COMMENT ON TABLE public.profiles
    IS 'Canonical application profile table. All writes are via FastAPI backend (service_role client). The SELECT policy is active for Flutter auth_gate existence checks. The INSERT policy is retained as a forward-guard. The UPDATE write policy was removed — it was dead code since service_role bypasses RLS. Authorization is enforced at the FastAPI layer (JWT verification + user_id scoping + guard_service_fields trigger).';

COMMENT ON TABLE public.profile_discovery_actions
    IS 'Discovery action history (pass, like, superlike, hide, block). All writes are backend-only via record_discovery_action(). The SELECT policy is retained. Write policies (INSERT/UPDATE/DELETE) were removed as dead code — service_role bypasses RLS for all action writes.';

COMMENT ON TABLE public.discovery_sessions
    IS 'Discovery session snapshots. All operations are backend-only (service_role). SELECT policy retained for potential future reads. Write policies were removed as dead code.';
