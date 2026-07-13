-- ==========================================================
-- TRUSTED CONTACT NOTICE + SELF-REMOVAL
--
-- Trusted contacts are not Nexus users - they never sign up, never see a
-- privacy policy, never consent to anything. This closes that gap: every
-- phone number first synced into safety_contacts gets a one-time SMS
-- notice with a link to a self-service removal portal (OTP-verified
-- against their own phone). If they remove themselves, that phone number
-- is permanently blocked from being re-added by the same user, and the
-- user is notified.
--
-- safety_contacts itself is a full-replace mirror (sync_safety_contacts
-- RPC deletes and reinserts every sync - see 20260721000000), so row ids
-- are not stable across syncs and can't carry "already notified" state.
-- This table is the durable, blind-indexed side record that survives
-- resyncs.
-- ==========================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.safety_contact_notices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

    phone_blind_index TEXT NOT NULL,

    first_notified_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    self_removed_at TIMESTAMPTZ,

    UNIQUE (user_id, phone_blind_index)
);

COMMENT ON TABLE public.safety_contact_notices IS
    'One row per (user, trusted-contact phone) pair ever synced. self_removed_at set means that phone permanently opted out of being this user''s trusted contact and sync_safety_contacts must not silently re-add it.';

CREATE INDEX IF NOT EXISTS idx_safety_contact_notices_user
    ON public.safety_contact_notices (user_id);

ALTER TABLE public.safety_contact_notices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.safety_contact_notices FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Deny all client-side safety contact notice access" ON public.safety_contact_notices;
CREATE POLICY "Deny all client-side safety contact notice access"
    ON public.safety_contact_notices
    FOR ALL
    USING (false)
    WITH CHECK (false);

COMMENT ON POLICY "Deny all client-side safety contact notice access" ON public.safety_contact_notices
    IS 'Explicit deny-all for anon/authenticated; only the backend service_role client reads/writes, same pattern as profile_age_change_log. The self-removal portal itself is unauthenticated (OTP-gated instead, like the rest of the trusted-contact portal), so it never gets a Postgres role of its own either.';

COMMIT;
