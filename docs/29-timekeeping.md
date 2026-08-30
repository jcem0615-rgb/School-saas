# Module 29: Employee timekeeping — timesheets and leave

## Overview

The QR scanner has always been able to scan an employee: an admin scans
a staff ID, and a record lands in `attendance` with a time in and, on the
second scan, a time out. What did not exist was anything that read those
records back as a **month** — which is the only form in which they are
any use, because payroll is run on a month and not on a scan.

And a month of scans on its own is misleading in one specific, expensive
way. A day with no scan looks identical whether the person was absent
without explanation or away on leave the office itself granted. Told
apart, one is a payroll deduction and the other is not.

So this module is two halves that only work together:

* **Leave** — an employee files, the office decides, and the decision is
  recorded with who made it and when.
* **The timesheet** — the month, assembled from the scans *and* the
  approved leave, so a blank day is correctly named.

## What is built

**Leave requests** — `schools/{schoolId}/leaveRequests/{id}`. Filed by
the employee, decided by Director/Principal/Admin. Client writes rather
than a callable, with `firestore.rules` doing the enforcement: filing is
a person asserting something about themselves, and the assertions that
matter (whose request it is, that it arrives undecided, who decided it)
are all expressible as rules.

**The timesheet** — no collection of its own. It is a read model,
assembled in `app/lib/features/timekeeping/domain/entities/timesheet.dart`
from the attendance records and the leave. Nothing is stored, because
nothing here is a new fact: it is two existing records read together.

**Screens** — `MyLeaveScreen` and `MyTimesheetScreen` for any employee;
`LeaveRequestsScreen` (the office's queue and its history) and
`TimesheetScreen` (any employee, any month) for Director, Principal and
Admin. Tiles on all seven staff dashboards; `/my-leave` is a real route
because a leave decision notification links to it.

**A notification** —
`functions/src/triggers/leave/onLeaveRequestDecided.ts`, on the
transition out of pending. Somebody who filed for Thursday and never
heard back either comes in when they should not have, or stays away when
they were expected.

## How a day is named

In order. The first that matches wins:

| Condition | Named |
| --- | --- |
| There is a scan, marked late | **Late** — and counted as worked |
| There is a scan | **Worked** |
| An *approved* leave request covers the day | **On leave** |
| The day is a rest day (Sat/Sun by default) | **Rest day** |
| Otherwise | **Absent** |

**A scan beats leave**, deliberately: somebody who came in on their
approved leave day was at work, whatever the paperwork says.

**Only approved leave counts.** A pending request is a plan — treating it
as leave would let anybody take the day by filing for it — and a declined
one is a day somebody was expected in.

**Rest days are named, not skipped.** Five absences in a week is a
conversation; seven is an accusation about two days nobody was expected.
The rest-day set is a parameter, so a school running Saturday classes
does not have every Saturday reported as absence.

## Deliberate choices

**Hours are not guessed.** A day with a time in and no time out
contributes *no* minutes, and the sheet says how many such days there
are. The alternatives — counting zero silently, or counting "until now" —
both put a number on a payslip that nobody measured.

**Leave is counted in working days, and stored.** The count is computed
once, when the request is filed, and kept. A request keeps the number it
was approved on even if the school later redefines its working week.

**Dates are `YYYY-MM-DD` strings, not timestamps.** Leave is counted in
days: "the 3rd to the 5th" means three whole days wherever the person
filing it happens to be. A timestamp would make that answer depend on a
timezone. This is the same reasoning the attendance date key already
follows.

**Its own collection, not a row in the approvals queue.** The generic
`approvals` collection (Module: approval history) could carry a leave
request in its `details` map, and the reason it does not is not
tidiness: the timesheet has to ask "was this day covered", which is a
date-range query, and an employee has to read their own requests without
being able to read the school's.

**The decision names the decider, and the rules pin it.**
`decidedByUid` must equal the caller's own uid and `decidedByRole` their
own role — the same rule the approvals queue uses. Without it, "approved
by the Director" is a field anybody with write access can type into.

**A decided request is not decided again**, and an approved one cannot be
withdrawn by the employee. The timesheet is already built on it.

**Nothing is ever deleted.** A leave record is what a timesheet and a
payslip get argued over. It is withdrawn or declined, not removed.

**This system does not run payroll.** It produces the sheet a payroll
clerk reads before they run it somewhere else. `LeaveType.isPaid` marks
the distinction they are looking for and drives nothing automatically —
deciding what an unpaid day costs is the school's calculation, in the
school's currency, under the school's contracts.

## Who can read what

| | Own leave | Everyone's leave | Own timesheet | Anyone's timesheet |
| --- | --- | --- | --- | --- |
| Any employee | yes | no | yes | no |
| Director, Principal, Admin | yes | yes | yes | yes |
| Student, parent | — | no | — | no |

An employee's list query filters on their own uid, which is what makes
the read rule satisfiable per document; the office's queue is unfiltered
and only their role clears it. A student or parent cannot file leave at
all.

## Covered by tests

* `app/test/unit/features/timekeeping/timesheet_test.dart` — the naming
  table above, in every case: pending and declined leave still counting
  as absence, a scan beating leave, a weekend never being absence, a
  missing time out contributing no hours, a school that works Saturdays,
  and the working-day arithmetic including a range that runs backwards.
* `test-rules/leave.rules.test.ts` — filing only for oneself and only as
  undecided, an employee unable to list the school's leave, a decision
  that cannot be recorded under somebody else's name or role, an
  already-decided request, and that nobody deletes one.
* `app/test/smoke/timekeeping_test.dart` — filing, withdrawing,
  deciding, the notification that follows a decision, and a timesheet
  reading an approved absence as leave.
* `app/test/smoke/portal_actions_test.dart` — the four screens render,
  and My Leave's form opens.

## Not covered

Two things. The `onLeaveRequestDecided` trigger is not exercised against
the emulator — the delivery path it calls is, indirectly, but the
trigger's own transition check is asserted by reading. And no test proves
a real QR scan of a staff ID reaches this timesheet, because that needs
a camera; the scan half is Module 7's, and this module reads what it
writes.
