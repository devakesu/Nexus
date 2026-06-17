-- ==========================================================
-- MATCHES
-- Tracks mutual like/superlike pairs (matches) between users.
-- Created by the application layer when a like-back action results in a match.
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.matches (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),

    -- The user who sent the original like/superlike
    liker_id        UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    -- The user who liked back, completing the match
    liked_back_id   UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

    tab             TEXT        NOT NULL DEFAULT 'Dating'
                                CHECK (tab IN ('Dating', 'Friends', 'Professional')),

    created_at      TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    -- Populated when either user dissolves the match (unmatch, block, or report)
    unmatched_at    TIMESTAMPTZ,
    unmatched_by    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,

    CONSTRAINT matches_unique_pair UNIQUE (liker_id, liked_back_id, tab),
    CONSTRAINT matches_no_self_match CHECK (liker_id <> liked_back_id)
);

COMMENT ON TABLE public.matches
    IS 'Mutual like pairs. A row is inserted when user A likes back user B. unmatched_at marks dissolution.';

COMMENT ON COLUMN public.matches.liker_id       IS 'User who sent the original like/superlike.';
COMMENT ON COLUMN public.matches.liked_back_id  IS 'User who reciprocated the like.';
COMMENT ON COLUMN public.matches.unmatched_at   IS 'Timestamp the match was dissolved; NULL means still active.';
COMMENT ON COLUMN public.matches.unmatched_by   IS 'Which user dissolved the match.';


-- ==========================================================
-- INDEXES
-- ==========================================================

-- Fast lookup of all active matches for a given user (liker side)
CREATE INDEX IF NOT EXISTS idx_matches_liker_active
    ON public.matches (liker_id, tab)
    WHERE unmatched_at IS NULL;

-- Fast lookup of all active matches for a given user (liked-back side)
CREATE INDEX IF NOT EXISTS idx_matches_liked_back_active
    ON public.matches (liked_back_id, tab)
    WHERE unmatched_at IS NULL;


-- ==========================================================
-- RLS
-- Users can select their own matches; backend service role handles writes.
-- ==========================================================

ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "matches_select_own"
    ON public.matches
    FOR SELECT
    TO authenticated
    USING (liker_id = (SELECT auth.uid()) OR liked_back_id = (SELECT auth.uid()));
