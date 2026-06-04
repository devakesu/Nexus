-- ==========================================================
-- NEXUS DISCOVERY ACTIONS
-- pass = temporary (14 days)
-- block = global across all tabs
-- hide / like / superlike = tab-specific and permanent until revoked
-- ==========================================================

-- Stores discovery interaction history between one viewer (actor) and one
-- candidate (target). Active rows influence feed suppression/visibility logic,
-- while revoked rows are retained for audit and analytics.
CREATE TABLE IF NOT EXISTS public.profile_discovery_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    actor_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    target_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,

    -- block is global, so tab is NULL for block and required for all other actions
    tab TEXT
        CHECK (tab IN ('Dating', 'Friends', 'Professional')),

    action TEXT NOT NULL
        CHECK (action IN ('pass', 'like', 'superlike', 'hide', 'block')),

    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT timezone('utc'::text, now()),

    -- Used only for temporary actions like pass.
    -- A pass is considered active only until expires_at.
    expires_at TIMESTAMP WITH TIME ZONE,

    -- Soft-revocation marker for audit/history retention.
    -- NULL means the row is currently active.
    revoked_at TIMESTAMP WITH TIME ZONE,

    -- Reserved for safe auxiliary context such as request metadata,
    -- experiment flags, or feed diagnostics.
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- A user cannot create a discovery action against themselves.
    CONSTRAINT profile_discovery_actions_actor_target_check
        CHECK (actor_id <> target_id),

    CONSTRAINT profile_discovery_actions_metadata_object_check
        CHECK (jsonb_typeof(metadata) = 'object'),

    -- block is universal across tabs; all other actions are tab-scoped.
    CONSTRAINT profile_discovery_actions_tab_action_check
        CHECK (
            (action = 'block' AND tab IS NULL)
            OR
            (action IN ('pass', 'like', 'superlike', 'hide') AND tab IS NOT NULL)
        ),

    -- Only pass may expire; permanent actions must leave expires_at NULL.
    CONSTRAINT profile_discovery_actions_expiry_check
        CHECK (
            (action = 'pass' AND expires_at IS NOT NULL)
            OR
            (action IN ('like', 'superlike', 'hide', 'block') AND expires_at IS NULL)
        ),

    -- For audit consistency: if a pass is revoked before natural expiry,
    -- the revocation time should not be later than the expiry time.
    CONSTRAINT profile_discovery_actions_inactive_state_check
        CHECK (
            revoked_at IS NULL
            OR action <> 'pass'
            OR revoked_at <= expires_at
        )
);

COMMENT ON TABLE public.profile_discovery_actions
    IS 'Per-user discovery action history. Pass is temporary, block is global, and other actions are tab-specific. Revoked rows are retained for audit.';

COMMENT ON COLUMN public.profile_discovery_actions.actor_id
    IS 'The viewer who performed the action.';

COMMENT ON COLUMN public.profile_discovery_actions.target_id
    IS 'The candidate profile the action was applied to.';

COMMENT ON COLUMN public.profile_discovery_actions.tab
    IS 'Discovery context for tab-scoped actions. Must be NULL for block and non-NULL for all other actions.';

COMMENT ON COLUMN public.profile_discovery_actions.action
    IS 'Action type: pass, like, superlike, hide, or block.';

COMMENT ON COLUMN public.profile_discovery_actions.expires_at
    IS 'UTC expiry timestamp for temporary pass actions. Permanent actions must keep this NULL.';

COMMENT ON COLUMN public.profile_discovery_actions.revoked_at
    IS 'UTC timestamp indicating the action has been revoked while preserving the audit trail. NULL means the row is currently active.';

COMMENT ON COLUMN public.profile_discovery_actions.metadata
    IS 'Optional JSON object for auxiliary non-authoritative discovery context.';


-- ==========================================================
-- UNIQUENESS
-- Active uniqueness only: revoked rows must not block re-creation
-- ==========================================================

-- Only one active global block may exist per actor->target pair.
CREATE UNIQUE INDEX IF NOT EXISTS uq_profile_discovery_actions_block
    ON public.profile_discovery_actions (actor_id, target_id, action)
    WHERE action = 'block' AND revoked_at IS NULL;

-- Only one active pass may exist per actor->target->tab combination.
CREATE UNIQUE INDEX IF NOT EXISTS uq_profile_discovery_actions_pass
    ON public.profile_discovery_actions (actor_id, target_id, tab, action)
    WHERE action = 'pass' AND revoked_at IS NULL;

