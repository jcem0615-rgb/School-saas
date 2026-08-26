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

## The ID card

The card is laid out as a credential rather than as a poster: a coloured
header band naming the issuer, a body row of photo, labelled fields and
QR, and a footer strip carrying the student number. Those three bands and
their gaps fill the 54mm height, so nothing falls through to a spacer and
leaves a band of dead white.

The name is printed in labelled parts — SURNAME, GIVEN NAME, MIDDLE NAME
— rather than as one run of text. A reader looking for a surname finds it
without parsing a sentence, and a long name no longer decides whether the
line fits. Surname first, for the same reason the TOR prints it that way:
it is what the school's own paperwork sorts by.

The school's uploaded logo is the card's background, at 6% opacity behind
everything. That is most of what makes a card look issued rather than
printed — the mark of the body that issued it, under the data. Faint
enough that the name over it stays the highest-contrast thing on the
card; a watermark that competes with the name is a card a guard has to
squint at.

Both faces are written once, in millimetres, and the screen scales them.
The preview is not decoration: it is what a student holds up instead of
the printed card, so it has to be the same card. Geometry lives in
consts (`_headerHeightMm` and friends) that the print and screen layouts
both read, rather than each carrying its own guesses.

`buildIdCardPdf` is exposed for tests. The PDF is a separate widget tree
from the preview and it is the artefact the school actually hands out; a
card that comes out blank, or throws because a signature is missing, is
not something a test of the preview would catch.

This is a school ID. It is deliberately not modelled on any government
credential — no republic seal, no agency wording, no national-ID layout —
because a school card that could be mistaken for a state-issued one is a
liability rather than a feature.

## Uploaded images off the web

`Image.network` handles a `data:` URI on the web, where it becomes an
`<img src>` and the browser decodes it, and fails on Android, iOS and
Windows, where it goes through an HTTP client. Demo mode produces exactly
those URIs, because `DemoUploadRepository` never touches a bucket — so an
uploaded logo or signature that looked right in the browser was simply
absent in the APK and the desktop build, silently, since the error
builder swallows it.

`UploadedImage` (screen) and `pdfImage` (print) decode the URI themselves
and fall back to the network for everything else. Every uploaded image in
the app goes through one of the two.

The demo school now ships a seal on file, drawn by
`tool/generate_demo_seal.py` and seeded as a data URI — the same shape an
upload takes. A demo with no logo demonstrates the absence of the
feature. Uploading one under School Branding still replaces it.
