ALTER TABLE public.sightings ADD COLUMN IF NOT EXISTS is_favorite boolean NOT NULL DEFAULT false;
