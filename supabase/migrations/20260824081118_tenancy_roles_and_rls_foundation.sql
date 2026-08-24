-- LogicClass on Postgres: the tenancy spine.
--
-- The app's backend is Firebase, where a "school" is a document id that
-- every nested path hangs off and firestore.rules decides who may read
-- what. This is the same shape in relational terms: schools are rows,
-- membership is a column, and RLS replaces the rules file.

create type public.user_role as enum (
  'owner','director','principal','admin','registrar',
  'faculty','staff','guidance','student','parent'
);
create type public.account_status as enum ('pending_approval','active','suspended');
create type public.subscription_status as enum ('active','grace_period','suspended');

-- The id is chosen, not generated: it is what every account in the school
-- is scoped to, it appears in URLs, and it cannot be renamed afterwards.
-- The pattern matches SCHOOL_ID_PATTERN in the createSchool callable.
create table public.schools (
  id                        text primary key
                            check (id ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name                      text not null check (length(btrim(name)) > 0),
  address_line              text,
  contact_email             text,
  contact_phone             text,
  logo_url                  text,
  billing_rate_per_student  numeric(10,2) not null default 0
                            check (billing_rate_per_student >= 0),
  created_at                timestamptz not null default now(),
  created_by                uuid references auth.users (id) on delete set null
);

-- Split from schools because it is the Owner's data, not the school's: a
-- Director may edit their own school's name and never its billing.
create table public.school_subscriptions (
  school_id               text primary key
                          references public.schools (id) on delete cascade,
  current_status          public.subscription_status not null default 'active',
  active_student_count    integer not null default 0
                          check (active_student_count >= 0),
  current_cycle_accrued   numeric(12,2) not null default 0,
  grace_period_started_at timestamptz,
  suspended_at            timestamptz,
  created_at              timestamptz not null default now()
);

create table public.user_profiles (
  id                   uuid primary key
                       references auth.users (id) on delete cascade,
  school_id            text references public.schools (id) on delete cascade,
  role                 public.user_role not null,
  status               public.account_status not null default 'active',
  first_name           text not null,
  last_name            text not null,
  email                text not null,
  must_change_password boolean not null default false,
  created_at           timestamptz not null default now(),
  -- The Owner is platform-level and belongs to no tenant; everybody else
  -- belongs to exactly one. Firebase expressed this by leaving schoolId
  -- off the Owner's custom claims, which nothing enforced.
  constraint owner_is_platform_level check (
    (role = 'owner'  and school_id is null) or
    (role <> 'owner' and school_id is not null)
  )
);

create index user_profiles_school_idx on public.user_profiles (school_id);

-- There is exactly one Owner. In Firebase that was a Cloud Function
-- refusing to run twice; here the database itself will not hold a second
-- row, so no code path -- not a migration, not a stray SQL console, not a
-- future function with a bug in it -- can produce one.
create unique index one_owner_only
  on public.user_profiles ((true))
  where role = 'owner';

alter table public.schools              enable row level security;
alter table public.school_subscriptions enable row level security;
alter table public.user_profiles        enable row level security;

comment on table public.schools is
  'One row per tenant. Created only by the Owner; the id is permanent because every account and record in the school is scoped to it.';
comment on index public.one_owner_only is
  'At most one owner account, enforced by the database rather than by application code.';
