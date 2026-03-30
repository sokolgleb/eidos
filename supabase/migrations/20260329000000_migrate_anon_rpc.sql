CREATE OR REPLACE FUNCTION public.migrate_anon_to_auth(anon_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE cur uuid := auth.uid(); BEGIN
  IF cur IS NULL OR cur = anon_id THEN RAISE EXCEPTION 'Unauthorized'; END IF;
  UPDATE public.sightings SET user_id = cur WHERE user_id = anon_id;
  UPDATE public.profiles SET
    language = COALESCE(profiles.language, anon.language),
    ip       = COALESCE(profiles.ip,       anon.ip),
    iso2     = COALESCE(profiles.iso2,     anon.iso2),
    platforms = ARRAY(SELECT DISTINCT unnest(profiles.platforms || anon.platforms))
  FROM (SELECT * FROM public.profiles WHERE id = anon_id) AS anon
  WHERE profiles.id = cur;
  DELETE FROM public.profiles WHERE id = anon_id;
END; $$;
