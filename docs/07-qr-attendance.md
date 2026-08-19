# Module 7: QR Attendance

## Overview

Every user gets a QR ID (`MyQrIdScreen`, reused across all nine roles).
Staff-facing roles (Director/Admin/Registrar/Faculty/Staff/Guidance) get a
scanner (`QrScannerScreen`) that marks attendance for whoever they scan.
Everyone can view attendance history for themselves; Parents can view a
linked child's.

This module was deliberately pulled forward in the build order (ahead of
Admin/Registrar/Faculty/Student/Parent portals) because six different
portals depend on its data existing — building those portals' "Attendance"
tabs first would have meant building against a collection nothing writes
to.

## Why attendance writes go through a callable, not client Firestore writes

Every other CRUD module so far (Announcements, Meetings, Approvals,
Expenses) allows direct client writes gated by rules, relying on the
generic audit trigger. Attendance is different for three reasons:

1. **Cross-user writes.** A Faculty member's scan creates a record *about
   a student*, not about themselves — this is exactly the kind of write
   Firestore rules struggle to validate safely (you'd need the rule to
   trust the client's claim about who was scanned).
2. **Server-computed status.** Present vs. late depends on the school's
   configured cutoff time compared against server time in the school's
   timezone — this must not be client-computed or a device with a wrong
   clock (or a malicious one) could mark itself present after cutoff.
3. **Duplicate-scan handling.** The transaction in `markAttendance.ts`
   decides time-in vs. time-out vs. already-completed atomically. Doing
   this as a client read-then-write would race under concurrent scans.

So `attendance` has `allow write: if false` in rules, full stop — the
Cloud Function's Admin SDK access is the only path in.

## QR token design

Tokens are opaque random hex strings (`randomBytes(16).toString("hex")`),
generated once in `provisionUser.ts` and stored on the user's Firestore
doc — never the raw Firebase Auth `uid`. Two reasons: a leaked/photographed
QR code shouldn't reveal anything reversible about the account, and lookup
is deliberately scoped to the *scanner's own school*
(`schools/{scannerSchoolId}/users where qrCode == token`) rather than a
global index, so a token can never match across tenants even by accident.

## Attendance record keying

Document ID is `${dateKey}_${personId}` (e.g. `2026-07-21_student_1`) --
this makes "has this person already been scanned today" a direct document
lookup inside the transaction rather than a query, and makes the record
naturally idempotent under retries.

## ID space: why `personId` isn't always the account ID

For staff scans, `attendance.personId` is the `users/{uid}` account ID.
For **student** scans, it's the linked `students/{studentId}` academic
record ID instead (resolved via `students where userId == scannedUid`,
falling back to the account ID if no linked record exists yet). This
matters because Payments, Grades, and Documents all key off the academic
`students/{studentId}` ID — a student can have that record without ever
having a portal login — and a Parent's `linkedStudentIds` needs to mean
the same thing in every module that checks it. Without this resolution
step, a parent could see their child's payment history but not their
attendance (or vice versa) depending on which ID space a given module
happened to use.

## Security Model additions this module

- `attendance`: readable by (a) the record's own subject, (b) any
  staff-facing monitoring role, (c) a Parent whose `linkedStudentIds`
  contains the record's `personId` — checked live via `get()` on the
  parent's own user doc, not a client-asserted relationship.
- Owner is deliberately excluded from attendance read access — billing
  only needs the *enrolled count*, not day-to-day attendance records, and
  extending Owner access into tenant operational data isn't a boundary
  this build wants to cross without a specific reason to.
- See `test-rules/attendance.rules.test.ts`.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `scan_qr_usecase_test.dart` | empty-token validation, delegation |
| Functions | `attendanceStatus.test.ts` | present/late boundary math, cutoff parsing/fallback |
| Rules | `attendance.rules.test.ts` | self/staff/linked-parent read access, universal write denial |

## Deferred to later modules

- Attendance Reports & Analytics (charts, trends) — Reports module
- Manual (non-QR) attendance entry for edge cases — Admin Portal module
- Per-school attendance cutoff configuration UI — Admin Portal module
  (the field `attendanceCutoffTime` on the tenant `schools/{schoolId}` doc
  already exists and is read by `markAttendance.ts`; only the settings
  screen to edit it is deferred)