-- Only one active hide may exist per actor->target->tab combination.
CREATE UNIQUE INDEX IF NOT EXISTS uq_profile_discovery_actions_hide
    ON public.profile_discovery_actions (actor_id, target_id, tab, action)
    WHERE action = 'hide' AND revoked_at IS NULL;

-- Only one active like may exist per actor->target->tab combination.
CREATE UNIQUE INDEX IF NOT EXISTS uq_profile_discovery_actions_like
    ON public.profile_discovery_actions (actor_id, target_id, tab, action)
    WHERE action = 'like' AND revoked_at IS NULL;

-- Only one active superlike may exist per actor->target->tab combination.
CREATE UNIQUE INDEX IF NOT EXISTS uq_profile_discovery_actions_superlike
    ON public.profile_discovery_actions (actor_id, target_id, tab, action)
    WHERE action = 'superlike' AND revoked_at IS NULL;


-- ==========================================================
-- QUERY INDEXES
-- ==========================================================

-- Fast lookup of a viewer's action history within a tab.
CREATE INDEX IF NOT EXISTS idx_profile_discovery_actions_actor_tab_created
    ON public.profile_discovery_actions (actor_id, tab, created_at DESC);

-- Supports tab-scoped action existence checks for one viewer and target.
CREATE INDEX IF NOT EXISTS idx_profile_discovery_actions_actor_target_tab_action
    ON public.profile_discovery_actions (actor_id, target_id, tab, action);

-- Supports global checks such as block existence between two users.
CREATE INDEX IF NOT EXISTS idx_profile_discovery_actions_actor_target_action
    ON public.profile_discovery_actions (actor_id, target_id, action);

-- Helps evaluate active pass cooldown windows efficiently.
CREATE INDEX IF NOT EXISTS idx_profile_discovery_actions_pass_expiry
    ON public.profile_discovery_actions (actor_id, tab, expires_at)
    WHERE action = 'pass' AND revoked_at IS NULL;

-- Hot-path suppression index used while filtering feed candidates.
CREATE INDEX IF NOT EXISTS idx_profile_discovery_actions_active_suppressions
    ON public.profile_discovery_actions (actor_id, target_id, action, tab, expires_at)
    WHERE revoked_at IS NULL AND action IN ('pass', 'hide', 'block');


-- ==========================================================
-- RLS
-- ==========================================================

ALTER TABLE public.profile_discovery_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own discovery actions" ON public.profile_discovery_actions;
CREATE POLICY "Users can view own discovery actions"
    ON public.profile_discovery_actions
    FOR SELECT
    USING ((SELECT auth.uid()) = actor_id);

DROP POLICY IF EXISTS "Users can insert own discovery actions" ON public.profile_discovery_actions;
CREATE POLICY "Users can insert own discovery actions"
    ON public.profile_discovery_actions
    FOR INSERT
    WITH CHECK ((SELECT auth.uid()) = actor_id);

DROP POLICY IF EXISTS "Users can update own discovery actions" ON public.profile_discovery_actions;
CREATE POLICY "Users can update own discovery actions"
    ON public.profile_discovery_actions
    FOR UPDATE
    USING ((SELECT auth.uid()) = actor_id)
    WITH CHECK ((SELECT auth.uid()) = actor_id);

DROP POLICY IF EXISTS "Users can delete own discovery actions" ON public.profile_discovery_actions;
CREATE POLICY "Users can delete own discovery actions"
    ON public.profile_discovery_actions
    FOR DELETE
    USING ((SELECT auth.uid()) = actor_id);

COMMENT ON POLICY "Users can view own discovery actions" ON public.profile_discovery_actions
    IS 'Allows a user to read only discovery action rows where they are the actor.';

COMMENT ON POLICY "Users can insert own discovery actions" ON public.profile_discovery_actions
    IS 'Allows a user to create discovery action rows only for their own actor_id.';

COMMENT ON POLICY "Users can update own discovery actions" ON public.profile_discovery_actions
    IS 'Allows a user to update only discovery action rows where they are the actor.';

COMMENT ON POLICY "Users can delete own discovery actions" ON public.profile_discovery_actions
    IS 'Allows a user to delete only discovery action rows where they are the actor.';


-- ==========================================================
-- TIMESTAMP TRIGGER
-- ==========================================================

DROP TRIGGER IF EXISTS trigger_update_profile_discovery_actions_timestamp ON public.profile_discovery_actions;
CREATE TRIGGER trigger_update_profile_discovery_actions_timestamp
    BEFORE UPDATE ON public.profile_discovery_actions
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_update_timestamp();

COMMENT ON TRIGGER trigger_update_profile_discovery_actions_timestamp ON public.profile_discovery_actions
    IS 'Applies handle_update_timestamp before every discovery action update.';