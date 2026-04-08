-- ═══════════════════════════════════════════════════════════════════════════════
-- Server-side account deletion with metadata tracking
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.delete_own_account()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  cur        uuid := auth.uid();
  cur_email  text;
  s_count    int;
BEGIN
  IF cur IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  -- Get email
  SELECT email INTO cur_email FROM auth.users WHERE id = cur;

  -- Count active sightings
  SELECT count(*) INTO s_count
  FROM public.sightings
  WHERE user_id = cur AND status = 'active';

  -- Soft-delete all active sightings
  UPDATE public.sightings
  SET status = 'deleted'
  WHERE user_id = cur AND status = 'active';

  -- Soft-delete profile with audit metadata
  UPDATE public.profiles
  SET
    status = 'deleted',
    meta   = meta || jsonb_build_object(
      'deleted_info', jsonb_build_object(
        'deleted_at',       now()::text,
        'reason',           'user_requested_deletion',
        'email',            cur_email,
        'sightings_count',  s_count
      )
    )
  WHERE id = cur;
END;
$$;
