-- Add dating_for column to profiles
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS dating_for TEXT[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN public.profiles.dating_for
    IS 'Predefined terms indicating what the user is dating for (e.g. short, long, fling, hookups).';

CREATE INDEX IF NOT EXISTS idx_profiles_dating_for
    ON public.profiles USING gin (dating_for);
