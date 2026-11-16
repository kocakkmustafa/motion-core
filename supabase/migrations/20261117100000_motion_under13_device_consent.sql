-- Motion under-13 parental consent through a device token (ADR-008, VELI-01).
-- The child has no account and no Auth session yet: the parent approves by
-- mail against a random per-device token. Only SHA-256 digests are stored (of
-- the device token, the link token and the parent address); the raw values
-- never reach a table. Sign-up carries the raw device token in the age
-- metadata; the BEFORE trigger digests it, consumes the approval and strips
-- the metadata. A direct under-13 sign-up without an approved token is still
-- refused (P0013). Server-only tables: no client policy, no grant.
-- Engineering defaults, not legal advice.

-- Device-side consent, keyed by the digest of the device token. No foreign
-- key: there is no account to point at.
create table public.motion_device_consents (
  device_token_digest text primary key
    check (device_token_digest ~ '^[0-9a-f]{64}$'),
  status text not null
    check (status in ('pending', 'approved', 'denied', 'expired')),
  method text not null default 'email_link'
    check (method in ('email_link')),
  -- Cleared when the parent decides (approve or deny).
  parent_email_digest text,
  -- Link token digest. Kept after approval (it becomes the manage digest on
  -- the account row); cleared on denial.
  link_digest text unique,
  locale text not null default 'en' check (char_length(locale) <= 16),
  -- Fixed retention clock (30 days); reset only when an expired row restarts.
  created_at timestamptz not null default now(),
  -- Last mail sent.
  requested_at timestamptz not null default now(),
  -- Link validity (7 days).
  expires_at timestamptz not null,
  decided_at timestamptz,
  requests_today integer not null default 1,
  requests_day date not null default current_date
);

-- Anonymous permanent trace of a decision. No key of any kind.
create table public.motion_consent_decisions (
  id uuid primary key default gen_random_uuid(),
  status text not null check (status in ('approved', 'denied', 'withdrawn')),
  decided_on date not null default current_date,
  method text not null default 'email_link'
);

alter table public.motion_device_consents enable row level security;
alter table public.motion_consent_decisions enable row level security;

revoke all on public.motion_device_consents from public, anon, authenticated;
revoke all on public.motion_consent_decisions from public, anon, authenticated;
grant select, insert, update, delete
  on public.motion_device_consents, public.motion_consent_decisions
  to service_role;

-- Account-side consent rows: a device-consented account has no parent address
-- on file, can be withdrawn, and records how consent was given.
alter table public.motion_parental_consents
  alter column parent_email_digest drop not null;
alter table public.motion_parental_consents
  drop constraint motion_parental_consents_status_check;
alter table public.motion_parental_consents
  add constraint motion_parental_consents_status_check
  check (status in ('pending', 'approved', 'denied', 'expired', 'withdrawn'));
alter table public.motion_parental_consents
  add column method text not null default 'email_link'
    check (method in ('email_link', 'device_token_email'));
-- Digest of the parent's link token, not the address: lets the parent
-- withdraw later without the server keeping the address.
alter table public.motion_parental_consents
  add column manage_digest text unique;
-- The consent row is written before its Auth row exists (BEFORE sign-up
-- trigger), so the foreign key is checked at commit, like the declaration's.
alter table public.motion_parental_consents
  alter constraint motion_parental_consents_user_id_fkey
  deferrable initially deferred;

