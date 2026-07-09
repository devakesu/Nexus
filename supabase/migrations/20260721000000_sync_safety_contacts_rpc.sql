-- Create an RPC function to sync safety contacts atomically in a single transaction.
CREATE OR REPLACE FUNCTION public.sync_safety_contacts(p_user_id UUID, p_contacts JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
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
