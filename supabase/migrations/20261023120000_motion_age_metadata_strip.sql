-- GoTrue writes its in-memory user (including the sign-up metadata) back to
-- auth.users after the insert, which undid the AFTER INSERT strip. Capture
-- and strip in a BEFORE trigger instead, and strip `motion_age` on every
-- later write as well. The declaration row is inserted before its Auth row
-- exists, so its foreign key is checked at commit.
alter table public.motion_age_declarations
  alter constraint motion_age_declarations_user_id_fkey
  deferrable initially deferred;

drop trigger motion_capture_signup_age on auth.users;

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
      coalesce(v_age ->> 'policy_version', 'unknown')
    );
  end if;
  new.raw_user_meta_data := new.raw_user_meta_data - 'motion_age';
  return new;
end;
$$;

revoke all on function public.motion_capture_signup_age()
  from public, anon, authenticated;

create trigger motion_capture_signup_age
before insert or update on auth.users
for each row execute function public.motion_capture_signup_age();