-- Turn an approved device token into account consent. Digest in, approval out;
-- the device row is deleted (the token digest is bound to the account and
-- gone). False when the token is unknown, not approved or older than 30 days.
create function public.motion_consume_device_consent(
  p_user_id uuid,
  p_device_token text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link text;
  v_locale text;
begin
  if p_user_id is null or p_device_token is null or p_device_token = '' then
    return false;
  end if;
  delete from public.motion_device_consents
    where device_token_digest
            = encode(sha256(convert_to(p_device_token, 'UTF8')), 'hex')
      and status = 'approved'
      and created_at > now() - interval '30 days'
    returning link_digest, locale into v_link, v_locale;
  if not found then
    return false;
  end if;
  insert into public.motion_parental_consents
    (user_id, status, method, manage_digest, locale, expires_at, decided_at)
  values
    (p_user_id, 'approved', 'device_token_email', v_link,
     coalesce(v_locale, 'en'), now(), now())
  on conflict (user_id) do update
    set status = 'approved',
        method = 'device_token_email',
        manage_digest = excluded.manage_digest,
        parent_email_digest = null,
        token_digest = null,
        decided_at = now();
  return true;
end;
$$;

revoke all on function public.motion_consume_device_consent(uuid, text)
  from public, anon, authenticated;

-- The four-argument form is replaced by a five-argument one. Under 13 the
-- declaration is stored only when the device token consumes an approval;
-- otherwise the direct sign-up refusal (P0013) is unchanged.
drop function public.motion_store_age_declaration(uuid, text, text, text);

create function public.motion_store_age_declaration(
  p_user_id uuid,
  p_birth_year_month text,
  p_country text,
  p_policy_version text,
  p_device_token text default null
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
  if v_band = 'blocked'
     and not public.motion_consume_device_consent(p_user_id, p_device_token)
  then
    raise exception 'motion_minimum_age' using errcode = 'P0013';
  end if;
  insert into public.motion_age_declarations
    (user_id, birth_year_month, country, policy_version)
  values (p_user_id, p_birth_year_month, upper(p_country), p_policy_version);
  return v_band;
end;
$$;

revoke all on function public.motion_store_age_declaration(
  uuid, text, text, text, text
) from public, anon, authenticated;

-- Sign-up trigger: pass the raw device token (metadata
-- motion_age.device_consent_token) to the declaration; strip all age
-- metadata, token included, from Auth.
create or replace function public.motion_capture_signup_age()
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
  -- Only the first write (sign-up) declares. A later metadata write cannot
  -- restate an age; the declaration is not self-editable.
  if tg_op = 'INSERT' then
    perform public.motion_store_age_declaration(
      new.id,
      v_age ->> 'birth_year_month',
      v_age ->> 'country',
      coalesce(v_age ->> 'policy_version', 'unknown'),
      v_age ->> 'device_consent_token'
    );
  end if;
  new.raw_user_meta_data := new.raw_user_meta_data - 'motion_age';
  return new;
end;
$$;

revoke all on function public.motion_capture_signup_age()
  from public, anon, authenticated;

-- Short retention, extended:
--  * pending links past expiry are marked expired (account and device rows);
--  * device rows (token digest, parent digest, link digest) go after 30 days,
--    whatever their status; a denied row also goes when the device reads it;
--  * unapproved consent-required or under-13 accounts go after 30 days;
--  * a withdrawn account goes 30 days after the withdrawal.
-- Scheduling (pg_cron or an operator job) is a separate approved action.
create or replace function public.motion_purge_unconsented_accounts(
  p_older_than interval default interval '30 days'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
  v_withdrawn integer;
begin
  update public.motion_parental_consents
    set status = 'expired', token_digest = null
    where status = 'pending' and expires_at < now();
  update public.motion_device_consents
    set status = 'expired', link_digest = null
    where status = 'pending' and expires_at < now();
  delete from public.motion_device_consents
    where created_at < now() - p_older_than;
  with doomed as (
    select d.user_id
    from public.motion_age_declarations d
    left join public.motion_parental_consents c on c.user_id = d.user_id
    where public.motion_age_band(d.birth_year_month, d.country, current_date)
            in ('blocked', 'parental_consent_required')
      and coalesce(c.status, 'none') not in ('approved', 'withdrawn')
      and d.declared_at < now() - p_older_than
  )
  delete from auth.users u using doomed where u.id = doomed.user_id;
  get diagnostics v_count = row_count;
  delete from auth.users u
    using public.motion_parental_consents c
    where c.user_id = u.id
      and c.status = 'withdrawn'
      and c.decided_at < now() - p_older_than;
  get diagnostics v_withdrawn = row_count;
  return v_count + v_withdrawn;
end;
$$;

revoke all on function public.motion_purge_unconsented_accounts(interval)
  from public, anon, authenticated;
grant execute on function public.motion_purge_unconsented_accounts(interval)
  to service_role;
