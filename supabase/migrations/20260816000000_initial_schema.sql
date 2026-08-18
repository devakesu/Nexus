-- ==========================================================
-- SECTION 1: EXTENSIONS & ENVIRONMENT CONFIGURATION
-- ==========================================================

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

COMMENT ON SCHEMA "public" IS 'standard public schema';

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA "public";

-- ==========================================================
-- SECTION 2: CORE FUNCTIONS, RPCs & TRIGGER PROCEDURES
-- ==========================================================

CREATE OR REPLACE FUNCTION "public"."apply_age_change"("p_user_id" "uuid", "p_new_age" integer, "p_min_interval_days" integer DEFAULT 365, "p_max_changes" integer DEFAULT 2) RETURNS timestamp with time zone
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_count INTEGER;
BEGIN
    PERFORM 1 FROM public.profiles WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'profile_not_found' USING ERRCODE = 'P0002';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.profile_age_change_log
    WHERE user_id = p_user_id
      AND changed_at > v_now - (p_min_interval_days || ' days')::interval;

    IF v_count >= p_max_changes THEN
        RAISE EXCEPTION 'age_change_limit_reached' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.profiles
    SET age = p_new_age, age_updated_at = v_now, updated_at = v_now
    WHERE id = p_user_id;
    INSERT INTO public.profile_age_change_log (user_id, changed_at) VALUES (p_user_id, v_now);

    RETURN v_now;
END;
$$;

ALTER FUNCTION "public"."apply_age_change"("p_user_id" "uuid", "p_new_age" integer, "p_min_interval_days" integer, "p_max_changes" integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."apply_name_change"("p_user_id" "uuid", "p_new_name" "text", "p_min_interval_days" integer DEFAULT 365, "p_max_changes" integer DEFAULT 2) RETURNS timestamp with time zone
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_count INTEGER;
BEGIN
    PERFORM 1 FROM public.profiles WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'profile_not_found' USING ERRCODE = 'P0002';
    END IF;

    SELECT count(*) INTO v_count
    FROM public.profile_name_change_log
    WHERE user_id = p_user_id
      AND changed_at > v_now - (p_min_interval_days || ' days')::interval;

    IF v_count >= p_max_changes THEN
        RAISE EXCEPTION 'name_change_limit_reached' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.profiles SET name = p_new_name, updated_at = v_now WHERE id = p_user_id;
    INSERT INTO public.profile_name_change_log (user_id, changed_at) VALUES (p_user_id, v_now);

    RETURN v_now;
END;
$$;

ALTER FUNCTION "public"."apply_name_change"("p_user_id" "uuid", "p_new_name" "text", "p_min_interval_days" integer, "p_max_changes" integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."check_match_precondition"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.profile_discovery_actions
        WHERE actor_id = NEW.liker_id
          AND target_id = NEW.liked_back_id
          AND action IN ('like', 'superlike')
          AND tab = NEW.tab
          AND revoked_at IS NULL
    ) THEN
        RAISE EXCEPTION 'No active incoming like found' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."check_match_precondition"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."claim_one_time_prekey"("target_user_id" "uuid") RETURNS TABLE("key_id" integer, "public_key" "bytea")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
    claimed_id UUID;
BEGIN
    SELECT c.id INTO claimed_id
    FROM public.chat_one_time_prekeys c
    WHERE c.user_id = target_user_id AND c.used_at IS NULL
    ORDER BY c.key_id
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    IF claimed_id IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    UPDATE public.chat_one_time_prekeys c
    SET used_at = timezone('utc'::text, now())
    WHERE c.id = claimed_id
    RETURNING c.key_id, c.public_key;
END;
$$;

ALTER FUNCTION "public"."claim_one_time_prekey"("target_user_id" "uuid") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."create_discovery_session_with_items"("p_viewer_id" "uuid", "p_tab" "text", "p_filters" "jsonb", "p_expires_at" timestamp with time zone, "p_viewer_spotify_connected" boolean, "p_items" "jsonb") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_session_id UUID;
    v_item RECORD;
BEGIN
    -- Insert the discovery session with the viewer connection flag
    INSERT INTO public.discovery_sessions (
        viewer_id,
        tab,
        filters,
        expires_at,
        viewer_spotify_connected
    )
    VALUES (
        p_viewer_id,
        p_tab,
        p_filters,
        p_expires_at,
        COALESCE(p_viewer_spotify_connected, false)
    )
    RETURNING id INTO v_session_id;

    -- Insert each item in the session (omitting viewer_spotify_connected)
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(
        position INT,
        candidate_id UUID,
        score DOUBLE PRECISION,
        x DOUBLE PRECISION,
        y DOUBLE PRECISION,
        orbit_tier INT,
        music_match_grade INT,
        candidate_spotify_connected BOOLEAN
    ) LOOP
        INSERT INTO public.discovery_session_items (
            session_id,
            position,
            candidate_id,
            score,
            x,
            y,
            orbit_tier,
            music_match_grade,
            candidate_spotify_connected
        )
        VALUES (
            v_session_id,
            v_item.position,
            v_item.candidate_id,
            v_item.score,
            v_item.x,
            v_item.y,
            v_item.orbit_tier,
            v_item.music_match_grade,
            COALESCE(v_item.candidate_spotify_connected, false)
        );
    END LOOP;

    RETURN v_session_id;
END;
$$;

ALTER FUNCTION "public"."create_discovery_session_with_items"("p_viewer_id" "uuid", "p_tab" "text", "p_filters" "jsonb", "p_expires_at" timestamp with time zone, "p_viewer_spotify_connected" boolean, "p_items" "jsonb") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."enforce_variant_age_range"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_variant TEXT;
BEGIN
    SELECT app_variant INTO v_variant FROM public.users WHERE id = NEW.id;

    IF v_variant IS DISTINCT FROM 'nexus' AND NEW.age > 27 THEN
        RAISE EXCEPTION 'age_out_of_range_for_variant' USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."enforce_variant_age_range"() OWNER TO "postgres";

COMMENT ON FUNCTION "public"."enforce_variant_age_range"() IS 'DB-level backstop for the 18-80 (nexus) / 18-27 (every other variant) age split - the FastAPI layer (app/api/user.py::update_profile_details) is the primary enforcement point, this trigger catches anything that bypasses it.';

CREATE OR REPLACE FUNCTION "public"."get_user_id_by_email"("email_addr" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'auth'
    AS $$
DECLARE
    user_id uuid;
BEGIN
    SELECT id INTO user_id FROM auth.users WHERE email = LOWER(email_addr) LIMIT 1;
    RETURN user_id;
END;
$$;

ALTER FUNCTION "public"."get_user_id_by_email"("email_addr" "text") OWNER TO "postgres";

COMMENT ON FUNCTION "public"."get_user_id_by_email"("email_addr" "text") IS 'Resolves a user UUID from auth.users by email. SECURITY DEFINER to bypass schema permissions.';

CREATE OR REPLACE FUNCTION "public"."guard_safety_sessions_escalation_columns"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        IF TG_OP = 'INSERT' THEN
            NEW.escalations_sent := 0;
            NEW.last_escalated_at := NULL;
            NEW.escalation_cancelled_at := NULL;
        ELSIF TG_OP = 'UPDATE' THEN
            IF NEW.escalations_sent IS DISTINCT FROM OLD.escalations_sent OR
               NEW.last_escalated_at IS DISTINCT FROM OLD.last_escalated_at OR
               NEW.escalation_cancelled_at IS DISTINCT FROM OLD.escalation_cancelled_at THEN

                -- Revert any attempted modification to old values
                NEW.escalations_sent := OLD.escalations_sent;
                NEW.last_escalated_at := OLD.last_escalated_at;
                NEW.escalation_cancelled_at := OLD.escalation_cancelled_at;
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."guard_safety_sessions_escalation_columns"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."guard_service_fields"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF auth.role() IS DISTINCT FROM 'service_role' THEN
        IF NEW.is_deactivated IS DISTINCT FROM OLD.is_deactivated OR
           NEW.deactivated_at IS DISTINCT FROM OLD.deactivated_at THEN
            RAISE EXCEPTION 'permission denied: profile deactivation states are server-side only';
        END IF;

        IF NEW.is_friends_active IS DISTINCT FROM OLD.is_friends_active OR
           NEW.is_professional_active IS DISTINCT FROM OLD.is_professional_active OR
           NEW.is_dating_active IS DISTINCT FROM OLD.is_dating_active THEN
            RAISE EXCEPTION 'permission denied: profile active flags are server-side only';
        END IF;

        IF NEW.has_imported_data IS DISTINCT FROM OLD.has_imported_data OR
           NEW.import_sync_code IS DISTINCT FROM OLD.import_sync_code OR
           NEW.import_sync_expires_at IS DISTINCT FROM OLD.import_sync_expires_at THEN
            RAISE EXCEPTION 'permission denied: import sync fields are server-side only';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."guard_service_fields"() OWNER TO "postgres";

COMMENT ON FUNCTION "public"."guard_service_fields"() IS 'SECURITY DEFINER trigger blocking non-service writes to server-governed profile fields: deactivation state, tab-active flags, and import sync fields.';

CREATE OR REPLACE FUNCTION "public"."prevent_users_app_variant_update"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF OLD.app_variant IS NOT NULL AND NEW.app_variant IS DISTINCT FROM OLD.app_variant THEN
        RAISE EXCEPTION 'app_variant cannot be modified after user account creation.';
    END IF;
    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."prevent_users_app_variant_update"() OWNER TO "postgres";

COMMENT ON FUNCTION "public"."prevent_users_app_variant_update"() IS 'Blocks updates to app_variant after user row creation to prevent privilege escalation.';

CREATE OR REPLACE FUNCTION "public"."handle_deactivation_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF NEW.is_deactivated = TRUE AND OLD.is_deactivated = FALSE THEN
        NEW.deactivated_at = timezone('utc'::text, now());
    END IF;

    IF NEW.is_deactivated = FALSE AND OLD.is_deactivated = TRUE THEN
        NEW.deactivated_at = NULL;
    END IF;

    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."handle_deactivation_timestamp"() OWNER TO "postgres";

COMMENT ON FUNCTION "public"."handle_deactivation_timestamp"() IS 'Trigger function that derives deactivated_at from transitions of is_deactivated.';

CREATE OR REPLACE FUNCTION "public"."handle_update_timestamp"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."handle_update_timestamp"() OWNER TO "postgres";

COMMENT ON FUNCTION "public"."handle_update_timestamp"() IS 'Trigger function that refreshes updated_at to the current UTC timestamp before row update.';

CREATE OR REPLACE FUNCTION "public"."log_feedback_status_change"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
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

ALTER FUNCTION "public"."log_feedback_status_change"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."set_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
  NEW.updated_at = timezone('utc'::text, now());
  RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."set_updated_at"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."sync_safety_contacts"("p_user_id" "uuid", "p_contacts" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
DECLARE
    contact_record RECORD;
BEGIN
    -- Delete all existing contacts for the user
    DELETE FROM public.safety_contacts WHERE user_id = p_user_id;

    -- Insert new contacts if any
    IF p_contacts IS NOT NULL AND jsonb_array_length(p_contacts) > 0 THEN
        FOR contact_record IN SELECT * FROM jsonb_to_recordset(p_contacts) AS x(name TEXT, phone TEXT) LOOP
            INSERT INTO public.safety_contacts (user_id, name, phone)
            VALUES (p_user_id, contact_record.name::bytea, contact_record.phone::bytea);
        END LOOP;
    END IF;
END;
$$;

ALTER FUNCTION "public"."sync_safety_contacts"("p_user_id" "uuid", "p_contacts" "jsonb") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."touch_conversation_last_message"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
    UPDATE public.chat_conversations
    SET last_message_at = NEW.created_at
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$;

ALTER FUNCTION "public"."touch_conversation_last_message"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."upsert_signed_prekey"("target_user_id" "uuid", "new_key_id" integer, "new_public_key" "bytea", "new_signature" "bytea") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
    -- Mark any currently-active signed prekey (different key_id) as rotated.
    UPDATE public.chat_signed_prekeys
    SET rotated_at = timezone('utc'::text, now())
    WHERE user_id = target_user_id
      AND rotated_at IS NULL
      AND key_id <> new_key_id;

    -- Insert the new key, or update it in-place if the same key_id was already
    -- uploaded (idempotent re-upload after reactivation / retry).
    INSERT INTO public.chat_signed_prekeys (user_id, key_id, public_key, signature)
    VALUES (target_user_id, new_key_id, new_public_key, new_signature)
    ON CONFLICT (user_id, key_id) DO UPDATE
        SET public_key  = EXCLUDED.public_key,
            signature   = EXCLUDED.signature,
            rotated_at  = NULL;  -- re-activate if it was previously rotated
END;
$$;

ALTER FUNCTION "public"."upsert_signed_prekey"("target_user_id" "uuid", "new_key_id" integer, "new_public_key" "bytea", "new_signature" "bytea") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."validate_array_values"("arr" "text"[], "allowed" "text"[]) RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE STRICT
    SET "search_path" TO 'public', 'pg_temp'
    AS $$
BEGIN
    RETURN NOT EXISTS (
        SELECT 1
        FROM unnest(arr) AS elem
        WHERE elem <> ALL(allowed)
    );
END;
$$;

ALTER FUNCTION "public"."validate_array_values"("arr" "text"[], "allowed" "text"[]) OWNER TO "postgres";

COMMENT ON FUNCTION "public"."validate_array_values"("arr" "text"[], "allowed" "text"[]) IS 'Returns true when every element of the input array belongs to the allowed-value array.';

SET default_tablespace = '';

SET default_table_access_method = "heap";

-- ==========================================================
-- SECTION 3: CORE TABLES & DATA SCHEMAS
-- ==========================================================

CREATE TABLE IF NOT EXISTS "public"."account_history_archive" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "source_table" "text" NOT NULL,
    "reason_code" "text",
    "outcome" "text",
    "event_occurred_at" timestamp with time zone NOT NULL,
    "archived_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "account_history_archive_source_table_check" CHECK (("source_table" = ANY (ARRAY['user_reports'::"text", 'user_moderation_actions'::"text", 'feedback_reports'::"text"])))
);

ALTER TABLE ONLY "public"."account_history_archive" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."account_history_archive" OWNER TO "postgres";

COMMENT ON TABLE "public"."account_history_archive" IS 'Non-identifying archive of user_reports/user_moderation_actions/feedback_reports essentials, written by hard_purge_long_tail_accounts() just before an account''s final hard-delete. Holds no user identifier of any kind (not even a hash) - it is an aggregate trust & safety trail (reason codes, outcomes, timing), not a per-person record.';

CREATE TABLE IF NOT EXISTS "public"."chat_conversations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "match_id" "uuid" NOT NULL,
    "user_a_id" "uuid" NOT NULL,
    "user_b_id" "uuid" NOT NULL,
    "tab" "text" NOT NULL,
    "closed_reason" "text",
    "session_established_at" timestamp with time zone,
    "last_message_at" timestamp with time zone,
    "closed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "chat_conversations_closed_reason_check" CHECK (("closed_reason" = ANY (ARRAY['unmatch'::"text", 'block'::"text", 'report'::"text", 'account_deletion'::"text"]))),
    CONSTRAINT "chat_conversations_no_self_chat" CHECK (("user_a_id" <> "user_b_id")),
    CONSTRAINT "chat_conversations_tab_check" CHECK (("tab" = ANY (ARRAY['Dating'::"text", 'Friends'::"text", 'Professional'::"text"])))
);

ALTER TABLE "public"."chat_conversations" OWNER TO "postgres";

COMMENT ON TABLE "public"."chat_conversations" IS 'Conversation metadata for a match. Message ciphertext lives in chat_messages (later migration).';

COMMENT ON COLUMN "public"."chat_conversations"."match_id" IS 'The match this conversation belongs to; one conversation per match.';

COMMENT ON COLUMN "public"."chat_conversations"."last_message_at" IS 'NULL = matched but not chatting yet. Set on first message send.';

COMMENT ON COLUMN "public"."chat_conversations"."closed_at" IS 'Timestamp the conversation was closed alongside its match dissolving.';

COMMENT ON COLUMN "public"."chat_conversations"."closed_reason" IS 'Why the conversation closed: unmatch, block, report, or account_deletion. account_deletion is the only one that gets reopened automatically (by cancel_deletion(), if the user reactivates within the grace window).';

COMMENT ON COLUMN "public"."chat_conversations"."session_established_at" IS 'When both participants completed Signal Protocol session setup.';

CREATE TABLE IF NOT EXISTS "public"."chat_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "conversation_id" "uuid" NOT NULL,
    "message_id" "uuid" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "status" "text" DEFAULT 'proposed'::"text" NOT NULL,
    "event_time" "bytea" NOT NULL,
    "location_label" "bytea",
    "location_lat" "bytea",
    "location_lng" "bytea",
    "safety_enabled" boolean DEFAULT false NOT NULL,
    "safety_interval_seconds" integer,
    "reminder_sent_at" timestamp with time zone,
    "safety_reminder_sent_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "chat_events_safety_interval_seconds_check" CHECK ((("safety_interval_seconds" IS NULL) OR ("safety_interval_seconds" > 0))),
    CONSTRAINT "chat_events_status_check" CHECK (("status" = ANY (ARRAY['proposed'::"text", 'confirmed'::"text", 'cancelled'::"text"])))
);

