-- ==========================================================
-- NEXUS FULL DATABASE SCHEMA (INITIAL)
-- ==========================================================

-- This schema separates user-facing profile data from privacy-preserving
-- pseudonym/vector tables. Client access is restricted through RLS, while
-- privileged backend flows are expected to use the Supabase service role.


-- ==========================================================
-- 0. EXTENSIONS
-- ==========================================================

-- pgvector powers semantic embedding storage/search.
CREATE EXTENSION IF NOT EXISTS vector;

-- pgcrypto is used for cryptographic helpers such as deterministic blind indexes.
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ==========================================================
-- 1. VALIDATION FUNCTIONS
-- ==========================================================

-- Ensures every element in arr belongs to the supplied allowed-value list.
CREATE OR REPLACE FUNCTION public.validate_array_values(arr TEXT[], allowed TEXT[])
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
STRICT
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN NOT EXISTS (
        SELECT 1
        FROM unnest(arr) AS elem
        WHERE elem <> ALL(allowed)
    );
END;
$$;


-- ==========================================================
-- 2. SHARED TRIGGER FUNCTIONS
-- ==========================================================

-- Keeps updated_at in UTC in sync on every UPDATE.
CREATE OR REPLACE FUNCTION public.handle_update_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$;

-- Maintains deactivated_at as a derived lifecycle timestamp.
-- Sets it when a profile is deactivated and clears it on reactivation.
CREATE OR REPLACE FUNCTION public.handle_deactivation_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.is_deactivated = TRUE AND OLD.is_deactivated = FALSE THEN
        NEW.deactivated_at = timezone('utc'::text, now());
    END IF;

    IF NEW.is_deactivated = FALSE AND OLD.is_deactivated = TRUE THEN
        NEW.deactivated_at = NULL;
    END IF;

    RETURN NEW;
END;
$$;

-- Prevents client-side mutation of server-owned lifecycle/completeness fields.
-- SECURITY DEFINER is intentional here so the function runs with owner privileges
-- while still inspecting the caller's Supabase role via auth.role().
CREATE OR REPLACE FUNCTION public.guard_service_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        IF NEW.is_deactivated IS DISTINCT FROM OLD.is_deactivated OR
           NEW.deactivated_at IS DISTINCT FROM OLD.deactivated_at THEN
            RAISE EXCEPTION 'permission denied: profile deactivation states are server-side only';
        END IF;

        IF NEW.is_profile_complete IS DISTINCT FROM OLD.is_profile_complete THEN
            RAISE EXCEPTION 'permission denied: profile completion flag is server-side only';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;


-- ==========================================================
-- 3. MAIN PROFILES TABLE
-- ==========================================================

-- Stores the canonical app-level profile for each authenticated user.
-- One row per auth.users row.
CREATE TABLE IF NOT EXISTS public.profiles (
    -- Internal identifiers
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,

    -- Required at registration
    name TEXT NOT NULL CHECK (char_length(name) BETWEEN 2 AND 100),
    branch TEXT NOT NULL,
    year INT NOT NULL CHECK (year BETWEEN 1 AND 5),
    age INT NOT NULL CHECK (age BETWEEN 18 AND 27),

    -- Lifecycle flags
    -- These are server-governed fields and must not be client-editable.
    is_profile_complete BOOLEAN NOT NULL DEFAULT FALSE,
    is_deactivated BOOLEAN NOT NULL DEFAULT FALSE,
    deactivated_at TIMESTAMP WITH TIME ZONE,

    -- Optional encrypted scalar profile fields
    display_gender BYTEA,
    display_sexuality BYTEA,
    hometown BYTEA,
    partner_values BYTEA,
    children_plans BYTEA,
    religious_beliefs BYTEA,
    lifestyle BYTEA,
    drinking BYTEA,
    smoking BYTEA,
    role BYTEA,

    -- Discovery routing
    -- search_buckets = how this profile is categorized for inbound discovery.
    search_buckets TEXT[] NOT NULL DEFAULT '{}'
        CHECK (public.validate_array_values(search_buckets, ARRAY['M', 'F', 'NB', 'Q'])),

    -- target_buckets = which categories this user is open to seeing/matching with.
    target_buckets TEXT[] NOT NULL DEFAULT '{}'
        CHECK (public.validate_array_values(target_buckets, ARRAY['M', 'F', 'NB', 'Open'])),

    -- Match context (encrypted at rest; plaintext structure is validated in backend before encryption)
    looking_for BYTEA,
    activities BYTEA,
    causes_supported BYTEA,
    top_artists BYTEA,
    tech_skills BYTEA,
    languages BYTEA,
    ai_vibe_tags BYTEA,
    pets BYTEA,

    -- Structured scoring inputs (encrypted at rest; JSON validation must happen before encryption)
    interests BYTEA,
    sub_interests BYTEA,
    value_dimensions BYTEA,

    -- Blind indexes for encrypted exact-match filters
    branch_blind_index TEXT,
    smoking_blind_index TEXT,
    drinking_blind_index TEXT,
    role_blind_index TEXT
);


