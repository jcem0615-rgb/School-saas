# School Management SaaS

A multi-tenant School Management SaaS for Philippine schools, billed at
₱3/active-student/day. Supports Elementary, High School, and College
divisions under a single school tenant, with data isolation enforced by
role, division, and (for College) department.

**Stack**: Flutter (Riverpod, go_router, Clean Architecture) · Firebase
(Auth, Firestore, Cloud Functions, Storage) · Cloud Functions in
TypeScript.

This repo was built module-by-module; **`docs/`** has one file per
module explaining what was built, every non-obvious design decision, and
what's deliberately deferred. Start there before making changes — a lot
of "why is this collection shaped like this" questions are already
answered in the doc for the module that introduced it.

## Status

All 9 role portals (Owner, Director, Principal, Admin, Registrar,
Faculty, Student, Parent, Staff, Guidance), Auth, QR Attendance,
Payments, and the Division/Program isolation system are built and
tested. **Not yet built**: Notifications (push), Reports, Documents
(PDF/Excel — TOR, Form 137, printable IDs), the standalone Inventory
module, session-timeout/device-tracking security hardening, and
deployment/CI configuration. See the end of
`docs/14-staff-guidance-portals.md` for the full remaining list.

## Repository layout

```
app/                Flutter application
  lib/
    core/            shared config, constants, router, theme, errors
    features/        one folder per module (auth, owner_portal, ...),
                      each following domain/data/presentation
  test/unit/         Dart unit tests, mirrors lib/features/**

functions/           Cloud Functions (TypeScript)
  src/
    callable/        HTTPS callables (provisionUser, recordPayment, ...)
    triggers/        Firestore triggers (generic audit logger, ...)
    scheduled/       cron jobs (billing, grace period checks)
    shared/          pure logic + cross-cutting helpers, unit-tested
  test/              Jest unit tests, mirrors src/**

firestore.rules       Security rules - the real enforcement boundary
firestore.indexes.json
storage.rules
firebase.json          Emulator ports, deploy config
test-rules/             Firestore Rules tests (needs the emulator)
docs/                   One doc per module, in build order
```

## Prerequisites

- Flutter SDK (3.3+ Dart)
- Node.js 20
- Firebase CLI (`npm install -g firebase-tools`)
- A Firebase project per environment (`dev`/`staging`/`prod` — see
  `.firebaserc`), or just the emulator suite for local testing

## Setup

```bash
# Flutter app
cd app
flutter pub get

# Cloud Functions
cd ../functions
npm install
npm run build

# Rules test suite (root level)
cd ..
npm install
```

You'll also need actual Firebase config files that aren't checked in:
`app/lib/firebase_options.dart` (via `flutterfire configure`) and
platform-specific `google-services.json` / `GoogleService-Info.plist`.
None of the test suites below need these — they run against the emulator
or pure Dart/TS logic — but the app itself won't build without them.

## Running the tests

Three independent suites, each covering a different layer:

```bash
# 1. Flutter/Dart unit tests (domain layer: entities, use cases, validation)
cd app
flutter test

# 2. Cloud Functions unit tests (pure logic: billing math, claims guards, ...)
cd functions
npm test                # fast, no emulator needed
npm run test:emulator   # the one counter test that needs Firestore (atomicity check)

# 3. Firestore Security Rules tests (the actual "no data leak" proof)
# from the repo root:
npm install
npm run test:rules
```

`test:rules` starts the Firestore + Auth emulators, runs every
`test-rules/*.rules.test.ts` file against your actual `firestore.rules`,
and tears the emulator down — this is what proves tenant isolation,
role boundaries, and division/department scoping actually hold, not just
that the code compiles. If you change `firestore.rules`, run this before
trusting the change.

## A note on how this was built

Every module's Cloud Functions and Firestore collections were designed
together with their Security Rules and rules tests in the same pass —
the rules are the actual security boundary in this architecture, not the
client UI. Several real bugs were caught and fixed this way during the
build itself (documented in `docs/08-payments.md` and
`docs/15-divisions-and-programs.md`); if you add a new collection or
role capability, the expected pattern is: add the Cloud Function/rule,
then add a rules test that would have caught the bug you're worried
about, in the same commit.