ALTER TABLE "public"."chat_events" OWNER TO "postgres";

COMMENT ON TABLE "public"."chat_events" IS 'Date/plan proposals attached to a chat_messages row. event_time, location_lat, location_lng, and location_label are encrypted with Field-Level Encryption (MultiFernet); title/notes live only as ciphertext on the linked message.';

COMMENT ON COLUMN "public"."chat_events"."message_id" IS 'The chat_messages row (type=event) whose decrypted ciphertext holds {title, notes}.';

COMMENT ON COLUMN "public"."chat_events"."event_time" IS 'Encrypted ISO timestamp of the event.';

COMMENT ON COLUMN "public"."chat_events"."location_lat" IS 'Encrypted latitude of the location.';

COMMENT ON COLUMN "public"."chat_events"."location_lng" IS 'Encrypted longitude of the location.';

COMMENT ON COLUMN "public"."chat_events"."location_label" IS 'Encrypted label of the location.';

COMMENT ON COLUMN "public"."chat_events"."reminder_sent_at" IS 'Set by the reminder scheduler once a push has fired for this event.';

COMMENT ON COLUMN "public"."chat_events"."safety_enabled" IS 'Set when the event creator opted into auto-configuring Meetup Safety for this plan at creation time. Personal to the creator - the other participant is unaffected and can still use the separate "Set up a safety check-in" shortcut on their own copy of the event card.';

COMMENT ON COLUMN "public"."chat_events"."safety_interval_seconds" IS 'The check-in interval the creator chose, set only when safety_enabled - feeds the pre-event reminder copy and the MeetupSafetyPage prefill.';

COMMENT ON COLUMN "public"."chat_events"."safety_reminder_sent_at" IS 'Set by the reminder scheduler once the "Meetup Safety turns on soon" push has fired for this event. Tracked separately from reminder_sent_at since the two reminders have different lead times and audiences (both participants vs. creator only).';

CREATE TABLE IF NOT EXISTS "public"."chat_identity_keys" (
    "user_id" "uuid" NOT NULL,
    "identity_public_key" "bytea" NOT NULL,
    "registration_id" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

ALTER TABLE "public"."chat_identity_keys" OWNER TO "postgres";

COMMENT ON TABLE "public"."chat_identity_keys" IS 'One Signal Protocol identity public key per user (single device for v1). Private key never leaves the device.';

CREATE TABLE IF NOT EXISTS "public"."chat_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "conversation_id" "uuid" NOT NULL,
    "sender_id" "uuid" NOT NULL,
    "message_type" "text" DEFAULT 'text'::"text" NOT NULL,
    "ciphertext" "text" NOT NULL,
    "ciphertext_metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "delivered_at" timestamp with time zone,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "chat_messages_message_type_check" CHECK (("message_type" = ANY (ARRAY['text'::"text", 'image'::"text", 'voice'::"text", 'event'::"text", 'location'::"text"])))
);

ALTER TABLE "public"."chat_messages" OWNER TO "postgres";

COMMENT ON TABLE "public"."chat_messages" IS 'E2E-encrypted chat messages. Server stores ciphertext + protocol metadata only, never plaintext or keys.';

COMMENT ON COLUMN "public"."chat_messages"."ciphertext" IS 'Base64-encoded Signal Protocol message envelope (PreKeySignalMessage or SignalMessage).';

COMMENT ON COLUMN "public"."chat_messages"."ciphertext_metadata" IS 'Protocol bookkeeping only, e.g. {"signal_message_type": "prekey"|"whisper"}. Never content.';

CREATE TABLE IF NOT EXISTS "public"."chat_one_time_prekeys" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "key_id" integer NOT NULL,
    "public_key" "bytea" NOT NULL,
    "used_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

ALTER TABLE "public"."chat_one_time_prekeys" OWNER TO "postgres";

COMMENT ON TABLE "public"."chat_one_time_prekeys" IS 'One-time prekey pool for X3DH. Each row may be claimed (used_at set) exactly once via claim_one_time_prekey().';

CREATE TABLE IF NOT EXISTS "public"."chat_presence" (
    "user_id" "uuid" NOT NULL,
    "is_online" boolean DEFAULT false NOT NULL,
    "last_active_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

ALTER TABLE "public"."chat_presence" OWNER TO "postgres";

COMMENT ON TABLE "public"."chat_presence" IS 'Presence heartbeat per user. Read access is backend-mediated only, gated on profiles.share_active_status.';

CREATE TABLE IF NOT EXISTS "public"."chat_signed_prekeys" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "key_id" integer NOT NULL,
    "public_key" "bytea" NOT NULL,
    "signature" "bytea" NOT NULL,
    "rotated_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

ALTER TABLE "public"."chat_signed_prekeys" OWNER TO "postgres";

COMMENT ON TABLE "public"."chat_signed_prekeys" IS 'Rotating signed prekeys used in X3DH. Current key for a user = most recent row with rotated_at IS NULL.';

CREATE TABLE IF NOT EXISTS "public"."deleted_account_blocklist" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "phone_blind_index" "text" NOT NULL,
    "reason_code" "text" NOT NULL,
    "cooldown_expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "deleted_account_blocklist_reason_code_check" CHECK (("reason_code" = ANY (ARRAY['suspended'::"text", 'banned'::"text", 'restricted'::"text", 'unresolved_report'::"text"])))
);

ALTER TABLE ONLY "public"."deleted_account_blocklist" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."deleted_account_blocklist" OWNER TO "postgres";

COMMENT ON TABLE "public"."deleted_account_blocklist" IS 'Cooldown blocklist for phone numbers belonging to accounts that were flagged (suspended/banned/restricted/under active report review) at deletion time, to prevent immediate ban-evasion re-registration. Independent of users/auth.users by design - must survive account purge. Rows are purged by a daily expiry job (expire_blocklist_entries()) once cooldown_expires_at has passed.';

CREATE TABLE IF NOT EXISTS "public"."discovery_session_items" (
    "session_id" "uuid" NOT NULL,
    "position" integer NOT NULL,
    "candidate_id" "uuid" NOT NULL,
    "score" double precision NOT NULL,
    "orbit_tier" integer DEFAULT 0 NOT NULL,
    "x" double precision DEFAULT 0.0 NOT NULL,
    "y" double precision DEFAULT 0.0 NOT NULL,
    "music_match_grade" integer,
    "candidate_spotify_connected" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "discovery_session_items_position_check" CHECK (("position" >= 0))
);

ALTER TABLE ONLY "public"."discovery_session_items" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."discovery_session_items" OWNER TO "postgres";

COMMENT ON TABLE "public"."discovery_session_items" IS 'Ordered ranked candidates belonging to a discovery session snapshot.';

COMMENT ON COLUMN "public"."discovery_session_items"."position" IS 'Zero-based stable order position within the frozen ranked discovery session.';

COMMENT ON COLUMN "public"."discovery_session_items"."candidate_id" IS 'Profile id of the ranked candidate stored at the given session position.';

COMMENT ON COLUMN "public"."discovery_session_items"."score" IS 'Score assigned at snapshot creation time and retained for stable pagination.';

CREATE TABLE IF NOT EXISTS "public"."discovery_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "viewer_id" "uuid" NOT NULL,
    "tab" "text" NOT NULL,
    "filters" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "viewer_spotify_connected" boolean DEFAULT false NOT NULL,
    "last_cursor_position" integer DEFAULT 0 NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "discovery_sessions_filters_object_check" CHECK (("jsonb_typeof"("filters") = 'object'::"text")),
    CONSTRAINT "discovery_sessions_tab_check" CHECK (("tab" = ANY (ARRAY['Dating'::"text", 'Friends'::"text", 'Professional'::"text"])))
);

ALTER TABLE ONLY "public"."discovery_sessions" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."discovery_sessions" OWNER TO "postgres";

COMMENT ON TABLE "public"."discovery_sessions" IS 'Discovery session snapshots. All operations are backend-only (service_role). SELECT policy retained for potential future reads. Write policies were removed as dead code.';

COMMENT ON COLUMN "public"."discovery_sessions"."viewer_id" IS 'The user for whom the frozen discovery session was created.';

COMMENT ON COLUMN "public"."discovery_sessions"."filters" IS 'Normalized discovery filters captured when the session snapshot was created.';

COMMENT ON COLUMN "public"."discovery_sessions"."expires_at" IS 'UTC timestamp after which the discovery session should be treated as invalid and rebuilt.';

COMMENT ON COLUMN "public"."discovery_sessions"."last_cursor_position" IS 'Optional server-maintained pagination progress marker for debugging, analytics, or resumability.';

CREATE TABLE IF NOT EXISTS "public"."feedback_report_comments" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "report_id" "uuid" NOT NULL,
    "author_id" "uuid" NOT NULL,
    "body" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "feedback_report_comments_body_length_check" CHECK ((("char_length"(TRIM(BOTH FROM "body")) >= 1) AND ("char_length"(TRIM(BOTH FROM "body")) <= 3000)))
);

ALTER TABLE "public"."feedback_report_comments" OWNER TO "postgres";

COMMENT ON TABLE "public"."feedback_report_comments" IS 'Discussion thread on a feedback_reports ticket.';

CREATE TABLE IF NOT EXISTS "public"."feedback_report_status_history" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "report_id" "uuid" NOT NULL,
    "status" "text" NOT NULL,
    "note" "text",
    "changed_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "feedback_report_status_history_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'in_progress'::"text", 'resolved'::"text", 'closed'::"text"])))
);

ALTER TABLE "public"."feedback_report_status_history" OWNER TO "postgres";

COMMENT ON TABLE "public"."feedback_report_status_history" IS 'Append-only status timeline for feedback_reports, populated by trigger.';

CREATE TABLE IF NOT EXISTS "public"."feedback_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "query_type" "text" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "subject" "text" NOT NULL,
    "message" "text" NOT NULL,
    "attachment_paths" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "github_issue_url" "text",
    "platform" "text",
    "app_version" "text",
    "device_info" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "reviewed_by" "uuid",
    "reviewer_notes" "text",
    "reviewed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "feedback_reports_attachment_paths_limit_check" CHECK ((("array_length"("attachment_paths", 1) IS NULL) OR ("array_length"("attachment_paths", 1) <= 5))),
    CONSTRAINT "feedback_reports_device_info_object_check" CHECK (("jsonb_typeof"("device_info") = 'object'::"text")),
    CONSTRAINT "feedback_reports_github_url_format_check" CHECK ((("github_issue_url" IS NULL) OR ("github_issue_url" ~~ 'https://github.com/%'::"text"))),
    CONSTRAINT "feedback_reports_github_url_scope_check" CHECK ((("github_issue_url" IS NULL) OR ("query_type" = 'bug_report'::"text"))),
    CONSTRAINT "feedback_reports_message_length_check" CHECK ((("char_length"(TRIM(BOTH FROM "message")) >= 10) AND ("char_length"(TRIM(BOTH FROM "message")) <= 5000))),
    CONSTRAINT "feedback_reports_metadata_object_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "feedback_reports_platform_check" CHECK ((("platform" IS NULL) OR ("platform" = ANY (ARRAY['android'::"text", 'ios'::"text"])))),
    CONSTRAINT "feedback_reports_query_type_check" CHECK (("query_type" = ANY (ARRAY['help'::"text", 'feedback'::"text", 'bug_report'::"text", 'suspended'::"text", 'security'::"text", 'legal_grievance'::"text", 'other'::"text"]))),
    CONSTRAINT "feedback_reports_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'in_progress'::"text", 'resolved'::"text", 'closed'::"text"]))),
    CONSTRAINT "feedback_reports_subject_length_check" CHECK ((("char_length"(TRIM(BOTH FROM "subject")) >= 3) AND ("char_length"(TRIM(BOTH FROM "subject")) <= 150)))
);

ALTER TABLE "public"."feedback_reports" OWNER TO "postgres";

COMMENT ON TABLE "public"."feedback_reports" IS 'User-submitted Help, Feedback & Bug Report tickets. Status changes are logged to feedback_report_status_history via trigger.';

COMMENT ON COLUMN "public"."feedback_reports"."query_type" IS 'Ticket category: help, feedback, bug_report, suspended, security, legal_grievance, or other.';

COMMENT ON COLUMN "public"."feedback_reports"."github_issue_url" IS 'Optional linked GitHub issue, bug_report tickets only.';

