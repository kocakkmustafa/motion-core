-- Store reviewers need full paid-content access without purchasing a product.
-- This grant is separate from provider-verified subscriptions and expires.
create table public.motion_store_review_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now(),
  expires_at timestamptz not null,
  purpose text not null default 'store_review'
    check (purpose = 'store_review'),
  constraint motion_store_review_access_max_duration check (
    expires_at > granted_at
    and expires_at <= granted_at + interval '90 days'
  )
);

alter table public.motion_store_review_access enable row level security;
revoke all on public.motion_store_review_access from public, anon, authenticated;
grant select, insert, update, delete on public.motion_store_review_access
  to service_role;
