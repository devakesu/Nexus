-- Add HMAC blind index columns for children_plans and religious_beliefs.
-- These are scalar enum fields; the blind index allows equality/IN filtering
-- without revealing the underlying encrypted value.
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS children_plans_blind_index    BYTEA,
    ADD COLUMN IF NOT EXISTS religious_beliefs_blind_index BYTEA;

CREATE INDEX IF NOT EXISTS idx_profiles_children_plans_bi
    ON public.profiles (children_plans_blind_index);

CREATE INDEX IF NOT EXISTS idx_profiles_religious_beliefs_bi
    ON public.profiles (religious_beliefs_blind_index);

COMMENT ON COLUMN public.profiles.children_plans_blind_index
    IS 'HMAC-SHA256 of decrypted children_plans value for equality filtering without decryption.';

COMMENT ON COLUMN public.profiles.religious_beliefs_blind_index
    IS 'HMAC-SHA256 of decrypted religious_beliefs value for equality filtering without decryption.';
