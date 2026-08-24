# Supabase

The app's backend is Firebase. This directory is the beginning of a
Postgres equivalent, not a second copy of it — the two do not run side by
side, and nothing in `app/` reads from here yet.

## What exists

`migrations/` holds the tenancy spine, applied to the **LogicClass**
project (`gikihpfdfssccnnketbe`, ap-southeast-1):

- `schools`, `school_subscriptions`, `user_profiles`
- the role and status enums, matching `UserRole` in
  `app/lib/core/constants/user_roles.dart`
- row level security on every table, standing in for `firestore.rules`
- security-definer helpers in a `private` schema, deliberately outside the
  PostgREST-exposed schemas so none of them is reachable over HTTP

Two invariants the Firebase side enforced in application code are
enforced by the database here instead:

- **One owner.** A partial unique index, so no code path can produce a
  second — not a migration, not a SQL console, not a future function with
  a bug in it. In Firebase this was a Cloud Function that refused to run
  twice.
- **The owner belongs to no school.** A check constraint. Firebase
  expressed this by leaving `schoolId` off the owner's custom claims,
  which nothing enforced.

## Edge functions

Three are deployed, the three whose Firebase counterparts operate on
exactly the tables that exist:

| Function | Firebase original | Notes |
| --- | --- | --- |
| `bootstrap-owner` | `bootstrapOwner` | Needs the `OWNER_EMAIL` secret |
| `create-school` | `createSchool` | Delegates to the `create_school` RPC |
| `provision-user` | `provisionUser` | Service role; mints Auth accounts |

All three have `verify_jwt` on.

`create-school` deliberately does almost nothing itself. A school is two
rows and half a school is unusable, so the inserts belong in a Postgres
function, whose body is a transaction. It calls that RPC with the
*caller's* JWT rather than the service role, so RLS still decides — the
function holds no privilege to lose.

`provision-user` is the opposite: minting an Auth account is not
something RLS can express, so it runs as the service role and every check
in it is load-bearing. The provisioning matrix is copied from the Firebase
version, including that `owner` appears in no row of it.

### Who may claim the owner role

`bootstrap-owner` reads the permitted address from `OWNER_EMAIL` if that
secret is set, and otherwise from `private.app_config`. It is currently
set in the table, to the project owner's address.

The table exists because edge-function secrets can only be set from the
dashboard or by a CLI holding a personal access token — neither of which
was available where this was built. `private.app_config` is the same
thing as a row: outside the schemas PostgREST exposes, no grants to anon
or authenticated, RLS on with no policies, so only the service role can
read it. The security linter reports `rls_enabled_no_policy` at INFO
level for it; there, that is the intent.

To move it to a real secret later, set one — the env var takes
precedence and no code changes:

```sh
supabase secrets set OWNER_EMAIL=you@example.com --project-ref gikihpfdfssccnnketbe
```

With neither set, the function refuses every caller rather than falling
back to something permissive.

The address grants nothing on its own. Claiming the role also requires
signing in as it, with the address verified, and only while no owner
exists — after which `one_owner_only` refuses everyone, that address
included.

## What does not exist yet

Everything else. Students, attendance, coursework, grades, payments,
announcements, guidance records, the audit log — about twenty collections
— plus the remaining callables (`markAttendance`, the payment functions,
the billing jobs) and a Dart data layer built on `supabase_flutter`
instead of `cloud_firestore`.

That is the bulk of the work. Moving this app off Firebase is a rewrite of
its data layer, not a deployment, and this directory is the foundation it
would sit on.

## Applying migrations

They are already applied to the project above. To rebuild elsewhere:

```sh
supabase link --project-ref <ref>
supabase db push
```

## The CLI

`supabase init` scaffolding is committed, so the CLI works against this
repo. It is not how the migrations here were applied — those went through
the Supabase MCP connector, which carries its own auth — but it is what
you would use locally or from CI.

The CLI needs a personal access token, which the connector's credentials
are not:

```sh
export SUPABASE_ACCESS_TOKEN=...        # supabase.com/dashboard/account/tokens
supabase link --project-ref gikihpfdfssccnnketbe
supabase migration list                 # local vs remote, should agree
supabase db push                        # apply anything new
```

`supabase db push` on the current tree is a no-op: all three migrations
are already applied to the LogicClass project.
