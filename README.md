# LogicClass

LogicClass is a multi-tenant school management SaaS for Philippine schools, billed at
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
or pure Dart/TS logic — and neither does **demo mode**, described next.

## Running the app (demo mode)

The app runs with no Firebase project, no emulator, and no network:

```bash
cd app
flutter run -d chrome
```

If you need a build that does not depend on the Dart debug service —
useful for sharing, or if the debug build comes up blank — build once and
serve the output as static files:

```bash
cd app && flutter build web --release --no-web-resources-cdn && (cd build/web && python3 -m http.server 8080)
```

Then open `http://127.0.0.1:8080`. Note that `flutter run -d web-server`
serves a *debug* build whose renderer waits on a debug-service connection
that only the Chrome/Edge devices (or the Dart Debug extension) provide —
without it the page loads but never paints. Use `-d chrome` or the
release build above instead.

That's the whole setup. `lib/main.dart` defaults to `DEMO_MODE=true`,
which swaps every repository for an in-memory implementation from
`lib/demo/`. Only the repository layer is replaced — the router,
controllers, use cases, and all ~200 widget files are the real ones, so
what you click through is the actual app, not a mock-up of it.

Sign in with any of ten seeded accounts, one per role:

| Role | Email | Role | Email |
|---|---|---|---|
| Owner | `owner@demo.ph` | Faculty | `faculty@demo.ph` |
| Director | `director@demo.ph` | Staff | `staff@demo.ph` |
| Principal | `principal@demo.ph` | Guidance | `guidance@demo.ph` |
| Admin | `admin@demo.ph` | Student | `student@demo.ph` |
| Registrar | `registrar@demo.ph` | Parent | `parent@demo.ph` |

The password for all of them is `demo1234`. A floating **Demo accounts**
button switches roles in one tap without logging out.

Seeded data covers four schools in mixed subscription states, eight
students across all three divisions, payments including a refund, two
weeks of attendance, coursework, grades, approvals, and an audit trail —
enough that no screen is empty. Writes are live: recording a payment
updates the student's balance and shows up in the audit log immediately.
Nothing persists across a page reload.

**Demo mode is not a security model.** The real access boundary is
`firestore.rules`, and the fakes reproduce none of it — anything the UI
lets you tap will succeed regardless of role. Role, division, and
department isolation is proven by `npm run test:rules`, not by clicking
around in demo mode.

To run against real Firebase instead, generate `firebase_options.dart`,
uncomment the `Firebase.initializeApp` call in `lib/main.dart`, and run
with `--dart-define=DEMO_MODE=false`.

## Running on a phone

The `android/` and `ios/` folders are checked in and configured for the
plugins this app uses -- camera and gallery for QR scanning and receipts,
location for the emergency alert, notifications for pushes -- so demo mode
runs on a device with no further setup:

```bash
cd app
flutter run            # with a phone attached, or an emulator/simulator running
```

Identifiers, both of which must match what you register in the Firebase
console before the app can talk to a real backend:

| Platform | Identifier | Where |
|---|---|---|
| Android | `ph.schoolsaas.school_saas` | `android/app/build.gradle.kts` |
| iOS | `ph.schoolsaas.schoolSaas` | Xcode target, or `ios/Runner.xcodeproj` |

Change them before your first release -- an Android `applicationId` cannot
be changed once the app is on the Play Store.

**What is still needed for a real (non-demo) build on a phone:** the same
Firebase config this repo has never carried. `flutterfire configure`
generates `app/lib/firebase_options.dart`, writes
`android/app/google-services.json` and
`ios/Runner/GoogleService-Info.plist`, and adds the `google-services`
Gradle plugin. That plugin is deliberately *not* wired up here: without
the matching JSON file it fails the Android build, which would mean nobody
could run demo mode on a phone until they had a Firebase project.

Minimums are pinned rather than inherited: `minSdk = 23` (firebase_auth
5.x requires it) and iOS 15. Notification scheduling needs Java 8+ APIs on
older Androids, so core library desugaring is switched on in the app's
Gradle file.

## Running the tests

Three independent suites, each covering a different layer:

```bash
# 1. Flutter/Dart unit tests (domain layer: entities, use cases, validation)
#    plus test/smoke/, which boots the whole app in demo mode and checks
#    that all ten roles reach their portal without throwing
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

`test:rules` needs the Firebase CLI. If you'd rather not install it, the
suite runs against any Firestore emulator you point it at:

```bash
java -jar cloud-firestore-emulator.jar --host=127.0.0.1 --port=8085 &
FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 npx jest --config jest.config.js --runInBand
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
