-- ==========================================================
-- ACCOUNT HISTORY ARCHIVE - Tier-2 long-tail purge target
--
-- account_deletion_long_tail_purge_days (default 3 years, see
-- app/core/config.py) after a Tier-1 purge anonymized an account
-- (public.users.purged_at), hard_purge_long_tail_accounts()
-- (app/db/account_deletion.py) deletes the auth.users row for good via the
-- same supabase_client.auth.admin.delete_user precedent already used at
-- app/api/user.py:143 - this finally cascades away the anonymized
-- profiles/users shell and everything still hanging off it (old matches,
-- chat_conversations, chat_messages, user_reports, user_moderation_actions,
-- feedback_reports, etc).
--
-- Before that cascade fires, non-identifying essentials of the account's
-- trust & safety records are copied here so aggregate T&S intelligence
-- (how many reports/bans, what kinds, what outcomes) survives the final
-- purge without retaining any identity. Deliberately NOT foreign-keyed to
-- users/auth.users/profiles - must outlive the row it was archived from -
-- and deliberately holds no user id, hash, or other identifier at all.
-- ==========================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.account_history_archive (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_table      TEXT NOT NULL
        CHECK (source_table IN ('user_reports', 'user_moderation_actions', 'feedback_reports')),
    reason_code       TEXT,
    outcome           TEXT,
    event_occurred_at TIMESTAMPTZ NOT NULL,
    archived_at       TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.account_history_archive IS
    'Non-identifying archive of user_reports/user_moderation_actions/feedback_reports essentials, written by hard_purge_long_tail_accounts() just before an account''s final hard-delete. Holds no user identifier of any kind (not even a hash) - it is an aggregate trust & safety trail (reason codes, outcomes, timing), not a per-person record.';

-- service_role only - same deny-all pattern as deleted_account_blocklist.
ALTER TABLE public.account_history_archive ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.account_history_archive FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Deny all client-side archive access" ON public.account_history_archive;

CREATE POLICY "Deny all client-side archive access"
    ON public.account_history_archive
    FOR ALL
    USING (false)
    WITH CHECK (false);

COMMIT;
