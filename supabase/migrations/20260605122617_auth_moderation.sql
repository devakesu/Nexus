/*
  migration: add users, user_devices, and user_moderation_actions

  purpose:
    - create app-managed account data linked to auth.users
    - support per-device fcm token storage
    - track moderation state and moderation history

  notes:
    - public.users is the application-facing companion table for auth.users
    - user_devices stores device/app-install level push state, not user-level state
    - user_moderation_actions stores private moderation history and audit data
    - row access is enforced with RLS
    - allowed writable columns are further restricted with column-level grants
*/

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

/*
  section: helper functions

  set_updated_at:
    keeps updated_at fresh on mutable tables

  handle_new_auth_user:
    inserts or syncs a public.users row after auth signup

  sync_user_email_from_auth:
    keeps public.users.email aligned to auth.users.email changes
*/

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  raw_email text;
BEGIN
  raw_email := LOWER(COALESCE(NEW.email, ''));

  INSERT INTO public.users (
    id,
    email,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    raw_email,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE
  SET
    email = EXCLUDED.email,
    updated_at = NOW();

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_user_email_from_auth()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  raw_email text;
BEGIN
  raw_email := LOWER(COALESCE(NEW.email, ''));

  UPDATE public.users
  SET
    email = raw_email,
    updated_at = NOW()
  WHERE id = NEW.id;

  RETURN NEW;
END;
$$;

/*
  section: core tables
*/

CREATE TABLE IF NOT EXISTS public.users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL UNIQUE,
  mobile text,
  accepted_terms_version text,
  terms_accepted_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  is_suspended boolean NOT NULL DEFAULT false,
  suspended_until timestamptz,
  moderation_status text NOT NULL DEFAULT 'clear',
  moderated_at timestamptz,
  moderation_reason_code text,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  CONSTRAINT users_moderation_status_check
    CHECK (moderation_status IN ('clear', 'review', 'restricted', 'banned')),
  CONSTRAINT users_terms_pair_check
    CHECK (
      (accepted_terms_version IS NULL AND terms_accepted_at IS NULL)
      OR
      (accepted_terms_version IS NOT NULL AND terms_accepted_at IS NOT NULL)
    ),
  CONSTRAINT users_suspension_consistency_check
    CHECK (
      (is_suspended = false AND suspended_until IS NULL)
      OR
      is_suspended = true
    )
);

CREATE TABLE IF NOT EXISTS public.user_devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  platform text,
  device_id text,
  fcm_token text NOT NULL UNIQUE,
  is_active boolean NOT NULL DEFAULT true,
  last_seen_at timestamptz NOT NULL DEFAULT NOW(),
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.user_moderation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  action_type text NOT NULL,
  reason_code text,
  private_notes text,
  evidence_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  expires_at timestamptz,
  revoked_at timestamptz,
  CONSTRAINT user_moderation_actions_action_type_check
    CHECK (action_type IN ('warn', 'restrict', 'suspend', 'ban', 'unsuspend', 'clear')),
  CONSTRAINT user_moderation_actions_expiry_check
    CHECK (expires_at IS NULL OR expires_at >= created_at),
  CONSTRAINT user_moderation_actions_revoked_check
    CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);

/*
  section: schema comments

  postgres supports COMMENT ON for tables and columns, which is the standard
  way to document schema objects in-database.
*/

COMMENT ON TABLE public.users IS 'App-managed account data keyed to auth.users.';
COMMENT ON COLUMN public.users.id IS 'Primary key matching auth.users.id.';
COMMENT ON COLUMN public.users.email IS 'Normalized login email copied from auth.users.';
COMMENT ON COLUMN public.users.mobile IS 'Optional user mobile number for app-level contact use.';
COMMENT ON COLUMN public.users.accepted_terms_version IS 'Single current terms version accepted by the user.';
COMMENT ON COLUMN public.users.terms_accepted_at IS 'Timestamp when the current terms version was accepted.';
COMMENT ON COLUMN public.users.is_active IS 'General account availability flag for app access.';
COMMENT ON COLUMN public.users.is_suspended IS 'Whether the account is currently suspended.';
COMMENT ON COLUMN public.users.suspended_until IS 'Optional suspension expiry time; null can represent indefinite suspension.';
COMMENT ON COLUMN public.users.moderation_status IS 'Current moderation state: clear, review, restricted, or banned.';
COMMENT ON COLUMN public.users.moderated_at IS 'Timestamp of the latest moderation status change.';
COMMENT ON COLUMN public.users.moderation_reason_code IS 'Compact internal reason code for the latest moderation state.';
COMMENT ON COLUMN public.users.created_at IS 'Row creation timestamp.';
COMMENT ON COLUMN public.users.updated_at IS 'Row update timestamp.';

