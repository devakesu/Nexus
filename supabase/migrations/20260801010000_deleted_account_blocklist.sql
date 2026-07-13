-- ==========================================================
-- DELETED ACCOUNT BLOCKLIST - ban-evasion cooldown
--
-- When a flagged account (suspended/banned/restricted, or with an
-- unresolved report against it) is purged, its phone blind index is copied
-- here for a cooldown window before it can be claimed by a new signup - see
-- purge_due_accounts()/is_phone_blocklisted() in app/db/account_deletion.py
-- and the check added to set_verified_mobile() in app/db/users.py.
--
-- Deliberately NOT foreign-keyed to users/auth.users: this table exists
-- specifically to outlive the account row it originated from (the whole
-- point is that the account is gone by the time this matters). An
-- unflagged, good-standing account never gets a row here at all - see
-- deletion_flagged_for_blocklist in 20260801000000_account_deletion_lifecycle.sql.
-- ==========================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.deleted_account_blocklist (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_blind_index   TEXT NOT NULL,
    cooldown_expires_at TIMESTAMPTZ NOT NULL,
    reason_code         TEXT NOT NULL
        CHECK (reason_code IN ('suspended', 'banned', 'restricted', 'unresolved_report')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.deleted_account_blocklist IS
    'Cooldown blocklist for phone numbers belonging to accounts that were flagged (suspended/banned/restricted/under active report review) at deletion time, to prevent immediate ban-evasion re-registration. Independent of users/auth.users by design - must survive account purge. Rows are purged by a daily expiry job (expire_blocklist_entries()) once cooldown_expires_at has passed.';

-- Lookup hot path: the phone-claim path (set_verified_mobile) must check
-- this before allowing a number to be claimed. Query callers should always
-- filter cooldown_expires_at > now() explicitly rather than relying solely
-- on this partial index's predicate.
CREATE INDEX IF NOT EXISTS idx_deleted_account_blocklist_phone
    ON public.deleted_account_blocklist (phone_blind_index);

-- service_role only - never client-readable, same deny-all pattern as
-- profile_pseudonym_map / spotify_connections.
ALTER TABLE public.deleted_account_blocklist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deleted_account_blocklist FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Deny all client-side blocklist access" ON public.deleted_account_blocklist;

CREATE POLICY "Deny all client-side blocklist access"
    ON public.deleted_account_blocklist
    FOR ALL
    USING (false)
    WITH CHECK (false);

COMMIT;
