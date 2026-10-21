-- Age declaration, parental consent restriction and retention helpers.
-- Run against a disposable local Supabase only (same harness as motion_rls.sql).
begin;

do $test$
declare
  teen uuid := '33333333-3333-3333-3333-333333333333';
  child uuid := '44444444-4444-4444-4444-444444444444';
  adult uuid := '55555555-5555-5555-5555-555555555555';
  ym_teen text := to_char(current_date - interval '14 years 2 months', 'YYYY-MM');
  ym_child text := to_char(current_date - interval '10 years', 'YYYY-MM');
  ym_adult text := to_char(current_date - interval '30 years', 'YYYY-MM');
  meta jsonb;
  band text;
  count_rows integer;
begin
  -- Sign-up metadata is captured once and stripped from Auth.
  insert into auth.users
    (id, instance_id, aud, role, email, encrypted_password,
     raw_user_meta_data, created_at, updated_at)
  values
    (teen, '00000000-0000-0000-0000-000000000000', 'authenticated',
     'authenticated', 'teen@motion.test', 'x',
     jsonb_build_object('motion_age', jsonb_build_object(
       'birth_year_month', ym_teen, 'country', 'DE',
       'policy_version', '2026-10-21.1')),
     now(), now());
  select raw_user_meta_data into meta from auth.users where id = teen;
  if meta ? 'motion_age' then
    raise exception 'age metadata was not stripped';
  end if;
  if not exists (
    select 1 from public.motion_age_declarations
    where user_id = teen and birth_year_month = ym_teen and country = 'DE'
  ) then
    raise exception 'declaration was not captured';
  end if;

  -- Under 13 cannot sign up.
  begin
    insert into auth.users
      (id, instance_id, aud, role, email, encrypted_password,
       raw_user_meta_data, created_at, updated_at)
    values
      (child, '00000000-0000-0000-0000-000000000000', 'authenticated',
       'authenticated', 'child@motion.test', 'x',
       jsonb_build_object('motion_age', jsonb_build_object(
         'birth_year_month', ym_child, 'country', 'US',
         'policy_version', '2026-10-21.1')),
       now(), now());
    raise exception 'under-13 sign-up was accepted';
  exception when sqlstate 'P0013' then
    null;
  end;

  if public.motion_age_band(ym_teen, 'DE', current_date)
       <> 'parental_consent_required'
    or public.motion_age_band(ym_teen, 'US', current_date) <> 'teen'
    or public.motion_age_band(ym_adult, null, current_date) <> 'adult'
  then
    raise exception 'band computation drifted';
  end if;
  if not public.motion_account_restricted(teen) then
    raise exception 'consent-pending teen is not restricted';
  end if;

  -- Restricted teen cannot write the shared profile.
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', teen, 'role', 'authenticated')::text, true);
  begin
    insert into public.motion_profiles (user_id, display_name)
      values (teen, 'Teen');
    raise exception 'restricted profile write was accepted';
  exception when insufficient_privilege then
    null;
  end;
  -- The teen sees its own status, never the token digest.
  select count(*) into count_rows from public.motion_age_declarations;
  if count_rows <> 1 then
    raise exception 'own declaration read failed: %', count_rows;
  end if;
  begin
    perform token_digest from public.motion_parental_consents;
    raise exception 'token digest was readable';
  exception when insufficient_privilege then
    null;
  end;
  -- A declaration cannot be restated.
  begin
    perform public.motion_record_age_declaration(ym_adult, 'DE', 'v');
    raise exception 'second declaration was accepted';
  exception when unique_violation then
    null;
  end;
  reset role;

  -- Approval lifts the restriction.
  insert into public.motion_parental_consents
    (user_id, status, parent_email_digest, expires_at)
  values (teen, 'approved', repeat('a', 64), now() + interval '7 days');
  if public.motion_account_restricted(teen) then
    raise exception 'approved teen is still restricted';
  end if;
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', teen, 'role', 'authenticated')::text, true);
  insert into public.motion_profiles (user_id, display_name)
    values (teen, 'Teen');
  reset role;

  -- Legacy account declares once through the RPC.
  insert into auth.users
    (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
  values
    (adult, '00000000-0000-0000-0000-000000000000', 'authenticated',
     'authenticated', 'adult@motion.test', 'x', now(), now());
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', adult, 'role', 'authenticated')::text, true);
  band := public.motion_record_age_declaration(ym_adult, 'TR', '2026-10-21.1');
  if band <> 'adult' then
    raise exception 'legacy declaration band: %', band;
  end if;
  reset role;

  -- Purge removes only unapproved consent-required accounts past 30 days.
  update public.motion_parental_consents set status = 'pending'
    where user_id = teen;
  update public.motion_age_declarations
    set declared_at = now() - interval '31 days' where user_id = teen;
  if public.motion_purge_unconsented_accounts() <> 1 then
    raise exception 'unconsented purge count';
  end if;
  if exists (select 1 from auth.users where id = teen) then
    raise exception 'unconsented teen survived purge';
  end if;
  if not public.motion_was_account_deleted(teen) then
    raise exception 'purge wrote no deletion receipt';
  end if;
  if not exists (select 1 from auth.users where id = adult) then
    raise exception 'purge removed an adult';
  end if;

  -- Restore re-application: a resurrected deleted account is removed again.
  delete from public.motion_deleted_account_receipts;
  insert into auth.users
    (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
  values
    (teen, '00000000-0000-0000-0000-000000000000', 'authenticated',
     'authenticated', 'teen@motion.test', 'x', now(), now());
  if public.motion_reapply_deleted_accounts(array[
       encode(sha256(convert_to(teen::text, 'UTF8')), 'hex')
     ]) <> 1
  then
    raise exception 'reapply count';
  end if;
  if exists (select 1 from auth.users where id = teen)
    or not public.motion_was_account_deleted(teen)
  then
    raise exception 'reapply did not delete and re-record the account';
  end if;

  -- Clients cannot call the server-only helpers.
  set local role authenticated;
  begin
    perform public.motion_reapply_deleted_accounts(array['x']);
    raise exception 'client called reapply';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.motion_purge_unconsented_accounts();
    raise exception 'client called purge';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end;
$test$;

rollback;
