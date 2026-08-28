# Module 21: System Check

## Overview

The preflight for the half hour before a school is let in. Every check in
it is a real first-day failure: rules left in test mode, a function that
never deployed, an index nobody created, a bucket that refuses writes,
an account with no claims. Each is invisible until somebody hits the one
screen that needs it — which, on an onboarding call, is the worst
possible moment to find out.

Director and Admin only, alongside the audit trail and reports.

## What it checks

| Check | Passes when | Fails because |
|---|---|---|
| Database reachable | A read from the school's records returns | Wrong project id or API key, Firestore not enabled |
| **Security rules deployed** | A write the rules must refuse **is** refused | Project still on test-mode rules |
| Cloud Functions deployed | All twelve answer and refuse an empty payload | Not deployed, or deployed to another region |
| Database indexes created | Five probe queries run | `firestore:indexes` never deployed |
| File storage writable | A probe file is written and removed | Storage rules not deployed, or Storage not enabled |
| Account claims set | The token carries a role and the right `schoolId` | Account made by hand in the console; or a stale token |
| School details filled in | Name, logo, year, principal and DPO all set | Nobody has been through Branding yet — a **warning**, not a failure |

## The rules check is the one that matters

A project left in test mode allows every write from any signed-in
client. Everything in the app still works — better, in fact, since
nothing is ever refused — so there is **no symptom at all** until the day
somebody notices one school reading another's records.

`scheduleBlocks` refuses every client write outright, so a write that
*succeeds* is proof the deployed rules are not these rules. If it does
succeed, the probe deletes what it wrote, so the check does not leave
behind the junk record it was warning about.

## Nothing here changes the school's data

Safe by construction rather than by cleanup:

- **Callables** are called with an empty payload. Every one of them
  validates `schoolId` before it touches the database, so the call is
  refused before any write. That is a property of how they were written,
  and this check quietly depends on it — a callable that started writing
  before validating would make this probe unsafe.
- **The rules probe** attempts a write the rules must refuse. It only
  writes anything in the case where it is about to report a failure.
- **The index probes** are reads.
- **The storage probe** is the one real write: a one-pixel PNG to a
  dedicated `preflight/` path, removed immediately. A PNG rather than a
  text file because `storage.rules` accepts only images and PDFs — see
  below.

Nothing runs on open, either. Twelve function calls and a Storage write
are something a person asks for, not something a screen does to a live
deployment because it was navigated to.

## `invalid-argument` is the pass

For the callable probe, being *refused* is success: it means the function
is deployed, in the right region, and got far enough to validate its
input. `unauthenticated` and `permission-denied` also count as deployed
— whether this account may call it is a different question from whether
it exists.

Not answering at all is the failure, and it arrives under several codes:
`not-found`, `internal`, `unavailable`, `deadline-exceeded`, `cancelled`.
A refused connection and a wrong region both land in that set.

## Demo mode reports that nothing was checked

This is the one demo repository that deliberately does **not** simulate
its real counterpart. Every other fake exists so the demo behaves like
the app; `DemoSystemCheckRepository` exists so it does not.

A preflight that goes green against an in-memory store is worse than no
preflight — it is a green light that means nothing, shown to the one
person who most needs it to mean something. So demo mode checks nothing,
returns no results, and says so.

## Running it against the emulator suite

`--dart-define=USE_FIREBASE_EMULATORS=true` (with `DEMO_MODE=false`)
points every SDK at a locally running Firebase Emulator Suite. Opt-in and
off by default: a build that silently talked to localhost instead of the
school's project would be the worst kind of configuration bug, since
everything would appear to work, against nothing.

```sh
firebase emulators:start --only auth,firestore,storage
flutter build web --release \
  --dart-define=DEMO_MODE=false \
  --dart-define=USE_FIREBASE_EMULATORS=true \
  --dart-define=FIREBASE_PROJECT_ID=demo-logicclass \
  --dart-define=FIREBASE_API_KEY=any-non-empty-value \
  --dart-define=FIREBASE_APP_ID=1:1:web:local \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=1 \
  --dart-define=FIREBASE_STORAGE_BUCKET=demo-logicclass.appspot.com \
  --dart-define=FIREBASE_AUTH_DOMAIN=localhost
```

This is the real rules engine, real Firestore, real Auth with real custom
claims and real Storage — not a stand-in for them. What it cannot prove
is composite indexes (the emulator serves any query without one, so that
check passes vacuously), region routing, and real project configuration.

## What the first real run found

Two defects, both of which only a real run could surface, and both in the
checks themselves rather than in the thing being checked:

- **An unreachable Functions backend was reported as a warning.** Only
  `not-found` was treated as missing, but a refused connection, a wrong
  region and a dead deployment all arrive as `internal` or `unavailable`.
  A school with no functions deployed would have been told "worth a
  look" instead of "not ready". Those codes are failures now.
- **The storage probe uploaded a text file.** `storage.rules` accepts
  only `image/*` and `application/pdf`, so the probe was refused by rules
  that were working perfectly — reporting a correct deployment as broken
  and telling somebody to redeploy the rules that had just done their
  job. It uploads a one-pixel PNG now.

A third defect was found in the screen rather than the probes: the claims
check calls `getIdTokenResult(force: true)` on purpose, that refresh makes
`authStateProvider` emit, and the controller was `ref.watch`ing its
repository — so it was disposed and rebuilt in `AsyncData(null)` a moment
after producing the report. The screen sat back at "Run the checks" as
though nothing had happened. It `ref.read`s now.

## Verified, both directions

| Scenario | Result |
|---|---|
| Correct deployment | 6 of 7 green; Functions correctly red, since that emulator was not running |
| Test-mode rules | **Security rules deployed** goes red: "A write that the rules must refuse was accepted" |
| Cleanup | The rules probe deleted the document it wrote; nothing left behind |

The rules check is the one that matters, and it catches the thing it
exists to catch.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `system_check_test.dart` | ready/warning/failure arithmetic; demo mode never reads as ready; a failing check cannot be constructed without a remedy |
| Demo | `system_check_test.dart` (smoke) | demo mode reports nothing checked and invents no results; nothing runs until asked |

The real probes are not unit-tested, and cannot honestly be: what they
test is a deployment, and a fake deployment would be testing the fake.
They are verified by running them, as described above.

## Deferred

- **A one-shot CLI version**, so the preflight can run in a deploy
  pipeline rather than from a screen.
- **Emulator awareness in the report.** The checks run correctly against
  the suite, but the report does not say it was an emulator it checked.
  The Auth emulator's own red banner is currently the only clue.
- **Re-checking after a fix** without re-running everything.
