-- The helpers were in `public`, which PostgREST exposes: every one of
-- them was reachable as /rest/v1/rpc/<name>, by anon as well as by
-- signed-in users. The trigger functions especially had no business
-- being callable at all.
--
-- Revoking EXECUTE is not the fix. An RLS policy expression is evaluated
-- as the querying user, so taking EXECUTE away from `authenticated`
-- would break every policy that calls one. Moving them to a schema
-- PostgREST does not expose removes the HTTP surface and leaves the
-- policies working.

create schema if not exists private;

create function private.auth_role()
  returns public.user_role
  language sql stable security definer set search_path = public, pg_temp
as $$ select role from public.user_profiles where id = auth.uid() $$;

create function private.auth_school_id()
  returns text
  language sql stable security definer set search_path = public, pg_temp
as $$ select school_id from public.user_profiles where id = auth.uid() $$;

create function private.is_owner()
  returns boolean
  language sql stable security definer set search_path = public, pg_temp
as $$ select coalesce(private.auth_role() = 'owner', false) $$;

create function private.is_active()
  returns boolean
  language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce(
    (select status = 'active' from public.user_profiles where id = auth.uid()),
    false)
$$;

create function private.belongs_to_school(target text)
  returns boolean
  language sql stable security definer set search_path = public, pg_temp
as $$ select private.auth_school_id() is not distinct from target $$;

create function private.has_role(target text, roles public.user_role[])
  returns boolean
  language sql stable security definer set search_path = public, pg_temp
as $$
  select private.belongs_to_school(target)
     and private.is_active()
     and private.auth_role() = any (roles)
$$;

create function private.schools_guard_billing_rate()
  returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.billing_rate_per_student is distinct from old.billing_rate_per_student
     and not private.is_owner() then
    raise exception 'Only the owner can change a school''s billing rate';
  end if;
  if new.id is distinct from old.id then
    raise exception 'A school id is permanent';
  end if;
  return new;
end $$;

create function private.user_profiles_guard_privileges()
  returns trigger language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  -- profiles_self_update proves who you are, not what you may change.
  -- Without this it would let anyone promote themselves.
  if new.role is distinct from old.role
     or new.school_id is distinct from old.school_id
     or new.status is distinct from old.status then
    raise exception 'Role, school and status are set by the server, not the account holder';
  end if;
  return new;
end $$;

grant usage on schema private to authenticated;

create trigger schools_guard_billing_rate
  before update on public.schools
  for each row execute function private.schools_guard_billing_rate();

create trigger user_profiles_guard_privileges
  before update on public.user_profiles
  for each row
  when (current_setting('role', true) is distinct from 'service_role')
  execute function private.user_profiles_guard_privileges();

-- Schools: readable by their own members, and by the Owner across the
-- platform. Only the Owner creates or removes one -- there is no sign-up.
create policy schools_read_own on public.schools
  for select to authenticated
  using (private.is_owner() or private.belongs_to_school(id));

create policy schools_owner_insert on public.schools
  for insert to authenticated
  with check (private.is_owner());

create policy schools_owner_delete on public.schools
  for delete to authenticated
  using (private.is_owner());

create policy schools_update on public.schools
  for update to authenticated
  using (private.is_owner() or private.has_role(id, array['director','admin']::public.user_role[]))
  with check (private.is_owner() or private.has_role(id, array['director','admin']::public.user_role[]));

-- Subscriptions are the Owner's ledger. A school may look at its own
-- status -- that is what the "suspended" notice reads -- and change none
-- of it.
create policy subscriptions_read on public.school_subscriptions
  for select to authenticated
  using (private.is_owner() or private.belongs_to_school(school_id));

create policy subscriptions_owner_write on public.school_subscriptions
  for all to authenticated
  using (private.is_owner())
  with check (private.is_owner());

-- Profiles: your own always, your school's colleagues, everything for the
-- Owner. Reading your own row stays possible while suspended, so the app
-- can explain why rather than showing a blank screen.
create policy profiles_read on public.user_profiles
  for select to authenticated
  using (
    id = auth.uid()
    or private.is_owner()
    or private.belongs_to_school(school_id)
  );

-- Nobody writes a role from the client. Provisioning runs server-side
-- with the service role, which bypasses RLS entirely -- the same division
-- the Cloud Functions had, where callables minted accounts and the rules
-- file denied the client.
create policy profiles_self_update on public.user_profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

comment on schema private is
  'Security-definer helpers backing the RLS policies. Deliberately outside the PostgREST-exposed schemas so none of it is reachable over HTTP.';
