-- ==========================================================
-- GUARD ESCALATION BOOKKEEPING COLUMNS ON safety_sessions
-- Prevents clients (authenticated role) from modifying these
-- columns directly, leaving them writable only by service_role.
-- ==========================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.guard_safety_sessions_escalation_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF current_setting('role', true) = 'authenticated' THEN
        IF NEW.escalations_sent IS DISTINCT FROM OLD.escalations_sent OR
           NEW.last_escalated_at IS DISTINCT FROM OLD.last_escalated_at OR
           NEW.escalation_cancelled_at IS DISTINCT FROM OLD.escalation_cancelled_at THEN
            
            -- Revert any attempted modification to old values
            NEW.escalations_sent := OLD.escalations_sent;
            NEW.last_escalated_at := OLD.last_escalated_at;
            NEW.escalation_cancelled_at := OLD.escalation_cancelled_at;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_safety_sessions_escalation ON public.safety_sessions;
CREATE TRIGGER guard_safety_sessions_escalation
    BEFORE UPDATE ON public.safety_sessions
    FOR EACH ROW
    EXECUTE FUNCTION public.guard_safety_sessions_escalation_columns();

COMMIT;
