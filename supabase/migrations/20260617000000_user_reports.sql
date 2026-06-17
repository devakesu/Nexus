-- ==========================================================
-- USER REPORTS
-- Stores user-generated reports against other profiles for admin review.
-- Reporting a user also creates a block (handled in application layer).
-- ==========================================================

CREATE TABLE IF NOT EXISTS public.user_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    reporter_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    target_id   UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

    -- Discovery tab context (may be null if submitted outside a tab context)
    tab TEXT CHECK (tab IN ('Dating', 'Friends', 'Professional')),

    -- Structured reason code for admin triage
    reason TEXT NOT NULL
        CHECK (reason IN ('scam', 'bot', 'harassment', 'inappropriate', 'spam', 'underage', 'other')),

    -- Free-text elaboration, required when reason = 'other'
    reason_detail TEXT,

    -- Moderation state updated by admins
    review_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (review_status IN ('pending', 'reviewed', 'actioned', 'dismissed')),

    reviewed_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at   TIMESTAMPTZ,
    reviewer_notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),

    -- Reserved for auxiliary context (device info, session hints, etc.)
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT user_reports_actor_target_check
        CHECK (reporter_id <> target_id),

    CONSTRAINT user_reports_other_reason_check
        CHECK (reason <> 'other' OR (reason_detail IS NOT NULL AND length(trim(reason_detail)) > 0)),

    CONSTRAINT user_reports_metadata_object_check
        CHECK (jsonb_typeof(metadata) = 'object')
);

COMMENT ON TABLE public.user_reports
    IS 'User-generated reports against other profiles. Each report triggers a mutual block in profile_discovery_actions. Admin-reviewable via review_status.';

COMMENT ON COLUMN public.user_reports.reporter_id IS 'User who filed the report.';
COMMENT ON COLUMN public.user_reports.target_id IS 'Profile being reported.';
COMMENT ON COLUMN public.user_reports.tab IS 'Discovery tab context at the time of report.';
COMMENT ON COLUMN public.user_reports.reason IS 'Structured reason code for admin triage.';
COMMENT ON COLUMN public.user_reports.reason_detail IS 'Free-text elaboration; required when reason is other.';
COMMENT ON COLUMN public.user_reports.review_status IS 'Admin review lifecycle: pending → reviewed → actioned or dismissed.';
COMMENT ON COLUMN public.user_reports.reviewed_by IS 'Admin user who reviewed this report.';
COMMENT ON COLUMN public.user_reports.reviewed_at IS 'Timestamp the report was reviewed.';
COMMENT ON COLUMN public.user_reports.reviewer_notes IS 'Internal notes from the reviewing admin.';
COMMENT ON COLUMN public.user_reports.created_at IS 'Row creation timestamp.';
COMMENT ON COLUMN public.user_reports.metadata IS 'Auxiliary JSON context for internal review tooling.';


-- ==========================================================
-- INDEXES
-- ==========================================================

-- Admin queue: newest pending reports first
CREATE INDEX IF NOT EXISTS idx_user_reports_review_status_created
    ON public.user_reports (review_status, created_at DESC);

-- Prevent the same reporter→target pair from flooding the queue
CREATE INDEX IF NOT EXISTS idx_user_reports_reporter_target
    ON public.user_reports (reporter_id, target_id);

-- Target-centric view for account moderation
CREATE INDEX IF NOT EXISTS idx_user_reports_target_created
    ON public.user_reports (target_id, created_at DESC);


-- ==========================================================
-- RLS
-- Users may submit reports but cannot read them (admin service role bypasses RLS).
-- ==========================================================

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user_reports_insert_own"
    ON public.user_reports
    FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = reporter_id);

-- No SELECT policy for authenticated role; admin reads via service_role key.
