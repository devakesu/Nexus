-- ==========================================================
-- NEXUS MEC DATABASE SCHEMA (V5 - HARDENED PRODUCTION)
-- ==========================================================

-- Enable the pgvector extension for handling high-dimensional NLP vectors
CREATE EXTENSION IF NOT EXISTS vector;

-- ==========================================================
-- VALIDATION FUNCTIONS & CUSTOM CONSTRAINTS
-- ==========================================================

-- Enforces that all values inside the value_dimensions JSONB map are strictly on a 0-9 scale.
CREATE OR REPLACE FUNCTION public.validate_value_dimensions(dims JSONB)
RETURNS BOOLEAN AS $$
DECLARE
    val NUMERIC;
    k TEXT;
    v TEXT;
BEGIN
    IF dims = '{}'::jsonb THEN
        RETURN TRUE;
    END IF;

    IF jsonb_typeof(dims) != 'object' THEN
        RETURN FALSE;
    END IF;

    FOR k IN SELECT jsonb_object_keys(dims) LOOP
        v := dims->>k;

        -- Prevent casting crashes by enforcing decimal constraints via string regex
        IF v !~ '^-?[0-9]+(\.[0-9]+)?$' THEN
            RETURN FALSE;
        END IF;

        val := v::NUMERIC;

        -- Enforce our strict 0-9 scale constraint bounds
        IF val < 0 OR val > 9 THEN
            RETURN FALSE;
        END IF;
    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql STABLE;

