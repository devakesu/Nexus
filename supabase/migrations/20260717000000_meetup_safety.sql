-- ==========================================================
-- MEETUP SAFETY
-- Server-side mirror of trusted contacts (previously client-only, in
-- flutter_secure_storage), active recurring check-in sessions, fired SOS/
-- inform alerts, and encrypted Silent SOS "Digital Witness" evidence
-- segments. See the Meetup Safety plan, Milestones A-C.
-- ==========================================================

BEGIN;

-- ==========================================================
-- TRUSTED CONTACTS
-- The device remains the primary copy (instant, offline-friendly reads);
-- this mirror exists so the backend can compose and send SOS/inform SMS
-- without needing the device online at alert time.
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.safety_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

    name TEXT NOT NULL,
    phone TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT safety_contacts_name_length_check
        CHECK (char_length(trim(name)) BETWEEN 1 AND 100),

    CONSTRAINT safety_contacts_phone_length_check
        CHECK (char_length(trim(phone)) BETWEEN 6 AND 20)
);

COMMENT ON TABLE public.safety_contacts
    IS 'Server-side mirror of a user''s up-to-3 trusted contacts, synced from the device on every add/remove so alerts can be sent without the device online.';

CREATE INDEX IF NOT EXISTS idx_safety_contacts_user
    ON public.safety_contacts (user_id);

ALTER TABLE public.safety_contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "safety_contacts_all_own"
    ON public.safety_contacts
    FOR ALL
    TO authenticated
    USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);


-- ==========================================================
-- CHECK-IN SESSIONS
-- One row per active (or most-recently-ended) Meetup Safety session. The
-- recurring check-in loop's exact-alarm scheduling lives entirely on-device
-- (see meetup_safety_session.dart) - this row exists so the backend has
-- session context (label, interval, event) to include in alert messages,
-- and as the anchor for a future dead-man's-switch escalation job.
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.safety_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

    label TEXT,
    interval_seconds INTEGER NOT NULL,
    next_checkin_at TIMESTAMPTZ,
    event_context JSONB NOT NULL DEFAULT '{}'::jsonb,

    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'ended')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT safety_sessions_interval_positive_check
        CHECK (interval_seconds > 0),

    CONSTRAINT safety_sessions_event_context_object_check
        CHECK (jsonb_typeof(event_context) = 'object')
);

COMMENT ON TABLE public.safety_sessions
    IS 'Mirrors the on-device recurring Meetup Safety check-in loop state, for alert message context and future server-side escalation.';
COMMENT ON COLUMN public.safety_sessions.event_context
    IS 'Optional linked chat event details (venue, tab, scheduled time) for richer alert copy.';

CREATE INDEX IF NOT EXISTS idx_safety_sessions_user_status
    ON public.safety_sessions (user_id, status);

DROP TRIGGER IF EXISTS set_safety_sessions_updated_at ON public.safety_sessions;
CREATE TRIGGER set_safety_sessions_updated_at
    BEFORE UPDATE ON public.safety_sessions
    FOR EACH ROW
    EXECUTE PROCEDURE public.set_updated_at();

ALTER TABLE public.safety_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "safety_sessions_all_own"
    ON public.safety_sessions
    FOR ALL
    TO authenticated
    USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);


-- ==========================================================
-- FIRED ALERTS
-- One row per SOS/inform trigger - an audit trail, and the anchor evidence
-- segments attach to.
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.safety_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.safety_sessions(id) ON DELETE SET NULL,

    alert_type TEXT NOT NULL
        CHECK (alert_type IN ('sos_silent', 'sos_loud', 'inform')),

    current_location JSONB,
    contacts_notified INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT safety_alerts_location_object_check
        CHECK (current_location IS NULL OR jsonb_typeof(current_location) = 'object')
);

COMMENT ON TABLE public.safety_alerts
    IS 'Audit trail of SOS/inform triggers and how many trusted contacts were notified.';

CREATE INDEX IF NOT EXISTS idx_safety_alerts_user_created
    ON public.safety_alerts (user_id, created_at DESC);

ALTER TABLE public.safety_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "safety_alerts_select_own"
    ON public.safety_alerts
    FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "safety_alerts_insert_own"
    ON public.safety_alerts
    FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id);


-- ==========================================================
-- DIGITAL WITNESS EVIDENCE
-- Metadata for Silent SOS video/audio segments. The decryption key is
-- escrowed here (not held only on-device) so a future OTP-authenticated
-- trusted-contact portal can decrypt it after verifying the requester -
-- the server never sees the plaintext media itself, only ciphertext in
-- storage plus this key, and access to this table is locked to the owning
-- user until that portal exists.
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.safety_evidence (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    alert_id UUID NOT NULL REFERENCES public.safety_alerts(id) ON DELETE CASCADE,

    storage_path TEXT NOT NULL,
    media_key_base64 TEXT NOT NULL,
    content_type TEXT NOT NULL CHECK (content_type IN ('video', 'audio')),
    duration_seconds NUMERIC,

    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.safety_evidence
    IS 'Encrypted Silent SOS recording segments (video/audio). storage_path points into the private safety_evidence bucket; media_key_base64 is the AES-GCM key escrowed for future authenticated trusted-contact access.';

CREATE INDEX IF NOT EXISTS idx_safety_evidence_alert
    ON public.safety_evidence (alert_id);

ALTER TABLE public.safety_evidence ENABLE ROW LEVEL SECURITY;

CREATE POLICY "safety_evidence_select_own"
    ON public.safety_evidence
    FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "safety_evidence_insert_own"
    ON public.safety_evidence
    FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id);


-- ==========================================================
-- EVIDENCE STORAGE
-- Private bucket, folder-per-user ownership (path convention:
-- '{user_id}/{uuid}.<ext>'), same shape as feedback_attachments.
-- ==========================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'safety_evidence',
    'safety_evidence',
    false,
    52428800, -- 50MB per segment (short video/audio clips)
    ARRAY['video/mp4', 'video/quicktime', 'audio/aac', 'audio/mp4', 'application/octet-stream']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "safety_evidence_insert_own" ON storage.objects;
CREATE POLICY "safety_evidence_insert_own"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'safety_evidence'
        AND (storage.foldername(name))[1] = (auth.uid())::text
    );

DROP POLICY IF EXISTS "safety_evidence_select_own" ON storage.objects;
CREATE POLICY "safety_evidence_select_own"
    ON storage.objects
    FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'safety_evidence'
        AND (storage.foldername(name))[1] = (auth.uid())::text
    );

COMMIT;
