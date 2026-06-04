-- ==========================================================
-- NEXUS DISCOVERY SESSIONS
-- Snapshot-based pagination for unstable candidate pools
-- ==========================================================

-- Stores one frozen discovery feed snapshot per viewer/tab/filter combination.
-- A session allows the client to page through a stable ranked result set even
-- if the live candidate pool changes after the first page is generated.
CREATE TABLE IF NOT EXISTS public.discovery_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    viewer_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    tab TEXT NOT NULL CHECK (tab IN ('Dating', 'Friends', 'Professional')),

    -- Serialized normalized request filters captured at session creation time.
    filters JSONB NOT NULL DEFAULT '{}'::jsonb,

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now()),

    -- Session snapshots are intentionally short-lived so feeds stay reasonably fresh
    -- while still remaining stable for pagination.
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,

    -- Optional server-side progress marker. This is not required for client-driven
    -- pagination, but can be useful for analytics, resumability, or debugging.
    last_cursor_position INT NOT NULL DEFAULT 0,

    CONSTRAINT discovery_sessions_filters_object_check
        CHECK (jsonb_typeof(filters) = 'object')
);

-- Stores the ordered ranked candidates belonging to a discovery session.
-- position is the frozen order key used for stable page retrieval.
CREATE TABLE IF NOT EXISTS public.discovery_session_items (
    session_id UUID NOT NULL REFERENCES public.discovery_sessions(id) ON DELETE CASCADE,
    position INT NOT NULL CHECK (position >= 0),
    candidate_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    score DOUBLE PRECISION NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now()),
    PRIMARY KEY (session_id, position),
    UNIQUE (session_id, candidate_id)
);

COMMENT ON TABLE public.discovery_sessions
    IS 'Server-side snapshot of a ranked discovery feed for one viewer, tab, and filter set. Used to keep paging stable while live candidate pools change.';

COMMENT ON TABLE public.discovery_session_items
    IS 'Ordered ranked candidates belonging to a discovery session snapshot.';

COMMENT ON COLUMN public.discovery_sessions.viewer_id
    IS 'The user for whom the frozen discovery session was created.';

COMMENT ON COLUMN public.discovery_sessions.filters
    IS 'Normalized discovery filters captured when the session snapshot was created.';

COMMENT ON COLUMN public.discovery_sessions.expires_at
    IS 'UTC timestamp after which the discovery session should be treated as invalid and rebuilt.';

COMMENT ON COLUMN public.discovery_sessions.last_cursor_position
    IS 'Optional server-maintained pagination progress marker for debugging, analytics, or resumability.';

COMMENT ON COLUMN public.discovery_session_items.position
    IS 'Zero-based stable order position within the frozen ranked discovery session.';

COMMENT ON COLUMN public.discovery_session_items.candidate_id
    IS 'Profile id of the ranked candidate stored at the given session position.';

COMMENT ON COLUMN public.discovery_session_items.score
    IS 'Score assigned at snapshot creation time and retained for stable pagination.';


-- ==========================================================
-- INDEXES
-- ==========================================================

-- Fast lookup of recent sessions for one user and tab.
CREATE INDEX IF NOT EXISTS idx_discovery_sessions_viewer_tab_created
    ON public.discovery_sessions (viewer_id, tab, created_at DESC);

-- Supports expiry cleanup jobs and invalid-session checks.
CREATE INDEX IF NOT EXISTS idx_discovery_sessions_expiry
    ON public.discovery_sessions (expires_at);

-- Supports efficient ordered page reads from a session snapshot.
CREATE INDEX IF NOT EXISTS idx_discovery_session_items_session_position
    ON public.discovery_session_items (session_id, position);

-- Optional helper index for reverse lookups and analytics by candidate.
CREATE INDEX IF NOT EXISTS idx_discovery_session_items_candidate
    ON public.discovery_session_items (candidate_id);


-- ==========================================================
-- RLS
-- ==========================================================

