-- A deletion receipt lets each app remove its own on-device records even if
-- Auth expires its cached session before it can observe user_not_found.
-- Only a digest of the random Auth UUID is retained; no profile or raw ID is.
create table public.motion_deleted_account_receipts (
  user_id_digest text primary key
);

alter table public.motion_deleted_account_receipts enable row level security;
revoke all on public.motion_deleted_account_receipts from public, anon, authenticated;

create function public.motion_record_deleted_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.motion_deleted_account_receipts (user_id_digest)
    values (encode(sha256(convert_to(old.id::text, 'UTF8')), 'hex'))
    on conflict do nothing;
  return old;
end;
$$;

revoke all on function public.motion_record_deleted_account() from public, anon, authenticated;

create trigger motion_record_deleted_account
after delete on auth.users
for each row execute function public.motion_record_deleted_account();

create function public.motion_was_account_deleted(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.motion_deleted_account_receipts
    where user_id_digest = encode(
      sha256(convert_to(p_user_id::text, 'UTF8')), 'hex'
    )
  );
$$;

revoke all on function public.motion_was_account_deleted(uuid) from public;
grant execute on function public.motion_was_account_deleted(uuid)
  to anon, authenticated;
