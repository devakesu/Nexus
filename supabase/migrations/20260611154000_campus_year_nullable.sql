-- Migration: Make campus_year column nullable

ALTER TABLE public.profiles ALTER COLUMN campus_year DROP NOT NULL;