COMMENT ON COLUMN "public"."feedback_reports"."attachment_paths" IS 'Object paths in the feedback_attachments storage bucket.';

COMMENT ON COLUMN "public"."feedback_reports"."status" IS 'Admin triage lifecycle: open -> in_progress -> resolved or closed.';

COMMENT ON COLUMN "public"."feedback_reports"."reviewed_by" IS 'Admin user who last changed the status.';

COMMENT ON COLUMN "public"."feedback_reports"."metadata" IS 'Auxiliary JSON context for internal review tooling.';

CREATE TABLE IF NOT EXISTS "public"."matches" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "liker_id" "uuid" NOT NULL,
    "liked_back_id" "uuid" NOT NULL,
    "tab" "text" DEFAULT 'Dating'::"text" NOT NULL,
    "unmatched_by" "uuid",
    "unmatched_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "matches_no_self_match" CHECK (("liker_id" <> "liked_back_id")),
    CONSTRAINT "matches_tab_check" CHECK (("tab" = ANY (ARRAY['Dating'::"text", 'Friends'::"text", 'Professional'::"text"])))
);

ALTER TABLE "public"."matches" OWNER TO "postgres";

COMMENT ON TABLE "public"."matches" IS 'Mutual like pairs. A row is inserted when user A likes back user B. unmatched_at marks dissolution.';

COMMENT ON COLUMN "public"."matches"."liker_id" IS 'User who sent the original like/superlike.';

COMMENT ON COLUMN "public"."matches"."liked_back_id" IS 'User who reciprocated the like.';

COMMENT ON COLUMN "public"."matches"."unmatched_at" IS 'Timestamp the match was dissolved; NULL means still active.';

COMMENT ON COLUMN "public"."matches"."unmatched_by" IS 'Which user dissolved the match.';

CREATE TABLE IF NOT EXISTS "public"."profile_age_change_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "changed_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

ALTER TABLE ONLY "public"."profile_age_change_log" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."profile_age_change_log" OWNER TO "postgres";

COMMENT ON TABLE "public"."profile_age_change_log" IS 'Append-only log of age changes, one row per change. Rolling-window eligibility = count of rows with changed_at > now() - interval ''365 days'' < 2. Deny-all client RLS - service_role backend access only, same pattern as profile_name_change_log.';

CREATE TABLE IF NOT EXISTS "public"."profile_discovery_actions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "target_id" "uuid" NOT NULL,
    "tab" "text",
    "action" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "seen_at" timestamp with time zone,
    "expires_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "profile_discovery_actions_action_check" CHECK (("action" = ANY (ARRAY['pass'::"text", 'like'::"text", 'superlike'::"text", 'hide'::"text", 'block'::"text"]))),
    CONSTRAINT "profile_discovery_actions_actor_target_check" CHECK (("actor_id" <> "target_id")),
    CONSTRAINT "profile_discovery_actions_expiry_check" CHECK (((("action" = 'pass'::"text") AND ("expires_at" IS NOT NULL)) OR (("action" = ANY (ARRAY['like'::"text", 'superlike'::"text", 'hide'::"text", 'block'::"text"])) AND ("expires_at" IS NULL)))),
    CONSTRAINT "profile_discovery_actions_inactive_state_check" CHECK ((("revoked_at" IS NULL) OR ("action" <> 'pass'::"text") OR ("revoked_at" <= "expires_at"))),
    CONSTRAINT "profile_discovery_actions_metadata_object_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "profile_discovery_actions_tab_action_check" CHECK (((("action" = 'block'::"text") AND ("tab" IS NULL)) OR (("action" = ANY (ARRAY['pass'::"text", 'like'::"text", 'superlike'::"text", 'hide'::"text"])) AND ("tab" IS NOT NULL)))),
    CONSTRAINT "profile_discovery_actions_tab_check" CHECK (("tab" = ANY (ARRAY['Dating'::"text", 'Friends'::"text", 'Professional'::"text"])))
);

ALTER TABLE "public"."profile_discovery_actions" OWNER TO "postgres";

COMMENT ON TABLE "public"."profile_discovery_actions" IS 'Discovery action history (pass, like, superlike, hide, block). All writes are backend-only via record_discovery_action(). The SELECT policy is retained. Write policies (INSERT/UPDATE/DELETE) were removed as dead code — service_role bypasses RLS for all action writes.';

COMMENT ON COLUMN "public"."profile_discovery_actions"."actor_id" IS 'The viewer who performed the action.';

COMMENT ON COLUMN "public"."profile_discovery_actions"."target_id" IS 'The candidate profile the action was applied to.';

COMMENT ON COLUMN "public"."profile_discovery_actions"."tab" IS 'Discovery context for tab-scoped actions. Must be NULL for block and non-NULL for all other actions.';

COMMENT ON COLUMN "public"."profile_discovery_actions"."action" IS 'Action type: pass, like, superlike, hide, or block.';

COMMENT ON COLUMN "public"."profile_discovery_actions"."expires_at" IS 'UTC expiry timestamp for temporary pass actions. Permanent actions must keep this NULL.';

COMMENT ON COLUMN "public"."profile_discovery_actions"."revoked_at" IS 'UTC timestamp indicating the action has been revoked while preserving the audit trail. NULL means the row is currently active.';

COMMENT ON COLUMN "public"."profile_discovery_actions"."metadata" IS 'Optional JSON object for auxiliary non-authoritative discovery context.';

COMMENT ON COLUMN "public"."profile_discovery_actions"."seen_at" IS 'Timestamp when the target user viewed this like/superlike. NULL means unseen.';

CREATE TABLE IF NOT EXISTS "public"."profile_name_change_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "changed_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

ALTER TABLE ONLY "public"."profile_name_change_log" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."profile_name_change_log" OWNER TO "postgres";

COMMENT ON TABLE "public"."profile_name_change_log" IS 'Append-only log of display-name changes, one row per change. Rolling-window eligibility = count of rows with changed_at > now() - interval ''365 days'' < 2. Deny-all client RLS - service_role backend access only, same pattern as spotify_connections.';

CREATE TABLE IF NOT EXISTS "public"."profile_pseudonym_map" (
    "user_id" "uuid" NOT NULL,
    "pseudonym_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

ALTER TABLE ONLY "public"."profile_pseudonym_map" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."profile_pseudonym_map" OWNER TO "postgres";

COMMENT ON TABLE "public"."profile_pseudonym_map" IS 'Private identity bridge mapping canonical profile ids to stable pseudonym ids for anonymized downstream processing.';

CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "age" integer NOT NULL,
    "search_bucket" "text" DEFAULT 'NB'::"text" NOT NULL,
    "pronouns" "bytea",
    "display_gender" "bytea",
    "display_sexuality" "bytea",
    "campus_name" "bytea",
    "campus_branch" "bytea",
    "campus_year" integer,
    "bio" "bytea",
    "profile_pic" "bytea",
    "normal_pics" "bytea",
    "hometown" "bytea",
    "current_place" "bytea",
    "is_dating_active" boolean DEFAULT false NOT NULL,
    "is_friends_active" boolean DEFAULT false NOT NULL,
    "is_professional_active" boolean DEFAULT false NOT NULL,
    "dating_target_buckets" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "friends_target_buckets" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "professional_target_buckets" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "dating_for" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "lifestyle" "bytea",
    "drinking" "bytea",
    "smoking" "bytea",
    "pets" "bytea",
    "children_plans" "bytea",
    "religious_beliefs" "bytea",
    "partner_values" "bytea",
    "value_dimensions" "bytea",
    "interests" "bytea",
    "sub_interests" "bytea",
    "activities" "bytea",
    "causes_supported" "bytea",
    "languages" "bytea",
    "tech_skills" "bytea",
    "role_at" "bytea",
    "role_type" "bytea",
    "looking_for" "bytea",
    "ai_vibe_tags" "bytea",
    "top_artists" "bytea",
    "artist_affinity" "bytea",
    "genre_affinity" "bytea",
    "campus_branch_blind_index" "text",
    "smoking_blind_index" "text",
    "drinking_blind_index" "text",
    "children_plans_blind_index" "bytea",
    "religious_beliefs_blind_index" "bytea",
    "hidden_profile_fields" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "share_active_status" boolean DEFAULT true NOT NULL,
    "share_read_receipts" boolean DEFAULT true NOT NULL,
    "email_notify_matches" boolean DEFAULT true NOT NULL,
    "email_notify_messages" boolean DEFAULT true NOT NULL,
    "email_notify_digest" boolean DEFAULT true NOT NULL,
    "email_notify_product_updates" boolean DEFAULT true NOT NULL,
    "email_notify_promotions" boolean DEFAULT true NOT NULL,
    "has_imported_data" boolean DEFAULT false NOT NULL,
    "import_sync_code" "text",
    "import_sync_expires_at" timestamp with time zone,
    "is_deactivated" boolean DEFAULT false NOT NULL,
    "deactivated_at" timestamp with time zone,
    "age_updated_at" timestamp with time zone,
    "music_taste_synced_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "check_search_bucket" CHECK (("search_bucket" = ANY (ARRAY['M'::"text", 'F'::"text", 'NB'::"text"]))),
    CONSTRAINT "profiles_age_check" CHECK ((("age" >= 18) AND ("age" <= 80))),
    CONSTRAINT "profiles_dating_target_buckets_check" CHECK ("public"."validate_array_values"("dating_target_buckets", ARRAY['M'::"text", 'F'::"text", 'NB'::"text", 'Open'::"text"])),
    CONSTRAINT "profiles_friends_target_buckets_check" CHECK ("public"."validate_array_values"("friends_target_buckets", ARRAY['M'::"text", 'F'::"text", 'NB'::"text", 'Open'::"text"])),
    CONSTRAINT "profiles_name_check" CHECK ((("char_length"("name") >= 2) AND ("char_length"("name") <= 100))),
    CONSTRAINT "profiles_professional_target_buckets_check" CHECK ("public"."validate_array_values"("professional_target_buckets", ARRAY['M'::"text", 'F'::"text", 'NB'::"text", 'Open'::"text"])),
    CONSTRAINT "profiles_year_check" CHECK ((("campus_year" >= 1) AND ("campus_year" <= 5)))
);

ALTER TABLE "public"."profiles" OWNER TO "postgres";

COMMENT ON TABLE "public"."profiles" IS 'Canonical application profile table. All mutations (INSERT, UPDATE, DELETE) are strictly server-orchestrated via FastAPI backend (service_role client) to enforce Field-Level Encryption (FLE), GDPR Art 9 special category consent, and invariant protections. Direct client reads (SELECT) are guarded by RLS for authorized user profile retrieval and existence checks.';

COMMENT ON COLUMN "public"."profiles"."campus_branch" IS 'Encrypted campus branch / major of the user. Blind index in campus_branch_blind_index.';

COMMENT ON COLUMN "public"."profiles"."is_deactivated" IS 'Server-maintained soft-deactivation flag. Deactivated profiles are hidden from normal client reads/updates via RLS.';

COMMENT ON COLUMN "public"."profiles"."deactivated_at" IS 'UTC timestamp derived from changes to is_deactivated; set on deactivation and cleared on reactivation.';

COMMENT ON COLUMN "public"."profiles"."display_gender" IS 'Encrypted display-gender field stored as ciphertext (BYTEA).';

COMMENT ON COLUMN "public"."profiles"."role_at" IS 'Encrypted company or institute name for professional context.';

COMMENT ON COLUMN "public"."profiles"."activities" IS 'Encrypted match-context payload stored as ciphertext (BYTEA); plaintext array structure is handled in trusted backend code before encryption.';

COMMENT ON COLUMN "public"."profiles"."value_dimensions" IS 'Encrypted structured preference/value scores stored as ciphertext (BYTEA); plaintext JSON validation must happen before encryption in trusted backend code.';

COMMENT ON COLUMN "public"."profiles"."campus_branch_blind_index" IS 'HMAC-SHA256 deterministic blind hash for encrypted campus branch queries.';

COMMENT ON COLUMN "public"."profiles"."smoking_blind_index" IS 'HMAC-SHA256 deterministic blind hash for encrypted smoking lookups.';

COMMENT ON COLUMN "public"."profiles"."drinking_blind_index" IS 'HMAC-SHA256 deterministic blind hash for encrypted drinking lookups.';

COMMENT ON COLUMN "public"."profiles"."is_friends_active" IS 'Server-maintained flag: profile is active in Friends discovery.';

COMMENT ON COLUMN "public"."profiles"."is_professional_active" IS 'Server-maintained flag: profile is active in Professional discovery.';

COMMENT ON COLUMN "public"."profiles"."is_dating_active" IS 'Server-maintained flag: profile is active in Dating discovery.';

COMMENT ON COLUMN "public"."profiles"."dating_target_buckets" IS 'Tab-specific outbound discovery preference buckets for Dating.';

COMMENT ON COLUMN "public"."profiles"."friends_target_buckets" IS 'Tab-specific outbound discovery preference buckets for Friends.';

COMMENT ON COLUMN "public"."profiles"."professional_target_buckets" IS 'Tab-specific outbound discovery preference buckets for Professional.';

COMMENT ON COLUMN "public"."profiles"."has_imported_data" IS 'Set to TRUE after a successful cross-flavor import handshake. Prevents re-import.';

COMMENT ON COLUMN "public"."profiles"."import_sync_code" IS 'Active 6-character alphanumeric export code generated by a flavor account for one-time data transfer to the main nexus account.';

COMMENT ON COLUMN "public"."profiles"."import_sync_expires_at" IS 'UTC expiry timestamp for the active import_sync_code. The backend rejects codes past this time.';

COMMENT ON COLUMN "public"."profiles"."profile_pic" IS 'Encrypted object storage path string representing the mandatory avatar image token.';

COMMENT ON COLUMN "public"."profiles"."normal_pics" IS 'Encrypted JSON string array matching 1-4 validation bounding paths.';

COMMENT ON COLUMN "public"."profiles"."campus_name" IS 'Encrypted campus/institute name of the user.';

COMMENT ON COLUMN "public"."profiles"."current_place" IS 'Encrypted Current Place of the user profile.';

COMMENT ON COLUMN "public"."profiles"."pronouns" IS 'Encrypted pronouns of the user profile.';

COMMENT ON COLUMN "public"."profiles"."bio" IS 'Encrypted user bio/self-description, max 1000 characters.';

COMMENT ON COLUMN "public"."profiles"."search_bucket" IS 'Allowed inbound discovery category (single value) used to route this profile.';

COMMENT ON COLUMN "public"."profiles"."dating_for" IS 'Predefined terms indicating what the user is dating for (e.g. short, long, fling, hookups).';

COMMENT ON COLUMN "public"."profiles"."children_plans_blind_index" IS 'HMAC-SHA256 of decrypted children_plans value for equality filtering without decryption.';

