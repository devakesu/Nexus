-- ==========================================================
-- RESET profile_name_change_log FOR ALL USERS
--
-- Bug: GlassTextField (mobile/lib/screens/home/tabs/profile/widgets/
-- glass_text_field.dart) calls its onFieldSubmitted callback on every
-- focus loss, even when the user typed nothing - and update_profile_details
-- (app/api/user.py) treated any non-null `name` in the payload as a real
-- change, unconditionally consuming one of the 2 yearly name-change slots
-- via apply_name_change. Simply tapping into the Display Name field and
-- tapping away without editing anything silently burned a change slot.
--
-- The application-layer fix (skip the rate-limit/moderation checks and
-- the apply_name_change RPC call entirely when the submitted name equals
-- the current stored name) ships alongside this migration. This migration
-- undoes the erroneous consumption already recorded: since log rows don't
-- distinguish a genuine change from a same-value resubmission, the only
-- correct remediation is a full reset - every user gets their full 2/year
-- allowance back.
-- ==========================================================

BEGIN;

DELETE FROM public.profile_name_change_log;

COMMIT;
