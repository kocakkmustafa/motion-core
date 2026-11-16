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

  -- GoTrue rewrites the user row after insert; a later write that carries
  -- the metadata again must neither keep it nor restate the age.
  update auth.users
    set raw_user_meta_data = raw_user_meta_data || jsonb_build_object(
      'motion_age', jsonb_build_object('birth_year_month', ym_adult,
        'country', 'US', 'policy_version', '2026-10-21.1'),
      'email_verified', true)
    where id = teen;
  select raw_user_meta_data into meta from auth.users where id = teen;
  if meta ? 'motion_age' or not (meta ? 'email_verified') then
    raise exception 'metadata rewrite was not stripped: %', meta;
  end if;
  if not exists (
    select 1 from public.motion_age_declarations
    where user_id = teen and birth_year_month = ym_teen and country = 'DE'
  ) then
    raise exception 'a metadata rewrite restated the declaration';
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

  -- A signed-in caller reads only its own restriction (R4.2); the service
  -- role and callers without claims (SQL editor, pg_cron) read any account.
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', adult, 'role', 'authenticated')::text, true);
  if public.motion_account_restricted(adult) then
    raise exception 'adult reads itself as restricted';
  end if;
  begin
    perform public.motion_account_restricted(teen);
    raise exception 'another account''s restriction was readable';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.motion_account_restricted(null);
    raise exception 'a null account was readable';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
  perform set_config('request.jwt.claims',
    json_build_object('role', 'service_role')::text, true);
  if public.motion_account_restricted(teen) then
    raise exception 'service role reads an approved teen as restricted';
  end if;
  perform set_config('request.jwt.claims', '', true);
  if public.motion_account_restricted(teen) then
    raise exception 'owner session reads an approved teen as restricted';
  end if;

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

-- VELI-01 (ADR-008): under-13 device consent. Same harness, same transaction.
do $test$
declare
  child uuid := '66666666-6666-6666-6666-666666666666';
  child2 uuid := '77777777-7777-7777-7777-777777777777';
  ym_child text := to_char(current_date - interval '10 years', 'YYYY-MM');
  raw_ok text := repeat('a', 43);
  raw_pending text := repeat('b', 43);
  raw_old text := repeat('c', 43);
  raw_denied text := repeat('d', 43);
  meta jsonb;
  consent record;
  n integer;
  signup jsonb;
