-- ==========================================================
-- MATCH PRECONDITION TRIGGER
-- Ensures a match row cannot be created unless an active, unrevoked
-- incoming like (like/superlike) exists from liker_id to liked_back_id.
-- ==========================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.check_match_precondition()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profile_discovery_actions
        WHERE actor_id = NEW.liker_id
          AND target_id = NEW.liked_back_id
          AND action IN ('like', 'superlike')
          AND tab = NEW.tab
          AND revoked_at IS NULL
    ) THEN
        RAISE EXCEPTION 'No active incoming like found' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_matches_precondition ON public.matches;
CREATE TRIGGER trigger_matches_precondition
    BEFORE INSERT ON public.matches
    FOR EACH ROW
    EXECUTE FUNCTION public.check_match_precondition();

COMMIT;
