-- ==========================================================
-- NEXUS TAB-SPECIFIC TARGET BUCKETS
-- Keep search_buckets global, split target_buckets by tab
-- ==========================================================

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS dating_target_buckets TEXT[] NOT NULL DEFAULT '{}'
        CHECK (public.validate_array_values(dating_target_buckets, ARRAY['M', 'F', 'NB', 'Open'])),
    ADD COLUMN IF NOT EXISTS friends_target_buckets TEXT[] NOT NULL DEFAULT '{}'
        CHECK (public.validate_array_values(friends_target_buckets, ARRAY['M', 'F', 'NB', 'Open'])),
    ADD COLUMN IF NOT EXISTS professional_target_buckets TEXT[] NOT NULL DEFAULT '{}'
        CHECK (public.validate_array_values(professional_target_buckets, ARRAY['M', 'F', 'NB', 'Open']));

COMMENT ON COLUMN public.profiles.dating_target_buckets
    IS 'Tab-specific outbound discovery preference buckets for Dating.';

COMMENT ON COLUMN public.profiles.friends_target_buckets
    IS 'Tab-specific outbound discovery preference buckets for Friends.';

COMMENT ON COLUMN public.profiles.professional_target_buckets
    IS 'Tab-specific outbound discovery preference buckets for Professional.';

-- Optional backfill: carry old global target_buckets forward into all tabs.
UPDATE public.profiles
SET
    dating_target_buckets = CASE
        WHEN dating_target_buckets = '{}'::text[] THEN target_buckets
        ELSE dating_target_buckets
    END,
    friends_target_buckets = CASE
        WHEN friends_target_buckets = '{}'::text[] THEN target_buckets
        ELSE friends_target_buckets
    END,
    professional_target_buckets = CASE
        WHEN professional_target_buckets = '{}'::text[] THEN target_buckets
        ELSE professional_target_buckets
    END;

CREATE INDEX IF NOT EXISTS idx_profiles_dating_target_buckets
    ON public.profiles USING gin (dating_target_buckets);

CREATE INDEX IF NOT EXISTS idx_profiles_friends_target_buckets
    ON public.profiles USING gin (friends_target_buckets);

CREATE INDEX IF NOT EXISTS idx_profiles_professional_target_buckets
    ON public.profiles USING gin (professional_target_buckets);

-- Remove the old shared target_buckets column after backfill.
DROP INDEX IF EXISTS public.idx_profiles_target_buckets;

ALTER TABLE public.profiles
    DROP COLUMN IF EXISTS target_buckets;