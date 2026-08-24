create extension if not exists unaccent with schema extensions;

-- Third implementation of this, and the first two disagreed: the
-- TypeScript folded "Muñoz Elementary" to "mun-oz-elementary" and the
-- Dart to "mu-oz-elementary", because NFKD splits the letter and leaves a
-- combining mark for the separator rule to catch. Filipino school names
-- carry enough enyes for that to be the common case. Doing it in the
-- database means the server has one answer, whatever calls it.
create function private.slugify(source text)
  returns text
  language sql stable
  set search_path = extensions, pg_temp
as $$
  select left(
    trim(both '-' from regexp_replace(lower(unaccent(source)), '[^a-z0-9]+', '-', 'g')),
    48)
$$;

grant execute on function private.slugify(text) to authenticated;

-- Creating a school is two rows: the school and its subscription. A
-- function body runs inside the caller's transaction, so either both
-- land or neither does. Half a school is invisible in the Owner's list
-- and unusable by its Director.
--
-- SECURITY INVOKER on purpose. The obvious way to write this is DEFINER,
-- which would then need EXECUTE granted to authenticated -- an exposed
-- definer function, exactly what was just moved out of `public`. As
-- invoker it runs under the caller's own RLS: the schools_owner_insert
-- policy is what actually decides, and the explicit check below only
-- exists to return a sentence instead of a policy violation.
create function public.create_school(
  p_name          text,
  p_billing_rate  numeric,
  p_school_id     text default null,
  p_address_line  text default null,
  p_contact_email text default null,
  p_contact_phone text default null
) returns text
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  v_id text;
begin
  if not private.is_owner() then
    raise exception 'Only the owner can create a school'
      using errcode = '42501';
  end if;

  if p_name is null or length(btrim(p_name)) = 0 then
    raise exception 'The school needs a name' using errcode = '22023';
  end if;

  if p_billing_rate is null or p_billing_rate < 0 then
    raise exception 'Billing rate must be zero or more' using errcode = '22023';
  end if;

  v_id := coalesce(nullif(btrim(p_school_id), ''), private.slugify(p_name));

  if v_id is null or v_id !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'School id must be lowercase letters, digits and hyphens'
      using errcode = '22023';
  end if;

  insert into public.schools (
    id, name, address_line, contact_email, contact_phone,
    billing_rate_per_student, created_by
  ) values (
    v_id,
    btrim(p_name),
    nullif(btrim(p_address_line), ''),
    lower(nullif(btrim(p_contact_email), '')),
    nullif(btrim(p_contact_phone), ''),
    p_billing_rate,
    auth.uid()
  );

  -- Defaults cover the rest: active, no students, nothing accrued. A
  -- school created a moment ago has not been billed for anyone.
  insert into public.school_subscriptions (school_id) values (v_id);

  return v_id;
exception
  when unique_violation then
    -- Overwriting would hand a second school every record belonging to
    -- the first, since the id is what everything is scoped to.
    raise exception 'A school with the id "%" already exists', v_id
      using errcode = '23505';
end $$;

grant execute on function public.create_school(text, numeric, text, text, text, text)
  to authenticated;

comment on function public.create_school is
  'Creates a school and its subscription atomically. Owner only, enforced by RLS on the underlying inserts.';
