-- Migration: add_spatial_fields_to_discovery_session_items
-- Purpose: prepare discovery sessions for orbit/canvas rendering

BEGIN;

ALTER TABLE discovery_session_items
ADD COLUMN IF NOT EXISTS x double precision,
ADD COLUMN IF NOT EXISTS y double precision,
ADD COLUMN IF NOT EXISTS orbit_tier integer;

CREATE INDEX IF NOT EXISTS idx_discovery_session_items_session_position
ON discovery_session_items (session_id, position);

CREATE INDEX IF NOT EXISTS idx_discovery_session_items_session_x
ON discovery_session_items (session_id, x);

CREATE INDEX IF NOT EXISTS idx_discovery_session_items_session_y
ON discovery_session_items (session_id, y);

CREATE INDEX IF NOT EXISTS idx_discovery_session_items_session_orbit_tier
ON discovery_session_items (session_id, orbit_tier);

COMMIT;