-- ==========================================================
-- CHAT MEDIA STORAGE
-- Private bucket for E2E-encrypted photo/voice attachments. Unlike
-- user_media (bucket-wide access for any authenticated user, appropriate
-- there since profile photos are meant to be browsable), chat media must
-- be scoped to exactly the two participants of the owning conversation -
-- enforced via storage.foldername(name), since uploads are written to
-- `{conversation_id}/{message_local_id}.enc`.
--
-- Objects are always ciphertext (AES-256-GCM encrypted client-side with a
-- random per-attachment key that itself only ever travels inside the
-- Signal Protocol-encrypted message envelope) - the server never has a
-- usable decryption key, so allowed_mime_types is fixed to
-- application/octet-stream regardless of the original media type.
-- ==========================================================

BEGIN;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'chat_media',
    'chat_media',
    false,
    20971520, -- 20MB ciphertext cap per attachment
    ARRAY['application/octet-stream']
)
ON CONFLICT (id) DO NOTHING;

-- Participants of the conversation named by the object's top-level path
-- segment may read attachments.
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
        )
    );

-- Participants may upload into an open (not closed/unmatched) conversation
-- they belong to. No UPDATE/DELETE policy - attachments are immutable from
-- the client's perspective, same as chat_messages rows.
DROP POLICY IF EXISTS "chat_media_insert_participant" ON storage.objects;
CREATE POLICY "chat_media_insert_participant"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'chat_media'
        AND EXISTS (
            SELECT 1 FROM public.chat_conversations c
            WHERE c.id::text = (storage.foldername(name))[1]
              AND (c.user_a_id = (SELECT auth.uid()) OR c.user_b_id = (SELECT auth.uid()))
              AND c.closed_at IS NULL
        )
    );

COMMIT;
