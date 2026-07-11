-- ==========================================================
-- SPOTIFY PLAYLISTS + WEIGHTED ARTIST AFFINITY
--
-- Extends the existing top_artists-only Spotify integration with:
--   1. A persistent (encrypted) Spotify connection, so playlists can be
--      resynced on demand without forcing the user through OAuth again.
--   2. Owned/collaborative playlist storage - private, owner-only, never
--      surfaced to peers (see app/db/profiles.py fetch_peer_profile_by_id
--      and app/db/sessions.py fetch_discovery_node_detail, neither of
--      which select artist_affinity or touch spotify_playlists).
--   3. A frequency-weighted artist_affinity signal for the matching engine,
--      replacing the flat top_artists set-overlap scoring. top_artists
--      itself is untouched structurally - it remains the bounded public
--      display list; its computation just changes upstream (see
--      app/services/spotify_sync.py).
-- ==========================================================

BEGIN;

-- 1. profiles: new matching-engine signal + freshness marker
-- --------------------------------------------------------

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS artist_affinity BYTEA;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS music_taste_synced_at TIMESTAMPTZ;

COMMENT ON COLUMN public.profiles.artist_affinity IS
    'Encrypted JSON object {lowercased_artist_name: weight in (0,1]}, <=50 entries. Blend of /me/top/artists rank and owned/collaborative playlist track frequency. Matching-engine input only - must never be selected into fetch_peer_profile_by_id, fetch_discovery_node_detail, or any other peer-facing query.';
COMMENT ON COLUMN public.profiles.music_taste_synced_at IS
    'UTC timestamp of the last successful Spotify sync (artist_affinity + top_artists + spotify_playlists). NULL if never synced under this flow.';


-- 2. spotify_connections: encrypted refresh token, one row per user
-- --------------------------------------------------------
-- Deny-all client RLS, same pattern as vector_profiles / profile_pseudonym_map:
-- this table is never read or written by anything other than the backend's
-- service_role client, which bypasses RLS entirely.

CREATE TABLE IF NOT EXISTS public.spotify_connections (
    user_id           UUID        PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    spotify_user_id   TEXT        NOT NULL,
    refresh_token     BYTEA       NOT NULL,
    granted_scopes    TEXT        NOT NULL DEFAULT '',
    connected_at      TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    last_synced_at    TIMESTAMPTZ,
    last_sync_status  TEXT,
    last_sync_error   TEXT,
    disconnected_at   TIMESTAMPTZ
);

COMMENT ON TABLE public.spotify_connections IS
    'Encrypted Spotify OAuth refresh tokens enabling on-demand/periodic resync without re-running OAuth. Deny-all RLS - service_role backend access only.';
COMMENT ON COLUMN public.spotify_connections.refresh_token IS
    'Fernet-encrypted (MultiFernet, same scheme as profiles PII columns) Spotify refresh token.';

ALTER TABLE public.spotify_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.spotify_connections FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Deny all client-side spotify connection access" ON public.spotify_connections;
CREATE POLICY "Deny all client-side spotify connection access"
    ON public.spotify_connections
    FOR ALL
    USING (false)
    WITH CHECK (false);

COMMENT ON POLICY "Deny all client-side spotify connection access" ON public.spotify_connections
    IS 'Explicit deny-all RLS policy for client roles; intended access is privileged backend only. No GRANT is issued to anon/authenticated - see 20260724000000_revoke_default_privileges.sql.';


-- 3. spotify_playlists: one row per owned/collaborative playlist
-- --------------------------------------------------------
-- Self-select RLS: the owner can read their own rows. All writes happen
-- exclusively through the FastAPI backend's service_role client (RLS is a
-- defense-in-depth backstop, matching the established convention - see
-- 20260620000000_rls_rationalize.sql / the "matches" table). No playlist
-- cover art or track images are stored: Spotify's returned image URLs
-- expire in under a day, and Spotify Developer Policy prohibits caching/
-- downloading their visual content, so only text (names, artist names,
-- Spotify track ids) is persisted.

CREATE TABLE IF NOT EXISTS public.spotify_playlists (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id              UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    spotify_playlist_id  TEXT        NOT NULL,
    name                 BYTEA       NOT NULL,
    is_collaborative     BOOLEAN     NOT NULL DEFAULT FALSE,
    track_count          INTEGER     NOT NULL DEFAULT 0,
    tracks               BYTEA,
    synced_at            TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT spotify_playlists_unique_per_user UNIQUE (user_id, spotify_playlist_id)
);

COMMENT ON TABLE public.spotify_playlists IS
    'Playlists the user owns or collaborates on (Get Playlist Items 403s for merely-followed playlists). name/tracks encrypted. PRIVATE - only ever served to the owner via GET /api/v1/spotify/playlists; never joined into discovery/likes/orbit responses.';
COMMENT ON COLUMN public.spotify_playlists.tracks IS
    'Fernet-encrypted JSON array of {spotify_track_id, name, artists: [names]} - names only, no audio/images/preview URLs/popularity, per Spotify Developer Policy.';

CREATE INDEX IF NOT EXISTS idx_spotify_playlists_user ON public.spotify_playlists (user_id);

ALTER TABLE public.spotify_playlists ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "spotify_playlists_select_own" ON public.spotify_playlists;
CREATE POLICY "spotify_playlists_select_own"
    ON public.spotify_playlists
    FOR SELECT
    TO authenticated
    USING (user_id = (SELECT auth.uid()));

-- Explicit GRANT required: 20260724000000_revoke_default_privileges.sql
-- revoked default table privileges for anon/authenticated on every table
-- created afterwards, so the RLS policy above is inert without this -
-- Postgres checks table-level privileges before RLS is ever evaluated.
GRANT SELECT ON public.spotify_playlists TO authenticated;

COMMIT;
