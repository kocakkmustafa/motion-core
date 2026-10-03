-- Explicit server access: local auto_expose_new_tables=false does not grant CRUD.
-- Client policies and column grants remain unchanged.
grant select, insert, update, delete
  on public.motion_profiles, public.motion_entitlements,
     public.motion_deleted_account_receipts
  to service_role;
