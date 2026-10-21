-- Motion 13+ age declarations, parental consent and short-retention helpers.
-- Values mirror packages/motion_account/lib/src/motion_age_policy.dart; a
-- package test checks parity. Engineering defaults, not legal advice.

-- Digital-consent age by ISO 3166-1 alpha-2; unknown/unlisted region => 16.
create function public.motion_consent_age(p_country text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case upper(coalesce(p_country, ''))
    when 'AT' then 14 when 'BE' then 13 when 'BG' then 14 when 'HR' then 16
    when 'CY' then 14 when 'CZ' then 15 when 'DK' then 13 when 'EE' then 13
    when 'FI' then 13 when 'FR' then 15 when 'DE' then 16 when 'GR' then 15
    when 'HU' then 16 when 'IE' then 16 when 'IT' then 14 when 'LV' then 13
    when 'LT' then 14 when 'LU' then 16 when 'MT' then 13 when 'NL' then 16
    when 'PL' then 16 when 'PT' then 13 when 'RO' then 16 when 'SK' then 16
    when 'SI' then 15 when 'ES' then 14 when 'SE' then 13 when 'IS' then 13
    when 'LI' then 16 when 'NO' then 13 when 'GB' then 13 when 'CH' then 16
    when 'US' then 13 when 'CA' then 14 when 'BR' then 16 when 'MX' then 18
    when 'AR' then 16 when 'KR' then 14 when 'CN' then 14 when 'JP' then 16
    when 'IN' then 18 when 'ID' then 18 when 'SA' then 18 when 'AE' then 18
    when 'TR' then 18 when 'AU' then 16
    else 16
  end;
$$;

-- Whole years from YYYY-MM; the birth month counts as "birthday not reached".
create function public.motion_age_years(p_birth_year_month text, p_today date)
returns integer
language sql
immutable
set search_path = ''
as $$
  select extract(year from p_today)::integer
       - split_part(p_birth_year_month, '-', 1)::integer
       - case when extract(month from p_today)::integer
                   <= split_part(p_birth_year_month, '-', 2)::integer
              then 1 else 0 end;
$$;

-- blocked | parental_consent_required | teen | adult
create function public.motion_age_band(
  p_birth_year_month text,
  p_country text,
  p_today date
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when public.motion_age_years(p_birth_year_month, p_today) < 13
      then 'blocked'
    when public.motion_age_years(p_birth_year_month, p_today)
         < public.motion_consent_age(p_country)
      then 'parental_consent_required'
    when public.motion_age_years(p_birth_year_month, p_today) < 18
      then 'teen'
    else 'adult'
  end;
$$;

create table public.motion_age_declarations (
  user_id uuid primary key references auth.users(id) on delete cascade,
  birth_year_month text not null
    check (birth_year_month ~ '^[0-9]{4}-(0[1-9]|1[0-2])$'),
  country text check (country ~ '^[A-Z]{2}$'),
  policy_version text not null check (char_length(policy_version) <= 32),
  declared_at timestamptz not null default now()
);

-- One row per teen account. The parent address is never stored in clear:
-- only a digest to rate-limit and match a repeated request.
create table public.motion_parental_consents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null
    check (status in ('pending', 'approved', 'denied', 'expired')),
  parent_email_digest text not null,
  token_digest text unique,
  locale text not null default 'en' check (char_length(locale) <= 16),
  requested_at timestamptz not null default now(),
  expires_at timestamptz not null,
  decided_at timestamptz,
  requests_today integer not null default 1,
  requests_day date not null default current_date
);

alter table public.motion_age_declarations enable row level security;
alter table public.motion_parental_consents enable row level security;

create policy motion_age_declarations_select_own
  on public.motion_age_declarations for select to authenticated
  using ((select auth.uid()) = user_id);
create policy motion_parental_consents_select_own
  on public.motion_parental_consents for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.motion_age_declarations from public, anon, authenticated;
revoke all on public.motion_parental_consents from public, anon, authenticated;
grant select on public.motion_age_declarations to authenticated;
-- The token digest is server-only; teens read status and timing.
grant select (user_id, status, requested_at, expires_at, decided_at)
  on public.motion_parental_consents to authenticated;
-- Explicit server access (auto_expose_new_tables=false grants nothing).
grant select, insert, update, delete
  on public.motion_age_declarations, public.motion_parental_consents
  to service_role;

-- Account features stay closed while a required parental approval is missing.
-- An undeclared legacy account is not restricted here; clients ask first.
create function public.motion_account_restricted(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select public.motion_age_band(d.birth_year_month, d.country, current_date)
             in ('blocked', 'parental_consent_required')
           and not exists (
             select 1 from public.motion_parental_consents c
             where c.user_id = d.user_id and c.status = 'approved'
           )
    from public.motion_age_declarations d
    where d.user_id = p_user_id
  ), false);
$$;

