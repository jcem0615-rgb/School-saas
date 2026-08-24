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

## What does not exist yet

Everything else. Students, attendance, coursework, grades, payments,
announcements, guidance records, the audit log — about twenty collections
— plus the callables (`provisionUser`, `createSchool`, `markAttendance`,
the billing jobs) as Edge Functions, and a Dart data layer built on
`supabase_flutter` instead of `cloud_firestore`.

That is the bulk of the work. Moving this app off Firebase is a rewrite of
its data layer, not a deployment, and this directory is the foundation it
would sit on.

## Applying migrations

They are already applied to the project above. To rebuild elsewhere:

```sh
supabase link --project-ref <ref>
supabase db push
```
