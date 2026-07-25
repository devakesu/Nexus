-- ==========================================================
-- CONTACT FORM & FEEDBACK REPORTS UPDATE
-- Allows unauthenticated / guest contact submissions (nullable user_id)
-- and expands query_type to support account appeals ('suspended'),
-- security inquiries ('security'), and general contact ('other').
-- ==========================================================

BEGIN;

-- 1. Make user_id optional so unauthenticated visitors can submit contact tickets
ALTER TABLE public.feedback_reports
    ALTER COLUMN user_id DROP NOT NULL;

-- 2. Expand query_type check constraint
ALTER TABLE public.feedback_reports
    DROP CONSTRAINT IF EXISTS feedback_reports_query_type_check;

ALTER TABLE public.feedback_reports
    ADD CONSTRAINT feedback_reports_query_type_check
    CHECK (query_type IN ('help', 'feedback', 'bug_report', 'suspended', 'security', 'other'));

COMMENT ON COLUMN public.feedback_reports.query_type
    IS 'Ticket category: help, feedback, bug_report, suspended, security, or other.';

COMMIT;
