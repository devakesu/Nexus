-- ==========================================================
-- ACCOUNT DELETION - new chat_conversations.closed_reason value
--
-- closed_reason currently allows only 'unmatch', 'block', 'report'
-- (20260704000000_chat_conversations.sql). Account deletion needs a
-- distinct fourth value: when a user requests deletion, their open
-- conversations are closed with reason='account_deletion' rather than a
-- real unmatch, specifically so cancel_deletion() can safely reopen only
-- conversations closed for *this* reason (an exact match on
-- closed_reason='account_deletion') without ever touching a conversation
-- that was separately, genuinely unmatched/blocked/reported before the
-- deletion request. See request_deletion()/cancel_deletion() in
-- app/db/account_deletion.py.
-- ==========================================================

BEGIN;

ALTER TABLE public.chat_conversations
    DROP CONSTRAINT IF EXISTS chat_conversations_closed_reason_check;

ALTER TABLE public.chat_conversations
    ADD CONSTRAINT chat_conversations_closed_reason_check
        CHECK (closed_reason IN ('unmatch', 'block', 'report', 'account_deletion'));

COMMENT ON COLUMN public.chat_conversations.closed_reason IS
    'Why the conversation closed: unmatch, block, report, or account_deletion. account_deletion is the only one that gets reopened automatically (by cancel_deletion(), if the user reactivates within the grace window).';

COMMIT;