-- ==========================================================
-- 4. PROFILE RLS
-- ==========================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Authenticated users may read only their own active profile row.
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile"
    ON public.profiles
    FOR SELECT
    USING ((SELECT auth.uid()) = id AND is_deactivated = FALSE);

-- Authenticated users may create only the row whose id matches their auth user id.
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile"
    ON public.profiles
    FOR INSERT
    WITH CHECK ((SELECT auth.uid()) = id);

-- Authenticated users may update only their own active profile row.
-- Field-level protection for server-owned columns is enforced separately by trigger.
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
    ON public.profiles
    FOR UPDATE
    USING ((SELECT auth.uid()) = id AND is_deactivated = FALSE)
    WITH CHECK ((SELECT auth.uid()) = id AND is_deactivated = FALSE);


-- ==========================================================
-- 5. PROFILE INDEXES
-- ==========================================================

-- GIN indexes support fast membership/overlap queries on array-based discovery fields.
CREATE INDEX IF NOT EXISTS idx_profiles_search_buckets
    ON public.profiles USING gin (search_buckets);

CREATE INDEX IF NOT EXISTS idx_profiles_target_buckets
    ON public.profiles USING gin (target_buckets);

CREATE INDEX IF NOT EXISTS idx_profiles_age
    ON public.profiles (age);

CREATE INDEX IF NOT EXISTS idx_profiles_year
    ON public.profiles (year);

-- Blind-index btree indexes support deterministic exact-match lookups on protected fields.
CREATE INDEX IF NOT EXISTS idx_profiles_branch_blind
    ON public.profiles (branch_blind_index);

CREATE INDEX IF NOT EXISTS idx_profiles_smoking_blind
    ON public.profiles (smoking_blind_index);

CREATE INDEX IF NOT EXISTS idx_profiles_drinking_blind
    ON public.profiles (drinking_blind_index);

CREATE INDEX IF NOT EXISTS idx_profiles_role_blind
    ON public.profiles (role_blind_index);

-- Partial index for the hot path used by matching/eligibility queries.
CREATE INDEX IF NOT EXISTS idx_profiles_matching_eligibility
    ON public.profiles (id)
    WHERE is_profile_complete = TRUE AND is_deactivated = FALSE;


-- ==========================================================
-- 6. PROFILE TRIGGERS
-- ==========================================================

DROP TRIGGER IF EXISTS trigger_update_profile_timestamp ON public.profiles;
CREATE TRIGGER trigger_update_profile_timestamp
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_update_timestamp();

DROP TRIGGER IF EXISTS trigger_handle_deactivation ON public.profiles;
CREATE TRIGGER trigger_handle_deactivation
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_deactivation_timestamp();

DROP TRIGGER IF EXISTS trigger_guard_service_fields ON public.profiles;
CREATE TRIGGER trigger_guard_service_fields
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_service_fields();


