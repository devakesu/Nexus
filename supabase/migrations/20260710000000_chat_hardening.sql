-- ==========================================================
-- PHASE 7 HARDENING
-- Closes a gap found during the RLS/Realtime security review: every other
-- chat table (chat_messages, chat_events) was added to the
-- supabase_realtime publication, but chat_conversations was missed. The
-- client needs live UPDATE events on chat_conversations.closed_at so an
-- open chat screen can detect the other user unmatching/blocking mid-
-- conversation and react (disable the composer, tear down its message
-- subscription) instead of only finding out the next time it's reopened.
-- RLS (chat_conversations_select_own) already scopes this correctly -
-- this migration only fixes realtime delivery, not access control.
-- ==========================================================

BEGIN;

ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_conversations;

COMMIT;
