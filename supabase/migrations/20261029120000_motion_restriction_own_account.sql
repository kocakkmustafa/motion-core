-- A signed-in caller may ask only about its own account. The profile RLS
-- policies pass auth.uid(); the consent function calls with the service role.
-- Before this, any authenticated user could learn whether another account
-- (by UUID) was a consent-pending minor. Callers without JWT claims (SQL
-- editor, pg_cron, database owner) are unchanged.
create or replace function public.motion_account_restricted(p_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := nullif(current_setting('request.jwt.claims', true), '')::jsonb
    ->> 'role';
begin
  if v_role is not null
     and v_role <> 'service_role'
     and p_user_id is distinct from (select auth.uid()) then
    raise exception 'motion_restriction_not_own_account'
      using errcode = '42501';
  end if;
  return coalesce((
    select public.motion_age_band(d.birth_year_month, d.country, current_date)
             in ('blocked', 'parental_consent_required')
           and not exists (
             select 1 from public.motion_parental_consents c
             where c.user_id = d.user_id and c.status = 'approved'
           )
    from public.motion_age_declarations d
    where d.user_id = p_user_id
  ), false);
end;
$$;

revoke all on function public.motion_account_restricted(uuid) from public;
grant execute on function public.motion_account_restricted(uuid)
  to authenticated, service_role;
