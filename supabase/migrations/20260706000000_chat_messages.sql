-- ==========================================================
-- CHAT MESSAGES
-- Ciphertext-only storage: the server never has plaintext or key
-- material. `ciphertext` is a base64-encoded Signal Protocol message
-- envelope (stored as TEXT rather than BYTEA - this table is written by
-- the FastAPI backend but read directly by the mobile client via
-- Supabase Realtime/PostgREST, and TEXT round-trips identically across
-- both without bytea/hex-encoding ambiguity). `ciphertext_metadata` is
-- protocol bookkeeping only (e.g. which Signal message type it is) -
-- never content.
-- ==========================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.chat_messages (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id     UUID        NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
    sender_id           UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    message_type        TEXT        NOT NULL DEFAULT 'text'
                                     CHECK (message_type IN ('text', 'image', 'voice', 'event', 'location')),
    ciphertext          TEXT        NOT NULL,
    ciphertext_metadata JSONB       NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    -- Metadata-only delivery/read signals (Phase 4 wires read receipts to
    -- the privacy setting; delivered_at is reserved for a later phase).
    delivered_at        TIMESTAMPTZ,
    read_at             TIMESTAMPTZ
);

COMMENT ON TABLE public.chat_messages IS
    'E2E-encrypted chat messages. Server stores ciphertext + protocol metadata only, never plaintext or keys.';
COMMENT ON COLUMN public.chat_messages.ciphertext IS
    'Base64-encoded Signal Protocol message envelope (PreKeySignalMessage or SignalMessage).';
COMMENT ON COLUMN public.chat_messages.ciphertext_metadata IS
    'Protocol bookkeeping only, e.g. {"signal_message_type": "prekey"|"whisper"}. Never content.';


-- ==========================================================
-- INDEXES
-- ==========================================================

CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation_created
    ON public.chat_messages (conversation_id, created_at);


-- ==========================================================
-- TRIGGER: keep chat_conversations.last_message_at in sync
-- This is what flips a conversation from "New Chat candidate" to an
-- active conversation in the Phase 1 Chats list / picker.
-- ==========================================================

CREATE OR REPLACE FUNCTION public.touch_conversation_last_message()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.chat_conversations
    SET last_message_at = NEW.created_at
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_conversation_last_message_at ON public.chat_messages;
CREATE TRIGGER set_conversation_last_message_at
    AFTER INSERT ON public.chat_messages
    FOR EACH ROW
    EXECUTE PROCEDURE public.touch_conversation_last_message();


-- ==========================================================
-- RLS
-- Only SELECT is exposed to clients (participants of the parent
-- conversation). All writes go through the backend service role, which
-- validates participancy + conversation open-state before inserting and
-- fires the push notification - same trust model as public.matches.
-- ==========================================================

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "chat_messages_select_participant"
    ON public.chat_messages
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.chat_conversations c
            WHERE c.id = chat_messages.conversation_id
              AND (c.user_a_id = (SELECT auth.uid()) OR c.user_b_id = (SELECT auth.uid()))
        )
    );


-- ==========================================================
-- REALTIME
-- Enable Postgres Changes so mobile clients get INSERT events for
-- conversations they participate in (enforced by the RLS policy above,
-- which Realtime respects for authenticated subscribers).
-- ==========================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;

COMMIT;