ALTER TABLE public.discovery_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discovery_session_items ENABLE ROW LEVEL SECURITY;

-- Optional but recommended defense-in-depth so even table owners must obey RLS.
ALTER TABLE public.discovery_sessions FORCE ROW LEVEL SECURITY;
ALTER TABLE public.discovery_session_items FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own discovery sessions" ON public.discovery_sessions;
CREATE POLICY "Users can view own discovery sessions"
    ON public.discovery_sessions
    FOR SELECT
    USING ((SELECT auth.uid()) = viewer_id);

DROP POLICY IF EXISTS "Users can insert own discovery sessions" ON public.discovery_sessions;
CREATE POLICY "Users can insert own discovery sessions"
    ON public.discovery_sessions
    FOR INSERT
    WITH CHECK ((SELECT auth.uid()) = viewer_id);

DROP POLICY IF EXISTS "Users can update own discovery sessions" ON public.discovery_sessions;
CREATE POLICY "Users can update own discovery sessions"
    ON public.discovery_sessions
    FOR UPDATE
    USING ((SELECT auth.uid()) = viewer_id)
    WITH CHECK ((SELECT auth.uid()) = viewer_id);

DROP POLICY IF EXISTS "Users can delete own discovery sessions" ON public.discovery_sessions;
CREATE POLICY "Users can delete own discovery sessions"
    ON public.discovery_sessions
    FOR DELETE
    USING ((SELECT auth.uid()) = viewer_id);

COMMENT ON POLICY "Users can view own discovery sessions" ON public.discovery_sessions
    IS 'Allows a user to read only discovery sessions where they are the viewer.';

COMMENT ON POLICY "Users can insert own discovery sessions" ON public.discovery_sessions
    IS 'Allows a user to create discovery sessions only for their own viewer_id.';

COMMENT ON POLICY "Users can update own discovery sessions" ON public.discovery_sessions
    IS 'Allows a user to update only discovery sessions where they are the viewer.';

COMMENT ON POLICY "Users can delete own discovery sessions" ON public.discovery_sessions
    IS 'Allows a user to delete only discovery sessions where they are the viewer.';


DROP POLICY IF EXISTS "Users can view own discovery session items" ON public.discovery_session_items;
CREATE POLICY "Users can view own discovery session items"
    ON public.discovery_session_items
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.discovery_sessions ds
            WHERE ds.id = discovery_session_items.session_id
              AND ds.viewer_id = (SELECT auth.uid())
        )
    );

-- Needed if session items are inserted while running under a role subject to RLS.
DROP POLICY IF EXISTS "Users can insert own discovery session items" ON public.discovery_session_items;
CREATE POLICY "Users can insert own discovery session items"
    ON public.discovery_session_items
    FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.discovery_sessions ds
            WHERE ds.id = discovery_session_items.session_id
              AND ds.viewer_id = (SELECT auth.uid())
        )
    );

-- Optional: useful if application-level cleanup deletes items directly instead of
-- relying on ON DELETE CASCADE from discovery_sessions.
DROP POLICY IF EXISTS "Users can delete own discovery session items" ON public.discovery_session_items;
CREATE POLICY "Users can delete own discovery session items"
    ON public.discovery_session_items
    FOR DELETE
    USING (
        EXISTS (
            SELECT 1
            FROM public.discovery_sessions ds
            WHERE ds.id = discovery_session_items.session_id
              AND ds.viewer_id = (SELECT auth.uid())
        )
    );

COMMENT ON POLICY "Users can view own discovery session items" ON public.discovery_session_items
    IS 'Allows a user to read only session items belonging to discovery sessions they own.';

COMMENT ON POLICY "Users can insert own discovery session items" ON public.discovery_session_items
    IS 'Allows a user to insert session items only into discovery sessions they own.';

COMMENT ON POLICY "Users can delete own discovery session items" ON public.discovery_session_items
    IS 'Allows a user to delete session items only from discovery sessions they own.';