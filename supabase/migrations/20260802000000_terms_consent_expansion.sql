-- ==========================================================
-- TERMS/CONSENT EXPANSION - itemized, auditable consent
--
-- Splits the previous single bundled "accepted_terms_version" checkbox
-- into three distinct consents, per app/api/user.py's consent-recording
-- endpoint and mobile/lib/screens/terms_consent_screen.dart:
--   1. general              - Terms of Service & Privacy Policy (mandatory)
--   2. special_category     - processing sexual orientation / religious
--                             belief fields, GDPR Art 9 explicit consent
--                             (mandatory - still required to use the app,
--                             but must be recorded as its own distinct
--                             consent, not bundled into #1)
--   3. safety_data          - location/safety-feature data processing
--                             (Meetup Safety check-ins, SOS, Digital
--                             Witness) - OPTIONAL, independently
--                             toggleable at any time, never blocks general
--                             app access on its own.
--
-- users.accepted_terms_version/terms_accepted_at (existing columns) keep
-- representing consent #1. This migration adds the current-state columns
-- for #2 and #3, plus an append-only audit log recording every accept
-- *and* decline event for all three - current-state columns answer "is
-- this user consented right now", the log answers "prove what they agreed
-- to and when", mirroring the existing profile_age_change_log /
-- user_moderation_actions current-state-plus-log convention.
-- ==========================================================

BEGIN;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS special_category_consent_version TEXT,
    ADD COLUMN IF NOT EXISTS special_category_consent_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS safety_data_consent_version TEXT,
    ADD COLUMN IF NOT EXISTS safety_data_consent_at TIMESTAMPTZ;

COMMENT ON COLUMN public.users.special_category_consent_version IS
    'Terms version the user gave explicit consent to sexual-orientation/religious-belief processing under (GDPR Art 9). NULL means never consented. Mandatory to use the app, same gate as accepted_terms_version.';
COMMENT ON COLUMN public.users.safety_data_consent_version IS
    'Terms version the user consented to Meetup Safety/SOS/Digital Witness location-data processing under. NULL means not consented (or since revoked) - optional, independently toggleable, gates only the safety-feature surfaces, never general app access.';

CREATE TABLE IF NOT EXISTS public.terms_consent_log (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    category     TEXT        NOT NULL
        CHECK (category IN ('general', 'special_category', 'safety_data')),
    granted      BOOLEAN     NOT NULL,
    terms_version TEXT       NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

CREATE INDEX IF NOT EXISTS idx_terms_consent_log_user_created_at
    ON public.terms_consent_log (user_id, created_at DESC);

COMMENT ON TABLE public.terms_consent_log IS
    'Append-only audit trail of every consent accept/decline event across all three categories - the durable evidence trail for DPDP/GDPR consent proof. Deny-all client RLS, service_role backend access only, same pattern as profile_age_change_log.';

ALTER TABLE public.terms_consent_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.terms_consent_log FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Deny all client-side terms consent log access" ON public.terms_consent_log;
CREATE POLICY "Deny all client-side terms consent log access"
    ON public.terms_consent_log
    FOR ALL
    USING (false)
    WITH CHECK (false);

COMMENT ON POLICY "Deny all client-side terms consent log access" ON public.terms_consent_log
    IS 'Explicit deny-all for anon/authenticated; only the backend service_role client reads/writes. No GRANT issued - see 20260724000000_revoke_default_privileges.sql.';

COMMIT;