revoke all on function public.motion_account_restricted(uuid) from public;
grant execute on function public.motion_account_restricted(uuid)
  to authenticated, service_role;

create function public.motion_store_age_declaration(
  p_user_id uuid,
  p_birth_year_month text,
  p_country text,
  p_policy_version text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_band text;
begin
  if p_birth_year_month !~ '^[0-9]{4}-(0[1-9]|1[0-2])$' then
    raise exception 'invalid_birth_year_month' using errcode = '22023';
  end if;
  v_band := public.motion_age_band(
    p_birth_year_month, upper(p_country), current_date
  );
  if v_band = 'blocked' then
    raise exception 'motion_minimum_age' using errcode = 'P0013';
  end if;
  insert into public.motion_age_declarations
    (user_id, birth_year_month, country, policy_version)
  values (p_user_id, p_birth_year_month, upper(p_country), p_policy_version);
  return v_band;
end;
$$;

revoke all on function public.motion_store_age_declaration(uuid, text, text, text)
  from public, anon, authenticated;

-- First declaration for a signed-in account without one (e.g. a legacy
-- account). A declaration is not self-editable afterwards: corrections go
-- through support, so a refused teen cannot simply restate an older age.
create function public.motion_record_age_declaration(
  p_birth_year_month text,
  p_country text,
  p_policy_version text
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.motion_age_declarations where user_id = v_user
  ) then
    raise exception 'age_already_declared' using errcode = '23505';
  end if;
  return public.motion_store_age_declaration(
    v_user, p_birth_year_month, p_country, p_policy_version
  );
end;
$$;

revoke all on function public.motion_record_age_declaration(text, text, text)
  from public, anon;
grant execute on function public.motion_record_age_declaration(text, text, text)
  to authenticated;

-- Sign-up carries the neutral age screen result in user metadata. Copy it to
-- the declaration table once and strip it from Auth metadata. Under 13 the
-- sign-up itself fails (defence in depth; the client gate stops it first).
create function public.motion_capture_signup_age()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_age jsonb := new.raw_user_meta_data -> 'motion_age';
begin
  if v_age is null then
    return new;
  end if;
  perform public.motion_store_age_declaration(
    new.id,
    v_age ->> 'birth_year_month',
    v_age ->> 'country',
    coalesce(v_age ->> 'policy_version', 'unknown')
  );
  update auth.users
    set raw_user_meta_data = raw_user_meta_data - 'motion_age'
    where id = new.id;
  return new;
end;
$$;

revoke all on function public.motion_capture_signup_age()
  from public, anon, authenticated;

create trigger motion_capture_signup_age
after insert on auth.users
for each row execute function public.motion_capture_signup_age();

-- Restricted (consent-pending) accounts cannot write the shared profile.
drop policy motion_profiles_insert_own on public.motion_profiles;
drop policy motion_profiles_update_own on public.motion_profiles;
create policy motion_profiles_insert_own
  on public.motion_profiles for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and not public.motion_account_restricted((select auth.uid()))
  );
create policy motion_profiles_update_own
  on public.motion_profiles for update to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and not public.motion_account_restricted((select auth.uid()))
  );

-- Short retention: an unapproved teen account is deleted after 30 days.
-- Deleting the Auth user cascades product rows and writes the anonymous
-- deletion receipt, so every app clears that account's files when online.
-- Scheduling (pg_cron or an operator job) is a separate approved action.
create function public.motion_purge_unconsented_accounts(
  p_older_than interval default interval '30 days'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  update public.motion_parental_consents
    set status = 'expired', token_digest = null
    where status = 'pending' and expires_at < now();
  with doomed as (
    select d.user_id
    from public.motion_age_declarations d
    left join public.motion_parental_consents c on c.user_id = d.user_id
    where public.motion_age_band(d.birth_year_month, d.country, current_date)
            = 'parental_consent_required'
      and coalesce(c.status, 'none') <> 'approved'
      and d.declared_at < now() - p_older_than
  )
  delete from auth.users u using doomed where u.id = doomed.user_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.motion_purge_unconsented_accounts(interval)
  from public, anon, authenticated;
grant execute on function public.motion_purge_unconsented_accounts(interval)
  to service_role;

-- Backup restore: a 30-day point-in-time restore can resurrect accounts that
-- were deleted after the restore point. The operator replays the off-database
-- deletion journal (digests only) after every restore. Deleting the Auth user
-- re-writes the receipt and cascades product rows. Returns rows deleted.
create function public.motion_reapply_deleted_accounts(p_digests text[])
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into public.motion_deleted_account_receipts (user_id_digest)
    select distinct unnest(p_digests)
    on conflict do nothing;
  delete from auth.users u
    where encode(sha256(convert_to(u.id::text, 'UTF8')), 'hex')
          = any (p_digests);
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.motion_reapply_deleted_accounts(text[])
  from public, anon, authenticated;
grant execute on function public.motion_reapply_deleted_accounts(text[])
  to service_role;
