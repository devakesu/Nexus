-- ==========================================================
-- LIKES SEEN TRACKING
-- Adds seen_at to profile_discovery_actions so the target user's
-- "Likes" inbox can distinguish new vs already-viewed likes.
-- ==========================================================

ALTER TABLE public.profile_discovery_actions
    ADD COLUMN IF NOT EXISTS seen_at TIMESTAMPTZ NULL;

COMMENT ON COLUMN public.profile_discovery_actions.seen_at
    IS 'Timestamp when the target user viewed this like/superlike. NULL means unseen.';

-- Fast index for the likes-inbox query:
--   SELECT ... WHERE target_id = $1 AND action IN ('like','superlike')
--                AND tab = $2 AND revoked_at IS NULL
CREATE INDEX IF NOT EXISTS idx_pda_likes_inbox
    ON public.profile_discovery_actions (target_id, tab, action, revoked_at)
    WHERE action IN ('like', 'superlike') AND revoked_at IS NULL;
