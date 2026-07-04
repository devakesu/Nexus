-- ==========================================================
-- SIGNAL PROTOCOL KEY MATERIAL
-- Server acts as a pure public-key bulletin board for X3DH: it stores
-- only public keys, never private keys or Double Ratchet session state
-- (those live exclusively on-device). Single-device-per-user for v1 -
-- logging into chat on a new device resets the identity there.
-- ==========================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.chat_identity_keys (
    user_id             UUID        PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
    identity_public_key BYTEA       NOT NULL,
    registration_id     INTEGER     NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.chat_identity_keys IS
    'One Signal Protocol identity public key per user (single device for v1). Private key never leaves the device.';

CREATE TABLE IF NOT EXISTS public.chat_signed_prekeys (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    key_id      INTEGER     NOT NULL,
    public_key  BYTEA       NOT NULL,
    signature   BYTEA       NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    rotated_at  TIMESTAMPTZ,

    CONSTRAINT chat_signed_prekeys_unique_key_id UNIQUE (user_id, key_id)
);

COMMENT ON TABLE public.chat_signed_prekeys IS
    'Rotating signed prekeys used in X3DH. Current key for a user = most recent row with rotated_at IS NULL.';

CREATE TABLE IF NOT EXISTS public.chat_one_time_prekeys (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    key_id      INTEGER     NOT NULL,
    public_key  BYTEA       NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT chat_one_time_prekeys_unique_key_id UNIQUE (user_id, key_id)
);

COMMENT ON TABLE public.chat_one_time_prekeys IS
    'One-time prekey pool for X3DH. Each row may be claimed (used_at set) exactly once via claim_one_time_prekey().';


-- ==========================================================
-- INDEXES
-- ==========================================================

CREATE INDEX IF NOT EXISTS idx_chat_signed_prekeys_user_current
    ON public.chat_signed_prekeys (user_id, created_at DESC)
    WHERE rotated_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_chat_one_time_prekeys_user_unused
    ON public.chat_one_time_prekeys (user_id, key_id)
    WHERE used_at IS NULL;


-- ==========================================================
-- ATOMIC ONE-TIME PREKEY CLAIM
-- Prevents two concurrent bundle fetches (e.g. two different matches
-- opening a chat with the same user at once) from handing out the same
-- one-time prekey. Not granted to authenticated/anon - only reachable
-- via the backend's service-role connection.
-- ==========================================================

CREATE OR REPLACE FUNCTION public.claim_one_time_prekey(target_user_id UUID)
RETURNS TABLE (key_id INTEGER, public_key BYTEA)
LANGUAGE plpgsql
AS $$
DECLARE
    claimed_id UUID;
BEGIN
    SELECT c.id INTO claimed_id
    FROM public.chat_one_time_prekeys c
    WHERE c.user_id = target_user_id AND c.used_at IS NULL
    ORDER BY c.key_id
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    IF claimed_id IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    UPDATE public.chat_one_time_prekeys c
    SET used_at = timezone('utc'::text, now())
    WHERE c.id = claimed_id
    RETURNING c.key_id, c.public_key;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_one_time_prekey(UUID) FROM PUBLIC, anon, authenticated;


-- ==========================================================
-- TRIGGERS
-- ==========================================================

DROP TRIGGER IF EXISTS set_chat_identity_keys_updated_at ON public.chat_identity_keys;
CREATE TRIGGER set_chat_identity_keys_updated_at
    BEFORE UPDATE ON public.chat_identity_keys
    FOR EACH ROW
    EXECUTE PROCEDURE public.set_updated_at();


-- ==========================================================
-- RLS
-- All three tables are readable/writable only by their owning user -
-- there is no direct cross-user SELECT. A user fetching a match's key
-- bundle always goes through the backend (service role + active-match
-- check), consistent with how other cross-user reads in this schema
-- (e.g. matches) are gated at the application layer.
-- ==========================================================

ALTER TABLE public.chat_identity_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_signed_prekeys ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_one_time_prekeys ENABLE ROW LEVEL SECURITY;

CREATE POLICY "chat_identity_keys_owner_select"
    ON public.chat_identity_keys
    FOR SELECT
    TO authenticated
    USING (user_id = (SELECT auth.uid()));

CREATE POLICY "chat_signed_prekeys_owner_select"
    ON public.chat_signed_prekeys
    FOR SELECT
    TO authenticated
    USING (user_id = (SELECT auth.uid()));

CREATE POLICY "chat_one_time_prekeys_owner_select"
    ON public.chat_one_time_prekeys
    FOR SELECT
    TO authenticated
    USING (user_id = (SELECT auth.uid()));

COMMIT;