begin
  -- Server-only tables carry digests only: no raw token or address column.
  select count(*) into n from information_schema.columns
    where table_schema = 'public'
      and table_name in ('motion_device_consents', 'motion_consent_decisions')
      and column_name in ('device_token', 'raw_token', 'token', 'parent_email',
                          'email', 'user_id', 'child_name', 'birth_year_month');
  if n <> 0 then
    raise exception 'a raw token, address or child key column exists: %', n;
  end if;
  select count(*) into n from pg_attribute a
    join pg_class c on c.oid = a.attrelid
    where c.relname = 'motion_device_consents' and a.attnum > 0
      and a.attname = 'device_token_digest' and a.atttypid = 'text'::regtype;
  if n <> 1 then raise exception 'device table is not keyed by a digest'; end if;
  -- No foreign key: the device row precedes any account.
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.motion_device_consents'::regclass and contype = 'f'
  ) then
    raise exception 'device consents carry a foreign key';
  end if;

  insert into public.motion_device_consents
    (device_token_digest, status, parent_email_digest, link_digest,
     expires_at, decided_at)
  values
    (encode(sha256(convert_to(raw_ok, 'UTF8')), 'hex'), 'approved', null,
     repeat('1', 64), now() + interval '7 days', now()),
    (encode(sha256(convert_to(raw_pending, 'UTF8')), 'hex'), 'pending',
     repeat('9', 64), repeat('2', 64), now() + interval '7 days', null),
    (encode(sha256(convert_to(raw_old, 'UTF8')), 'hex'), 'approved', null,
     repeat('3', 64), now() + interval '7 days', now()),
    (encode(sha256(convert_to(raw_denied, 'UTF8')), 'hex'), 'denied', null,
     null, now() + interval '7 days', now());
  update public.motion_device_consents
    set created_at = now() - interval '31 days'
    where device_token_digest
          = encode(sha256(convert_to(raw_old, 'UTF8')), 'hex');

  -- Direct under-13 sign-up (no token, pending, expired, denied, wrong token)
  -- is refused and leaves nothing behind (P0013).
  foreach signup in array array[
    null::jsonb,
    jsonb_build_object('device_consent_token', raw_pending),
    jsonb_build_object('device_consent_token', raw_old),
    jsonb_build_object('device_consent_token', raw_denied),
    jsonb_build_object('device_consent_token', repeat('z', 43))
  ] loop
    begin
      insert into auth.users
        (id, instance_id, aud, role, email, encrypted_password,
         raw_user_meta_data, created_at, updated_at)
      values
        (child, '00000000-0000-0000-0000-000000000000', 'authenticated',
         'authenticated', 'child@motion.test', 'x',
         jsonb_build_object('motion_age', jsonb_build_object(
           'birth_year_month', ym_child, 'country', 'US',
           'policy_version', '2026-11-17.1') || coalesce(signup, '{}')),
         now(), now());
      raise exception 'under-13 sign-up without an approved token: %', signup;
    exception when sqlstate 'P0013' then
      null;
    end;
  end loop;
  if exists (select 1 from auth.users where id = child)
     or exists (select 1 from public.motion_age_declarations
                where user_id = child)
     or exists (select 1 from public.motion_parental_consents
                where user_id = child) then
    raise exception 'a refused sign-up left rows behind';
  end if;
  -- A refused attempt did not consume the pending approval either.
  select count(*) into n from public.motion_device_consents;
  if n <> 4 then raise exception 'refusals consumed device rows: %', n; end if;

  -- Approved token: the account is created, consent is written, the device
  -- row is gone, the metadata (token included) is stripped.
  insert into auth.users
    (id, instance_id, aud, role, email, encrypted_password,
     raw_user_meta_data, created_at, updated_at)
  values
    (child, '00000000-0000-0000-0000-000000000000', 'authenticated',
     'authenticated', 'child@motion.test', 'x',
     jsonb_build_object('motion_age', jsonb_build_object(
       'birth_year_month', ym_child, 'country', 'US',
       'policy_version', '2026-11-17.1', 'device_consent_token', raw_ok)),
     now(), now());
  select raw_user_meta_data into meta from auth.users where id = child;
  if meta ? 'motion_age' or meta::text like '%' || raw_ok || '%' then
    raise exception 'age metadata or device token was not stripped: %', meta;
  end if;
  select * into consent from public.motion_parental_consents
    where user_id = child;
  if consent.status is distinct from 'approved'
     or consent.method is distinct from 'device_token_email'
     or consent.parent_email_digest is not null
     or consent.manage_digest is distinct from repeat('1', 64) then
    raise exception 'device consent was not carried over: %', consent;
  end if;
  if exists (
    select 1 from public.motion_device_consents
    where device_token_digest = encode(sha256(convert_to(raw_ok, 'UTF8')), 'hex')
  ) then
    raise exception 'token digest survived binding to the account';
  end if;
  if public.motion_account_restricted(child) then
    raise exception 'consented child is restricted';
  end if;
  if public.motion_age_band(ym_child, 'US', current_date) <> 'blocked' then
    raise exception 'band computation drifted';
  end if;

  -- A consumed token cannot create a second account.
  begin
    insert into auth.users
      (id, instance_id, aud, role, email, encrypted_password,
       raw_user_meta_data, created_at, updated_at)
    values
      (child2, '00000000-0000-0000-0000-000000000000', 'authenticated',
       'authenticated', 'child2@motion.test', 'x',
       jsonb_build_object('motion_age', jsonb_build_object(
         'birth_year_month', ym_child, 'country', 'US',
         'policy_version', '2026-11-17.1', 'device_consent_token', raw_ok)),
       now(), now());
    raise exception 'a consumed token was accepted twice';
  exception when sqlstate 'P0013' then
    null;
  end;

  -- Withdrawal closes account features again.
  update public.motion_parental_consents
    set status = 'withdrawn', decided_at = now() where user_id = child;
  if not public.motion_account_restricted(child) then
    raise exception 'withdrawn consent does not restrict the account';
  end if;
  -- Purge: not before 30 days, then the account goes with its receipt.
  if public.motion_purge_unconsented_accounts() <> 0
     or not exists (select 1 from auth.users where id = child) then
    raise exception 'a fresh withdrawal was purged early';
  end if;
  update public.motion_parental_consents
    set decided_at = now() - interval '31 days' where user_id = child;
  if public.motion_purge_unconsented_accounts() <> 1 then
    raise exception 'withdrawn purge count';
  end if;
  if exists (select 1 from auth.users where id = child)
     or exists (select 1 from public.motion_parental_consents
                where user_id = child)
     or not public.motion_was_account_deleted(child) then
    raise exception 'withdrawn account purge did not cascade with a receipt';
  end if;

  -- The 30 day clock removed the unclaimed old approval; the rest (still
  -- inside the window) stays: pending, denied.
  select count(*) into n from public.motion_device_consents;
  if n <> 2 then raise exception 'device retention purge: %', n; end if;
  if exists (
    select 1 from public.motion_device_consents
    where device_token_digest = encode(sha256(convert_to(raw_old, 'UTF8')), 'hex')
  ) then
    raise exception 'a 31 day old device row survived';
  end if;
  update public.motion_device_consents set created_at = now() - interval '31 days';
  perform public.motion_purge_unconsented_accounts();
  select count(*) into n from public.motion_device_consents;
  if n <> 0 then raise exception 'pending/denied rows survived 30 days: %', n; end if;

  -- Clients cannot read or call the device machinery.
  set local role authenticated;
  begin
    perform 1 from public.motion_device_consents;
    raise exception 'device consents readable by a client';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform 1 from public.motion_consent_decisions;
    raise exception 'decisions readable by a client';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.motion_consume_device_consent(child, raw_ok);
    raise exception 'client called consume';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end;