COMMENT ON TABLE public.user_devices IS 'Per-device push notification registrations for users.';
COMMENT ON COLUMN public.user_devices.id IS 'Primary key for the device registration row.';
COMMENT ON COLUMN public.user_devices.user_id IS 'Owning user for this device registration.';
COMMENT ON COLUMN public.user_devices.platform IS 'Client platform such as ios, android, or web.';
COMMENT ON COLUMN public.user_devices.device_id IS 'Client-supplied device or installation identifier.';
COMMENT ON COLUMN public.user_devices.fcm_token IS 'Firebase Cloud Messaging token for this app installation.';
COMMENT ON COLUMN public.user_devices.is_active IS 'Whether this device registration should currently receive pushes.';
COMMENT ON COLUMN public.user_devices.last_seen_at IS 'Last heartbeat or refresh time from the client.';
COMMENT ON COLUMN public.user_devices.created_at IS 'Row creation timestamp.';
COMMENT ON COLUMN public.user_devices.updated_at IS 'Row update timestamp.';

COMMENT ON TABLE public.user_moderation_actions IS 'Historical moderation actions applied to a user account.';
COMMENT ON COLUMN public.user_moderation_actions.id IS 'Primary key for the moderation action row.';
COMMENT ON COLUMN public.user_moderation_actions.user_id IS 'User affected by the moderation action.';
COMMENT ON COLUMN public.user_moderation_actions.action_type IS 'Action type such as warn, restrict, suspend, ban, unsuspend, or clear.';
COMMENT ON COLUMN public.user_moderation_actions.reason_code IS 'Compact moderation reason code.';
COMMENT ON COLUMN public.user_moderation_actions.private_notes IS 'Internal-only moderator notes.';
COMMENT ON COLUMN public.user_moderation_actions.evidence_json IS 'Structured evidence payload for internal review.';
COMMENT ON COLUMN public.user_moderation_actions.created_by IS 'Moderator or system actor that created the action.';
COMMENT ON COLUMN public.user_moderation_actions.created_at IS 'Action creation timestamp.';
COMMENT ON COLUMN public.user_moderation_actions.expires_at IS 'Optional action expiry timestamp.';
COMMENT ON COLUMN public.user_moderation_actions.revoked_at IS 'Optional timestamp when the action was revoked.';

/*
  section: indexes
*/

CREATE INDEX IF NOT EXISTS users_email_idx
  ON public.users (LOWER(email));

CREATE INDEX IF NOT EXISTS users_is_active_idx
  ON public.users (is_active);

CREATE INDEX IF NOT EXISTS users_moderation_status_idx
  ON public.users (moderation_status);

CREATE INDEX IF NOT EXISTS users_suspended_until_idx
  ON public.users (suspended_until);

CREATE INDEX IF NOT EXISTS user_devices_user_id_idx
  ON public.user_devices (user_id, is_active);

CREATE INDEX IF NOT EXISTS user_devices_device_id_idx
  ON public.user_devices (device_id)
  WHERE device_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS user_devices_last_seen_at_idx
  ON public.user_devices (last_seen_at);

CREATE INDEX IF NOT EXISTS user_moderation_actions_user_id_idx
  ON public.user_moderation_actions (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS user_moderation_actions_action_type_idx
  ON public.user_moderation_actions (action_type);

CREATE INDEX IF NOT EXISTS user_moderation_actions_active_idx
  ON public.user_moderation_actions (user_id, revoked_at, expires_at);

/*
  section: triggers

  auth.users triggers:
    keep public.users synchronized with auth identity rows

  updated_at triggers:
    maintain write timestamps on mutable tables
*/

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.handle_new_auth_user();

DROP TRIGGER IF EXISTS on_auth_user_updated_sync_email ON auth.users;
CREATE TRIGGER on_auth_user_updated_sync_email
  AFTER UPDATE OF email ON auth.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.sync_user_email_from_auth();

DROP TRIGGER IF EXISTS set_users_updated_at ON public.users;
CREATE TRIGGER set_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE PROCEDURE public.set_updated_at();

DROP TRIGGER IF EXISTS set_user_devices_updated_at ON public.user_devices;
CREATE TRIGGER set_user_devices_updated_at
  BEFORE UPDATE ON public.user_devices
  FOR EACH ROW
  EXECUTE PROCEDURE public.set_updated_at();

/*
  section: row level security
*/

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_moderation_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_select_own"
  ON public.users
  FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) = id);

CREATE POLICY "users_update_own"
  ON public.users
  FOR UPDATE
  TO authenticated
  USING ((SELECT auth.uid()) = id)
  WITH CHECK ((SELECT auth.uid()) = id);

CREATE POLICY "user_devices_select_own"
  ON public.user_devices
  FOR SELECT
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "user_devices_insert_own"
  ON public.user_devices
  FOR INSERT
  TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "user_devices_update_own"
  ON public.user_devices
  FOR UPDATE
  TO authenticated
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "user_devices_delete_own"
  ON public.user_devices
  FOR DELETE
  TO authenticated
  USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "user_moderation_actions_select_none_for_users"
  ON public.user_moderation_actions
  FOR SELECT
  TO authenticated
  USING (false);

/*
  section: column-level privileges

  important:
    rls restricts which rows a user can touch
    grant/revoke restricts which columns a user can update

  revoke table-level update first, then grant update only on allowed columns
*/

REVOKE UPDATE
  ON TABLE public.users
  FROM authenticated;

GRANT SELECT
  ON TABLE public.users
  TO authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLE public.user_devices
  TO authenticated;

GRANT UPDATE (
  mobile,
  accepted_terms_version,
  terms_accepted_at
)
  ON TABLE public.users
  TO authenticated;

COMMIT;