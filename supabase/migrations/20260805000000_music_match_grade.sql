-- Migration: add_music_match_grade_fields_to_discovery_session_items

BEGIN;

-- Add music match grade columns
ALTER TABLE public.discovery_session_items 
ADD COLUMN IF NOT EXISTS music_match_grade INT,
ADD COLUMN IF NOT EXISTS viewer_spotify_connected BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN IF NOT EXISTS candidate_spotify_connected BOOLEAN NOT NULL DEFAULT false;

-- Re-create discovery session creation function to accept and insert music grade columns
CREATE OR REPLACE FUNCTION public.create_discovery_session_with_items(
    p_viewer_id UUID,
    p_tab TEXT,
    p_filters JSONB,
    p_expires_at TIMESTAMPTZ,
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
    -- Insert the discovery session
    INSERT INTO public.discovery_sessions (viewer_id, tab, filters, expires_at)
    VALUES (p_viewer_id, p_tab, p_filters, p_expires_at)
    RETURNING id INTO v_session_id;

    -- Insert each item in the session
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        position INT,
        candidate_id UUID,
        score DOUBLE PRECISION,
        x DOUBLE PRECISION,
        y DOUBLE PRECISION,
        orbit_tier INT,
        music_match_grade INT,
        viewer_spotify_connected BOOLEAN,
        candidate_spotify_connected BOOLEAN
    ) LOOP
        INSERT INTO public.discovery_session_items (
            session_id, position, candidate_id, score, x, y, orbit_tier,
            music_match_grade, viewer_spotify_connected, candidate_spotify_connected
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
            COALESCE(v_item.viewer_spotify_connected, false),
            COALESCE(v_item.candidate_spotify_connected, false)
        );
    END LOOP;

    RETURN v_session_id;
END;
$$;

REVOKE ALL ON FUNCTION public.create_discovery_session_with_items(UUID, TEXT, JSONB, TIMESTAMPTZ, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_discovery_session_with_items(UUID, TEXT, JSONB, TIMESTAMPTZ, JSONB) TO service_role;

COMMIT;
