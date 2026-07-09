-- ==========================================================
-- USER_MEDIA: OWNER-SCOPED WRITE/READ ACCESS (H1 FIX)
-- ==========================================================
-- The original policy (20260608183500_profile_media.sql) granted every
-- authenticated user FOR ALL access to the entire user_media bucket, scoped
-- only by bucket_id - any signed-in user could list/download/overwrite/
-- delete any other user's profile photos. Uploads are always written to
-- '{user_id}/photo_*.jpg' (see client_ai_image_provider.dart), so ownership
-- can be enforced the same way chat_media and safety_evidence already do,
-- via the object path's top-level folder segment.
--
-- SELECT is scoped to owner-only too, matching the "move to signed URLs"
-- direction: other users' photos are no longer readable by any authenticated
-- client directly against storage. Instead, the backend (which already knows
-- - via its own query/authorization for discovery, chat, likes, moderation-
-- subjects - that the requester may see a given profile) exchanges that
-- profile's storage paths for short-lived signed URLs using the service-role
-- client, which bypasses this RLS entirely. See app/db/profiles.py's
-- sign_profile_media / sign_profile_media_bulk.
-- ==========================================================

BEGIN;

DROP POLICY IF EXISTS "Allow backend storage tracking access" ON storage.objects;

CREATE POLICY "user_media_select_own"
    ON storage.objects
    FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'user_media'
        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    );

CREATE POLICY "user_media_insert_own"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'user_media'
        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    );

CREATE POLICY "user_media_update_own"
    ON storage.objects
    FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'user_media'
        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    )
    WITH CHECK (
        bucket_id = 'user_media'
        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    );

CREATE POLICY "user_media_delete_own"
    ON storage.objects
    FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'user_media'
        AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    );

COMMIT;
