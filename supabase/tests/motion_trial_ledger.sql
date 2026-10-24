-- Contract: one Motion+ trial row per account, own-row read only, server
-- writes only, deleted with the account. Rolled back.
begin;
insert into auth.users
  (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'trial-a@motion.test', 'x', now(), now()),
  ('77777777-7777-7777-7777-777777777777', '00000000-0000-0000-0000-000000000000', 'authenticated',
   'authenticated', 'trial-b@motion.test', 'x', now(), now());

-- Server writes; the first trial wins and a second row for the account fails.
set local role service_role;
insert into public.motion_trial_ledger (user_id, store, app_id, original_transaction_id)
  values ('66666666-6666-6666-6666-666666666666', 'apple', 'jablab', '2000000000000001');
do $$
begin
  insert into public.motion_trial_ledger (user_id, store, app_id, original_transaction_id)
    values ('66666666-6666-6666-6666-666666666666', 'google', 'lissom', 'token');
  raise exception 'second trial row accepted';
exception when unique_violation then null;
end $$;
do $$
begin
  insert into public.motion_trial_ledger (user_id, scope, store, app_id, original_transaction_id)
    values ('77777777-7777-7777-7777-777777777777', 'individual', 'apple', 'jablab', 'x');
  raise exception 'non Motion+ scope accepted';
exception when check_violation then null;
end $$;
reset role;

-- A signed-in account reads only its own row and cannot write.
select set_config('request.jwt.claims',
  json_build_object('sub', '77777777-7777-7777-7777-777777777777', 'role', 'authenticated')::text, true);
set local role authenticated;
do $$
declare seen integer;
begin
  select count(*) into seen from public.motion_trial_ledger;
  if seen <> 0 then raise exception 'foreign trial row visible'; end if;
  begin
    insert into public.motion_trial_ledger (user_id, store, app_id, original_transaction_id)
      values (auth.uid(), 'apple', 'jablab', 'self');
    raise exception 'client insert accepted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform original_transaction_id from public.motion_trial_ledger;
    raise exception 'transaction reference readable by client';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
select set_config('request.jwt.claims',
  json_build_object('sub', '66666666-6666-6666-6666-666666666666', 'role', 'authenticated')::text, true);
set local role authenticated;
do $$
begin
  if (select count(*) from public.motion_trial_ledger) <> 1 then
    raise exception 'own trial row not visible';
  end if;
end $$;
reset role;

-- Account deletion removes the trial record.
delete from auth.users where id = '66666666-6666-6666-6666-666666666666';
do $$
begin
  if exists (select 1 from public.motion_trial_ledger) then
    raise exception 'trial row survived account deletion';
  end if;
end $$;
rollback;
