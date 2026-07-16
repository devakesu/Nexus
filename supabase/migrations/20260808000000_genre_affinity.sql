-- Migration: add_genre_affinity_to_profiles
--
-- Adds a genre_affinity column that stores a frequency-weighted map of
-- music genres derived from Spotify's /me/top/artists response.
-- Schema mirrors artist_affinity: encrypted JSON { genre_name: weight }.
-- Matching-engine input only - same privacy rules apply: must never be
-- selected into fetch_peer_profile_by_id or fetch_discovery_node_detail.

BEGIN;

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS genre_affinity BYTEA;

COMMENT ON COLUMN public.profiles.genre_affinity IS
    'Encrypted JSON object {genre_name: weight in (0,1]}, <=30 entries. '
    'Weighted genre signal blended from /me/top/artists genres, '
    'weighted by each artist''s rank/frequency in artist_affinity. '
    'Matching-engine input only - must never be selected into '
    'fetch_peer_profile_by_id, fetch_discovery_node_detail, '
    'or any other peer-facing query.';

COMMIT;