COMMENT ON COLUMN "public"."profiles"."religious_beliefs_blind_index" IS 'HMAC-SHA256 of decrypted religious_beliefs value for equality filtering without decryption.';

COMMENT ON COLUMN "public"."profiles"."role_type" IS 'Encrypted JSON array of predefined role-type tags (e.g. Founder, Engineer). Filtered post-fetch via list-overlap; no blind index needed.';

COMMENT ON COLUMN "public"."profiles"."hidden_profile_fields" IS 'Fields the profile owner has chosen to hide from other users. Used only for presentation; scoring uses the full profile.';

COMMENT ON COLUMN "public"."profiles"."share_active_status" IS 'Whether this user allows matches to see "Active now" / "last active" presence.';

COMMENT ON COLUMN "public"."profiles"."share_read_receipts" IS 'Whether this user sends read receipts for messages they read.';

COMMENT ON COLUMN "public"."profiles"."email_notify_matches" IS 'Whether to email the user about new matches and likes.';

COMMENT ON COLUMN "public"."profiles"."email_notify_messages" IS 'Whether to email the user about new chat messages.';

COMMENT ON COLUMN "public"."profiles"."email_notify_digest" IS 'Whether to email the user a periodic activity digest.';

COMMENT ON COLUMN "public"."profiles"."email_notify_product_updates" IS 'Whether to email the user about product news and feature updates.';

COMMENT ON COLUMN "public"."profiles"."email_notify_promotions" IS 'Whether to email the user promotions and offers.';

COMMENT ON COLUMN "public"."profiles"."artist_affinity" IS 'Encrypted JSON object {lowercased_artist_name: weight in (0,1]}, <=50 entries. Blend of /me/top/artists rank and owned/collaborative playlist track frequency. Matching-engine input only - must never be selected into fetch_peer_profile_by_id, fetch_discovery_node_detail, or any other peer-facing query.';

COMMENT ON COLUMN "public"."profiles"."music_taste_synced_at" IS 'UTC timestamp of the last successful Spotify sync (artist_affinity + top_artists + spotify_playlists). NULL if never synced under this flow.';

COMMENT ON COLUMN "public"."profiles"."age_updated_at" IS 'UTC timestamp of the most recent age change. Age may only change again 365 days after this. Set at onboarding (first value counts as change #1) and by apply_age_change(). Never client-writable - mutations are backend/service_role-only.';

COMMENT ON COLUMN "public"."profiles"."genre_affinity" IS 'Encrypted JSON object {genre_name: weight in (0,1]}, <=30 entries. Weighted genre signal blended from /me/top/artists genres, weighted by each artist''s rank/frequency in artist_affinity. Matching-engine input only - must never be selected into fetch_peer_profile_by_id, fetch_discovery_node_detail, or any other peer-facing query.';

CREATE TABLE IF NOT EXISTS "public"."safety_alerts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "session_id" "uuid",
    "alert_type" "text" NOT NULL,
    "current_location" "bytea",
    "contacts_notified" integer DEFAULT 0 NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "safety_alerts_alert_type_check" CHECK (("alert_type" = ANY (ARRAY['sos_silent'::"text", 'sos_loud'::"text", 'inform'::"text"])))
);

ALTER TABLE "public"."safety_alerts" OWNER TO "postgres";

COMMENT ON TABLE "public"."safety_alerts" IS 'Audit trail of SOS/inform triggers and how many trusted contacts were notified.';

COMMENT ON COLUMN "public"."safety_alerts"."current_location" IS 'Encrypted geolocation JSON object.';

CREATE TABLE IF NOT EXISTS "public"."safety_contact_notices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "phone_blind_index" "text" NOT NULL,
    "first_notified_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "self_removed_at" timestamp with time zone
);

ALTER TABLE ONLY "public"."safety_contact_notices" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."safety_contact_notices" OWNER TO "postgres";

COMMENT ON TABLE "public"."safety_contact_notices" IS 'One row per (user, trusted-contact phone) pair ever synced. self_removed_at set means that phone permanently opted out of being this user''s trusted contact and sync_safety_contacts must not silently re-add it.';

CREATE TABLE IF NOT EXISTS "public"."safety_contacts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "bytea" NOT NULL,
    "phone" "bytea" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

ALTER TABLE "public"."safety_contacts" OWNER TO "postgres";

COMMENT ON TABLE "public"."safety_contacts" IS 'Server-side mirror of a user''s up-to-3 trusted contacts, synced from the device on every add/remove so alerts can be sent without the device online.';

COMMENT ON COLUMN "public"."safety_contacts"."name" IS 'Encrypted name.';

COMMENT ON COLUMN "public"."safety_contacts"."phone" IS 'Encrypted phone.';

CREATE TABLE IF NOT EXISTS "public"."safety_evidence" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "alert_id" "uuid" NOT NULL,
    "content_type" "text" NOT NULL,
    "storage_path" "text" NOT NULL,
    "media_key_base64" "text" NOT NULL,
    "duration_seconds" numeric,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "safety_evidence_content_type_check" CHECK (("content_type" = ANY (ARRAY['video'::"text", 'audio'::"text"])))
);

ALTER TABLE "public"."safety_evidence" OWNER TO "postgres";

COMMENT ON TABLE "public"."safety_evidence" IS 'Encrypted Silent SOS recording segments (video/audio). storage_path points into the private safety_evidence bucket; media_key_base64 is the AES-GCM key escrowed for future authenticated trusted-contact access. Note: Plaintext escrow deviates from pure E2E posture, carrying DB compromise / service-role exposure risk.';

CREATE TABLE IF NOT EXISTS "public"."safety_sessions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    "label" "text",
    "interval_seconds" integer NOT NULL,
    "battery_percent" smallint,
    "connection_type" "text",
    "event_context" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "escalations_sent" smallint DEFAULT 0 NOT NULL,
    "escalation_cancel_reason" "text",
    "escalation_cancel_note" "text",
    "next_checkin_at" timestamp with time zone,
    "last_heartbeat_at" timestamp with time zone,
    "last_escalated_at" timestamp with time zone,
    "escalation_cancelled_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "safety_sessions_escalation_cancel_reason_check" CHECK ((("escalation_cancel_reason" IS NULL) OR ("escalation_cancel_reason" = ANY (ARRAY['safe'::"text", 'other'::"text"])))),
    CONSTRAINT "safety_sessions_event_context_object_check" CHECK (("jsonb_typeof"("event_context") = 'object'::"text")),
    CONSTRAINT "safety_sessions_interval_positive_check" CHECK (("interval_seconds" > 0)),
    CONSTRAINT "safety_sessions_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'ended'::"text"])))
);

ALTER TABLE "public"."safety_sessions" OWNER TO "postgres";

COMMENT ON TABLE "public"."safety_sessions" IS 'Mirrors the on-device recurring Meetup Safety check-in loop state, for alert message context and future server-side escalation.';

COMMENT ON COLUMN "public"."safety_sessions"."event_context" IS 'Optional linked chat event details (venue, tab, scheduled time) for richer alert copy.';

COMMENT ON COLUMN "public"."safety_sessions"."last_heartbeat_at" IS 'Last time the device successfully checked in or started this session.';

COMMENT ON COLUMN "public"."safety_sessions"."battery_percent" IS 'Device battery percentage as of the last heartbeat, 0-100. Included in escalation SMS so trusted contacts can tell "phone likely died" from "something happened".';

COMMENT ON COLUMN "public"."safety_sessions"."connection_type" IS 'Device connection type as of the last heartbeat (wifi/cellular/offline) - the honest cross-platform substitute for signal strength, which iOS does not expose to third-party apps.';

COMMENT ON COLUMN "public"."safety_sessions"."escalations_sent" IS 'How many "device unreachable" alerts have fired for the current missed-checkin streak. Capped at 3; resets to 0 on the next successful heartbeat.';

COMMENT ON COLUMN "public"."safety_sessions"."escalation_cancelled_at" IS 'Set when a trusted contact taps the cancel link in an escalation SMS, stopping further escalations for this session.';

COMMENT ON COLUMN "public"."safety_sessions"."escalation_cancel_reason" IS 'Why a trusted contact cancelled further escalation: safe (they confirmed the user is fine) or other (free-text in escalation_cancel_note).';

CREATE TABLE IF NOT EXISTS "public"."spotify_connections" (
    "user_id" "uuid" NOT NULL,
    "spotify_user_id" "text" NOT NULL,
    "refresh_token" "bytea" NOT NULL,
    "granted_scopes" "text" DEFAULT ''::"text" NOT NULL,
    "last_sync_status" "text",
    "last_sync_error" "text",
    "last_synced_at" timestamp with time zone,
    "disconnected_at" timestamp with time zone,
    "connected_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

ALTER TABLE ONLY "public"."spotify_connections" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."spotify_connections" OWNER TO "postgres";

COMMENT ON TABLE "public"."spotify_connections" IS 'Encrypted Spotify OAuth refresh tokens enabling on-demand/periodic resync without re-running OAuth. Deny-all RLS - service_role backend access only.';

COMMENT ON COLUMN "public"."spotify_connections"."refresh_token" IS 'Fernet-encrypted (MultiFernet, same scheme as profiles PII columns) Spotify refresh token.';

CREATE TABLE IF NOT EXISTS "public"."spotify_playlists" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "spotify_playlist_id" "text" NOT NULL,
    "name" "bytea" NOT NULL,
    "is_collaborative" boolean DEFAULT false NOT NULL,
    "track_count" integer DEFAULT 0 NOT NULL,
    "tracks" "bytea",
    "synced_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

ALTER TABLE "public"."spotify_playlists" OWNER TO "postgres";

COMMENT ON TABLE "public"."spotify_playlists" IS 'Playlists the user owns or collaborates on (Get Playlist Items 403s for merely-followed playlists). name/tracks encrypted. PRIVATE - only ever served to the owner via GET /api/v1/spotify/playlists; never joined into discovery/likes/orbit responses.';

COMMENT ON COLUMN "public"."spotify_playlists"."tracks" IS 'Fernet-encrypted JSON array of {spotify_track_id, name, artists: [names]} - names only, no audio/images/preview URLs/popularity, per Spotify Developer Policy.';

CREATE TABLE IF NOT EXISTS "public"."terms_consent_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "category" "text" NOT NULL,
    "granted" boolean NOT NULL,
    "terms_version" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "terms_consent_log_category_check" CHECK (("category" = ANY (ARRAY['general'::"text", 'special_category'::"text", 'safety_data'::"text"])))
);

ALTER TABLE ONLY "public"."terms_consent_log" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."terms_consent_log" OWNER TO "postgres";

COMMENT ON TABLE "public"."terms_consent_log" IS 'Append-only audit trail of every consent accept/decline event across all three categories - the durable evidence trail for DPDP/GDPR consent proof. Deny-all client RLS, service_role backend access only, same pattern as profile_age_change_log.';

CREATE TABLE IF NOT EXISTS "public"."user_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "fcm_token" "text" NOT NULL,
    "platform" "text",
    "device_id" "text",
    "is_active" boolean DEFAULT true NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE "public"."user_devices" OWNER TO "postgres";

COMMENT ON TABLE "public"."user_devices" IS 'Per-device push notification registrations for users.';

COMMENT ON COLUMN "public"."user_devices"."id" IS 'Primary key for the device registration row.';

COMMENT ON COLUMN "public"."user_devices"."user_id" IS 'Owning user for this device registration.';

COMMENT ON COLUMN "public"."user_devices"."platform" IS 'Client platform such as ios, android, or web.';

COMMENT ON COLUMN "public"."user_devices"."device_id" IS 'Client-supplied device or installation identifier.';

COMMENT ON COLUMN "public"."user_devices"."fcm_token" IS 'Firebase Cloud Messaging token for this app installation.';

COMMENT ON COLUMN "public"."user_devices"."is_active" IS 'Whether this device registration should currently receive pushes.';

COMMENT ON COLUMN "public"."user_devices"."last_seen_at" IS 'Last heartbeat or refresh time from the client.';

COMMENT ON COLUMN "public"."user_devices"."created_at" IS 'Row creation timestamp.';

COMMENT ON COLUMN "public"."user_devices"."updated_at" IS 'Row update timestamp.';

CREATE TABLE IF NOT EXISTS "public"."user_moderation_actions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "action_type" "text" NOT NULL,
    "reason_code" "text",
    "private_notes" "text",
    "evidence_json" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "created_by" "uuid",
    "expires_at" timestamp with time zone,
    "revoked_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_moderation_actions_action_type_check" CHECK (("action_type" = ANY (ARRAY['warn'::"text", 'restrict'::"text", 'suspend'::"text", 'ban'::"text", 'unsuspend'::"text", 'clear'::"text"]))),
    CONSTRAINT "user_moderation_actions_expiry_check" CHECK ((("expires_at" IS NULL) OR ("expires_at" >= "created_at"))),
    CONSTRAINT "user_moderation_actions_revoked_check" CHECK ((("revoked_at" IS NULL) OR ("revoked_at" >= "created_at")))
);

ALTER TABLE "public"."user_moderation_actions" OWNER TO "postgres";

COMMENT ON TABLE "public"."user_moderation_actions" IS 'Historical moderation actions applied to a user account.';

COMMENT ON COLUMN "public"."user_moderation_actions"."id" IS 'Primary key for the moderation action row.';

COMMENT ON COLUMN "public"."user_moderation_actions"."user_id" IS 'User affected by the moderation action.';

COMMENT ON COLUMN "public"."user_moderation_actions"."action_type" IS 'Action type such as warn, restrict, suspend, ban, unsuspend, or clear.';

COMMENT ON COLUMN "public"."user_moderation_actions"."reason_code" IS 'Compact moderation reason code.';

COMMENT ON COLUMN "public"."user_moderation_actions"."private_notes" IS 'Internal-only moderator notes.';

COMMENT ON COLUMN "public"."user_moderation_actions"."evidence_json" IS 'Structured evidence payload for internal review.';

COMMENT ON COLUMN "public"."user_moderation_actions"."created_by" IS 'Moderator or system actor that created the action.';

COMMENT ON COLUMN "public"."user_moderation_actions"."created_at" IS 'Action creation timestamp.';

COMMENT ON COLUMN "public"."user_moderation_actions"."expires_at" IS 'Optional action expiry timestamp.';

COMMENT ON COLUMN "public"."user_moderation_actions"."revoked_at" IS 'Optional timestamp when the action was revoked.';

