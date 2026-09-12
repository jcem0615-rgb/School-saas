# Module 7: QR Attendance

> **This module is the gate record**: one time in and one time out per
> person per day. Attendance *per subject* -- the register a teacher
> takes at the start of each lesson -- is a separate thing, in
> [Module 28](28-subject-attendance.md). The two answer different
> questions and neither replaces the other.

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
   cutoff time (`attendanceCutoffTime`, 07:30 until the settings screen
   below is built) compared against server time in the school's
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

## A second tap at the gate was a day's pay

Any repeat scan on the same day used to be read as a time out. The queue
at a school gate produces two taps a few seconds apart -- a phone that
did not seem to respond, a student who scanned twice, a scanner held a
moment too long -- and the record then read *arrived 07:02, left 07:02*.

Nothing downstream flagged it, and that is what made it expensive:
`buildTimesheet` treats a day with both stamps filled in as a complete
day. A day that says a person was at work for zero minutes looks finished
rather than broken, so it went onto the payslip as zero hours. For an
hourly employee that is a day's pay, arrived at silently.

`classifyRepeatScan` puts a five-minute floor on it
(`MINIMUM_DWELL_MINUTES`). Inside that window a second tap is **not an
error** -- the person is already marked in, so the scanner answers
`too_soon` and says so; refusing the scan would train the queue to tap
again. Outside it, a second tap is a time out as before. A third tap on
a day that is already finished answers `already_completed` rather than
reopening it: the first time out is when they left.

The window is returned to the caller (`minimumDwellMinutes`) so the
scanner screen can explain itself in the school's own numbers rather than
carrying its own copy of the figure.

## What day it is at the school

`markAttendance` used to carry its own inline copy of "what is today's
date in the school's timezone" -- the same two lines the class-session
callables already read from `shared/attendance/schoolClock`. Both copies
were correct, which is exactly the state that drifts. There is now one,
and `schoolDateKey`/`schoolTimezone` are it. The distinction matters: a
scan at 8am in Manila is the previous evening in UTC, so a date key taken
from the server clock files every early scan under yesterday.

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

- `attendance`: readable by (a) the record's own subject, (b) Director and
  Admin, who are cross-division by design, (c) the other monitoring roles
  — Principal, Registrar, Faculty, Staff, Guidance — **within their own
  division**, (d) a Parent whose `linkedStudentIds` contains the record's
  `personId` — checked live via `get()` on the parent's own user doc, not
  a client-asserted relationship.
- The division scoping in (c) was added late. Attendance was the one
  per-student collection that granted blanket staff read: an elementary
  guidance counsellor barred from a Senior High student's grades and
  guidance file could still read, day by day, what time that child
  arrived at school. `attendanceScopeAllows` closes it, and has to branch
  on `personRole` first — `personId` is an auth uid for a member of staff
  and a `students/{id}` for a child, and a staff row has no division to
  scope by. A child scanned before Student Registration has made their
  academic record has none either (see the ID space section above), so
  the rule checks `exists()` before it fetches: a `get()` on a document
  that is not there throws, and a throw denies the whole read rather than
  the one branch.
- Owner is deliberately excluded from attendance read access — billing
  only needs the *enrolled count*, not day-to-day attendance records, and
  extending Owner access into tenant operational data isn't a boundary
  this build wants to cross without a specific reason to.
- See `test-rules/attendance.rules.test.ts`.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `scan_qr_usecase_test.dart` | empty-token validation, delegation |
| Functions | `attendanceStatus.test.ts` | present/late boundary math, cutoff parsing and its clock bounds, what a repeat scan means |
| Demo | `scanner_outcomes_test.dart` | all four outcomes parse; the four states a record can be in when an ID goes past, each set up rather than assumed |
| Emulator | `attendance-emulator/gateAndTimetable.test.ts` | `markAttendance` against a real Firestore: the queue at the gate, the time out that is real, the day filed under the school's date |
| Rules | `attendance.rules.test.ts` | self/staff/linked-parent read access, universal write denial |
| Rules | `division-isolation.rules.test.ts` | a scoped teacher is refused another division's attendance, and is not refused a colleague's |

## A scan means one of four things, and the app knew three

`markAttendance` returns `time_in`, `time_out`, `too_soon` or
`already_completed`. `ScanAction` carried three of them, and
`fromString` used `firstWhere` with no fallback — so the server's
`too_soon` did not mislabel anything, it **threw** `Bad state: No
element` inside the scanner.

That is the most common event at a gate. The queue backs up, the beep is
missed, the same ID goes past twice inside a few seconds; the server has
a long comment explaining precisely how carefully it handles that, and
the client could not receive the answer. The demo never produced one
either — its comment claimed "the same three-way outcome
markAttendance.ts returns", which was the false sameness that kept
anybody from noticing.

Three things came out of it:

- `ScanAction.tooSoon` exists, and `fromString` names a value it does not
  recognise instead of saying "No element" — a deployed scanner meeting a
  newer server should say what it saw.
- The overlay distinguishes **a scan that wrote something from one that
  did not**: a tick and the person's name for a time in or out, an
  information mark and a different colour for the two that changed
  nothing. Identical overlays tell somebody at a gate that a record
  exists when none does.
- It says how long to wait. `minimumDwellMinutes` was being sent by the
  server for exactly that message and read by nobody, so "that did not
  work" sent an operator tapping again instead of "already in, try again
  in five minutes".

The demo now applies the same five-minute floor and returns the same four
outcomes. Without the floor it timed somebody out on an immediate second
tap — demonstrating, in the demo, the exact failure the server exists to
prevent.

## A cutoff outside a real clock

`parseCutoffTime` checked the shape, `\d{1,2}:\d{2}`, and nothing else.
`"25:00"` and `"08:99"` both pass it, and both produce a cutoff later
than any moment of the day: every scan then compares as on time and
**nothing is ever marked late again**, for the whole school, silently.
Nobody notices a feature that has quietly stopped having opinions.

It is bounded to a real clock time now, and falls back to 07:30 rather
than accepting one. That matters *more* while the settings screen is
deferred, not less: the only way to set this today is to type it into
Firestore by hand, which is exactly where a typo lands.

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

### The card does not follow the app's theme

Its colours are fixed — `_cardFace`, `_cardInk`, `_cardMuted` — and that
is the point. The face used to be `theme.colorScheme.surface` while the
ink was a hard-coded `Colors.black87`, which in **dark mode painted a
dark navy card and left dark ink on top of it**. The name was there and
could not be read, on the one screen whose whole job is showing a name.

A card is a preview of something that comes out of a printer on white
stock. It has to look the same to a registrar on a dark laptop and a
parent on a light phone, because the paper does. The build method does
not call `Theme.of` at all.

The type was raised at the same time — labels from 1.15 to 1.45mm, values
from 1.95 to 2.45mm, the school name from 2.3 to 2.6mm — because a card is
read at arm's length across a gate, not at reading distance. Bigger text
in a fixed-height card is exactly how a layout starts overflowing, so
`id_assets_test.dart` renders the card with a long two-surname Filipino
name on the narrowest phone in common use and fails on overflow, which a
debug build throws.

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
