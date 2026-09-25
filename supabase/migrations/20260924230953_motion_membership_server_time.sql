-- A mobile clock cannot decide whether a paid right has expired.
-- SECURITY INVOKER retains the caller's own-row RLS policy.
create function public.motion_has_active_membership(p_app_id text)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select exists (
    select 1
    from public.motion_entitlements e
    where e.user_id = auth.uid()
      and e.app_id = p_app_id
      and e.state in ('active', 'grace')
      and e.expires_at > now()
  );
$$;

revoke all on function public.motion_has_active_membership(text)
  from public, anon;
grant execute on function public.motion_has_active_membership(text)
  to authenticated;
