-- ==========================================================
-- EXPAND FEEDBACK_ATTACHMENTS BUCKET ALLOWED MIME TYPES
-- Adds application/pdf and text/plain so web contact form
-- can upload PDF, TXT, and LOG files in addition to images.
-- ==========================================================

BEGIN;

UPDATE storage.buckets
SET allowed_mime_types = ARRAY[
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/webp',
    'image/gif',
    'application/pdf',
    'text/plain'
]
WHERE id = 'feedback_attachments';

COMMIT;
