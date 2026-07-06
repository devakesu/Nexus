-- ==========================================================
-- ENCRYPT CHAT EVENTS (date/plan proposals)
-- Alters event_time, location_lat, location_lng, location_label
-- to BYTEA so that they can store PII encrypted data.
-- ==========================================================

BEGIN;

-- Drop index depending on event_time
DROP INDEX IF EXISTS public.idx_chat_events_due_reminders;

-- Alter column types to BYTEA
ALTER TABLE public.chat_events ALTER COLUMN event_time TYPE BYTEA USING event_time::text::bytea;
ALTER TABLE public.chat_events ALTER COLUMN location_lat TYPE BYTEA USING location_lat::text::bytea;
ALTER TABLE public.chat_events ALTER COLUMN location_lng TYPE BYTEA USING location_lng::text::bytea;
ALTER TABLE public.chat_events ALTER COLUMN location_label TYPE BYTEA USING location_label::text::bytea;

-- Update column comments
COMMENT ON COLUMN public.chat_events.event_time IS 'Encrypted ISO timestamp of the event.';
COMMENT ON COLUMN public.chat_events.location_lat IS 'Encrypted latitude of the location.';
COMMENT ON COLUMN public.chat_events.location_lng IS 'Encrypted longitude of the location.';
COMMENT ON COLUMN public.chat_events.location_label IS 'Encrypted label of the location.';

-- Re-create scheduler query index without using event_time
CREATE INDEX IF NOT EXISTS idx_chat_events_pending_reminders
    ON public.chat_events (reminder_sent_at)
    WHERE reminder_sent_at IS NULL AND status <> 'cancelled';

COMMIT;
