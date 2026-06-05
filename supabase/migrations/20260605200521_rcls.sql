ALTER TABLE public.users
ADD CONSTRAINT users_terms_version_numeric_check
CHECK (
  accepted_terms_version IS NULL
  OR accepted_terms_version ~ '^[0-9]+$'
);

REVOKE UPDATE
  ON TABLE public.users
  FROM authenticated;

GRANT UPDATE (
  mobile
)
  ON TABLE public.users
  TO authenticated;
