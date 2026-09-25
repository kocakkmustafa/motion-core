-- A verified Motion+ purchase covers the five named consumer apps.
-- Keep the original product/store transaction in its one row; only the
-- entitlement scope broadens. Clients remain read-only under the existing RLS.
alter table public.motion_entitlements
  drop constraint motion_entitlements_app_id_check;
alter table public.motion_entitlements
  add constraint motion_entitlements_app_id_check check
    (app_id in ('ostinato', 'gravita', 'choreia', 'jablab', 'lissom',
                'motion_plus'));

create or replace function public.motion_has_active_membership(p_app_id text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select p_app_id in ('ostinato', 'gravita', 'choreia', 'jablab', 'lissom')
    and exists (
      select 1
      from public.motion_entitlements e
      where e.user_id = auth.uid()
        and e.app_id in (p_app_id, 'motion_plus')
        and e.state in ('active', 'grace')
        and e.expires_at > now()
    );
$$;

revoke all on function public.motion_has_active_membership(text)
  from public, anon;
grant execute on function public.motion_has_active_membership(text)
  to authenticated;
