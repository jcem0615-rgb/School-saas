-- Postgres grants EXECUTE on new functions to PUBLIC by default, and
-- anon is a member of PUBLIC. Schema USAGE is what actually stops anon
-- reaching these -- it has none on `private` -- but a single revoked
-- grant should not be the only thing standing between anonymous traffic
-- and a definer function. Take the default grant away too, so both
-- doors are shut.
revoke execute on all functions in schema private from public;

-- Re-grant to the one role that needs them: RLS policy expressions run
-- as the querying user, so `authenticated` must be able to call these or
-- every policy fails closed.
grant execute on function private.auth_role()                        to authenticated;
grant execute on function private.auth_school_id()                   to authenticated;
grant execute on function private.is_owner()                         to authenticated;
grant execute on function private.is_active()                        to authenticated;
grant execute on function private.belongs_to_school(text)            to authenticated;
grant execute on function private.has_role(text, public.user_role[]) to authenticated;

-- Anything created here later starts with no PUBLIC grant either.
alter default privileges in schema private revoke execute on functions from public;