-- Explicit helper function used to validate string items inside text arrays natively
CREATE OR REPLACE FUNCTION public.validate_array_values(arr TEXT[], allowed TEXT[])
RETURNS BOOLEAN AS $$
BEGIN
    RETURN NOT EXISTS (
        SELECT 1 FROM unnest(arr) AS elem
        WHERE elem <> ALL(allowed)
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- ==========================================================
-- MAIN TABLE PROFILE ARCHITECTURE
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.profiles (
    -- Internal Identifiers securely tied to Supabase Auth
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    
    -- Basic Campus Metrics with Hard Bounds & Injection Mitigation
    name TEXT NOT NULL CHECK (char_length(name) BETWEEN 2 AND 100),
    branch TEXT NOT NULL CHECK (branch IN ('CSBS', 'CSE', 'ECE', 'EEE', 'ME', 'CE', 'EE', 'EB')),
    year INT NOT NULL CHECK (year BETWEEN 1 AND 5),
    age INT NOT NULL CHECK (age BETWEEN 18 AND 27),
    
    -- Onboarding Metrics & International Privacy Compliance States (GDPR Article 17)
    is_profile_complete BOOLEAN NOT NULL DEFAULT FALSE,
    is_deactivated BOOLEAN NOT NULL DEFAULT FALSE,
    deactivated_at TIMESTAMP WITH TIME ZONE,
    
    -- Cosmetic & Identity Strings
    display_gender TEXT NOT NULL,
    display_sexuality TEXT NOT NULL,
    hometown TEXT,
    partner_values TEXT,
    children_plans TEXT,
    religious_beliefs TEXT,
    lifestyle TEXT,
    
    -- Stage 1 Database Filter Buckets
    search_buckets TEXT[] NOT NULL DEFAULT '{}'
        CHECK (cardinality(search_buckets) > 0)
        CHECK (public.validate_array_values(search_buckets, ARRAY['M', 'F', 'NB', 'Q'])),

    target_buckets TEXT[] NOT NULL DEFAULT '{}'
        CHECK (cardinality(target_buckets) > 0)
        CHECK (public.validate_array_values(target_buckets, ARRAY['M', 'F', 'NB', 'Open'])),
    
    -- Hard Dealbreakers
    drinking TEXT NOT NULL CHECK (drinking IN ('No', 'Sometimes', 'Socially', 'Regularly')),
    smoking TEXT NOT NULL CHECK (smoking IN ('No', 'Sometimes', 'Socially', 'Regularly')),
    
    -- Asymmetric Roles
    role TEXT,
    looking_for TEXT[] DEFAULT '{}',
    
    -- Set Token Arrays 
    activities TEXT[] DEFAULT '{}',
    causes_supported TEXT[] DEFAULT '{}',
    top_artists TEXT[] DEFAULT '{}',
    tech_skills TEXT[] DEFAULT '{}',
    languages TEXT[] DEFAULT '{}',
    ai_vibe_tags TEXT[] DEFAULT '{}',
    pets TEXT[] DEFAULT '{}',
    
    -- Structured Key-Value JSON Objects
    interests JSONB NOT NULL DEFAULT '{}',       
    sub_interests JSONB NOT NULL DEFAULT '{}',   
    value_dimensions JSONB NOT NULL DEFAULT '{}' CONSTRAINT profiles_value_dimensions_check CHECK (public.validate_value_dimensions(value_dimensions)),
    
    -- High-Dimensional Embeddings (384D for all-MiniLM-L6-v2)
    bio_embedding VECTOR(384),
    career_embedding VECTOR(384),
    identity_embedding VECTOR(384)
);

-- ==========================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ==========================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (((SELECT auth.uid()) = id) AND (is_deactivated = FALSE));

CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    WITH CHECK ((SELECT auth.uid()) = id);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING ((((SELECT auth.uid()) = id) AND (is_deactivated = FALSE)))
    WITH CHECK ((((SELECT auth.uid()) = id) AND (is_deactivated = FALSE)));

-- ==========================================================
-- PERFORMANCE INDEXES (STAGE 1 RETRIEVAL & FILTERING)
-- ==========================================================

-- GIN Indexes for Lightning Fast Set Intersection Overlaps
CREATE INDEX IF NOT EXISTS idx_profiles_search_buckets ON public.profiles USING gin (search_buckets);
CREATE INDEX IF NOT EXISTS idx_profiles_target_buckets ON public.profiles USING gin (target_buckets);
CREATE INDEX IF NOT EXISTS idx_profiles_activities ON public.profiles USING gin (activities);

-- Explicit HNSW Partial Indexes (Excludes NULLs explicitly to prevent ANN query loss)
CREATE INDEX IF NOT EXISTS idx_profiles_identity_embed 
    ON public.profiles USING hnsw (identity_embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE identity_embedding IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_career_embed 
    ON public.profiles USING hnsw (career_embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE career_embedding IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_profiles_bio_embed 
    ON public.profiles USING hnsw (bio_embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE bio_embedding IS NOT NULL;

-- B-Tree Composite Indexes for Quick Pre-Filtering
CREATE INDEX IF NOT EXISTS idx_profiles_age ON public.profiles (age);
CREATE INDEX IF NOT EXISTS idx_profiles_branch_year ON public.profiles (branch, year);

-- OPTIMIZATION: Partial index to instantly isolate eligible matching candidate spaces
CREATE INDEX IF NOT EXISTS idx_profiles_matching_eligibility 
    ON public.profiles (id) 
    WHERE is_profile_complete = TRUE AND is_deactivated = FALSE;

-- ==========================================================
-- METADATA & SECURITY TRIGGERS
-- ==========================================================

CREATE OR REPLACE FUNCTION public.handle_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_profile_timestamp
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_update_timestamp();

-- Automatically toggles compliance timestamps based on soft-deletion switches
CREATE OR REPLACE FUNCTION public.handle_deactivation_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_deactivated = TRUE AND OLD.is_deactivated = FALSE THEN
        NEW.deactivated_at = timezone('utc'::text, now());
    END IF;
    IF NEW.is_deactivated = FALSE AND OLD.is_deactivated = TRUE THEN
        NEW.deactivated_at = NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_handle_deactivation
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_deactivation_timestamp();

CREATE OR REPLACE FUNCTION public.guard_service_fields()
RETURNS TRIGGER AS $$
BEGIN
    -- If the executing transaction context does NOT possess the service_role key, throw an error
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_guard_service_fields
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_service_fields();