-- ==========================================================
-- 7. PROFILE COMMENTS
-- ==========================================================

COMMENT ON TABLE public.profiles
    IS 'Canonical application profile table keyed 1:1 to auth.users. Stores user-facing profile data plus server-governed lifecycle flags.';

COMMENT ON COLUMN public.profiles.is_profile_complete
    IS 'Server-maintained readiness flag used to gate matching eligibility and other downstream workflows.';

COMMENT ON COLUMN public.profiles.is_deactivated
    IS 'Server-maintained soft-deactivation flag. Deactivated profiles are hidden from normal client reads/updates via RLS.';

COMMENT ON COLUMN public.profiles.deactivated_at
    IS 'UTC timestamp derived from changes to is_deactivated; set on deactivation and cleared on reactivation.';

COMMENT ON COLUMN public.profiles.search_buckets
    IS 'Allowed inbound discovery categories used to route this profile into search/matching cohorts.';

COMMENT ON COLUMN public.profiles.target_buckets
    IS 'Allowed outbound preference categories describing which cohorts this user wants to discover or match with.';

COMMENT ON COLUMN public.profiles.display_gender
    IS 'Encrypted display-gender field stored as ciphertext (BYTEA).';

COMMENT ON COLUMN public.profiles.activities
    IS 'Encrypted match-context payload stored as ciphertext (BYTEA); plaintext array structure is handled in trusted backend code before encryption.';

COMMENT ON COLUMN public.profiles.value_dimensions
    IS 'Encrypted structured preference/value scores stored as ciphertext (BYTEA); plaintext JSON validation must happen before encryption in trusted backend code.';
    
COMMENT ON COLUMN public.profiles.branch_blind_index
    IS 'HMAC-SHA256 deterministic blind hash for encrypted branch queries.';

COMMENT ON COLUMN public.profiles.smoking_blind_index
    IS 'HMAC-SHA256 deterministic blind hash for encrypted smoking lookups.';

COMMENT ON COLUMN public.profiles.drinking_blind_index
    IS 'HMAC-SHA256 deterministic blind hash for encrypted drinking lookups.';

COMMENT ON COLUMN public.profiles.role_blind_index
    IS 'HMAC-SHA256 deterministic blind hash for encrypted professional role filters.';

COMMENT ON FUNCTION public.validate_array_values(TEXT[], TEXT[])
    IS 'Returns true when every element of the input array belongs to the allowed-value array.';

COMMENT ON FUNCTION public.handle_update_timestamp()
    IS 'Trigger function that refreshes updated_at to the current UTC timestamp before row update.';

COMMENT ON FUNCTION public.handle_deactivation_timestamp()
    IS 'Trigger function that derives deactivated_at from transitions of is_deactivated.';

COMMENT ON FUNCTION public.guard_service_fields()
    IS 'SECURITY DEFINER trigger function that blocks non-service callers from changing server-owned profile lifecycle/completeness fields.';

COMMENT ON TRIGGER trigger_update_profile_timestamp ON public.profiles
    IS 'Applies handle_update_timestamp before every profile update.';

COMMENT ON TRIGGER trigger_handle_deactivation ON public.profiles
    IS 'Applies handle_deactivation_timestamp before every profile update.';

COMMENT ON TRIGGER trigger_guard_service_fields ON public.profiles
    IS 'Prevents client-side updates to server-governed profile fields.';

COMMENT ON POLICY "Users can view own profile" ON public.profiles
    IS 'Allows a user to read only their own non-deactivated profile row.';

COMMENT ON POLICY "Users can insert own profile" ON public.profiles
    IS 'Allows a user to insert only the profile row keyed by their own auth.uid().';

COMMENT ON POLICY "Users can update own profile" ON public.profiles
    IS 'Allows a user to update only their own non-deactivated profile row; protected fields are still enforced by trigger logic.';


-- ==========================================================
-- 8. PSEUDONYM MAP
-- ==========================================================