CREATE TABLE IF NOT EXISTS "public"."user_reports" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "reporter_id" "uuid" NOT NULL,
    "target_id" "uuid" NOT NULL,
    "tab" "text",
    "reason" "text" NOT NULL,
    "reason_detail" "text",
    "review_status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "reviewed_by" "uuid",
    "reviewer_notes" "text",
    "reviewed_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "user_reports_actor_target_check" CHECK (("reporter_id" <> "target_id")),
    CONSTRAINT "user_reports_metadata_object_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "user_reports_other_reason_check" CHECK ((("reason" <> 'other'::"text") OR (("reason_detail" IS NOT NULL) AND ("length"(TRIM(BOTH FROM "reason_detail")) > 0)))),
    CONSTRAINT "user_reports_reason_check" CHECK (("reason" = ANY (ARRAY['scam'::"text", 'bot'::"text", 'harassment'::"text", 'inappropriate'::"text", 'spam'::"text", 'underage'::"text", 'other'::"text"]))),
    CONSTRAINT "user_reports_review_status_check" CHECK (("review_status" = ANY (ARRAY['pending'::"text", 'reviewed'::"text", 'actioned'::"text", 'dismissed'::"text"]))),
    CONSTRAINT "user_reports_tab_check" CHECK (("tab" = ANY (ARRAY['Dating'::"text", 'Friends'::"text", 'Professional'::"text"])))
);

ALTER TABLE "public"."user_reports" OWNER TO "postgres";

COMMENT ON TABLE "public"."user_reports" IS 'User-generated reports against other profiles. Each report triggers a mutual block in profile_discovery_actions. Admin-reviewable via review_status.';

COMMENT ON COLUMN "public"."user_reports"."reporter_id" IS 'User who filed the report.';

COMMENT ON COLUMN "public"."user_reports"."target_id" IS 'Profile being reported.';

COMMENT ON COLUMN "public"."user_reports"."tab" IS 'Discovery tab context at the time of report.';

COMMENT ON COLUMN "public"."user_reports"."reason" IS 'Structured reason code for admin triage.';

COMMENT ON COLUMN "public"."user_reports"."reason_detail" IS 'Free-text elaboration; required when reason is other.';

COMMENT ON COLUMN "public"."user_reports"."review_status" IS 'Admin review lifecycle: pending → reviewed → actioned or dismissed.';

COMMENT ON COLUMN "public"."user_reports"."reviewed_by" IS 'Admin user who reviewed this report.';

COMMENT ON COLUMN "public"."user_reports"."reviewed_at" IS 'Timestamp the report was reviewed.';

COMMENT ON COLUMN "public"."user_reports"."reviewer_notes" IS 'Internal notes from the reviewing admin.';

COMMENT ON COLUMN "public"."user_reports"."created_at" IS 'Row creation timestamp.';

COMMENT ON COLUMN "public"."user_reports"."metadata" IS 'Auxiliary JSON context for internal review tooling.';

CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "app_variant" "text" DEFAULT 'nexus'::"text" NOT NULL,
    "mobile" "bytea",
    "mobile_blind_index" "text",
    "mobile_verified_at" timestamp with time zone,
    "accepted_terms_version" "text",
    "terms_accepted_at" timestamp with time zone,
    "special_category_consent_version" "text",
    "special_category_consent_at" timestamp with time zone,
    "safety_data_consent_version" "text",
    "safety_data_consent_at" timestamp with time zone,
    "is_active" boolean DEFAULT true NOT NULL,
    "is_suspended" boolean DEFAULT false NOT NULL,
    "suspended_until" timestamp with time zone,
    "moderation_status" "text" DEFAULT 'clear'::"text" NOT NULL,
    "moderation_reason_code" "text",
    "moderated_at" timestamp with time zone,
    "deletion_flagged_reason_code" "text",
    "deletion_requested_at" timestamp with time zone,
    "scheduled_purge_at" timestamp with time zone,
    "purged_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "users_app_variant_check" CHECK (("app_variant" = ANY (ARRAY['nexus'::"text", 'nexus_mec'::"text"]))),
    CONSTRAINT "users_deletion_flagged_reason_code_check" CHECK ((("deletion_flagged_reason_code" IS NULL) OR ("deletion_flagged_reason_code" = ANY (ARRAY['suspended'::"text", 'banned'::"text", 'restricted'::"text", 'unresolved_report'::"text"])))),
    CONSTRAINT "users_deletion_pair_check" CHECK (((("deletion_requested_at" IS NULL) AND ("scheduled_purge_at" IS NULL)) OR (("deletion_requested_at" IS NOT NULL) AND ("scheduled_purge_at" IS NOT NULL)))),
    CONSTRAINT "users_moderation_status_check" CHECK (("moderation_status" = ANY (ARRAY['clear'::"text", 'review'::"text", 'restricted'::"text", 'banned'::"text"]))),
    CONSTRAINT "users_suspension_consistency_check" CHECK (((("is_suspended" = false) AND ("suspended_until" IS NULL)) OR ("is_suspended" = true))),
    CONSTRAINT "users_terms_pair_check" CHECK (((("accepted_terms_version" IS NULL) AND ("terms_accepted_at" IS NULL)) OR (("accepted_terms_version" IS NOT NULL) AND ("terms_accepted_at" IS NOT NULL)))),
    CONSTRAINT "users_terms_version_numeric_check" CHECK ((("accepted_terms_version" IS NULL) OR ("accepted_terms_version" ~ '^[0-9]+$'::"text")))
);

ALTER TABLE "public"."users" OWNER TO "postgres";

COMMENT ON TABLE "public"."users" IS 'App-managed account data keyed to auth.users.';

COMMENT ON COLUMN "public"."users"."id" IS 'Primary key matching auth.users.id.';

COMMENT ON COLUMN "public"."users"."accepted_terms_version" IS 'Single current terms version accepted by the user.';

COMMENT ON COLUMN "public"."users"."terms_accepted_at" IS 'Timestamp when the current terms version was accepted.';

COMMENT ON COLUMN "public"."users"."is_active" IS 'General account availability flag for app access.';

COMMENT ON COLUMN "public"."users"."is_suspended" IS 'Whether the account is currently suspended.';

COMMENT ON COLUMN "public"."users"."suspended_until" IS 'Optional suspension expiry time; null can represent indefinite suspension.';

COMMENT ON COLUMN "public"."users"."moderation_status" IS 'Current moderation state: clear, review, restricted, or banned.';

COMMENT ON COLUMN "public"."users"."moderated_at" IS 'Timestamp of the latest moderation status change.';

COMMENT ON COLUMN "public"."users"."moderation_reason_code" IS 'Compact internal reason code for the latest moderation state.';

COMMENT ON COLUMN "public"."users"."created_at" IS 'Row creation timestamp.';

COMMENT ON COLUMN "public"."users"."updated_at" IS 'Row update timestamp.';

COMMENT ON COLUMN "public"."users"."app_variant" IS 'Flavor identifier for this account. Controls which variant-specific UI and onboarding fields apply. Maintained by the backend and not editable by the client.';

COMMENT ON COLUMN "public"."users"."mobile" IS 'Encrypted mobile number, verified via app/core/account_phone_otp.py + the /api/v1/user/phone/otp endpoints. Independent of Supabase Auth (Phone provider disabled) - never written by an auth.users trigger. Backend/service_role-only.';

COMMENT ON COLUMN "public"."users"."mobile_verified_at" IS 'UTC timestamp the mobile number was last verified via the account phone OTP flow. NULL if never verified.';

COMMENT ON COLUMN "public"."users"."mobile_blind_index" IS 'Deterministic HMAC-SHA256 (compute_blind_index) of the verified mobile number, for exact-match lookup only - the encrypted mobile column itself cannot be queried by equality. Backend/service_role-only, written only by set_verified_mobile().';

COMMENT ON COLUMN "public"."users"."deletion_requested_at" IS 'Set when the user completes the delete-account confirmation flow (OTP + typed DELETE). NULL means no pending deletion. Backend/service_role-only.';

COMMENT ON COLUMN "public"."users"."scheduled_purge_at" IS 'deletion_requested_at + account_deletion_grace_period_days. The daily purge job anonymizes any row past this timestamp with purged_at still NULL.';

COMMENT ON COLUMN "public"."users"."deletion_flagged_reason_code" IS 'Frozen at request time: NULL for a good-standing account, otherwise the reason moderation_status/is_suspended/an unresolved user_reports row was flagged (banned/restricted/suspended/unresolved_report). Read (not recomputed) by the purge job, and written verbatim as deleted_account_blocklist.reason_code when non-NULL.';

COMMENT ON COLUMN "public"."users"."purged_at" IS 'Set by the Tier-1 purge job once anonymization has run. Prevents double-purge, distinguishes "purged" from "never requested", and starts the Tier-2 long-tail retention clock.';

COMMENT ON COLUMN "public"."users"."special_category_consent_version" IS 'Terms version the user gave explicit consent to sexual-orientation/religious-belief processing under (GDPR Art 9). NULL means never consented. Mandatory to use the app, same gate as accepted_terms_version.';

COMMENT ON COLUMN "public"."users"."safety_data_consent_version" IS 'Terms version the user consented to Meetup Safety/SOS/Digital Witness location-data processing under. NULL means not consented (or since revoked) - optional, independently toggleable, gates only the safety-feature surfaces, never general app access.';

CREATE TABLE IF NOT EXISTS "public"."vector_profiles" (
    "pseudonym_id" "uuid" NOT NULL,
    "bio_embedding" "public"."vector"(384),
    "career_embedding" "public"."vector"(384),
    "identity_embedding" "public"."vector"(384),
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);

ALTER TABLE ONLY "public"."vector_profiles" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."vector_profiles" OWNER TO "postgres";

COMMENT ON TABLE "public"."vector_profiles" IS 'Anonymized user embeddings keyed by pseudonym_id. Protected by forced deny-all RLS and intended for privileged backend access only.';

-- ==========================================================
-- SECTION 4: PRIMARY KEYS & UNIQUE CONSTRAINTS
-- ==========================================================

ALTER TABLE ONLY "public"."account_history_archive"
    ADD CONSTRAINT "account_history_archive_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."chat_conversations"
    ADD CONSTRAINT "chat_conversations_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."chat_conversations"
    ADD CONSTRAINT "chat_conversations_unique_match" UNIQUE ("match_id");

ALTER TABLE ONLY "public"."chat_events"
    ADD CONSTRAINT "chat_events_message_id_key" UNIQUE ("message_id");

ALTER TABLE ONLY "public"."chat_events"
    ADD CONSTRAINT "chat_events_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."chat_identity_keys"
    ADD CONSTRAINT "chat_identity_keys_pkey" PRIMARY KEY ("user_id");

ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."chat_one_time_prekeys"
    ADD CONSTRAINT "chat_one_time_prekeys_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."chat_one_time_prekeys"
    ADD CONSTRAINT "chat_one_time_prekeys_unique_key_id" UNIQUE ("user_id", "key_id");

ALTER TABLE ONLY "public"."chat_presence"
    ADD CONSTRAINT "chat_presence_pkey" PRIMARY KEY ("user_id");

ALTER TABLE ONLY "public"."chat_signed_prekeys"
    ADD CONSTRAINT "chat_signed_prekeys_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."chat_signed_prekeys"
    ADD CONSTRAINT "chat_signed_prekeys_unique_key_id" UNIQUE ("user_id", "key_id");

ALTER TABLE ONLY "public"."deleted_account_blocklist"
    ADD CONSTRAINT "deleted_account_blocklist_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."discovery_session_items"
    ADD CONSTRAINT "discovery_session_items_pkey" PRIMARY KEY ("session_id", "position");

ALTER TABLE ONLY "public"."discovery_session_items"
    ADD CONSTRAINT "discovery_session_items_session_id_candidate_id_key" UNIQUE ("session_id", "candidate_id");

ALTER TABLE ONLY "public"."discovery_sessions"
    ADD CONSTRAINT "discovery_sessions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."feedback_report_comments"
    ADD CONSTRAINT "feedback_report_comments_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."feedback_report_status_history"
    ADD CONSTRAINT "feedback_report_status_history_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."feedback_reports"
    ADD CONSTRAINT "feedback_reports_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."matches"
    ADD CONSTRAINT "matches_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."matches"
    ADD CONSTRAINT "matches_unique_pair" UNIQUE ("liker_id", "liked_back_id", "tab");

ALTER TABLE ONLY "public"."profile_age_change_log"
    ADD CONSTRAINT "profile_age_change_log_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."profile_discovery_actions"
    ADD CONSTRAINT "profile_discovery_actions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."profile_name_change_log"
    ADD CONSTRAINT "profile_name_change_log_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."profile_pseudonym_map"
    ADD CONSTRAINT "profile_pseudonym_map_pkey" PRIMARY KEY ("user_id");

ALTER TABLE ONLY "public"."profile_pseudonym_map"
    ADD CONSTRAINT "profile_pseudonym_map_pseudonym_id_key" UNIQUE ("pseudonym_id");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_import_sync_code_key" UNIQUE ("import_sync_code");

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."safety_alerts"
    ADD CONSTRAINT "safety_alerts_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."safety_contact_notices"
    ADD CONSTRAINT "safety_contact_notices_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."safety_contact_notices"
    ADD CONSTRAINT "safety_contact_notices_user_id_phone_blind_index_key" UNIQUE ("user_id", "phone_blind_index");

ALTER TABLE ONLY "public"."safety_contacts"
    ADD CONSTRAINT "safety_contacts_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."safety_evidence"
    ADD CONSTRAINT "safety_evidence_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."safety_sessions"
    ADD CONSTRAINT "safety_sessions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."spotify_connections"
    ADD CONSTRAINT "spotify_connections_pkey" PRIMARY KEY ("user_id");

ALTER TABLE ONLY "public"."spotify_playlists"
    ADD CONSTRAINT "spotify_playlists_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."spotify_playlists"
    ADD CONSTRAINT "spotify_playlists_unique_per_user" UNIQUE ("user_id", "spotify_playlist_id");

ALTER TABLE ONLY "public"."terms_consent_log"
    ADD CONSTRAINT "terms_consent_log_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_fcm_token_key" UNIQUE ("fcm_token");

ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_moderation_actions"
    ADD CONSTRAINT "user_moderation_actions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_reports"
    ADD CONSTRAINT "user_reports_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."vector_profiles"
    ADD CONSTRAINT "vector_profiles_pkey" PRIMARY KEY ("pseudonym_id");

-- ==========================================================
-- SECTION 5: PERFORMANCE & FILTER INDEXES
-- ==========================================================

CREATE INDEX "idx_chat_conversations_not_started" ON "public"."chat_conversations" USING "btree" ("user_a_id", "user_b_id", "tab") WHERE (("closed_at" IS NULL) AND ("last_message_at" IS NULL));

CREATE INDEX "idx_chat_conversations_user_a_active" ON "public"."chat_conversations" USING "btree" ("user_a_id", "tab", "last_message_at" DESC) WHERE ("closed_at" IS NULL);

CREATE INDEX "idx_chat_conversations_user_b_active" ON "public"."chat_conversations" USING "btree" ("user_b_id", "tab", "last_message_at" DESC) WHERE ("closed_at" IS NULL);

CREATE INDEX "idx_chat_events_conversation" ON "public"."chat_events" USING "btree" ("conversation_id");

