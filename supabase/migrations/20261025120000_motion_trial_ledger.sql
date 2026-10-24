-- One Motion+ free trial per Motion account (founder decision 2026-10-25).
-- Each app's Motion+ sits in its own store subscription group / package, so
-- the stores alone would allow one trial per app. The server records the
-- first verified Motion+ trial; later purchases in another app are sold
-- without a trial (Apple: signed introductory-offer eligibility = false;
-- Google Play: the developer-determined trial offer is not chosen).
-- The row belongs to the account and is deleted with it (short retention).
create table public.motion_trial_ledger (
  user_id uuid primary key references auth.users(id) on delete cascade,
  scope text not null default 'motion_plus' check (scope = 'motion_plus'),
  store text not null check (store in ('apple', 'google')),
  app_id text not null
    check (app_id in ('ostinato', 'gravita', 'choreia', 'jablab', 'lissom')),
  original_transaction_id text not null
    check (char_length(original_transaction_id) between 1 and 2048),
  started_at timestamptz not null default now()
);

alter table public.motion_trial_ledger enable row level security;

create policy motion_trial_ledger_select_own
  on public.motion_trial_ledger for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.motion_trial_ledger from public, anon, authenticated;
-- The account sees only whether and when its trial was used.
grant select (user_id, scope, app_id, started_at)
  on public.motion_trial_ledger to authenticated;
grant select, insert, update, delete on public.motion_trial_ledger
  to service_role;
