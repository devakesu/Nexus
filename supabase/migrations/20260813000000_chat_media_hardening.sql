-- ==========================================================
-- CHAT MEDIA RLS HARDENING
-- 1. Updates chat_media_select_participant to enforce that the conversation
--    is open (c.closed_at IS NULL), ensuring that blocked or unmatched users
--    cannot download media from terminated conversations.
-- 2. Adds chat_media_delete_participant policy so conversation participants
--    can clean up orphaned or failed media uploads in their open conversations.
-- ==========================================================

BEGIN;

-- 1. Select policy: authenticated participants of open conversations only.
DROP POLICY IF EXISTS "chat_media_select_participant" ON storage.objects;
CREATE POLICY "chat_media_select_participant"
    ON storage.objects
    FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'chat_media'
        AND EXISTS (
            SELECT 1 FROM public.chat_conversations c
            WHERE c.id::text = (storage.foldername(name))[1]
              AND (c.user_a_id = (SELECT auth.uid()) OR c.user_b_id = (SELECT auth.uid()))
              AND c.closed_at IS NULL
        )
    );

-- 2. Delete policy: authenticated participants of open conversations only.
DROP POLICY IF EXISTS "chat_media_delete_participant" ON storage.objects;
CREATE POLICY "chat_media_delete_participant"
    ON storage.objects
    FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'chat_media'
        AND EXISTS (
            SELECT 1 FROM public.chat_conversations c
            WHERE c.id::text = (storage.foldername(name))[1]
              AND (c.user_a_id = (SELECT auth.uid()) OR c.user_b_id = (SELECT auth.uid()))
              AND c.closed_at IS NULL
        )
    );

COMMIT;
