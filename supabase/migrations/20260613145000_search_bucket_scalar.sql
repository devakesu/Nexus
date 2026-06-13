-- ==========================================================
-- MIGRATE search_buckets ARRAY TO SINGLE search_bucket TEXT
-- ==========================================================

-- 1. Add new column search_bucket
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS search_bucket TEXT;

-- 2. Populate search_bucket with the first element of search_buckets, or 'NB' as fallback.
-- Map any 'Q' or invalid value to 'NB' to satisfy the constraint.
UPDATE public.profiles
SET search_bucket = CASE
    WHEN search_buckets IS NULL OR array_length(search_buckets, 1) IS NULL THEN 'NB'
    WHEN search_buckets[1] IN ('M', 'F', 'NB') THEN search_buckets[1]
    ELSE 'NB'
END;

-- 3. Make column NOT NULL, set default, and add constraint (dropping 'Q')
ALTER TABLE public.profiles
    ALTER COLUMN search_bucket SET NOT NULL,
    ALTER COLUMN search_bucket SET DEFAULT 'NB',
    ADD CONSTRAINT check_search_bucket CHECK (search_bucket IN ('M', 'F', 'NB'));

-- 4. Drop the old search_buckets column and its GIN index
DROP INDEX IF EXISTS public.idx_profiles_search_buckets;

ALTER TABLE public.profiles
    DROP COLUMN IF EXISTS search_buckets;

-- 5. Create new BTREE index on search_bucket
CREATE INDEX IF NOT EXISTS idx_profiles_search_bucket
    ON public.profiles (search_bucket);

-- 6. Add comment for the new column
COMMENT ON COLUMN public.profiles.search_bucket
    IS 'Allowed inbound discovery category (single value) used to route this profile.';
