-- ==========================================================
-- HELP, FEEDBACK & BUG REPORT — follow-up
-- Drops the contact_email override (the app now always resolves the
-- submitter's contact address from public.users by user_id) and adds a
-- discussion thread table so users can comment on and close their own
-- tickets.
-- ==========================================================

BEGIN;

ALTER TABLE public.feedback_reports
    DROP COLUMN IF EXISTS contact_email;


-- ==========================================================
-- COMMENTS
-- Discussion thread on a ticket. Submitted by the ticket owner via the app
-- today; author_id is left generic so a future admin panel can post to the
-- same thread using the same table.
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.feedback_report_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL REFERENCES public.feedback_reports(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    CONSTRAINT feedback_report_comments_body_length_check
        CHECK (char_length(trim(body)) BETWEEN 1 AND 3000)
);

COMMENT ON TABLE public.feedback_report_comments
    IS 'Discussion thread on a feedback_reports ticket.';

CREATE INDEX IF NOT EXISTS idx_feedback_report_comments_report_created
    ON public.feedback_report_comments (report_id, created_at);

ALTER TABLE public.feedback_report_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "feedback_report_comments_insert_own"
    ON public.feedback_report_comments
    FOR INSERT
    TO authenticated
    WITH CHECK (
        author_id = (SELECT auth.uid())
        AND EXISTS (
            SELECT 1 FROM public.feedback_reports r
            WHERE r.id = report_id AND r.user_id = (SELECT auth.uid())
        )
    );

CREATE POLICY "feedback_report_comments_select_own"
    ON public.feedback_report_comments
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.feedback_reports r
            WHERE r.id = report_id AND r.user_id = (SELECT auth.uid())
        )
    );

COMMIT;
