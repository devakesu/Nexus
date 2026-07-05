-- ==========================================================
-- CHAT EVENTS (date/plan proposals)
-- Balanced storage: event_time and location are stored here in plaintext
-- so the backend can schedule real reminder pushes (and, later, power
-- Safety Center's Date Check-In). Title/notes are NOT stored here at all -
-- they live only as ratchet-encrypted ciphertext on the linked
-- chat_messages row (message_type = 'event'), decryptable solely by the
-- two participants, identical to a normal text message.
-- ==========================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.chat_events (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id   UUID        NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
    message_id        UUID        NOT NULL UNIQUE REFERENCES public.chat_messages(id) ON DELETE CASCADE,
    created_by        UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

    event_time        TIMESTAMPTZ NOT NULL,
    location_lat      DOUBLE PRECISION,
    location_lng      DOUBLE PRECISION,
    location_label    TEXT,

    status            TEXT        NOT NULL DEFAULT 'proposed'
                                   CHECK (status IN ('proposed', 'confirmed', 'cancelled')),
    reminder_sent_at  TIMESTAMPTZ,

    created_at        TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.chat_events IS
    'Date/plan proposals attached to a chat_messages row. event_time/location are plaintext by design (reminder scheduling); title/notes live only as ciphertext on the linked message.';
COMMENT ON COLUMN public.chat_events.message_id IS
    'The chat_messages row (type=event) whose decrypted ciphertext holds {title, notes}.';
COMMENT ON COLUMN public.chat_events.reminder_sent_at IS
    'Set by the reminder scheduler once a push has fired for this event.';

CREATE INDEX IF NOT EXISTS idx_chat_events_conversation
    ON public.chat_events (conversation_id);

-- Scheduler query: due, not-yet-reminded, not-cancelled events.
CREATE INDEX IF NOT EXISTS idx_chat_events_due_reminders
    ON public.chat_events (event_time)
    WHERE reminder_sent_at IS NULL AND status <> 'cancelled';

DROP TRIGGER IF EXISTS set_chat_events_updated_at ON public.chat_events;
CREATE TRIGGER set_chat_events_updated_at
    BEFORE UPDATE ON public.chat_events
    FOR EACH ROW
    EXECUTE PROCEDURE public.set_updated_at();


-- ==========================================================
-- RLS
-- Only SELECT is exposed to clients (participants of the parent
-- conversation) - creation and status updates go through the backend
-- service role, same trust model as chat_messages.
-- ==========================================================

ALTER TABLE public.chat_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "chat_events_select_participant"
    ON public.chat_events
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.chat_conversations c
            WHERE c.id = chat_events.conversation_id
              AND (c.user_a_id = (SELECT auth.uid()) OR c.user_b_id = (SELECT auth.uid()))
        )
    );


-- ==========================================================
-- REALTIME
-- So both participants see status changes (confirmed/cancelled) live.
-- ==========================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_events;

COMMIT;
