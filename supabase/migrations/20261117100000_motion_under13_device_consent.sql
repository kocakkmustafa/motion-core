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
    check (status in ('pending', 'approved', 'denied', 'expired', 'withdrawn')),
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

-- Anonymous permanent trace of a decision. No key of any kind. The day is
-- rounded to the start of its (UTC) week so a row cannot be matched to a
-- request, a mail or an account by timing.
create table public.motion_consent_decisions (
  id uuid primary key default gen_random_uuid(),
  status text not null check (status in ('approved', 'denied', 'withdrawn')),
  decided_on date not null
    default ((date_trunc('week', now() at time zone 'utc'))::date),
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
  if v_band = 'blocked' then
    -- Nested on purpose: the consume call has a side effect and must run
    -- only for an under-13 declaration.
    if not public.motion_consume_device_consent(p_user_id, p_device_token)
    then
      raise exception 'motion_minimum_age' using errcode = 'P0013';
    end if;
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
  -- Mail counters are day keyed and append-only; only old days go.
  delete from public.motion_consent_mail_counters
    where day < (now() at time zone 'utc')::date - 1;
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

-- A withdrawn consent never comes back to pending or approved: a new consent
-- needs a new account flow (the withdrawn account is purged after 30 days).
create function public.motion_consent_no_revive()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'motion_consent_withdrawn' using errcode = '23514';
end;
$$;

create trigger motion_consent_no_revive
before update on public.motion_parental_consents
for each row
when (old.status = 'withdrawn' and new.status <> 'withdrawn')
execute function public.motion_consent_no_revive();

-- Consent mail counters: one row per key and UTC day, never decremented and
-- untouched by decisions. Keys: 'p:<parent address digest>' and
-- 'd:<device token digest>' (so one token redirected to other addresses is
-- counted too). Server-only. The limit is per UTC calendar day, so across
-- midnight a key can see up to twice the limit within 24 hours; it is a
-- brake on mail bombing, not a hard 24 hour cap, and there is no global limit.
create table public.motion_consent_mail_counters (
  counter_key text not null check (char_length(counter_key) <= 80),
  day date not null default (now() at time zone 'utc')::date,
  count integer not null default 1,
  primary key (counter_key, day)
);

alter table public.motion_consent_mail_counters enable row level security;
revoke all on public.motion_consent_mail_counters
  from public, anon, authenticated;
grant select, insert, update, delete
  on public.motion_consent_mail_counters to service_role;

-- Reserve one mail on every key, atomically and all-or-nothing, before the
-- mail is sent. False (and nothing counted) when any key is at the limit.
create function public.motion_consent_mail_slot(
  p_keys text[],
  p_limit integer default 5,
  p_day date default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_key text;
  v_count integer;
  v_day date := coalesce(p_day, (now() at time zone 'utc')::date);
begin
  -- The caller names the day it reserves on so a release hits the same row
  -- across midnight; only today or the neighbouring UTC days are accepted.
  if abs(v_day - (now() at time zone 'utc')::date) > 1 then
    raise exception 'invalid_mail_day' using errcode = '22023';
  end if;
  if p_keys is null or coalesce(array_length(p_keys, 1), 0) = 0 then
    raise exception 'invalid_mail_keys' using errcode = '22023';
  end if;
  -- No positive limit, no slot (the first insert would otherwise count 1).
  if p_limit is null or p_limit <= 0 then
    return false;
  end if;
  begin
    foreach v_key in array p_keys loop
      insert into public.motion_consent_mail_counters as c
        (counter_key, day, count)
      values (v_key, v_day, 1)
      on conflict (counter_key, day) do update set count = c.count + 1
        where c.count < p_limit
      returning c.count into v_count;
      if not found then
        raise exception 'motion_mail_limit' using errcode = 'P0014';
      end if;
    end loop;
  exception when sqlstate 'P0014' then
    return false;
  end;
  return true;
end;
$$;

revoke all on function public.motion_consent_mail_slot(
  text[], integer, date
) from public, anon, authenticated;
grant execute on function public.motion_consent_mail_slot(
  text[], integer, date
) to service_role;

-- Give a reserved slot back, only when no mail went out: atomic, never below
-- zero, on the day it was reserved (default: today, UTC).
create function public.motion_consent_mail_slot_release(
  p_keys text[],
  p_day date default null
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.motion_consent_mail_counters
    set count = greatest(count - 1, 0)
    where counter_key = any (p_keys)
      and day = coalesce(p_day, (now() at time zone 'utc')::date);
$$;

revoke all on function public.motion_consent_mail_slot_release(text[], date)
  from public, anon, authenticated;
grant execute on function public.motion_consent_mail_slot_release(text[], date)
  to service_role;

-- State-guarded claim of a device request, BEFORE the mail goes out: the
-- mail is sent only when the claim succeeded. A row a parent decided in the
-- meantime is never put back to pending: the existing status comes back
-- instead. 'ok' on success, 'too_soon' while a
-- pending request is younger than 10 minutes.
create function public.motion_device_consent_request(
  p_device_digest text,
  p_parent_digest text,
  p_link_digest text,
  p_locale text,
  p_expires_at timestamptz
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status text;
begin
  insert into public.motion_device_consents as d
    (device_token_digest, status, method, parent_email_digest, link_digest,
     locale, expires_at, requests_today, requests_day)
  values
    (p_device_digest, 'pending', 'email_link', p_parent_digest, p_link_digest,
     p_locale, p_expires_at, 1, (now() at time zone 'utc')::date)
  on conflict (device_token_digest) do update
    set status = 'pending',
        parent_email_digest = excluded.parent_email_digest,
        link_digest = excluded.link_digest,
        locale = excluded.locale,
        expires_at = excluded.expires_at,
        decided_at = null,
        created_at = case
          when d.status = 'expired' or d.expires_at < now()
               or d.status = 'approved'
               then now()
          else d.created_at end,
        requested_at = now(),
        requests_today = case
          when d.requests_day = (now() at time zone 'utc')::date
            then d.requests_today + 1
          else 1 end,
        requests_day = (now() at time zone 'utc')::date
    where d.status = 'expired'
       -- An approval nobody consumed within 30 days is no longer usable
       -- (consume refuses it): the device may start over.
       or (d.status = 'approved' and d.created_at < now() - interval '30 days')
       or (d.status = 'pending'
           and (d.expires_at < now()
                or d.requested_at <= now() - interval '10 minutes'));
  if found then
    return 'ok';
  end if;
  select status into v_status from public.motion_device_consents
    where device_token_digest = p_device_digest;
  return case when v_status = 'pending' then 'too_soon' else v_status end;
end;
$$;

revoke all on function public.motion_device_consent_request(
  text, text, text, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.motion_device_consent_request(
  text, text, text, text, timestamptz
) to service_role;

-- The mail could not be sent: drop the claim of that (never delivered) link.
-- Only a still pending row with that very link digest changes; it becomes
-- expired (no valid link exists), so the device can start over at once.
create function public.motion_device_consent_unclaim(
  p_device_digest text,
  p_link_digest text
)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.motion_device_consents
    set status = 'expired', link_digest = null, parent_email_digest = null,
        expires_at = now()
    where device_token_digest = p_device_digest
      and link_digest = p_link_digest
      and status = 'pending';
$$;

revoke all on function public.motion_device_consent_unclaim(text, text)
  from public, anon, authenticated;
grant execute on function public.motion_device_consent_unclaim(text, text)
  to service_role;