-- Maps a real profile id to a stable pseudonym id so downstream vector data can
-- avoid direct exposure of the primary user identifier.
CREATE TABLE IF NOT EXISTS public.profile_pseudonym_map (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    pseudonym_id UUID NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    PRIMARY KEY (user_id)
);

ALTER TABLE public.profile_pseudonym_map ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profile_pseudonym_map FORCE ROW LEVEL SECURITY;

-- No client-side access is permitted to this identity bridge table.
DROP POLICY IF EXISTS "Deny all client-side mapping access" ON public.profile_pseudonym_map;
CREATE POLICY "Deny all client-side mapping access"
    ON public.profile_pseudonym_map
    FOR ALL
    USING (false)
    WITH CHECK (false);

COMMENT ON TABLE public.profile_pseudonym_map
    IS 'Private identity bridge mapping canonical profile ids to stable pseudonym ids for anonymized downstream processing.';

COMMENT ON POLICY "Deny all client-side mapping access" ON public.profile_pseudonym_map
    IS 'Explicit deny-all RLS policy for client roles; intended access is privileged backend only.';


-- ==========================================================
-- 9. VECTOR PROFILES
-- ==========================================================

-- Stores anonymized embeddings keyed by pseudonym_id instead of user_id.
CREATE TABLE IF NOT EXISTS public.vector_profiles (
    pseudonym_id UUID PRIMARY KEY REFERENCES public.profile_pseudonym_map(pseudonym_id) ON DELETE CASCADE,
    bio_embedding VECTOR(384),
    career_embedding VECTOR(384),
    identity_embedding VECTOR(384),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

COMMENT ON TABLE public.vector_profiles
    IS 'Anonymized user embeddings keyed by pseudonym_id. Protected by forced deny-all RLS and intended for privileged backend access only.';

ALTER TABLE public.vector_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vector_profiles FORCE ROW LEVEL SECURITY;

-- No client-side access is permitted to embedding storage.
DROP POLICY IF EXISTS "Deny all client-side vector access" ON public.vector_profiles;
CREATE POLICY "Deny all client-side vector access"
    ON public.vector_profiles
    FOR ALL
    USING (false)
    WITH CHECK (false);

COMMENT ON POLICY "Deny all client-side vector access" ON public.vector_profiles
    IS 'Explicit deny-all RLS policy for client roles; vector access is restricted to privileged backend paths.';


-- ==========================================================
-- 10. VECTOR INDEXES
-- ==========================================================

-- HNSW indexes support approximate nearest-neighbor search over embeddings.
CREATE INDEX IF NOT EXISTS idx_vector_profiles_identity
    ON public.vector_profiles USING hnsw (identity_embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE identity_embedding IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_vector_profiles_career
    ON public.vector_profiles USING hnsw (career_embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE career_embedding IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_vector_profiles_bio
    ON public.vector_profiles USING hnsw (bio_embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE bio_embedding IS NOT NULL;


-- ==========================================================
-- 11. VECTOR TRIGGER
-- ==========================================================

DROP TRIGGER IF EXISTS trigger_update_vector_timestamp ON public.vector_profiles;
CREATE TRIGGER trigger_update_vector_timestamp
    BEFORE UPDATE ON public.vector_profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_update_timestamp();

COMMENT ON TRIGGER trigger_update_vector_timestamp ON public.vector_profiles
    IS 'Applies handle_update_timestamp before every vector profile update.';


-- ==========================================================
-- 12. FUNCTION PRIVILEGE HYGIENE
-- ==========================================================

-- These REVOKE statements reduce direct EXECUTE exposure for application roles.
-- They are privilege hygiene, not the primary mechanism protecting trigger behavior.
REVOKE ALL ON FUNCTION public.validate_array_values(TEXT[], TEXT[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_update_timestamp() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.handle_deactivation_timestamp() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_service_fields() FROM PUBLIC, anon, authenticated;

-- Default privileges apply to future functions created by the same creating role.
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM authenticated;