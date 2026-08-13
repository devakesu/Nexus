-- ==========================================================
-- MATCHES SYMMETRIC UNIQUE INDEX
-- Enforces that at most one active match exists per user pair per tab,
-- regardless of which user was liker_id vs liked_back_id.
-- ==========================================================

BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS uq_matches_symmetric_pair_active
    ON public.matches (LEAST(liker_id, liked_back_id), GREATEST(liker_id, liked_back_id), tab)
    WHERE unmatched_at IS NULL;

COMMIT;
