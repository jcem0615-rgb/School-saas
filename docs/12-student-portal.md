# Module 9d: Student Portal (+ shared Profile feature)

## Overview

This module is mostly consumption-side wiring — QR ID, Attendance,
Announcements, Payments/Balance, and My Activity History are all reused
directly from earlier modules with zero new code. What's actually new:
a shared **Profile** feature (every role needs one, not just students),
and Student Portal's own read-side views: Subjects, Assignments & Exams,
Grades, and Promissory Note.

## Profile: pulled out as shared infrastructure

Every portal's General Requirements list "Profile." Rather than build a
student-specific profile screen and repeat it eight more times across
Parent/Staff/Guidance/etc., this module introduces `features/profile/` as
shared infrastructure — `ProfileScreen` reads the signed-in user directly
from `authStateProvider` and edits only the fields the Module 4 self-edit
rule actually permits (`phone`, `photoUrl`). Every future portal just
links to `/profile`, the same way every portal already links to `/qr-id`.

## Resolving "my student record"

A signed-in Student's `uid` (Firebase Auth) is not the same ID as their
`students/{studentId}` academic record (see the ID-space discussion in
`docs/07-qr-attendance.md` and `docs/08-payments.md`). `watchMyStudentRecord()`
bridges this with a single query — `students where userId == myUid` —
and every other Student Portal screen depends on its result (`studentId`,
`section`) rather than re-deriving it. If no linked record exists (e.g. a
portal account was somehow created without the Registrar's normal linking
step), the dashboard shows an explicit message rather than crashing.

## Design choice: reuse entities, don't duplicate them

`StudentRepository` returns `StudentSummary` (Registrar Portal),
`CourseworkItem`/`Grade` (Faculty Portal), and `TeacherAssignment` (Admin
Portal) directly — a student's assignment is the exact same `CourseworkItem`
their teacher created, just queried by `section` instead of `teacherId`.
This is the fourth module in a row to extend rather than duplicate
Director Portal's generic `approvals` system too: **Promissory Note** is
`type: 'promissory_note'` with `{amount, reason}` in `details`, using the
exact same `createApprovalRequest` / `myApprovalsStreamProvider` Faculty's
Material Requests already introduced. No new collection, no new security
rule — the pattern established in Module 6 (any tenant member files,
only Director/Admin decides) keeps paying for itself.

## "Subjects" instead of "Schedule"

The spec's Student Portal lists "Schedule" and "Subjects" as separate
items. A true Schedule (day/time/room grid, period conflicts) is a
meaningfully larger feature than what Admin Portal's Teacher Assignment
covers today (subject + section + teacher, no day/time) — Module 9a
already deferred the full Schedules grid for this reason. Rather than
leave Student Portal with nothing here, `MySubjectsScreen` gives real,
useful value now (who teaches what, for this student's section) derived
from data that already exists, while the time-based Schedule grid stays
deferred until Admin Portal's Schedules feature is built to feed it.

## Testing

Student Portal's use cases are thin pass-throughs over existing,
already-tested queries (no new validation logic to unit test) — coverage
here is at the rules layer instead:

| Layer | File | Covers |
|---|---|---|
| Rules | `student-portal.rules.test.ts` | grade self-access via linked record, promissory note filing, self-decision block |

## Deferred to later modules

- **Notifications** (push notifications for new grades, announcements,
  payment due dates) — Notifications module.
- **Schedule** (day/time/room grid) — Admin Portal's Schedules feature,
  once built, will feed a corresponding Student-facing view.
- **Reports** (report card / grade summary export) — Reports module.
- **Promissory note PDF generation** — Documents module; the request/
  decision workflow itself is fully functional today, only the printable
  document is deferred.

## Opening an attachment

Every attachment — coursework material, a submitted answer, a payment
receipt — goes through `openAttachment()` rather than `launchUrl`
directly.

Almost always the URL is a Storage download link and the platform browser
handles it. The exception is a `data:` URI, which is what
`DemoUploadRepository` produces because demo mode never touches a bucket.
`launchUrl` cannot open one: Chrome blocks top-level navigation to
`data:` outright, and on Android and iOS nothing handles it. So tapping
an attachment in the demo did nothing at all, which reads as "the file is
missing" rather than "this build has no storage behind it".

`openAttachment` decodes a data URI and hands the bytes to the platform's
save dialog instead. The file lands in Downloads and opens in whatever
the device uses for a PDF — which is where an external launch would have
sent it anyway.

This is not demo-only plumbing. A teacher who uploads coursework *in the
demo* produces a data URI, and their students hit exactly this path.

The demo's own coursework now carries real one-page PDFs — the actual
problem set, the actual quiz, the actual reading — inlined as data URIs
(`DemoAttachments`). They replace a plausible-looking `example.org` link
that failed on tap, which was worse than no attachment: a student opened
the only piece of material on the screen and got a dead end.
