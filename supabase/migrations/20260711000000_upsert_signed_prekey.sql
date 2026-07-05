-- ==========================================================
-- ATOMIC SIGNED PREKEY UPSERT
-- Marks any existing active signed prekey for the user as rotated,
-- and inserts the new signed prekey in a single transaction to prevent TOCTOU races.
-- ==========================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.upsert_signed_prekey(
    target_user_id UUID,
    new_key_id INTEGER,
    new_public_key BYTEA,
    new_signature BYTEA
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE public.chat_signed_prekeys
    SET rotated_at = timezone('utc'::text, now())
    WHERE user_id = target_user_id AND rotated_at IS NULL;

    INSERT INTO public.chat_signed_prekeys (user_id, key_id, public_key, signature)
    VALUES (target_user_id, new_key_id, new_public_key, new_signature);
END;
$$;

REVOKE ALL ON FUNCTION public.upsert_signed_prekey(UUID, INTEGER, BYTEA, BYTEA) FROM PUBLIC, anon, authenticated;

COMMIT;
