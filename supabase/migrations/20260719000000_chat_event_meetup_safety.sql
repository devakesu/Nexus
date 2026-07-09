-- ==========================================================
-- CHAT EVENT -> MEETUP SAFETY AUTO-CONFIGURE (Milestone F)
-- Lets the event creator opt into Meetup Safety at plan-creation time.
-- Plain (unencrypted) columns - unlike event_time/location, there's no PII
-- here, just a flag + an interval chosen from a fixed set of options.
-- ==========================================================

BEGIN;

ALTER TABLE public.chat_events
    ADD COLUMN IF NOT EXISTS safety_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS safety_interval_seconds INTEGER
        CHECK (safety_interval_seconds IS NULL OR safety_interval_seconds > 0),
    ADD COLUMN IF NOT EXISTS safety_reminder_sent_at TIMESTAMPTZ;

COMMENT ON COLUMN public.chat_events.safety_enabled IS
    'Set when the event creator opted into auto-configuring Meetup Safety for this plan at creation time. Personal to the creator - the other participant is unaffected and can still use the separate "Set up a safety check-in" shortcut on their own copy of the event card.';
COMMENT ON COLUMN public.chat_events.safety_interval_seconds IS
    'The check-in interval the creator chose, set only when safety_enabled - feeds the pre-event reminder copy and the MeetupSafetyPage prefill.';
COMMENT ON COLUMN public.chat_events.safety_reminder_sent_at IS
    'Set by the reminder scheduler once the "Meetup Safety turns on soon" push has fired for this event. Tracked separately from reminder_sent_at since the two reminders have different lead times and audiences (both participants vs. creator only).';

CREATE INDEX IF NOT EXISTS idx_chat_events_pending_safety_reminders
    ON public.chat_events (safety_reminder_sent_at)
    WHERE safety_enabled = TRUE AND safety_reminder_sent_at IS NULL AND status <> 'cancelled';

COMMIT;
