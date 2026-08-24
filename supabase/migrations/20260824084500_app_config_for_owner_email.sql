-- Server-side configuration the edge functions read.
--
-- The natural home for OWNER_EMAIL is an edge-function secret, but that
-- is only settable through the dashboard or a CLI holding a personal
-- access token. This is the same thing expressed as a row: it lives in
-- `private`, which PostgREST does not expose, with no grants to anon or
-- authenticated and RLS on top -- so the only thing that can read it is
-- the service role, which is exactly who reads an env secret too.
--
-- It has one advantage over a secret: it is versioned and auditable.
-- And one drawback: a database dump contains it. For an email address
-- that is a question of privacy rather than of credentials -- nothing
-- here grants anything on its own; it only names who may claim the owner
-- role, and only then with a verified matching sign-in.
create table private.app_config (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);

alter table private.app_config enable row level security;
-- No policies at all: RLS with none denies everyone. The service role
-- bypasses RLS, which is the only caller that should see this. The
-- security linter reports this as rls_enabled_no_policy at INFO level;
-- here that is the intent rather than an oversight.
revoke all on private.app_config from public, anon, authenticated;
grant select on private.app_config to service_role;

comment on table private.app_config is
  'Server-side settings for the edge functions. Readable only by the service role -- no policies, and outside the exposed schemas.';
