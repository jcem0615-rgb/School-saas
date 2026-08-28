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
- **The storage probe** is the one real write: a few bytes to a
  dedicated `preflight/` path, removed immediately.

Nothing runs on open, either. Twelve function calls and a Storage write
are something a person asks for, not something a screen does to a live
deployment because it was navigated to.

## `invalid-argument` is the pass

For the callable probe, being *refused* is success: it means the function
is deployed, in the right region, and got far enough to validate its
input. `not-found` means it is not there. `unauthenticated` and
`permission-denied` also count as deployed — whether this account may
call it is a different question from whether it exists.

## Demo mode reports that nothing was checked

This is the one demo repository that deliberately does **not** simulate
its real counterpart. Every other fake exists so the demo behaves like
the app; `DemoSystemCheckRepository` exists so it does not.

A preflight that goes green against an in-memory store is worse than no
preflight — it is a green light that means nothing, shown to the one
person who most needs it to mean something. So demo mode checks nothing,
returns no results, and says so.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `system_check_test.dart` | ready/warning/failure arithmetic; demo mode never reads as ready; a failing check cannot be constructed without a remedy |
| Demo | `system_check_test.dart` (smoke) | demo mode reports nothing checked and invents no results; nothing runs until asked |

The real probes are not unit-tested, and cannot honestly be: what they
test is a deployment, and a fake deployment would be testing the fake.
They are verified by running them against a real Firebase project —
which is exactly the thing this module exists to make possible.

## Deferred

- **A one-shot CLI version**, so the preflight can run in a deploy
  pipeline rather than from a screen.
- **Emulator awareness.** Pointed at the emulator suite the checks behave
  sensibly but report on the emulator, and nothing says so.
- **Re-checking after a fix** without re-running everything.
