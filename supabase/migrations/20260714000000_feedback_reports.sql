-- ==========================================================
-- HELP, FEEDBACK & BUG REPORT
-- Stores user-submitted support tickets (help requests, product feedback,
-- and bug reports) plus a status timeline for admin triage.
-- ==========================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.feedback_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

    -- What kind of ticket this is.
    query_type TEXT NOT NULL
        CHECK (query_type IN ('help', 'feedback', 'bug_report')),

    subject TEXT NOT NULL,
    message TEXT NOT NULL,

    -- Optional override; defaults to the account email at send time when null.
    contact_email TEXT,

    -- Only meaningful (and only ever set) for bug_report tickets.
    github_issue_url TEXT,

    -- Paths within the private 'feedback_attachments' storage bucket,
    -- always prefixed with the submitting user's id (enforced server-side).
    attachment_paths TEXT[] NOT NULL DEFAULT '{}'::text[],

    -- Lightweight diagnostic context, mainly useful for bug_report tickets.
    app_version TEXT,
    platform TEXT CHECK (platform IS NULL OR platform IN ('android', 'ios')),
    device_info JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- Admin triage lifecycle.
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    reviewer_notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    -- Reserved for auxiliary context (client build info, session hints, etc.)
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT feedback_reports_subject_length_check
        CHECK (char_length(trim(subject)) BETWEEN 3 AND 150),

    CONSTRAINT feedback_reports_message_length_check
        CHECK (char_length(trim(message)) BETWEEN 10 AND 5000),

    CONSTRAINT feedback_reports_github_url_scope_check
        CHECK (github_issue_url IS NULL OR query_type = 'bug_report'),

    CONSTRAINT feedback_reports_github_url_format_check
        CHECK (github_issue_url IS NULL OR github_issue_url LIKE 'https://github.com/%'),

    CONSTRAINT feedback_reports_attachment_paths_limit_check
        CHECK (array_length(attachment_paths, 1) IS NULL OR array_length(attachment_paths, 1) <= 5),

    CONSTRAINT feedback_reports_device_info_object_check
        CHECK (jsonb_typeof(device_info) = 'object'),

    CONSTRAINT feedback_reports_metadata_object_check
        CHECK (jsonb_typeof(metadata) = 'object')
);

COMMENT ON TABLE public.feedback_reports
    IS 'User-submitted Help, Feedback & Bug Report tickets. Status changes are logged to feedback_report_status_history via trigger.';

COMMENT ON COLUMN public.feedback_reports.query_type IS 'Ticket category: help, feedback, or bug_report.';
COMMENT ON COLUMN public.feedback_reports.contact_email IS 'Optional override contact address; falls back to the account email.';
COMMENT ON COLUMN public.feedback_reports.github_issue_url IS 'Optional linked GitHub issue, bug_report tickets only.';
COMMENT ON COLUMN public.feedback_reports.attachment_paths IS 'Object paths in the feedback_attachments storage bucket.';
COMMENT ON COLUMN public.feedback_reports.status IS 'Admin triage lifecycle: open -> in_progress -> resolved or closed.';
COMMENT ON COLUMN public.feedback_reports.reviewed_by IS 'Admin user who last changed the status.';
COMMENT ON COLUMN public.feedback_reports.metadata IS 'Auxiliary JSON context for internal review tooling.';


-- ==========================================================
-- STATUS TIMELINE
-- Append-only history of status transitions, populated automatically by
-- trigger below (initial 'open' row on insert, one row per status change).
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.feedback_report_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID NOT NULL REFERENCES public.feedback_reports(id) ON DELETE CASCADE,
    status TEXT NOT NULL
        CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
    note TEXT,
    changed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

COMMENT ON TABLE public.feedback_report_status_history
    IS 'Append-only status timeline for feedback_reports, populated by trigger.';


-- ==========================================================
-- TRIGGERS
-- ==========================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = timezone('utc'::text, now());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_feedback_reports_updated_at ON public.feedback_reports;
CREATE TRIGGER set_feedback_reports_updated_at
    BEFORE UPDATE ON public.feedback_reports
    FOR EACH ROW
    EXECUTE PROCEDURE public.set_updated_at();

CREATE OR REPLACE FUNCTION public.log_feedback_status_change()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.feedback_report_status_history (report_id, status, note)
    VALUES (NEW.id, NEW.status, 'Ticket submitted.');
  ELSIF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO public.feedback_report_status_history (report_id, status, changed_by, note)
    VALUES (NEW.id, NEW.status, NEW.reviewed_by, NEW.reviewer_notes);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS log_feedback_reports_status_change ON public.feedback_reports;
CREATE TRIGGER log_feedback_reports_status_change
    AFTER INSERT OR UPDATE ON public.feedback_reports
    FOR EACH ROW
    EXECUTE PROCEDURE public.log_feedback_status_change();


-- ==========================================================
-- INDEXES
-- ==========================================================

CREATE INDEX IF NOT EXISTS idx_feedback_reports_user_created
    ON public.feedback_reports (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_feedback_reports_status_created
    ON public.feedback_reports (status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_feedback_report_status_history_report_created
    ON public.feedback_report_status_history (report_id, created_at);


-- ==========================================================
-- RLS
-- Users may submit tickets and read back their own; admins read everything
-- via the service_role key, which bypasses RLS entirely.
-- ==========================================================

ALTER TABLE public.feedback_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "feedback_reports_insert_own"
    ON public.feedback_reports
    FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "feedback_reports_select_own"
    ON public.feedback_reports
    FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

ALTER TABLE public.feedback_report_status_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "feedback_report_status_history_select_own"
    ON public.feedback_report_status_history
    FOR SELECT
    TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.feedback_reports r
            WHERE r.id = report_id AND r.user_id = (SELECT auth.uid())
        )
    );


-- ==========================================================
-- ATTACHMENTS STORAGE
-- Private bucket, folder-per-user ownership (path convention:
-- '{user_id}/{uuid}.<ext>'), enforced both by RLS below and by a
-- server-side prefix check before the path is ever stored on a report.
-- ==========================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'feedback_attachments',
    'feedback_attachments',
    false,
    8388608, -- 8MB per attachment
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "feedback_attachments_insert_own" ON storage.objects;
CREATE POLICY "feedback_attachments_insert_own"
    ON storage.objects
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'feedback_attachments'
        AND (storage.foldername(name))[1] = (auth.uid())::text
    );

DROP POLICY IF EXISTS "feedback_attachments_select_own" ON storage.objects;
CREATE POLICY "feedback_attachments_select_own"
    ON storage.objects
    FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'feedback_attachments'
        AND (storage.foldername(name))[1] = (auth.uid())::text
    );

DROP POLICY IF EXISTS "feedback_attachments_delete_own" ON storage.objects;
CREATE POLICY "feedback_attachments_delete_own"
    ON storage.objects
    FOR DELETE
    TO authenticated
    USING (
        bucket_id = 'feedback_attachments'
        AND (storage.foldername(name))[1] = (auth.uid())::text
    );

COMMIT;
