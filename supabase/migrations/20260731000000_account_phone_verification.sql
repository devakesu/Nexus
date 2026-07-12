-- ==========================================================
-- ACCOUNT PHONE VERIFICATION (independent of Supabase Auth)
--
-- Re-adds mobile storage to public.users, dropped in
-- 20260729000000_drop_users_email_mobile.sql when auth.users.phone was
-- made the source of truth. That's reversed here on purpose: the Phone
-- auth provider is being disabled at the Supabase project level (it
-- offered phone-based login with no way to keep verification without
-- also keeping login - see app/core/account_phone_otp.py), so
-- auth.users.phone is no longer touched at all. public.users becomes the
-- source of truth again, populated only by the new backend-owned OTP
-- flow (app/api/user.py's phone/otp endpoints), never by an auth.users
-- trigger.
--
-- Stored as BYTEA/Fernet-encrypted, matching this column's pre-drop
-- encrypted form (20260722000000_encrypt_pii_columns.sql) and the same
-- convention used for safety_contacts.phone - see app/core/crypto.py's
-- encrypt_to_hex/decrypt_pii.
--
-- No RLS/GRANT changes needed: the table-wide UPDATE grant for
-- `authenticated` was already revoked in 20260623000000_db_hardening.sql
-- (DB-1), so these new columns inherit that service-role-only posture
-- automatically. The existing users_select_own SELECT policy lets a
-- client read the ciphertext bytes, but only the backend holds
-- pii_encryption_key to decrypt them.
--
-- Historical backfill (auth.users.phone -> public.users.mobile for
-- already-verified users) is done via scripts/backfill_verified_mobile.py,
-- not here - Fernet encryption is application-layer (Python), not
-- something a raw SQL migration can perform.
-- ==========================================================

BEGIN;

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS mobile BYTEA;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS mobile_verified_at TIMESTAMPTZ;

COMMENT ON COLUMN public.users.mobile IS
    'Encrypted mobile number, verified via app/core/account_phone_otp.py + the /api/v1/user/phone/otp endpoints. Independent of Supabase Auth (Phone provider disabled) - never written by an auth.users trigger. Backend/service_role-only, see 20260623000000_db_hardening.sql DB-1.';

COMMENT ON COLUMN public.users.mobile_verified_at IS
    'UTC timestamp the mobile number was last verified via the account phone OTP flow. NULL if never verified.';

COMMIT;
