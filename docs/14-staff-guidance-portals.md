# Module 9f: Staff Portal & Guidance Portal

## Overview

The last two portals. Both are lighter-weight roles, and both benefit
from reuse the same way Parent Portal did: Staff's Material Requests
reuses Faculty's exact screen (same generic approvals inbox); QR
Attendance is reused by both roles unchanged. What's new: Checklist and
Daily Reports for Staff; Guidance Records and Student Summons for
Guidance — and one important, deliberate privacy asymmetry between the
two Guidance features.

## Staff Portal

**Checklist** — a personal daily task list (`checklistItems`, scoped by
`staffId` + `date`). Deliberately simple: staff add their own ad-hoc
tasks and check them off, rather than a template-driven recurring-task
system, which would be a meaningfully larger feature (recurrence rules,
admin-defined templates per role/department) than this build's scope
calls for right now.

**Daily Reports** — a short free-text end-of-day summary
(`dailyReports`). **Immutable by rule** — no update or delete, not even
for the author — because a work log's value depends on it being a
trustworthy point-in-time record; corrections happen by submitting a new
entry, not editing history. "Monthly Reports" (spec) is a grouped view
over this same collection rather than a separate feature; a proper
aggregated/exportable version belongs in the Reports module.

**Material Requests** — zero new code. Reuses
`faculty_portal/presentation/screens/material_requests_screen.dart`
directly; both roles file into the same `approvals` collection
established in Director Portal (Module 6) and extended for self-filing in
Faculty Portal (Module 9c).

## Guidance Portal

**Student Summons** (`summons`) — visible to Guidance/Director/Admin,
**and** to the student themselves and their linked parent. Being called
to the guidance office is exactly the kind of thing a family needs to
know about, so this follows the same self/staff/linked-parent pattern
established for attendance, grades, and payments.

**Student Guidance Records** (`guidanceRecords`) — deliberately does
**not** follow that pattern. This is the most restrictive read rule in
the entire schema: only Guidance/Director/Admin can read it — not the
student it's about, not their parent, not Faculty, not Registrar.
Counseling notes are internal staff records by nature; sharing them
directly with a family in raw form is a different (and much bigger)
product decision than this build makes on its own, so the safer default
is to keep them staff-only until a school explicitly wants otherwise.
`test-rules/staff-guidance-portals.rules.test.ts` pins this down
explicitly — five separate "cannot read" assertions (student, parent,
faculty, registrar) against one "can read" (guidance) — specifically
because this is the one place in the schema where the normal
self/parent-visibility pattern does NOT apply, and that's exactly the
kind of asymmetry a future contributor could accidentally "fix" by
copy-pasting the summons pattern without reading the comment first.

## Firestore collections added

```
schools/{schoolId}/checklistItems/{id}    -- staffId, task, date, completed
schools/{schoolId}/dailyReports/{id}      -- staffId, date, content (immutable)
schools/{schoolId}/guidanceRecords/{id}   -- studentId, category, notes (staff-only read)
schools/{schoolId}/summons/{id}           -- studentId, reason, scheduledDate, status
```

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `staff_usecases_test.dart` | task/report content validation |
| Domain | `guidance_usecases_test.dart` | guidance note/summons field validation |
| Rules | `staff-guidance-portals.rules.test.ts` | the guidanceRecords privacy boundary (5 negative cases), summons visibility, staff self-scoping, director oversight |

## Deferred to later modules

- **Reports** (staff performance summaries, guidance case load reports) — Reports module.
- **Recurring/templated checklists** — would need an admin-defined template
  system; the current ad-hoc personal checklist covers the spec's literal
  requirement without that added complexity.
- **Notifications** for new summons (a family should probably get a push
  alert, not just see it next time they open the app) — Notifications module.

## Where the build stands

All nine portals plus the shared cross-cutting infrastructure (Auth, QR
Attendance, Payments, Audit Trail, Profile) are now built. Remaining from
the original module order: Notifications (push), Reports (exports,
dashboards), Documents (PDF/Excel — TOR, Form 137, Student/Employee IDs,
receipts, certificates), the dedicated Inventory module, Security
hardening (session timeout, device tracking, login history, App Check),
Testing (broader integration/widget test coverage beyond what's been
written module-by-module), Deployment, and Production Optimization.
