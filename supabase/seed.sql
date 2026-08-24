-- Values that belong to this deployment rather than to the schema.
--
-- owner_email names the single address permitted to claim the owner role
-- through the bootstrap-owner edge function. It grants nothing by
-- itself: the claim also requires signing in as that address, with it
-- verified, and succeeds only while no owner exists.
insert into private.app_config (key, value)
values ('owner_email', 'jcem0615@gmail.com')
on conflict (key) do update
  set value = excluded.value, updated_at = now();
