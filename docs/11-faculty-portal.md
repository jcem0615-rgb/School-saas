# Module 9c: Faculty Portal

## Overview

Covers Lesson Plans, Lessons, Assignments, Projects, Exams, Quizzes, Grade
Submission, and Material Requests as new features. Attendance reuses the
QR Scanner (Faculty was already in the scanner-allowed role list since
Module 7); Announcements links to the existing Director Portal screen.

## Design choice: one `courseworkItems` collection, not six

Lesson Plans, Lessons, Assignments, Projects, Exams, and Quizzes share the
same shape closely enough — title, description, subject/section scoping,
an optional due date, an optional points value — that six parallel
collections plus six near-identical CRUD screens would be pure
duplication. `courseworkItems/{id}` unifies them behind a `type` field,
the same pattern Director Portal established for `approvals`. This also
means the Student Portal module (next in line after Parent/Staff/Guidance)
can build one "coursework feed" filtered by `type`, rather than querying
six different collections.

`CourseworkType.isGradable` distinguishes the two instructional-material
types (Lesson Plan, Lesson — no due date, no points) from the four
gradable-work types (Assignment, Project, Exam, Quiz — due date required).
This drives which fields the create form shows, and is enforced in the
use case, not just the UI (`CreateCourseworkItemUseCase` rejects a missing
due date for a gradable type before it ever reaches Firestore).

## Draft vs. published visibility

`courseworkItems` read access checks `published == true` OR staff role —
a Faculty member can save a draft assignment without it appearing in a
school-wide/student-facing feed prematurely, while colleagues (any
`faculty`/`director`/`admin`/`registrar`/`guidance`) can still see each
other's drafts for coordination purposes. See
`test-rules/faculty-portal.rules.test.ts` for the specific case (a
student blocked from an unpublished draft, a colleague not).

## Grades: correctable, but not reassignable

Faculty (or Director/Admin) can update an existing grade's `score` to fix
a data-entry mistake, but the update rule explicitly requires
`request.resource.data.studentId == resource.data.studentId` — a grade
can never be silently reassigned to a different student via an "update."
Reassigning a grade to the wrong student is exactly the kind of error that
should require deleting and recreating the record (with its own audit
trail entry showing a deletion happened), not a quiet field edit.

## Material Requests: reusing Director Portal's approvals system

No new collection, no new backend logic. Director Portal's `approvals`
collection already allowed "any active tenant member may file a request;
only Director/Admin decide it" since Module 6 — this module only adds the
missing filing-side pieces that Director Portal (built for the deciding
side) didn't need yet:

- `CreateApprovalRequestUseCase` / `DirectorRepository.createApprovalRequest`
- `myApprovalsStreamProvider` — a user's own filed requests, filtered
  server-side by `createdBy`, regardless of status (Director's existing
  `approvalsStreamProvider` shows everyone's requests filtered by status
  instead — a different axis for a different audience)

Faculty's `MaterialRequestsScreen` is a thin UI over this shared
infrastructure with `type: 'material_request'` — any future module
(Inventory purchase requests, Staff Portal leave requests) reuses the
exact same mechanism.

## "My Activity History" — a new personal audit view for every role

The spec lists "Audit Trail" as a General Requirement for *every* user,
which is a different thing from the full-school `AuditTrailScreen`
(Owner/Director/Admin only). This module extends the `auditLog` security
rule to also allow `resource.data.userId == request.auth.uid` — any user
can read their own entries — and adds `MyActivityScreen` /
`myActivityStreamProvider` to the shared Audit Trail feature (not
Faculty-specific; every portal's dashboard can link to
`/my-activity` going forward).

## Firestore collections added

```
schools/{schoolId}/courseworkItems/{id}  -- type, title, subject/section, teacherId, dueDate?, totalPoints?, published
schools/{schoolId}/grades/{id}           -- studentId, subject/section, term, score, maxScore, courseworkItemId?
```

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `faculty_usecases_test.dart` | due-date-required-for-gradable-types, score/maxScore bounds |
| Rules | `faculty-portal.rules.test.ts` | teacherId impersonation block, draft visibility, grade reassignment block, personal audit self-read |

## Deferred to later modules

- **Reports** (grade distributions, coursework completion, etc.) — Reports module.
- **Attachments** on coursework items (worksheets, rubrics) — Documents/Storage module.
- **Student/Parent-facing coursework feed and grade view** — Student Portal
  and Parent Portal modules; the read-side rules for both `courseworkItems`
  and `grades` already account for student/parent access (see
  `docs/07-qr-attendance.md` and `docs/08-payments.md` for the same
  self/staff/linked-parent access pattern reused here).

## Announcements to a class

A teacher posts from the same Announcements screen everyone else uses,
but the composer is a different one. A director picks roles; a teacher
picks classes.

Roles are the wrong unit for a teacher. "Students" means every student in
the school, and a Grade 10 adviser reminding their class to bring a
permit slip should not put it in front of the Grade 3s. A section is also
the unit a student, their parent and their teachers already have in
common, so targeting one needs no new grouping maintained alongside the
roster.

`AnnouncementAudience` therefore gained `sections` next to `roles`, and
the two are an **OR**. A notice for "Grade 10 - Rizal" has to reach that
section's students, their parents and the other teachers who take them;
making a teacher enumerate those roles as well would mean getting it
wrong in the direction that leaves the parents out.

`viewerSectionsProvider` is the one place that knows how each role
reaches a section — a student through their own record, a parent through
their children's, a teacher through their assignments — because working
that out on four portals' screens means getting it right four times, and
the failure is silent: a parent simply never sees the notice about
tomorrow's field trip. Everyone else belongs to no section, which is
exactly right: a class notice is not for the cashier.

The class list puts the **advisory** section first (`isAdviser` on the
teacher assignment). It is the one they mean most of the time, and a list
that buried it among five subject sections would make the common case the
hardest to find. One row per section, not per subject — a teacher taking
three subjects in one class posts to that class once.

`firestore.rules` now lets faculty create announcements, with
`createdBy == request.auth.uid` enforced on create and edits restricted
to their own. What has to be enforced there is authorship, not audience:
the audience is targeting, not access control, and the collection is
readable tenant-wide because Firestore rejects queries rather than
filtering them. **Nothing goes in an announcement that a student must not
read.**

A teacher's own posts sort to the top of their list and carry the edit
controls; everything else is read-only. An Edit button on the school's
payroll notice would only ever produce a permission error at the end of a
filled-in form.