CREATE INDEX "idx_chat_events_pending_reminders" ON "public"."chat_events" USING "btree" ("reminder_sent_at") WHERE (("reminder_sent_at" IS NULL) AND ("status" <> 'cancelled'::"text"));

CREATE INDEX "idx_chat_events_pending_safety_reminders" ON "public"."chat_events" USING "btree" ("safety_reminder_sent_at") WHERE (("safety_enabled" = true) AND ("safety_reminder_sent_at" IS NULL) AND ("status" <> 'cancelled'::"text"));

CREATE INDEX "idx_chat_messages_conversation_created" ON "public"."chat_messages" USING "btree" ("conversation_id", "created_at");

CREATE INDEX "idx_chat_one_time_prekeys_user_unused" ON "public"."chat_one_time_prekeys" USING "btree" ("user_id", "key_id") WHERE ("used_at" IS NULL);

CREATE INDEX "idx_chat_signed_prekeys_user_current" ON "public"."chat_signed_prekeys" USING "btree" ("user_id", "created_at" DESC) WHERE ("rotated_at" IS NULL);

CREATE INDEX "idx_deleted_account_blocklist_phone" ON "public"."deleted_account_blocklist" USING "btree" ("phone_blind_index");

CREATE INDEX "idx_discovery_session_items_candidate" ON "public"."discovery_session_items" USING "btree" ("candidate_id");

CREATE INDEX "idx_discovery_session_items_session_orbit_tier" ON "public"."discovery_session_items" USING "btree" ("session_id", "orbit_tier");

CREATE INDEX "idx_discovery_session_items_session_position" ON "public"."discovery_session_items" USING "btree" ("session_id", "position");

CREATE INDEX "idx_discovery_session_items_session_x" ON "public"."discovery_session_items" USING "btree" ("session_id", "x");

CREATE INDEX "idx_discovery_session_items_session_y" ON "public"."discovery_session_items" USING "btree" ("session_id", "y");

CREATE INDEX "idx_discovery_sessions_expiry" ON "public"."discovery_sessions" USING "btree" ("expires_at");

CREATE INDEX "idx_discovery_sessions_viewer_tab_created" ON "public"."discovery_sessions" USING "btree" ("viewer_id", "tab", "created_at" DESC);

CREATE INDEX "idx_feedback_report_comments_report_created" ON "public"."feedback_report_comments" USING "btree" ("report_id", "created_at");

CREATE INDEX "idx_feedback_report_status_history_report_created" ON "public"."feedback_report_status_history" USING "btree" ("report_id", "created_at");

CREATE INDEX "idx_feedback_reports_status_created" ON "public"."feedback_reports" USING "btree" ("status", "created_at" DESC);

CREATE INDEX "idx_feedback_reports_user_created" ON "public"."feedback_reports" USING "btree" ("user_id", "created_at" DESC);

CREATE INDEX "idx_matches_liked_back_active" ON "public"."matches" USING "btree" ("liked_back_id", "tab") WHERE ("unmatched_at" IS NULL);

CREATE INDEX "idx_matches_liker_active" ON "public"."matches" USING "btree" ("liker_id", "tab") WHERE ("unmatched_at" IS NULL);

CREATE INDEX "idx_matches_liker_liked_back" ON "public"."matches" USING "btree" ("liker_id", "liked_back_id");

CREATE INDEX "idx_pda_likes_inbox" ON "public"."profile_discovery_actions" USING "btree" ("target_id", "tab", "action", "revoked_at") WHERE (("action" = ANY (ARRAY['like'::"text", 'superlike'::"text"])) AND ("revoked_at" IS NULL));

CREATE INDEX "idx_profile_age_change_log_user_changed_at" ON "public"."profile_age_change_log" USING "btree" ("user_id", "changed_at" DESC);

CREATE INDEX "idx_profile_discovery_actions_active_suppressions" ON "public"."profile_discovery_actions" USING "btree" ("actor_id", "target_id", "action", "tab", "expires_at") WHERE (("revoked_at" IS NULL) AND ("action" = ANY (ARRAY['pass'::"text", 'hide'::"text", 'block'::"text"])));

CREATE INDEX "idx_profile_discovery_actions_actor_tab_created" ON "public"."profile_discovery_actions" USING "btree" ("actor_id", "tab", "created_at" DESC);

CREATE INDEX "idx_profile_discovery_actions_actor_target_action" ON "public"."profile_discovery_actions" USING "btree" ("actor_id", "target_id", "action");

CREATE INDEX "idx_profile_discovery_actions_actor_target_tab_action" ON "public"."profile_discovery_actions" USING "btree" ("actor_id", "target_id", "tab", "action");

CREATE INDEX "idx_profile_discovery_actions_pass_expiry" ON "public"."profile_discovery_actions" USING "btree" ("actor_id", "tab", "expires_at") WHERE (("action" = 'pass'::"text") AND ("revoked_at" IS NULL));

CREATE INDEX "idx_profile_name_change_log_user_changed_at" ON "public"."profile_name_change_log" USING "btree" ("user_id", "changed_at" DESC);

CREATE INDEX "idx_profiles_age" ON "public"."profiles" USING "btree" ("age");

CREATE INDEX "idx_profiles_campus_branch_blind" ON "public"."profiles" USING "btree" ("campus_branch_blind_index");

CREATE INDEX "idx_profiles_campus_year" ON "public"."profiles" USING "btree" ("campus_year");

CREATE INDEX "idx_profiles_children_plans_bi" ON "public"."profiles" USING "btree" ("children_plans_blind_index");

CREATE INDEX "idx_profiles_dating_eligibility" ON "public"."profiles" USING "btree" ("id") WHERE (("is_dating_active" = true) AND ("is_deactivated" = false));

CREATE INDEX "idx_profiles_dating_for" ON "public"."profiles" USING "gin" ("dating_for");

CREATE INDEX "idx_profiles_dating_target_buckets" ON "public"."profiles" USING "gin" ("dating_target_buckets");

CREATE INDEX "idx_profiles_drinking_blind" ON "public"."profiles" USING "btree" ("drinking_blind_index");

CREATE INDEX "idx_profiles_friends_eligibility" ON "public"."profiles" USING "btree" ("id") WHERE (("is_friends_active" = true) AND ("is_deactivated" = false));

CREATE INDEX "idx_profiles_friends_target_buckets" ON "public"."profiles" USING "gin" ("friends_target_buckets");

CREATE UNIQUE INDEX "idx_profiles_import_sync_code" ON "public"."profiles" USING "btree" ("import_sync_code") WHERE ("import_sync_code" IS NOT NULL);

CREATE INDEX "idx_profiles_professional_eligibility" ON "public"."profiles" USING "btree" ("id") WHERE (("is_professional_active" = true) AND ("is_deactivated" = false));

CREATE INDEX "idx_profiles_professional_target_buckets" ON "public"."profiles" USING "gin" ("professional_target_buckets");

CREATE INDEX "idx_profiles_religious_beliefs_bi" ON "public"."profiles" USING "btree" ("religious_beliefs_blind_index");

CREATE INDEX "idx_profiles_search_bucket" ON "public"."profiles" USING "btree" ("search_bucket");

CREATE INDEX "idx_profiles_smoking_blind" ON "public"."profiles" USING "btree" ("smoking_blind_index");

CREATE INDEX "idx_safety_alerts_user_created" ON "public"."safety_alerts" USING "btree" ("user_id", "created_at" DESC);

CREATE INDEX "idx_safety_contact_notices_user" ON "public"."safety_contact_notices" USING "btree" ("user_id");

CREATE INDEX "idx_safety_contacts_user" ON "public"."safety_contacts" USING "btree" ("user_id");

CREATE INDEX "idx_safety_evidence_alert" ON "public"."safety_evidence" USING "btree" ("alert_id");

CREATE INDEX "idx_safety_sessions_overdue" ON "public"."safety_sessions" USING "btree" ("status", "next_checkin_at") WHERE (("status" = 'active'::"text") AND ("escalation_cancelled_at" IS NULL));

CREATE INDEX "idx_safety_sessions_user_status" ON "public"."safety_sessions" USING "btree" ("user_id", "status");

CREATE INDEX "idx_spotify_playlists_user" ON "public"."spotify_playlists" USING "btree" ("user_id");

CREATE INDEX "idx_terms_consent_log_user_created_at" ON "public"."terms_consent_log" USING "btree" ("user_id", "created_at" DESC);

CREATE INDEX "idx_user_reports_reporter_target" ON "public"."user_reports" USING "btree" ("reporter_id", "target_id");

CREATE INDEX "idx_user_reports_review_status_created" ON "public"."user_reports" USING "btree" ("review_status", "created_at" DESC);

CREATE INDEX "idx_user_reports_target_created" ON "public"."user_reports" USING "btree" ("target_id", "created_at" DESC);

CREATE INDEX "idx_users_app_variant" ON "public"."users" USING "btree" ("app_variant");

CREATE INDEX "idx_users_pending_purge" ON "public"."users" USING "btree" ("scheduled_purge_at") WHERE (("deletion_requested_at" IS NOT NULL) AND ("purged_at" IS NULL));

CREATE INDEX "idx_vector_profiles_bio" ON "public"."vector_profiles" USING "hnsw" ("bio_embedding" "public"."vector_cosine_ops") WITH ("m"='16', "ef_construction"='64') WHERE ("bio_embedding" IS NOT NULL);

CREATE INDEX "idx_vector_profiles_career" ON "public"."vector_profiles" USING "hnsw" ("career_embedding" "public"."vector_cosine_ops") WITH ("m"='16', "ef_construction"='64') WHERE ("career_embedding" IS NOT NULL);

CREATE INDEX "idx_vector_profiles_identity" ON "public"."vector_profiles" USING "hnsw" ("identity_embedding" "public"."vector_cosine_ops") WITH ("m"='16', "ef_construction"='64') WHERE ("identity_embedding" IS NOT NULL);

CREATE UNIQUE INDEX "uq_profile_discovery_actions_active_like_or_superlike" ON "public"."profile_discovery_actions" USING "btree" ("actor_id", "target_id", "tab") WHERE (("action" = ANY (ARRAY['like'::"text", 'superlike'::"text"])) AND ("revoked_at" IS NULL));

CREATE UNIQUE INDEX "uq_profile_discovery_actions_block" ON "public"."profile_discovery_actions" USING "btree" ("actor_id", "target_id", "action") WHERE (("action" = 'block'::"text") AND ("revoked_at" IS NULL));

CREATE UNIQUE INDEX "uq_profile_discovery_actions_hide" ON "public"."profile_discovery_actions" USING "btree" ("actor_id", "target_id", "tab", "action") WHERE (("action" = 'hide'::"text") AND ("revoked_at" IS NULL));

CREATE UNIQUE INDEX "uq_profile_discovery_actions_like" ON "public"."profile_discovery_actions" USING "btree" ("actor_id", "target_id", "tab", "action") WHERE (("action" = 'like'::"text") AND ("revoked_at" IS NULL));

CREATE UNIQUE INDEX "uq_profile_discovery_actions_pass" ON "public"."profile_discovery_actions" USING "btree" ("actor_id", "target_id", "tab", "action") WHERE (("action" = 'pass'::"text") AND ("revoked_at" IS NULL));

CREATE UNIQUE INDEX "uq_profile_discovery_actions_superlike" ON "public"."profile_discovery_actions" USING "btree" ("actor_id", "target_id", "tab", "action") WHERE (("action" = 'superlike'::"text") AND ("revoked_at" IS NULL));

CREATE UNIQUE INDEX "uq_user_reports_pending" ON "public"."user_reports" USING "btree" ("reporter_id", "target_id") WHERE ("review_status" = 'pending'::"text");

CREATE INDEX "user_devices_device_id_idx" ON "public"."user_devices" USING "btree" ("device_id") WHERE ("device_id" IS NOT NULL);

CREATE INDEX "user_devices_last_seen_at_idx" ON "public"."user_devices" USING "btree" ("last_seen_at");

CREATE INDEX "user_devices_user_id_idx" ON "public"."user_devices" USING "btree" ("user_id", "is_active");

CREATE INDEX "user_moderation_actions_action_type_idx" ON "public"."user_moderation_actions" USING "btree" ("action_type");

CREATE INDEX "user_moderation_actions_active_idx" ON "public"."user_moderation_actions" USING "btree" ("user_id", "revoked_at", "expires_at");

CREATE INDEX "user_moderation_actions_user_id_idx" ON "public"."user_moderation_actions" USING "btree" ("user_id", "created_at" DESC);

CREATE INDEX "users_is_active_idx" ON "public"."users" USING "btree" ("is_active");

CREATE UNIQUE INDEX "users_mobile_blind_index_unique_idx" ON "public"."users" USING "btree" ("mobile_blind_index") WHERE ("mobile_blind_index" IS NOT NULL);

CREATE INDEX "users_moderation_status_idx" ON "public"."users" USING "btree" ("moderation_status");

CREATE INDEX "users_suspended_until_idx" ON "public"."users" USING "btree" ("suspended_until");

-- ==========================================================
-- SECTION 6: TRIGGERS & LIFECYCLE HOOKS
-- ==========================================================

CREATE OR REPLACE TRIGGER "guard_safety_sessions_escalation" BEFORE INSERT OR UPDATE ON "public"."safety_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."guard_safety_sessions_escalation_columns"();

CREATE OR REPLACE TRIGGER "log_feedback_reports_status_change" AFTER INSERT OR UPDATE ON "public"."feedback_reports" FOR EACH ROW EXECUTE FUNCTION "public"."log_feedback_status_change"();

CREATE OR REPLACE TRIGGER "set_chat_events_updated_at" BEFORE UPDATE ON "public"."chat_events" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "set_chat_identity_keys_updated_at" BEFORE UPDATE ON "public"."chat_identity_keys" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "set_chat_presence_updated_at" BEFORE UPDATE ON "public"."chat_presence" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "set_conversation_last_message_at" AFTER INSERT ON "public"."chat_messages" FOR EACH ROW EXECUTE FUNCTION "public"."touch_conversation_last_message"();

CREATE OR REPLACE TRIGGER "set_feedback_reports_updated_at" BEFORE UPDATE ON "public"."feedback_reports" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "set_safety_sessions_updated_at" BEFORE UPDATE ON "public"."safety_sessions" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "set_user_devices_updated_at" BEFORE UPDATE ON "public"."user_devices" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "set_users_updated_at" BEFORE UPDATE ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

CREATE OR REPLACE TRIGGER "trg_prevent_users_app_variant_update" BEFORE UPDATE OF "app_variant" ON "public"."users" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_users_app_variant_update"();

CREATE OR REPLACE TRIGGER "trg_enforce_variant_age_range" BEFORE INSERT OR UPDATE OF "age" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_variant_age_range"();

CREATE OR REPLACE TRIGGER "trigger_guard_service_fields" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."guard_service_fields"();

