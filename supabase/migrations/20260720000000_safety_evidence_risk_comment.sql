BEGIN;

COMMENT ON TABLE public.safety_evidence
    IS 'Encrypted Silent SOS recording segments (video/audio). storage_path points into the private safety_evidence bucket; media_key_base64 is the AES-GCM key escrowed for future authenticated trusted-contact access. Note: Plaintext escrow deviates from pure E2E posture, carrying DB compromise / service-role exposure risk.';

COMMIT;
