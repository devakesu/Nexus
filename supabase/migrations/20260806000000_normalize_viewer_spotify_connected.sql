-- Migration: normalize_viewer_spotify_connected_to_parent_table

BEGIN;

-- Drop viewer_spotify_connected from items table
ALTER TABLE public.discovery_session_items 
DROP COLUMN IF EXISTS viewer_spotify_connected;

-- Add viewer_spotify_connected to parent sessions table
ALTER TABLE public.discovery_sessions 
ADD COLUMN IF NOT EXISTS viewer_spotify_connected BOOLEAN NOT NULL DEFAULT false;

-- Re-create discovery session creation function with p_viewer_spotify_connected parameter
CREATE OR REPLACE FUNCTION public.create_discovery_session_with_items(
    p_viewer_id UUID,
    p_tab TEXT,
    p_filters JSONB,
    p_expires_at TIMESTAMPTZ,
    p_viewer_spotify_connected BOOLEAN,
    p_items JSONB
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_session_id UUID;
    v_item RECORD;
BEGIN
    -- Insert the discovery session with the viewer connection flag
    INSERT INTO public.discovery_sessions (
        viewer_id, 
        tab, 
        filters, 
        expires_at, 
        viewer_spotify_connected
    )
    VALUES (
        p_viewer_id, 
        p_tab, 
        p_filters, 
        p_expires_at, 
        COALESCE(p_viewer_spotify_connected, false)
    )
    RETURNING id INTO v_session_id;

    -- Insert each item in the session (omitting viewer_spotify_connected)
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        position INT,
        candidate_id UUID,
        score DOUBLE PRECISION,
        x DOUBLE PRECISION,
        y DOUBLE PRECISION,
        orbit_tier INT,
        music_match_grade INT,
        candidate_spotify_connected BOOLEAN
    ) LOOP
        INSERT INTO public.discovery_session_items (
            session_id, 
            position, 
            candidate_id, 
            score, 
            x, 
            y, 
            orbit_tier,
            music_match_grade, 
            candidate_spotify_connected
        )
        VALUES (
            v_session_id, 
            v_item.position, 
            v_item.candidate_id, 
            v_item.score, 
            v_item.x, 
            v_item.y, 
            v_item.orbit_tier,
            v_item.music_match_grade,
            COALESCE(v_item.candidate_spotify_connected, false)
        );
    END LOOP;

    RETURN v_session_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_discovery_session_with_items(UUID, TEXT, JSONB, TIMESTAMPTZ, BOOLEAN, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_discovery_session_with_items(UUID, TEXT, JSONB, TIMESTAMPTZ, BOOLEAN, JSONB) TO service_role;

COMMIT;