$test$;

-- Deleting the Auth user removes the consent row and writes the receipt
-- (motion-delete-account only calls admin.deleteUser).
do $test$
declare
  child uuid := '88888888-8888-8888-8888-888888888888';
  ym_child text := to_char(current_date - interval '9 years', 'YYYY-MM');
  raw text := repeat('e', 43);
begin
  insert into public.motion_device_consents
    (device_token_digest, status, link_digest, expires_at)
  values (encode(sha256(convert_to(raw, 'UTF8')), 'hex'), 'approved',
          repeat('4', 64), now() + interval '7 days');
  insert into auth.users
    (id, instance_id, aud, role, email, encrypted_password,
     raw_user_meta_data, created_at, updated_at)
  values
    (child, '00000000-0000-0000-0000-000000000000', 'authenticated',
     'authenticated', 'child3@motion.test', 'x',
     jsonb_build_object('motion_age', jsonb_build_object(
       'birth_year_month', ym_child, 'country', 'US',
       'policy_version', '2026-11-17.1', 'device_consent_token', raw)),
     now(), now());
  if not exists (select 1 from public.motion_parental_consents
                 where user_id = child) then
    raise exception 'consent row missing before delete';
  end if;
  delete from auth.users where id = child;
  if exists (select 1 from public.motion_parental_consents
             where user_id = child)
     or exists (select 1 from public.motion_age_declarations
                where user_id = child) then
    raise exception 'delete did not cascade consent and declaration';
  end if;
  if not public.motion_was_account_deleted(child) then
    raise exception 'delete wrote no receipt';
  end if;
end;
$test$;

-- VELI-01 review fixes: atomic mail counters, final withdrawal, state-guarded
-- request, anonymous trace week rounding.
do $test$
declare
  u uuid := '99999999-9999-9999-9999-999999999999';
  dig text := repeat('5', 64);
  n integer;
  r text;
  ok boolean;
  created timestamptz;
