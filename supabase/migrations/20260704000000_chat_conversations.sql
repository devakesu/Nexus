-- ==========================================================
-- CHAT CONVERSATIONS
-- One conversation per active match. Created lazily (by the backend)
-- the first time either matched user opens the chat / sends a message.
-- Message content itself is added in a later migration; this table is
-- pure conversation metadata used to drive the Chats list and the
-- "New Chat" (matched-but-not-chatting) picker.
-- ==========================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.chat_conversations (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    match_id            UUID        NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,

    -- Denormalized from matches for cheap RLS checks without a join.
    user_a_id           UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    user_b_id           UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    tab                 TEXT        NOT NULL
                                    CHECK (tab IN ('Dating', 'Friends', 'Professional')),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    -- NULL means "matched but no conversation started yet" - this is the
    -- exact flag the New Chat picker uses to distinguish candidates from
    -- active conversations. Set (and kept up to date) by a trigger on
    -- chat_messages once that table exists.
    last_message_at     TIMESTAMPTZ,

    -- Populated when the underlying match is dissolved (unmatch/block/report).
    closed_at           TIMESTAMPTZ,
    closed_reason       TEXT        CHECK (closed_reason IN ('unmatch', 'block', 'report')),

    -- Set once the two participants complete Signal Protocol session
    -- establishment (X3DH). No key material lives here or anywhere
    -- server-side beyond public bundles in later migrations.
    session_established_at TIMESTAMPTZ,

    CONSTRAINT chat_conversations_unique_match UNIQUE (match_id),
    CONSTRAINT chat_conversations_no_self_chat CHECK (user_a_id <> user_b_id)
);

COMMENT ON TABLE public.chat_conversations
    IS 'Conversation metadata for a match. Message ciphertext lives in chat_messages (later migration).';

COMMENT ON COLUMN public.chat_conversations.match_id            IS 'The match this conversation belongs to; one conversation per match.';
COMMENT ON COLUMN public.chat_conversations.last_message_at     IS 'NULL = matched but not chatting yet. Set on first message send.';
COMMENT ON COLUMN public.chat_conversations.closed_at           IS 'Timestamp the conversation was closed alongside its match dissolving.';
COMMENT ON COLUMN public.chat_conversations.closed_reason       IS 'Why the conversation closed: unmatch, block, or report.';
COMMENT ON COLUMN public.chat_conversations.session_established_at IS 'When both participants completed Signal Protocol session setup.';


-- ==========================================================
-- INDEXES
-- ==========================================================

-- Chats list: active conversations for a user, most recent first.
CREATE INDEX IF NOT EXISTS idx_chat_conversations_user_a_active
    ON public.chat_conversations (user_a_id, tab, last_message_at DESC)
    WHERE closed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_chat_conversations_user_b_active
    ON public.chat_conversations (user_b_id, tab, last_message_at DESC)
    WHERE closed_at IS NULL;

-- New Chat picker: conversations with no message sent yet.
CREATE INDEX IF NOT EXISTS idx_chat_conversations_not_started
    ON public.chat_conversations (user_a_id, user_b_id, tab)
    WHERE closed_at IS NULL AND last_message_at IS NULL;


-- ==========================================================
-- RLS
-- Participants can only read their own conversations. All writes
-- (create/close/session-established) go through the backend service
-- role, same trust model as public.matches.
-- ==========================================================

ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "chat_conversations_select_own"
    ON public.chat_conversations
    FOR SELECT
    TO authenticated
    USING (user_a_id = (SELECT auth.uid()) OR user_b_id = (SELECT auth.uid()));

COMMIT;
