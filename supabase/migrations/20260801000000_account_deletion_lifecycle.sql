-- ==========================================================
-- ACCOUNT DELETION LIFECYCLE (Tier 1: request -> grace window -> purge)
--
-- Adds the columns that drive self-serve account deletion
-- (app/db/account_deletion.py, app/api/account_deletion.py). Deletion is a
-- two-step process, not a single DELETE:
--   1. request_deletion() sets deletion_requested_at/scheduled_purge_at and
--      closes-but-does-not-unmatch the user's conversations. The account is
--      immediately signed out and hidden from discovery via
--      profiles.is_deactivated, but every row (profile, matches, chats) is
--      left untouched so cancel_deletion() can fully restore it.
--   2. A daily scheduler job (purge_due_accounts(), see
--      app/services/reminder_scheduler.py) anonymizes the profiles/users
--      rows in place once scheduled_purge_at has passed and the user never
--      cancelled - see purged_at below. Rows are never row-deleted at this
--      stage, since profiles/users are the ON DELETE CASCADE parent of the
--      match/chat/report graph (see 20260604180435_initial.sql,
--      20260605122617_auth_moderation.sql) - deleting them early would
--      destroy the counterparty's shared history and the trust & safety
--      audit trail along with it. A much later Tier-2 hard-delete (a
--      separate, far slower purge) is what finally removes the row for
--      good - see 20260801030000_account_history_archive.sql.
--
-- deletion_flagged_reason_code is frozen at request time (not recomputed at
-- purge time) so a user's moderation status can't change during the grace
-- window and quietly flip whether - or why - their phone number gets
-- cooldown-blocked from re-registration; it doubles as the reason_code
-- written to deleted_account_blocklist, so purge_due_accounts() never has
-- to re-derive it from (possibly since-changed) moderation state.
-- ==========================================================

BEGIN;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS deletion_requested_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS scheduled_purge_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deletion_flagged_reason_code TEXT,
    ADD COLUMN IF NOT EXISTS purged_at TIMESTAMPTZ;

ALTER TABLE public.users
    DROP CONSTRAINT IF EXISTS users_deletion_flagged_reason_code_check;

ALTER TABLE public.users
    ADD CONSTRAINT users_deletion_flagged_reason_code_check CHECK (
        deletion_flagged_reason_code IS NULL
        OR deletion_flagged_reason_code IN ('suspended', 'banned', 'restricted', 'unresolved_report')
    );

ALTER TABLE public.users
    DROP CONSTRAINT IF EXISTS users_deletion_pair_check;

ALTER TABLE public.users
    ADD CONSTRAINT users_deletion_pair_check CHECK (
        (deletion_requested_at IS NULL AND scheduled_purge_at IS NULL)
        OR (deletion_requested_at IS NOT NULL AND scheduled_purge_at IS NOT NULL)
    );

-- Purge job's poll query: WHERE scheduled_purge_at <= now() AND purged_at IS NULL
CREATE INDEX IF NOT EXISTS idx_users_pending_purge
    ON public.users (scheduled_purge_at)
    WHERE deletion_requested_at IS NOT NULL AND purged_at IS NULL;

COMMENT ON COLUMN public.users.deletion_requested_at IS
    'Set when the user completes the delete-account confirmation flow (OTP + typed DELETE). NULL means no pending deletion. Backend/service_role-only.';
COMMENT ON COLUMN public.users.scheduled_purge_at IS
    'deletion_requested_at + account_deletion_grace_period_days. The daily purge job anonymizes any row past this timestamp with purged_at still NULL.';
COMMENT ON COLUMN public.users.deletion_flagged_reason_code IS
    'Frozen at request time: NULL for a good-standing account, otherwise the reason moderation_status/is_suspended/an unresolved user_reports row was flagged (banned/restricted/suspended/unresolved_report). Read (not recomputed) by the purge job, and written verbatim as deleted_account_blocklist.reason_code when non-NULL.';
COMMENT ON COLUMN public.users.purged_at IS
    'Set by the Tier-1 purge job once anonymization has run. Prevents double-purge, distinguishes "purged" from "never requested", and starts the Tier-2 long-tail retention clock.';

COMMIT;
