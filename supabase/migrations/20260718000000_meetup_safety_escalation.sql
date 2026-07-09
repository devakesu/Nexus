-- ==========================================================
-- MEETUP SAFETY: DEAD-MAN'S-SWITCH ESCALATION
-- Adds heartbeat/escalation tracking to safety_sessions so a scheduled job
-- can detect a device gone unreachable past its check-in deadline and
-- notify trusted contacts, without a Nexus account or app on their end.
-- See the Meetup Safety plan, Milestone D.
-- ==========================================================

BEGIN;

ALTER TABLE public.safety_sessions
    ADD COLUMN IF NOT EXISTS last_heartbeat_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS battery_percent SMALLINT,
    ADD COLUMN IF NOT EXISTS connection_type TEXT,
    ADD COLUMN IF NOT EXISTS escalations_sent SMALLINT NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_escalated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS escalation_cancelled_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS escalation_cancel_reason TEXT
        CHECK (escalation_cancel_reason IS NULL OR escalation_cancel_reason IN ('safe', 'other')),
    ADD COLUMN IF NOT EXISTS escalation_cancel_note TEXT;

COMMENT ON COLUMN public.safety_sessions.last_heartbeat_at IS 'Last time the device successfully checked in or started this session.';
COMMENT ON COLUMN public.safety_sessions.battery_percent IS 'Device battery percentage as of the last heartbeat, 0-100. Included in escalation SMS so trusted contacts can tell "phone likely died" from "something happened".';
COMMENT ON COLUMN public.safety_sessions.connection_type IS 'Device connection type as of the last heartbeat (wifi/cellular/offline) - the honest cross-platform substitute for signal strength, which iOS does not expose to third-party apps.';
COMMENT ON COLUMN public.safety_sessions.escalations_sent IS 'How many "device unreachable" alerts have fired for the current missed-checkin streak. Capped at 3; resets to 0 on the next successful heartbeat.';
COMMENT ON COLUMN public.safety_sessions.escalation_cancelled_at IS 'Set when a trusted contact taps the cancel link in an escalation SMS, stopping further escalations for this session.';
COMMENT ON COLUMN public.safety_sessions.escalation_cancel_reason IS 'Why a trusted contact cancelled further escalation: safe (they confirmed the user is fine) or other (free-text in escalation_cancel_note).';

CREATE INDEX IF NOT EXISTS idx_safety_sessions_overdue
    ON public.safety_sessions (status, next_checkin_at)
    WHERE status = 'active' AND escalation_cancelled_at IS NULL;

COMMIT;
