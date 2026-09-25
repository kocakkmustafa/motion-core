-- One Motion identity shared by five apps. Paid access is scoped to one app.
-- Client devices can read their own verified rights, never grant them.
create table public.motion_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default ''
    check (char_length(display_name) <= 80),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.motion_entitlements (
  user_id uuid not null references auth.users(id) on delete cascade,
  app_id text not null check
    (app_id in ('ostinato', 'gravita', 'choreia', 'jablab', 'lissom')),
  store text not null check (store in ('apple', 'google')),
  product_id text not null,
  original_transaction_id text not null,
  state text not null check
    (state in ('active', 'grace', 'expired', 'revoked')),
  expires_at timestamptz not null,
  verified_at timestamptz not null,
  primary key (user_id, app_id, store, product_id),
  unique (store, original_transaction_id)
);

create index motion_entitlements_user_app_idx
  on public.motion_entitlements (user_id, app_id);

alter table public.motion_profiles enable row level security;
alter table public.motion_entitlements enable row level security;

create policy motion_profiles_select_own
  on public.motion_profiles for select to authenticated
  using ((select auth.uid()) = user_id);
create policy motion_profiles_insert_own
  on public.motion_profiles for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy motion_profiles_update_own
  on public.motion_profiles for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy motion_entitlements_select_own
  on public.motion_entitlements for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.motion_profiles from anon, authenticated;
revoke all on public.motion_entitlements from anon, authenticated;
grant select, insert, update on public.motion_profiles to authenticated;
grant select on public.motion_entitlements to authenticated;