COMMENT ON TRIGGER "trigger_guard_service_fields" ON "public"."profiles" IS 'Prevents client-side updates to server-governed profile fields.';

CREATE OR REPLACE TRIGGER "trigger_handle_deactivation" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."handle_deactivation_timestamp"();

COMMENT ON TRIGGER "trigger_handle_deactivation" ON "public"."profiles" IS 'Applies handle_deactivation_timestamp before every profile update.';

CREATE OR REPLACE TRIGGER "trigger_matches_precondition" BEFORE INSERT ON "public"."matches" FOR EACH ROW EXECUTE FUNCTION "public"."check_match_precondition"();

CREATE OR REPLACE TRIGGER "trigger_update_profile_discovery_actions_timestamp" BEFORE UPDATE ON "public"."profile_discovery_actions" FOR EACH ROW EXECUTE FUNCTION "public"."handle_update_timestamp"();

COMMENT ON TRIGGER "trigger_update_profile_discovery_actions_timestamp" ON "public"."profile_discovery_actions" IS 'Applies handle_update_timestamp before every discovery action update.';

CREATE OR REPLACE TRIGGER "trigger_update_profile_timestamp" BEFORE UPDATE ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."handle_update_timestamp"();

COMMENT ON TRIGGER "trigger_update_profile_timestamp" ON "public"."profiles" IS 'Applies handle_update_timestamp before every profile update.';

CREATE OR REPLACE TRIGGER "trigger_update_vector_timestamp" BEFORE UPDATE ON "public"."vector_profiles" FOR EACH ROW EXECUTE FUNCTION "public"."handle_update_timestamp"();

COMMENT ON TRIGGER "trigger_update_vector_timestamp" ON "public"."vector_profiles" IS 'Applies handle_update_timestamp before every vector profile update.';

-- ==========================================================
-- SECTION 7: FOREIGN KEY RELATIONSHIPS
-- ==========================================================

