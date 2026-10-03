begin;

do $test$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  bob uuid := '22222222-2222-2222-2222-222222222222';
  count_rows integer;
begin
  insert into auth.users
    (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
  values
    (alice, '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated', 'alice@motion.test', 'x', now(), now()),
    (bob, '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated', 'bob@motion.test', 'x', now(), now());

  insert into public.motion_profiles (user_id, display_name)
    values (alice, 'Alice'), (bob, 'Bob');
  insert into public.motion_store_review_access (user_id, expires_at)
    values (alice, now() + interval '30 days');
  insert into public.motion_entitlements
    (user_id, app_id, store, product_id, original_transaction_id,
     state, expires_at, verified_at)
  values
    (alice, 'jablab', 'apple', 'jablab.monthly', 'alice-jab-1',
     'active', now() + interval '30 days', now()),
    (bob, 'gravita', 'google', 'gravita.monthly', 'bob-grav-1',
     'active', now() + interval '30 days', now());

  insert into public.motion_entitlements
    (user_id, app_id, store, product_id, original_transaction_id,
     state, expires_at, verified_at)
  values
    (alice, 'choreia', 'apple', 'choreia.monthly', 'alice-chor-expired',
     'active', now() - interval '1 day', now());

  begin
    insert into public.motion_entitlements
      (user_id, app_id, store, product_id, original_transaction_id,
       state, expires_at, verified_at)
    values
      (alice, 'gravita', 'apple', 'gravita.monthly', 'alice-jab-1',
       'active', now() + interval '30 days', now());
    raise exception 'one store transaction granted two apps';
  exception when unique_violation then
    null;
  end;

  if exists (
    select 1
    from (values ('public.motion_profiles'), ('public.motion_entitlements'),
      ('public.motion_deleted_account_receipts')) as targets(table_name)
    cross join (values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')) as rights(privilege)
    where not has_table_privilege('service_role', targets.table_name, rights.privilege)
  ) then
    raise exception 'server CRUD privilege boundary failed';
  end if;

  if has_table_privilege('anon', 'public.motion_profiles', 'SELECT')
    or has_table_privilege('anon', 'public.motion_entitlements', 'SELECT')
    or has_column_privilege('authenticated',
      'public.motion_entitlements', 'original_transaction_id', 'SELECT')
    or not has_column_privilege('authenticated',
      'public.motion_entitlements', 'expires_at', 'SELECT')
    or has_table_privilege('anon',
      'public.motion_deleted_account_receipts', 'SELECT')
    or has_table_privilege('authenticated',
      'public.motion_entitlements', 'INSERT')
    or has_table_privilege('authenticated',
      'public.motion_entitlements', 'UPDATE')
    or has_table_privilege('anon',
      'public.motion_store_review_access', 'SELECT')
    or has_table_privilege('authenticated',
      'public.motion_store_review_access', 'SELECT')
    or has_table_privilege('authenticated',
      'public.motion_store_review_access', 'INSERT')
    or not has_table_privilege('service_role',
      'public.motion_store_review_access', 'SELECT')
    or has_function_privilege('anon',
      'public.motion_has_active_membership(text)', 'EXECUTE')
    or not has_function_privilege('authenticated',
      'public.motion_has_active_membership(text)', 'EXECUTE')
  then
    raise exception 'table privilege boundary failed';
  end if;

  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', alice, 'role', 'authenticated')::text, true);

  select count(*) into count_rows from public.motion_profiles;
  if count_rows <> 1 then
    raise exception 'profile owner read failed: %', count_rows;
  end if;
  select count(*) into count_rows from public.motion_entitlements;
  if count_rows <> 2 then
    raise exception 'entitlement owner read failed: %', count_rows;
  end if;
  if not public.motion_has_active_membership('jablab')
    or public.motion_has_active_membership('gravita')
    or public.motion_has_active_membership('choreia')
    or public.motion_has_active_membership('unknown')
  then
    raise exception 'server-time or app-scoped membership check failed';
  end if;
  select count(*) into count_rows from public.motion_entitlements
    where app_id = 'gravita' and state = 'active' and expires_at > now();
  if count_rows <> 0 then
    raise exception 'JabLab purchase unlocked Gravita';
  end if;
  begin
    insert into public.motion_store_review_access (user_id, expires_at)
      values (bob, now() + interval '1 day');
    raise exception 'client granted store review access';
  exception when insufficient_privilege then
    null;
  end;

  reset role;
  insert into public.motion_entitlements
    (user_id, app_id, store, product_id, original_transaction_id,
     state, expires_at, verified_at)
  values
    (alice, 'motion_plus', 'apple', 'motionplus.monthly',
     'alice-motion-plus-1', 'active', now() + interval '30 days', now());
  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', alice, 'role', 'authenticated')::text, true);
  if not public.motion_has_active_membership('ostinato')
    or not public.motion_has_active_membership('gravita')
    or not public.motion_has_active_membership('choreia')
    or not public.motion_has_active_membership('jablab')
    or not public.motion_has_active_membership('lissom')
    or public.motion_has_active_membership('unknown')
    or public.motion_has_active_membership('motion_plus')
  then
    raise exception 'Motion+ scope did not cover exactly five apps';
  end if;

  update public.motion_profiles set display_name = 'Wrong'
    where user_id = bob;
  get diagnostics count_rows = row_count;
  if count_rows <> 0 then
    raise exception 'cross-user profile update succeeded';
  end if;
  reset role;

  set local role authenticated;
  perform set_config('request.jwt.claims',
    json_build_object('sub', bob, 'role', 'authenticated')::text, true);
  if not public.motion_has_active_membership('gravita')
    or public.motion_has_active_membership('jablab')
    or public.motion_has_active_membership('ostinato')
  then
    raise exception 'cross-user membership check failed';
  end if;
  reset role;

  delete from auth.users where id = alice;
  select count(*) into count_rows from public.motion_profiles
    where user_id = alice;
  if count_rows <> 0 then
    raise exception 'deleted account retained profile';
  end if;
  select count(*) into count_rows from public.motion_entitlements
    where user_id = alice;
  if count_rows <> 0 then
    raise exception 'deleted account retained entitlement';
  end if;
  select count(*) into count_rows from public.motion_store_review_access
    where user_id = alice;
  if count_rows <> 0 then
    raise exception 'deleted account retained review grant';
  end if;
  if not public.motion_was_account_deleted(alice)
    or public.motion_was_account_deleted(bob)
  then
    raise exception 'deletion receipt did not distinguish users';
  end if;
  set local role anon;
  if not public.motion_was_account_deleted(alice)
    or public.motion_was_account_deleted(bob)
  then
    raise exception 'anonymous deletion receipt lookup failed';
  end if;
  reset role;
end;
$test$;

rollback;
