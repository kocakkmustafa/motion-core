-- Store transaction references include Google purchase tokens. The mobile
-- client needs the entitlement result, not the provider verification secret.
-- Keep RLS for row ownership and narrow the column-level read grant.
revoke select on public.motion_entitlements from authenticated;
grant select (user_id, app_id, store, product_id, state, expires_at, verified_at)
  on public.motion_entitlements to authenticated;
