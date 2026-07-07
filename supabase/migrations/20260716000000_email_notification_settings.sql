-- ==========================================================
-- EMAIL NOTIFICATION PREFERENCES
-- ==========================================================
-- Per-category opt-in/out flags for non-essential email
-- notifications. Mandatory account/transactional emails
-- (security alerts, password resets, receipts) are always
-- sent and are not gated by any column here.
-- ==========================================================

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS email_notify_matches BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS email_notify_messages BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS email_notify_digest BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS email_notify_product_updates BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS email_notify_promotions BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN public.profiles.email_notify_matches IS
  'Whether to email the user about new matches and likes.';
COMMENT ON COLUMN public.profiles.email_notify_messages IS
  'Whether to email the user about new chat messages.';
COMMENT ON COLUMN public.profiles.email_notify_digest IS
  'Whether to email the user a periodic activity digest.';
COMMENT ON COLUMN public.profiles.email_notify_product_updates IS
  'Whether to email the user about product news and feature updates.';
COMMENT ON COLUMN public.profiles.email_notify_promotions IS
  'Whether to email the user promotions and offers.';

COMMIT;
