-- ==========================================================
-- ADD LEGAL GRIEVANCE QUERY TYPE
-- Expands feedback_reports_query_type_check to support 'legal_grievance' and 'grievance'
-- ==========================================================

BEGIN;

ALTER TABLE public.feedback_reports
    DROP CONSTRAINT IF EXISTS feedback_reports_query_type_check;

ALTER TABLE public.feedback_reports
    ADD CONSTRAINT feedback_reports_query_type_check
    CHECK (query_type IN ('help', 'feedback', 'bug_report', 'suspended', 'security', 'legal_grievance', 'other'));

COMMENT ON COLUMN public.feedback_reports.query_type
    IS 'Ticket category: help, feedback, bug_report, suspended, security, legal_grievance, or other.';

COMMIT;
