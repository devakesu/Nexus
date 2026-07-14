-- ==========================================================
-- FIX: Make upsert_signed_prekey truly idempotent
--
-- The original INSERT would fail with a unique-constraint violation on
-- (user_id, key_id) when the client re-uploads the same signed prekey
-- (e.g. after account reactivation where key_id hasn't changed yet).
--
-- The UPDATE step marks the OLD active key as rotated_at, then the INSERT
-- must either create a new row OR safely overwrite if key_id is identical.
-- We handle this with ON CONFLICT (user_id, key_id) DO UPDATE so the
-- operation is always idempotent regardless of whether the key already
-- exists in any state (active or rotated).
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
    -- Mark any currently-active signed prekey (different key_id) as rotated.
    UPDATE public.chat_signed_prekeys
    SET rotated_at = timezone('utc'::text, now())
    WHERE user_id = target_user_id
      AND rotated_at IS NULL
      AND key_id <> new_key_id;

    -- Insert the new key, or update it in-place if the same key_id was already
    -- uploaded (idempotent re-upload after reactivation / retry).
    INSERT INTO public.chat_signed_prekeys (user_id, key_id, public_key, signature)
    VALUES (target_user_id, new_key_id, new_public_key, new_signature)
    ON CONFLICT (user_id, key_id) DO UPDATE
        SET public_key  = EXCLUDED.public_key,
            signature   = EXCLUDED.signature,
            rotated_at  = NULL;  -- re-activate if it was previously rotated
END;
$$;

COMMIT;