ALTER TABLE ONLY "public"."chat_conversations"
    ADD CONSTRAINT "chat_conversations_match_id_fkey" FOREIGN KEY ("match_id") REFERENCES "public"."matches"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chat_conversations"
    ADD CONSTRAINT "chat_conversations_user_a_id_fkey" FOREIGN KEY ("user_a_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chat_conversations"
    ADD CONSTRAINT "chat_conversations_user_b_id_fkey" FOREIGN KEY ("user_b_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chat_events"
    ADD CONSTRAINT "chat_events_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."chat_conversations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chat_events"
    ADD CONSTRAINT "chat_events_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chat_events"
    ADD CONSTRAINT "chat_events_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."chat_messages"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chat_identity_keys"
    ADD CONSTRAINT "chat_identity_keys_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "public"."chat_conversations"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chat_one_time_prekeys"
    ADD CONSTRAINT "chat_one_time_prekeys_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chat_presence"
    ADD CONSTRAINT "chat_presence_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."chat_signed_prekeys"
    ADD CONSTRAINT "chat_signed_prekeys_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."discovery_session_items"
    ADD CONSTRAINT "discovery_session_items_candidate_id_fkey" FOREIGN KEY ("candidate_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."discovery_session_items"
    ADD CONSTRAINT "discovery_session_items_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."discovery_sessions"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."discovery_sessions"
    ADD CONSTRAINT "discovery_sessions_viewer_id_fkey" FOREIGN KEY ("viewer_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."feedback_report_comments"
    ADD CONSTRAINT "feedback_report_comments_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."feedback_report_comments"
    ADD CONSTRAINT "feedback_report_comments_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "public"."feedback_reports"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."feedback_report_status_history"
    ADD CONSTRAINT "feedback_report_status_history_changed_by_fkey" FOREIGN KEY ("changed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "public"."feedback_report_status_history"
    ADD CONSTRAINT "feedback_report_status_history_report_id_fkey" FOREIGN KEY ("report_id") REFERENCES "public"."feedback_reports"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."feedback_reports"
    ADD CONSTRAINT "feedback_reports_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "public"."feedback_reports"
    ADD CONSTRAINT "feedback_reports_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."matches"
    ADD CONSTRAINT "matches_liked_back_id_fkey" FOREIGN KEY ("liked_back_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."matches"
    ADD CONSTRAINT "matches_liker_id_fkey" FOREIGN KEY ("liker_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."matches"
    ADD CONSTRAINT "matches_unmatched_by_fkey" FOREIGN KEY ("unmatched_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "public"."profile_age_change_log"
    ADD CONSTRAINT "profile_age_change_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profile_discovery_actions"
    ADD CONSTRAINT "profile_discovery_actions_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profile_discovery_actions"
    ADD CONSTRAINT "profile_discovery_actions_target_id_fkey" FOREIGN KEY ("target_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profile_name_change_log"
    ADD CONSTRAINT "profile_name_change_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profile_pseudonym_map"
    ADD CONSTRAINT "profile_pseudonym_map_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."safety_alerts"
    ADD CONSTRAINT "safety_alerts_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."safety_sessions"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "public"."safety_alerts"
    ADD CONSTRAINT "safety_alerts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."safety_contact_notices"
    ADD CONSTRAINT "safety_contact_notices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."safety_contacts"
    ADD CONSTRAINT "safety_contacts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."safety_evidence"
    ADD CONSTRAINT "safety_evidence_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "public"."safety_alerts"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."safety_evidence"
    ADD CONSTRAINT "safety_evidence_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."safety_sessions"
    ADD CONSTRAINT "safety_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."spotify_connections"
    ADD CONSTRAINT "spotify_connections_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."spotify_playlists"
    ADD CONSTRAINT "spotify_playlists_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."terms_consent_log"
    ADD CONSTRAINT "terms_consent_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."user_moderation_actions"
    ADD CONSTRAINT "user_moderation_actions_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "public"."user_moderation_actions"
    ADD CONSTRAINT "user_moderation_actions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."user_reports"
    ADD CONSTRAINT "user_reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."user_reports"
    ADD CONSTRAINT "user_reports_reviewed_by_fkey" FOREIGN KEY ("reviewed_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "public"."user_reports"
    ADD CONSTRAINT "user_reports_target_id_fkey" FOREIGN KEY ("target_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."vector_profiles"
    ADD CONSTRAINT "vector_profiles_pseudonym_id_fkey" FOREIGN KEY ("pseudonym_id") REFERENCES "public"."profile_pseudonym_map"("pseudonym_id") ON DELETE CASCADE;

-- ==========================================================
-- SECTION 8: ROW LEVEL SECURITY (RLS) & ACCESS POLICIES
-- ==========================================================

-- 1. Explicit Deny-All Policies (Backend / service_role Only)
CREATE POLICY "Deny all client-side age change log access" ON "public"."profile_age_change_log" USING (false) WITH CHECK (false);
COMMENT ON POLICY "Deny all client-side age change log access" ON "public"."profile_age_change_log" IS 'Explicit deny-all for anon/authenticated; only the backend service_role client reads/writes. No GRANT issued.';

CREATE POLICY "Deny all client-side archive access" ON "public"."account_history_archive" USING (false) WITH CHECK (false);

CREATE POLICY "Deny all client-side blocklist access" ON "public"."deleted_account_blocklist" USING (false) WITH CHECK (false);

CREATE POLICY "Deny all client-side mapping access" ON "public"."profile_pseudonym_map" USING (false) WITH CHECK (false);
COMMENT ON POLICY "Deny all client-side mapping access" ON "public"."profile_pseudonym_map" IS 'Explicit deny-all RLS policy for client roles; intended access is privileged backend only.';

CREATE POLICY "Deny all client-side name change log access" ON "public"."profile_name_change_log" USING (false) WITH CHECK (false);
COMMENT ON POLICY "Deny all client-side name change log access" ON "public"."profile_name_change_log" IS 'Explicit deny-all for anon/authenticated; only the backend service_role client reads/writes. No GRANT issued.';

CREATE POLICY "Deny all client-side safety contact notice access" ON "public"."safety_contact_notices" USING (false) WITH CHECK (false);
COMMENT ON POLICY "Deny all client-side safety contact notice access" ON "public"."safety_contact_notices" IS 'Explicit deny-all for anon/authenticated; only the backend service_role client reads/writes.';

CREATE POLICY "Deny all client-side spotify connection access" ON "public"."spotify_connections" USING (false) WITH CHECK (false);
COMMENT ON POLICY "Deny all client-side spotify connection access" ON "public"."spotify_connections" IS 'Explicit deny-all RLS policy for client roles; intended access is privileged backend only.';

CREATE POLICY "Deny all client-side terms consent log access" ON "public"."terms_consent_log" USING (false) WITH CHECK (false);
COMMENT ON POLICY "Deny all client-side terms consent log access" ON "public"."terms_consent_log" IS 'Explicit deny-all for anon/authenticated; only the backend service_role client reads/writes. No GRANT issued.';

CREATE POLICY "Deny all client-side vector access" ON "public"."vector_profiles" USING (false) WITH CHECK (false);
COMMENT ON POLICY "Deny all client-side vector access" ON "public"."vector_profiles" IS 'Explicit deny-all RLS policy for client roles; vector access is restricted to privileged backend paths.';

-- 2. Client Scoped SELECT Policies (Guarded by auth.uid())
CREATE POLICY "Users can view own discovery actions" ON "public"."profile_discovery_actions" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") = "actor_id"));
COMMENT ON POLICY "Users can view own discovery actions" ON "public"."profile_discovery_actions" IS 'Allows a user to read only discovery action rows where they are the actor.';

CREATE POLICY "Users can view own discovery session items" ON "public"."discovery_session_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."discovery_sessions" "ds"
  WHERE (("ds"."id" = "discovery_session_items"."session_id") AND ("ds"."viewer_id" = ( SELECT "auth"."uid"() AS "uid"))))));
COMMENT ON POLICY "Users can view own discovery session items" ON "public"."discovery_session_items" IS 'Allows a user to read only session items belonging to discovery sessions they own.';

CREATE POLICY "Users can view own discovery sessions" ON "public"."discovery_sessions" FOR SELECT USING ((( SELECT "auth"."uid"() AS "uid") = "viewer_id"));
COMMENT ON POLICY "Users can view own discovery sessions" ON "public"."discovery_sessions" IS 'Allows a user to read only discovery sessions where they are the viewer.';

CREATE POLICY "Users can view own profile" ON "public"."profiles" FOR SELECT USING (((( SELECT "auth"."uid"() AS "uid") = "id") AND ("is_deactivated" = false)));
COMMENT ON POLICY "Users can view own profile" ON "public"."profiles" IS 'Allows a user to read only their own non-deactivated profile row. Profile creation and updates are server-gated via backend service_role to enforce Field-Level Encryption and invariants.';

-- 3. Table-by-Table RLS Enforcement & Specific SELECT Policies
ALTER TABLE "public"."account_history_archive" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."account_history_archive" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."chat_conversations" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."chat_conversations" FORCE ROW LEVEL SECURITY;
CREATE POLICY "chat_conversations_select_own" ON "public"."chat_conversations" FOR SELECT TO "authenticated" USING ((("user_a_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("user_b_id" = ( SELECT "auth"."uid"() AS "uid"))));

ALTER TABLE "public"."chat_events" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."chat_events" FORCE ROW LEVEL SECURITY;
CREATE POLICY "chat_events_select_participant" ON "public"."chat_events" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."chat_conversations" "c"
  WHERE (("c"."id" = "chat_events"."conversation_id") AND (("c"."user_a_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("c"."user_b_id" = ( SELECT "auth"."uid"() AS "uid")))))));

ALTER TABLE "public"."chat_identity_keys" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."chat_identity_keys" FORCE ROW LEVEL SECURITY;
CREATE POLICY "chat_identity_keys_owner_select" ON "public"."chat_identity_keys" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));

ALTER TABLE "public"."chat_messages" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."chat_messages" FORCE ROW LEVEL SECURITY;
CREATE POLICY "chat_messages_select_participant" ON "public"."chat_messages" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."chat_conversations" "c"
  WHERE (("c"."id" = "chat_messages"."conversation_id") AND (("c"."user_a_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("c"."user_b_id" = ( SELECT "auth"."uid"() AS "uid")))))));

ALTER TABLE "public"."chat_one_time_prekeys" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."chat_one_time_prekeys" FORCE ROW LEVEL SECURITY;
CREATE POLICY "chat_one_time_prekeys_owner_select" ON "public"."chat_one_time_prekeys" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));

ALTER TABLE "public"."chat_presence" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."chat_presence" FORCE ROW LEVEL SECURITY;
CREATE POLICY "chat_presence_owner_select" ON "public"."chat_presence" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));

ALTER TABLE "public"."chat_signed_prekeys" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."chat_signed_prekeys" FORCE ROW LEVEL SECURITY;
CREATE POLICY "chat_signed_prekeys_owner_select" ON "public"."chat_signed_prekeys" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));

ALTER TABLE "public"."deleted_account_blocklist" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."deleted_account_blocklist" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."discovery_session_items" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."discovery_session_items" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."discovery_sessions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."discovery_sessions" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."feedback_report_comments" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."feedback_report_comments" FORCE ROW LEVEL SECURITY;
CREATE POLICY "feedback_report_comments_select_own" ON "public"."feedback_report_comments" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."feedback_reports" "r"
  WHERE (("r"."id" = "feedback_report_comments"."report_id") AND ("r"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));

ALTER TABLE "public"."feedback_report_status_history" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."feedback_report_status_history" FORCE ROW LEVEL SECURITY;
CREATE POLICY "feedback_report_status_history_select_own" ON "public"."feedback_report_status_history" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."feedback_reports" "r"
  WHERE (("r"."id" = "feedback_report_status_history"."report_id") AND ("r"."user_id" = ( SELECT "auth"."uid"() AS "uid"))))));

ALTER TABLE "public"."feedback_reports" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."feedback_reports" FORCE ROW LEVEL SECURITY;
CREATE POLICY "feedback_reports_select_own" ON "public"."feedback_reports" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

ALTER TABLE "public"."matches" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."matches" FORCE ROW LEVEL SECURITY;
CREATE POLICY "matches_select_own" ON "public"."matches" FOR SELECT TO "authenticated" USING ((("liker_id" = ( SELECT "auth"."uid"() AS "uid")) OR ("liked_back_id" = ( SELECT "auth"."uid"() AS "uid"))));

ALTER TABLE "public"."profile_age_change_log" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."profile_age_change_log" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."profile_discovery_actions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."profile_discovery_actions" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."profile_name_change_log" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."profile_name_change_log" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."profile_pseudonym_map" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."profile_pseudonym_map" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."profiles" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."safety_alerts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."safety_alerts" FORCE ROW LEVEL SECURITY;
CREATE POLICY "safety_alerts_select_own" ON "public"."safety_alerts" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

ALTER TABLE "public"."safety_contact_notices" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."safety_contact_notices" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."safety_contacts" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."safety_contacts" FORCE ROW LEVEL SECURITY;
CREATE POLICY "safety_contacts_select_own" ON "public"."safety_contacts" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

ALTER TABLE "public"."safety_evidence" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."safety_evidence" FORCE ROW LEVEL SECURITY;
CREATE POLICY "safety_evidence_select_own" ON "public"."safety_evidence" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

ALTER TABLE "public"."safety_sessions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."safety_sessions" FORCE ROW LEVEL SECURITY;
CREATE POLICY "safety_sessions_select_own" ON "public"."safety_sessions" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

ALTER TABLE "public"."spotify_connections" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."spotify_connections" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."spotify_playlists" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."spotify_playlists" FORCE ROW LEVEL SECURITY;
CREATE POLICY "spotify_playlists_select_own" ON "public"."spotify_playlists" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));

ALTER TABLE "public"."terms_consent_log" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."terms_consent_log" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_devices" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."user_devices" FORCE ROW LEVEL SECURITY;
CREATE POLICY "user_devices_select_own" ON "public"."user_devices" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "user_id"));

ALTER TABLE "public"."user_moderation_actions" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."user_moderation_actions" FORCE ROW LEVEL SECURITY;
CREATE POLICY "user_moderation_actions_select_none_for_users" ON "public"."user_moderation_actions" FOR SELECT TO "authenticated" USING (false);

ALTER TABLE "public"."user_reports" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."user_reports" FORCE ROW LEVEL SECURITY;

ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."users" FORCE ROW LEVEL SECURITY;
CREATE POLICY "users_select_own" ON "public"."users" FOR SELECT TO "authenticated" USING ((( SELECT "auth"."uid"() AS "uid") = "id"));

ALTER TABLE "public"."vector_profiles" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "public"."vector_profiles" FORCE ROW LEVEL SECURITY;

-- ==========================================================
-- SECTION 9: REALTIME REPLICATION CONFIGURATION
-- ==========================================================
-- Note on Firebase App Check & Realtime Security Boundary:
-- WebSocket/Realtime connections to Supabase bypass Firebase App Check gating.
-- Direct access is restricted at the PostgreSQL Row-Level Security (RLS) layer
-- (chat_conversations_select_participant, chat_events_select_participant,
-- and chat_messages_select_participant) requiring verified Supabase JWTs.
-- To prevent message type and protocol metadata leakage across WebSocket streams,
-- column-level publication filtering is enforced on chat_messages below.

ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."chat_conversations";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."chat_events";

-- Column-level filtering: Exclude ciphertext_metadata and message_type from Realtime payloads
-- to prevent traffic analysis and metadata leakage to WebSocket eavesdroppers.
ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."chat_messages" (
    "id",
    "conversation_id",
    "sender_id",
    "ciphertext",
    "delivered_at",
    "read_at",
    "created_at"
);

GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_in"("cstring", "oid", integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_out"("public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_recv"("internal", "oid", integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_send"("public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_typmod_in"("cstring"[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_in"("cstring", "oid", integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_out"("public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_recv"("internal", "oid", integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_send"("public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_typmod_in"("cstring"[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(real[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(real[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(double precision[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(double precision[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(integer[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(integer[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_halfvec"(numeric[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_sparsevec"(numeric[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_float4"("public"."halfvec", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec"("public"."halfvec", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_sparsevec"("public"."halfvec", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_to_vector"("public"."halfvec", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_halfvec"("public"."sparsevec", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec"("public"."sparsevec", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_to_vector"("public"."sparsevec", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_halfvec"("public"."vector", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_sparsevec"("public"."vector", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "service_role";

REVOKE ALL ON FUNCTION "public"."apply_age_change"("p_user_id" "uuid", "p_new_age" integer, "p_min_interval_days" integer, "p_max_changes" integer) FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."apply_age_change"("p_user_id" "uuid", "p_new_age" integer, "p_min_interval_days" integer, "p_max_changes" integer) TO "service_role";

REVOKE ALL ON FUNCTION "public"."apply_name_change"("p_user_id" "uuid", "p_new_name" "text", "p_min_interval_days" integer, "p_max_changes" integer) FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."apply_name_change"("p_user_id" "uuid", "p_new_name" "text", "p_min_interval_days" integer, "p_max_changes" integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."binary_quantize"("public"."vector") TO "service_role";

REVOKE ALL ON FUNCTION "public"."check_match_precondition"() FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."check_match_precondition"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."claim_one_time_prekey"("target_user_id" "uuid") FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."claim_one_time_prekey"("target_user_id" "uuid") TO "service_role";

GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "service_role";

REVOKE ALL ON FUNCTION "public"."create_discovery_session_with_items"("p_viewer_id" "uuid", "p_tab" "text", "p_filters" "jsonb", "p_expires_at" timestamp with time zone, "p_viewer_spotify_connected" boolean, "p_items" "jsonb") FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."create_discovery_session_with_items"("p_viewer_id" "uuid", "p_tab" "text", "p_filters" "jsonb", "p_expires_at" timestamp with time zone, "p_viewer_spotify_connected" boolean, "p_items" "jsonb") TO "service_role";

REVOKE ALL ON FUNCTION "public"."enforce_variant_age_range"() FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_variant_age_range"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."get_user_id_by_email"("email_addr" "text") FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_id_by_email"("email_addr" "text") TO "service_role";

REVOKE ALL ON FUNCTION "public"."guard_safety_sessions_escalation_columns"() FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."guard_safety_sessions_escalation_columns"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."guard_service_fields"() FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."guard_service_fields"() TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_accum"(double precision[], "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_add"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_avg"(double precision[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_cmp"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_combine"(double precision[], double precision[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_concat"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_eq"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ge"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_gt"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_l2_squared_distance"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_le"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_lt"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_mul"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_ne"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_negative_inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_spherical_distance"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."halfvec_sub"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."hamming_distance"(bit, bit) TO "service_role";

REVOKE ALL ON FUNCTION "public"."handle_deactivation_timestamp"() FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."handle_deactivation_timestamp"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."handle_update_timestamp"() FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."handle_update_timestamp"() TO "service_role";

GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_bit_support"("internal") TO "service_role";

GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_halfvec_support"("internal") TO "service_role";

GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnsw_sparsevec_support"("internal") TO "service_role";

GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "service_role";

GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_bit_support"("internal") TO "service_role";

GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflat_halfvec_support"("internal") TO "service_role";

GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "service_role";

GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "postgres";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "anon";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "authenticated";
GRANT ALL ON FUNCTION "public"."jaccard_distance"(bit, bit) TO "service_role";

GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."halfvec", "public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_norm"("public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_normalize"("public"."vector") TO "service_role";

REVOKE ALL ON FUNCTION "public"."log_feedback_status_change"() FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."log_feedback_status_change"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."set_updated_at"() FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."set_updated_at"() TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_cmp"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_eq"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ge"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_gt"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_l2_squared_distance"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_le"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_lt"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_ne"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "anon";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sparsevec_negative_inner_product"("public"."sparsevec", "public"."sparsevec") TO "service_role";

GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."halfvec", integer, integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "anon";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."subvector"("public"."vector", integer, integer) TO "service_role";

REVOKE ALL ON FUNCTION "public"."sync_safety_contacts"("p_user_id" "uuid", "p_contacts" "jsonb") FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."sync_safety_contacts"("p_user_id" "uuid", "p_contacts" "jsonb") TO "service_role";

REVOKE ALL ON FUNCTION "public"."touch_conversation_last_message"() FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."touch_conversation_last_message"() TO "service_role";

REVOKE ALL ON FUNCTION "public"."upsert_signed_prekey"("target_user_id" "uuid", "new_key_id" integer, "new_public_key" "bytea", "new_signature" "bytea") FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."upsert_signed_prekey"("target_user_id" "uuid", "new_key_id" integer, "new_public_key" "bytea", "new_signature" "bytea") TO "service_role";

REVOKE ALL ON FUNCTION "public"."validate_array_values"("arr" "text"[], "allowed" "text"[]) FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "public"."validate_array_values"("arr" "text"[], "allowed" "text"[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_concat"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."halfvec") TO "service_role";

GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "service_role";

-- ==========================================================
-- SECTION 10: ROLE PRIVILEGES & ACCESS CONTROL
-- ==========================================================

-- Revoke all table, function, and sequence privileges from client roles
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated, PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM anon, authenticated, PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM anon, authenticated, PUBLIC;

-- Grant full table, function, and sequence access to superuser/admin backend roles
GRANT ALL ON ALL TABLES IN SCHEMA public TO postgres, service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO postgres, service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO postgres, service_role;

-- Grant explicit, minimum required SELECT privileges to authenticated role (guarded by RLS)
GRANT SELECT ON TABLE "public"."chat_conversations" TO "authenticated";
GRANT SELECT ON TABLE "public"."chat_events" TO "authenticated";
GRANT SELECT ON TABLE "public"."chat_identity_keys" TO "authenticated";
GRANT SELECT ON TABLE "public"."chat_messages" TO "authenticated";
GRANT SELECT ON TABLE "public"."chat_one_time_prekeys" TO "authenticated";
GRANT SELECT ON TABLE "public"."chat_presence" TO "authenticated";
GRANT SELECT ON TABLE "public"."chat_signed_prekeys" TO "authenticated";
GRANT SELECT ON TABLE "public"."discovery_sessions" TO "authenticated";
GRANT SELECT ON TABLE "public"."discovery_session_items" TO "authenticated";
GRANT SELECT ON TABLE "public"."feedback_reports" TO "authenticated";
GRANT SELECT ON TABLE "public"."feedback_report_comments" TO "authenticated";
GRANT SELECT ON TABLE "public"."feedback_report_status_history" TO "authenticated";
GRANT SELECT ON TABLE "public"."matches" TO "authenticated";
GRANT SELECT ON TABLE "public"."profile_discovery_actions" TO "authenticated";
GRANT SELECT ON TABLE "public"."profiles" TO "authenticated";
GRANT SELECT ON TABLE "public"."safety_alerts" TO "authenticated";
GRANT SELECT ON TABLE "public"."safety_contacts" TO "authenticated";
GRANT SELECT ON TABLE "public"."safety_evidence" TO "authenticated";
GRANT SELECT ON TABLE "public"."safety_sessions" TO "authenticated";
GRANT SELECT ON TABLE "public"."spotify_playlists" TO "authenticated";
GRANT SELECT ON TABLE "public"."user_devices" TO "authenticated";
GRANT SELECT ON TABLE "public"."users" TO "authenticated";

-- Default Privileges Hardening
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM anon, authenticated, PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM anon, authenticated, PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM anon, authenticated, PUBLIC;

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres", "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres", "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres", "service_role";

-- ==========================================================
-- SECTION 11: STORAGE BUCKETS & OBJECT RLS POLICIES
-- ==========================================================

-- 1. user_media (5MB limit per photo)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'user_media',
    'user_media',
    false,
    5242880,
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
) ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];

-- 2. chat_media (20MB limit for E2EE ciphertext attachments)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'chat_media',
    'chat_media',
    false,
    20971520,
    ARRAY['application/octet-stream']
) ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 20971520,
    allowed_mime_types = ARRAY['application/octet-stream'];

-- 3. safety_evidence (50MB limit per video/audio segment)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'safety_evidence',
    'safety_evidence',
    false,
    52428800,
    ARRAY['video/mp4', 'video/quicktime', 'audio/aac', 'audio/mp4', 'application/octet-stream']
) ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 52428800,
    allowed_mime_types = ARRAY['video/mp4', 'video/quicktime', 'audio/aac', 'audio/mp4', 'application/octet-stream'];

-- 4. feedback_attachments (8MB limit for tickets/reports)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'feedback_attachments',
    'feedback_attachments',
    false,
    8388608,
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif', 'application/pdf', 'text/plain']
) ON CONFLICT (id) DO UPDATE SET
    public = false,
    file_size_limit = 8388608,
    allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif', 'application/pdf', 'text/plain'];

-- Storage Object Policies: user_media
DROP POLICY IF EXISTS "user_media_select_own" ON storage.objects;
CREATE POLICY "user_media_select_own" ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'user_media' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "user_media_insert_own" ON storage.objects;
CREATE POLICY "user_media_insert_own" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'user_media' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "user_media_update_own" ON storage.objects;
CREATE POLICY "user_media_update_own" ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'user_media' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text)
    WITH CHECK (bucket_id = 'user_media' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "user_media_delete_own" ON storage.objects;
CREATE POLICY "user_media_delete_own" ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'user_media' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

-- Storage Object Policies: chat_media
DROP POLICY IF EXISTS "chat_media_select_participant" ON storage.objects;
CREATE POLICY "chat_media_select_participant" ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'chat_media'
        AND EXISTS (
            SELECT 1 FROM public.chat_conversations c
            WHERE c.id::text = (storage.foldername(name))[1]
              AND (c.user_a_id = (SELECT auth.uid()) OR c.user_b_id = (SELECT auth.uid()))
              AND c.closed_at IS NULL
        )
    );

DROP POLICY IF EXISTS "chat_media_insert_participant" ON storage.objects;
CREATE POLICY "chat_media_insert_participant" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'chat_media'
        AND EXISTS (
            SELECT 1 FROM public.chat_conversations c
            WHERE c.id::text = (storage.foldername(name))[1]
              AND (c.user_a_id = (SELECT auth.uid()) OR c.user_b_id = (SELECT auth.uid()))
              AND c.closed_at IS NULL
        )
    );

DROP POLICY IF EXISTS "chat_media_delete_participant" ON storage.objects;
CREATE POLICY "chat_media_delete_participant" ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'chat_media'
        AND EXISTS (
            SELECT 1 FROM public.chat_conversations c
            WHERE c.id::text = (storage.foldername(name))[1]
              AND (c.user_a_id = (SELECT auth.uid()) OR c.user_b_id = (SELECT auth.uid()))
              AND c.closed_at IS NULL
        )
    );

-- Storage Object Policies: safety_evidence
DROP POLICY IF EXISTS "safety_evidence_select_own" ON storage.objects;
CREATE POLICY "safety_evidence_select_own" ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'safety_evidence' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "safety_evidence_insert_own" ON storage.objects;
CREATE POLICY "safety_evidence_insert_own" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'safety_evidence' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "safety_evidence_delete_own" ON storage.objects;
CREATE POLICY "safety_evidence_delete_own" ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'safety_evidence' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

-- Storage Object Policies: feedback_attachments
DROP POLICY IF EXISTS "feedback_attachments_select_own" ON storage.objects;
CREATE POLICY "feedback_attachments_select_own" ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'feedback_attachments' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "feedback_attachments_insert_own" ON storage.objects;
CREATE POLICY "feedback_attachments_insert_own" ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'feedback_attachments' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

DROP POLICY IF EXISTS "feedback_attachments_delete_own" ON storage.objects;
CREATE POLICY "feedback_attachments_delete_own" ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'feedback_attachments' AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);
