-- ═══════════════════════════════════════════════════════════════════════════════
-- Full schema: drop & recreate all tables
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── Drop existing tables ──────────────────────────────────────────────────────

DROP TABLE IF EXISTS public.sightings CASCADE;
DROP TABLE IF EXISTS public.profiles  CASCADE;

-- ── Drop existing enum types ──────────────────────────────────────────────────

DROP TYPE IF EXISTS public.sighting_status CASCADE;
DROP TYPE IF EXISTS public.profile_status  CASCADE;

-- ── Enum types ────────────────────────────────────────────────────────────────

CREATE TYPE public.profile_status  AS ENUM ('active', 'deleted', 'banned');
CREATE TYPE public.sighting_status AS ENUM ('active', 'deleted');

-- ── Shared: set updated_at on every row update ────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- ── profiles ──────────────────────────────────────────────────────────────────

CREATE TABLE public.profiles (
  id          uuid                  PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  timestamptz           NOT NULL DEFAULT now(),
  updated_at  timestamptz           NOT NULL DEFAULT now(),
  first_name  text,
  last_name   text,
  email       text,
  status      public.profile_status NOT NULL DEFAULT 'active',
  ip          text,
  iso2        text,
  language    text,                  -- set once on first install, never overwritten
  platforms   text[]                NOT NULL DEFAULT '{}',
  app_version text,
  tags        text[]                NOT NULL DEFAULT '{}',
  settings    jsonb                 NOT NULL DEFAULT '{}',
  meta        jsonb                 NOT NULL DEFAULT '{}'
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles: owner select" ON public.profiles
  FOR SELECT USING (auth.uid() = id);
CREATE POLICY "profiles: owner insert" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles: owner update" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- language is set once: once populated it is never overwritten by an UPDATE
CREATE OR REPLACE FUNCTION public.preserve_language()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.language IS NOT NULL THEN
    NEW.language = OLD.language;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_profiles_preserve_language
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.preserve_language();

-- Auto-create an empty profile row when a new auth user is registered
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id)
  VALUES (NEW.id)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE INDEX idx_profiles_status     ON public.profiles (status);
CREATE INDEX idx_profiles_created_at ON public.profiles (created_at DESC);
CREATE INDEX idx_profiles_updated_at ON public.profiles (updated_at DESC);
CREATE INDEX idx_profiles_tags       ON public.profiles USING GIN (tags);

-- ── sightings ─────────────────────────────────────────────────────────────────

CREATE TABLE public.sightings (
  id            text                   PRIMARY KEY,
  user_id       uuid                   NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at    timestamptz            NOT NULL DEFAULT now(),
  updated_at    timestamptz            NOT NULL DEFAULT now(),
  status        public.sighting_status NOT NULL DEFAULT 'active',
  original_url  text                   NOT NULL DEFAULT '',
  annotated_url text                   NOT NULL DEFAULT '',
  is_public     boolean                NOT NULL DEFAULT false,
  ip            text,
  iso2          text,
  tags          text[]                 NOT NULL DEFAULT '{}',
  categories    text[]                 NOT NULL DEFAULT '{}',
  title         text,
  description   text,
  meta          jsonb                  NOT NULL DEFAULT '{}'
);

ALTER TABLE public.sightings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sightings: owner select" ON public.sightings
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "sightings: owner insert" ON public.sightings
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "sightings: owner update" ON public.sightings
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "sightings: owner delete" ON public.sightings
  FOR DELETE USING (auth.uid() = user_id);

CREATE TRIGGER trg_sightings_updated_at
  BEFORE UPDATE ON public.sightings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX idx_sightings_user_status  ON public.sightings (user_id, status);
CREATE INDEX idx_sightings_status       ON public.sightings (status);
CREATE INDEX idx_sightings_created_at   ON public.sightings (created_at DESC);
CREATE INDEX idx_sightings_updated_at   ON public.sightings (updated_at DESC);
CREATE INDEX idx_sightings_tags         ON public.sightings USING GIN (tags);
CREATE INDEX idx_sightings_categories   ON public.sightings USING GIN (categories);

-- ── TTL cleanup for soft-deleted sightings ────────────────────────────────────
-- Activate via Supabase Dashboard → Database → Scheduled Jobs (pg_cron):
--
--   SELECT cron.schedule(
--     'cleanup-deleted-sightings',
--     '0 3 * * *',
--     $$
--       DELETE FROM public.sightings
--       WHERE status = 'deleted'
--         AND updated_at < now() - INTERVAL '7 days';
--     $$
--   );
