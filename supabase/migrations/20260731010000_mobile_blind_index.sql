-- ==========================================================
-- MOBILE BLIND INDEX - phone number as a login lookup key
--
-- public.users.mobile is Fernet-encrypted (app/core/crypto.py), so it can't
-- be looked up by equality directly. This adds a deterministic HMAC-SHA256
-- blind index (same technique already used for children_plans/
-- religious_beliefs, see compute_blind_index) so the backend can resolve
-- "which account verified this phone number" for the phone-as-username
-- login flow (app/api/user.py's /api/v1/auth/login-by-phone endpoints) -
-- the OTP itself is still only ever sent to that account's verified EMAIL,
-- never SMS, so this doesn't reintroduce the SIM-swap surface the Phone
-- auth provider was disabled to close.
--
-- Uniqueness is enforced (partial, so multiple NULLs are fine) because the
-- lookup must resolve to exactly one account - without this, two accounts
-- could both claim the same phone number and the login flow would have no
-- correct answer for which one to sign in as.
-- ==========================================================

BEGIN;

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS mobile_blind_index TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS users_mobile_blind_index_unique_idx
    ON public.users (mobile_blind_index)
    WHERE mobile_blind_index IS NOT NULL;

COMMENT ON COLUMN public.users.mobile_blind_index IS
    'Deterministic HMAC-SHA256 (compute_blind_index) of the verified mobile number, for exact-match lookup only - the encrypted mobile column itself cannot be queried by equality. Backend/service_role-only, written only by set_verified_mobile().';

COMMIT;
