-- ==========================================================
-- CHAT PRIVACY SETTINGS
-- Two more toggles alongside the existing hidden_profile_fields column,
-- wiring up the previously-stub "Active Status" and "Read Receipts"
-- switches in privacy_settings_page.dart.
-- ==========================================================

BEGIN;

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS share_active_status BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS share_read_receipts BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.profiles.share_active_status IS
    'Whether this user allows matches to see "Active now" / "last active" presence.';
COMMENT ON COLUMN public.profiles.share_read_receipts IS
    'Whether this user sends read receipts for messages they read.';


-- ==========================================================
-- CHAT PRESENCE
-- Metadata-only signal, separate from chat_messages content. Driven by a
-- lightweight heartbeat from the client (not on every API call) while a
-- chat screen is foregrounded. Exposed to other users only through a
-- backend endpoint that checks share_active_status server-side - never
-- via direct client SELECT - so a modified client can't bypass the
-- privacy toggle.
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.chat_presence (
    user_id         UUID        PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    last_active_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    is_online       BOOLEAN     NOT NULL DEFAULT false,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.chat_presence IS
    'Presence heartbeat per user. Read access is backend-mediated only, gated on profiles.share_active_status.';

DROP TRIGGER IF EXISTS set_chat_presence_updated_at ON public.chat_presence;
CREATE TRIGGER set_chat_presence_updated_at
    BEFORE UPDATE ON public.chat_presence
    FOR EACH ROW
    EXECUTE PROCEDURE public.set_updated_at();

ALTER TABLE public.chat_presence ENABLE ROW LEVEL SECURITY;

CREATE POLICY "chat_presence_owner_select"
    ON public.chat_presence
    FOR SELECT
    TO authenticated
    USING (user_id = (SELECT auth.uid()));

COMMIT;
