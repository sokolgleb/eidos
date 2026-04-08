-- ═══════════════════════════════════════════════════════════════════════════════
-- Anonymous → OAuth account linking with metadata tracking
-- Replaces the old migrate_anon_to_auth (hard-delete) with a soft-delete version
-- ═══════════════════════════════════════════════════════════════════════════════

-- ── migrate_anon_to_auth (v2) ─────────────────────────────────────────────────
-- Optionally transfers sightings, merges profile metadata, soft-deletes anon.
CREATE OR REPLACE FUNCTION public.migrate_anon_to_auth(
  anon_id             uuid,
  transfer_sightings  boolean DEFAULT true
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  cur         uuid := auth.uid();
  cur_email   text;
  anon_total  int;
  transferred int := 0;
BEGIN
  IF cur IS NULL OR cur = anon_id THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Get current user email
  SELECT email INTO cur_email FROM auth.users WHERE id = cur;

  -- Count anon's active sightings
  SELECT count(*) INTO anon_total
  FROM public.sightings
  WHERE user_id = anon_id AND status = 'active';

  -- Optionally transfer sightings
  IF transfer_sightings THEN
    UPDATE public.sightings
    SET user_id = cur
    WHERE user_id = anon_id AND status = 'active';
    transferred := anon_total;
  END IF;

  -- Merge profile metadata from anon → auth
  UPDATE public.profiles SET
    language        = COALESCE(profiles.language,  anon.language),
    ip              = COALESCE(profiles.ip,        anon.ip),
    iso2            = COALESCE(profiles.iso2,      anon.iso2),
    platforms       = ARRAY(SELECT DISTINCT unnest(profiles.platforms       || anon.platforms)),
    oauth_providers = ARRAY(SELECT DISTINCT unnest(profiles.oauth_providers || anon.oauth_providers))
  FROM (SELECT * FROM public.profiles WHERE id = anon_id) AS anon
  WHERE profiles.id = cur;

  -- Soft-delete anon profile with audit metadata
  UPDATE public.profiles
  SET
    status = 'deleted',
    meta   = meta || jsonb_build_object(
      'deleted_info', jsonb_build_object(
        'deleted_at',           now()::text,
        'reason',               'linked_to_oauth',
        'linked_to_user_id',    cur::text,
        'linked_to_email',      cur_email,
        'sightings_transferred', transferred,
        'sightings_total',       anon_total
      )
    )
  WHERE id = anon_id;

  RETURN jsonb_build_object(
    'anon_sighting_count', anon_total,
    'transferred',         transferred
  );
END;
$$;

-- ── reactivate_own_profile ────────────────────────────────────────────────────
-- Re-enables a soft-deleted profile (e.g. user signs in again after deletion).
CREATE OR REPLACE FUNCTION public.reactivate_own_profile()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.profiles
  SET
    status = 'active',
    meta   = meta - 'deleted_info'
  WHERE id = auth.uid()
    AND status = 'deleted';
END;
$$;

-- ── get_own_profile_state ─────────────────────────────────────────────────────
-- Returns profile status and active sighting count for the calling user.
-- Used by client after signInWithIdToken to decide new vs existing account.
CREATE OR REPLACE FUNCTION public.get_own_profile_state()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  p_status  public.profile_status;
  s_count   int;
BEGIN
  SELECT status INTO p_status FROM public.profiles WHERE id = auth.uid();
  SELECT count(*) INTO s_count FROM public.sightings
  WHERE user_id = auth.uid() AND status = 'active';

  RETURN jsonb_build_object(
    'status',         p_status::text,
    'sighting_count', s_count
  );
END;
$$;
