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
  See *One figure, three places* below -- this arithmetic has to hold
  everywhere the same number is shown.
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

## One figure, three places

"Money collected" is computed in three separate implementations: the
Collections report here, the Director's dashboard tile
(`director_remote_datasource`), and the school totals screen
(`school_totals_remote_datasource`). They must agree, and for a while two
of them did while the third quietly did not.

A refund is two writes, not one. The original payment flips to
`status: 'refunded'` and **keeps its positive amount**; a second row is
created for the negative amount with `status: 'completed'`. The pair nets
to zero only if both rows are counted.

The dashboard filtered its sum on `status == 'completed'`, which dropped
the refunded original and kept the negative row. A payment of PHP 2,500
taken and refunded the same day therefore showed on the Director's
dashboard as **-PHP 2,500** rather than nothing -- the school appearing to
have lost money it never had. The filter is gone; all three now sum every
row in the period.

The demo store had a *different* wrong answer -- it excluded refund rows
while keeping the payments they reversed, so the same day overstated by
PHP 2,500 -- which is why the demo never reproduced the live bug. It sums
every row now too.

`collections_figures_test.dart` holds the three to the same answer,
including a test that reads the dashboard figure and the report headline
for one day and asserts they match. A refund's arithmetic is the sort of
thing that gets re-derived in a fourth place next year; the test is what
makes the fourth place fail loudly rather than differ quietly.

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
| Smoke | `collections_figures_test.dart` | a same-day payment and refund net to nothing, one refund among three leaves the other two standing, and the dashboard agrees with the Collections report on the same day |

## Deferred

- **Division-scoped reports** for the Principal -- see above for why it is
  a build rather than a filter.
- **Reports for the Principal at all.** The Principal dashboard has no
  Reports tile, and rules do not let a Principal read `payments`, so
  opening the screen as one would error on the two money reports rather
  than show a narrower version of them. This is a gap, not a defect: no
  screen currently points a Principal at it. It reads sharper now that the
  Principal is oversight-only -- oversight without reports is thin -- and
  the fix is the division-scoped build above plus a rules decision about
  what money a Principal may see, not a tile.
- **Charts.** These are tables, and a table is what gets forwarded to a
  division office. A trend line over terms would be the first chart worth
  having.
- **Server-side rollups** for schools past the read ceiling.
- **Scheduled delivery** (a monthly collections report mailed on the 1st)
  -- the PDF builder is ready for it; the scheduling is not built.
