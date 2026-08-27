# Module 18: Reports

## Overview

Four reports, deferred by name in nine other documents and built once the
things they report on existed:

| Report | Answers |
|---|---|
| Enrollment by Division | Who is on the roll, by division and grade level |
| Collections and Receivables | What was charged, what came in, what is still owed |
| Attendance Rate by Section | How often students turned up, and where they did not |
| Grade Distribution by Subject | How a cohort is actually doing, banded |

Collections could not honestly be built before Module 8's fee assessment
landed. Until assessments existed there was no "assessed" figure to
collect against -- only a balance somebody had typed -- so a collection
rate had nothing to be a rate *of*.

## One table shape, three renderings

Every report produces a `ReportTable`: a title, a subtitle, two or three
headline figures, columns, rows, and a note. Fixing the shape is what
makes the spreadsheet export, the printed PDF and the on-screen table
each get written once instead of four times. A fifth report costs a
builder function and nothing else.

The builders are pure functions over lists (`EnrollmentReport.build`,
`CollectionsReport.build`, and so on), which is why the arithmetic a
school will quote to a division office is unit-testable with no database
in the loop.

## Rows, not aggregates

Firestore's `count()` and `sum()` answer "how many" and "how much" but
cannot group, and every report here is a group-by: enrolment *by
division*, attendance *by section*, marks *by subject*. So the documents
come back and the domain layer groups them.

That trade has a ceiling, and `ReportsRemoteDataSource._limit` (5,000 per
collection) is where it sits. **Hitting it is reported, not hidden**: the
note gets an `INCOMPLETE` warning at the front, rendered as an error
banner on screen and printed on the PDF. A report quietly built from the
first five thousand of six thousand scans is not slightly wrong -- it is
wrong in a way that looks exactly like being right.

A school that outgrows the ceiling needs server-side rollup documents
written by a scheduled function, not a bigger number here.

## Director and Admin only

That is a rules constraint, not a product decision. Those two roles have
an unconditional read on `students`, `payments`, `grades` and
`attendance`. Every other staff role's read on at least one of those is
scoped per document (`scopeAllowsStudentById`), and Firestore evaluates
list queries per matched document -- so a school-wide query from a
principal's account is refused outright rather than returning their
slice.

A division-scoped report is real work (per-division queries, a division
picker, and a rules test proving the scoping holds), not a filter on this
one. `app_router.dart` redirects every other role away from `/reports`,
alongside the audit trail, for the same reason.

## What each report refuses to imply

Each table carries a note, and the note travels into **both** exports.
A caveat that lives beside the figures on a monitor and nowhere else gets
separated from them the moment anyone prints or mails the report, which
is the whole point of a report.

- **Enrollment** is a head count taken *today*. The student record holds
  one status and changing it overwrites what was there, so a student who
  transferred out last term is counted as transferred out, not as
  enrolled in the term they left.
- **Collections**: Assessed and Collected are period figures; Outstanding
  is the balance as it stands now. The last column is therefore a ratio
  of two period figures, not a settlement rate for those students.
  Credit balances are excluded from Outstanding and disclosed separately
  -- one family's overpayment must not quietly settle another's arrears.
  Collected sums every payment row as it stands, because a refund is its
  own negative row and the payment it reverses keeps its positive one.
- **Attendance**: the rate counts present and late together. A late
  student came to school, so lateness gets its own column instead of
  being deducted. Excused absences sit outside the rate on both sides --
  a section with an outbreak must not read as a discipline problem.
  Days counts dates attendance was *taken*, not the school calendar.
  Scans pointing at student records the reader cannot see are counted and
  disclosed, never dropped silently: a rate over an unknown fraction of
  the scans is not a rate.
- **Grades** band on the DepEd descriptors (Outstanding 90+, Very
  Satisfactory 85-89, Satisfactory 80-84, Fairly Satisfactory 75-79, Did
  Not Meet Expectations below 75), with 75 passing. Every recorded mark
  counts once, quizzes included -- these are not computed final grades,
  and a subject that records more coursework weighs more in the average.
  Term choices come from the terms actually used, because terms are free
  text and a typed filter would return nothing when the office writes
  "1st Quarter" and the reader typed "Q1".

## Firestore

```
schools/{schoolId}/students      -- isDeleted == false
schools/{schoolId}/payments      -- isDeleted == false, createdAt in range
schools/{schoolId}/assessments   -- isDeleted == false, assessedAt in range
schools/{schoolId}/attendance    -- date (a 'YYYY-MM-DD' string) in range
schools/{schoolId}/grades        -- isDeleted == false, submittedAt in range
```

Three composite indexes were added for the equality-plus-range pairs
(`payments`, `assessments`, `grades`). Attendance needs none: `date` is
stored as a `YYYY-MM-DD` string precisely so it sorts and ranges as text.

Reports read only. Nothing in this module writes.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `report_builders_test.dart` | the arithmetic of all four reports, plus `ReportPeriod` boundaries |
| Demo | `reports_test.dart` | each kind reads only what it declares, the period actually narrows, every report builds against the seeded school |

## Deferred

- **Division-scoped reports** for the Principal -- see above for why it is
  a build rather than a filter.
- **Charts.** These are tables, and a table is what gets forwarded to a
  division office. A trend line over terms would be the first chart worth
  having.
- **Server-side rollups** for schools past the read ceiling.
- **Scheduled delivery** (a monthly collections report mailed on the 1st)
  -- the PDF builder is ready for it; the scheduling is not built.