begin
  -- Counters: five slots, the sixth is refused; nothing is counted on refusal.
  for n in 1..5 loop
    if not public.motion_consent_mail_slot(array['p:x'], 5) then
      raise exception 'slot % refused', n;
    end if;
  end loop;
  if public.motion_consent_mail_slot(array['p:x'], 5) then
    raise exception 'sixth slot granted';
  end if;
  -- All or nothing across keys: 'p:x' is full, 'd:y' must stay untouched.
  if public.motion_consent_mail_slot(array['d:y', 'p:x'], 5) then
    raise exception 'a full key did not refuse the pair';
  end if;
  if exists (select 1 from public.motion_consent_mail_counters
             where counter_key = 'd:y') then
    raise exception 'a refused pair counted the free key';
  end if;
  if not public.motion_consent_mail_slot(array['d:y'], 5) then
    raise exception 'free key refused';
  end if;
  -- Old days are cleaned by the purge; today stays.
  insert into public.motion_consent_mail_counters (counter_key, day, count)
    values ('p:old', current_date - 2, 5), ('p:yesterday', current_date - 1, 5);
  perform public.motion_purge_unconsented_accounts();
  if exists (select 1 from public.motion_consent_mail_counters
             where counter_key = 'p:old')
     or not exists (select 1 from public.motion_consent_mail_counters
                    where counter_key = 'p:yesterday')
     or not exists (select 1 from public.motion_consent_mail_counters
                    where counter_key = 'p:x' and count = 5) then
    raise exception 'counter cleanup is wrong';
  end if;

  -- State-guarded request: never puts a decided row back to pending.
  r := public.motion_device_consent_request(
    repeat('6', 64), dig, repeat('7', 64), 'en', now() + interval '7 days');
  if r <> 'ok' then raise exception 'new request: %', r; end if;
  r := public.motion_device_consent_request(
    repeat('6', 64), dig, repeat('8', 64), 'en', now() + interval '7 days');
  if r <> 'too_soon' then raise exception 'immediate resend: %', r; end if;
  foreach r in array array['approved', 'denied', 'withdrawn'] loop
    update public.motion_device_consents
      set status = r, parent_email_digest = null,
          requested_at = now() - interval '1 hour'
      where device_token_digest = repeat('6', 64);
    if public.motion_device_consent_request(
         repeat('6', 64), dig, repeat('8', 64), 'en',
         now() + interval '7 days') <> r
       or (select status from public.motion_device_consents
           where device_token_digest = repeat('6', 64)) <> r then
      raise exception 'a % row was revived', r;
    end if;
  end loop;
  update public.motion_device_consents
    set status = 'expired', created_at = now() - interval '20 days'
    where device_token_digest = repeat('6', 64);
  if public.motion_device_consent_request(
       repeat('6', 64), dig, repeat('8', 64), 'en',
       now() + interval '7 days') <> 'ok' then
    raise exception 'expired row did not restart';
  end if;
  select created_at into created from public.motion_device_consents
    where device_token_digest = repeat('6', 64);
  if created < now() - interval '1 minute' then
    raise exception 'retention clock did not restart';
  end if;

  -- A withdrawn device row can never be consumed.
  insert into public.motion_device_consents
    (device_token_digest, status, link_digest, expires_at)
  values (encode(sha256(convert_to(repeat('w', 43), 'UTF8')), 'hex'),
          'withdrawn', repeat('a', 64), now() + interval '7 days');
  if public.motion_consume_device_consent(u, repeat('w', 43)) then
    raise exception 'a withdrawn device row was consumed';
  end if;

  -- Withdrawn account consent is final.
  insert into auth.users
    (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
  values (u, '00000000-0000-0000-0000-000000000000', 'authenticated',
          'authenticated', 'final@motion.test', 'x', now(), now());
  insert into public.motion_parental_consents
    (user_id, status, expires_at, decided_at)
  values (u, 'withdrawn', now(), now());
  update public.motion_parental_consents
    set decided_at = now() where user_id = u;
  foreach r in array array['pending', 'approved', 'expired', 'denied'] loop
    begin
      update public.motion_parental_consents set status = r where user_id = u;
      raise exception 'withdrawn went back to %', r;
    exception when check_violation then
      null;
    end;
  end loop;
  begin
    insert into public.motion_parental_consents
      (user_id, status, parent_email_digest, expires_at)
    values (u, 'pending', dig, now())
    on conflict (user_id) do update set status = 'pending';
    raise exception 'upsert revived a withdrawn consent';
  exception when check_violation then
    null;
  end;

  -- The anonymous trace is week rounded and carries no key.
  insert into public.motion_consent_decisions (status) values ('approved');
  if (select extract(isodow from decided_on) from public.motion_consent_decisions
      order by id limit 1) <> 1 then
    raise exception 'decided_on is not a week start';
  end if;

  -- Server only.
  set local role authenticated;
  begin
    perform public.motion_consent_mail_slot(array['x'], 5);
    raise exception 'client called the slot function';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.motion_device_consent_request(
      repeat('1', 64), dig, dig, 'en', now());
    raise exception 'client called the request function';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform 1 from public.motion_consent_mail_counters;
    raise exception 'counters readable by a client';
  exception when insufficient_privilege then
    null;
  end;
  reset role;
end;
$test$;

rollback;
