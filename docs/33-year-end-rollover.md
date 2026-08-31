# Module 33 — Year-end rollover

Moving a school up a year: who is promoted, who repeats, who graduates,
and the act of actually changing every student record to say so.

Nothing in this system did this before. A school without it either types
nine hundred grade levels by hand every June or keeps the real class
lists somewhere else — and once the class lists live somewhere else, so
does everything downstream of them.

## It is a plan somebody reads, not a button

This is the least reversible thing in the app. A promotion written wrongly
puts a child in a class they cannot follow; a retention written wrongly
holds one back for a year; and a rollover run twice puts every student in
the school two years above where they belong.

So the shape is: the marks produce a **recommendation** per student, the
registrar reads a class list they recognise, changes any row they
disagree with, and only then presses the button — behind a confirmation
that says in plain words what is about to happen and that it cannot be
undone from the app.

One section at a time. That is how a registrar works, it keeps the read
bounded, and a screen that asked somebody to check nine hundred rows in
one sitting is a screen that gets scrolled past.

## What the recommendation is based on

DepEd Order 8, s. 2015 for Grades 1-10: every subject passed is a
promotion; one or two subjects failed is *promotion after passing
remedial classes*; three or more is retention. Senior High is assessed
per semester on its own rules and a college runs on units and standing,
so for those divisions this is a starting point rather than an answer.

Two things follow from that:

- **"Remedial required" is its own outcome**, not a promotion with an
  asterisk. DepEd's wording is a promotion that has not happened yet, and
  making it a separate outcome means a school that ignores the remedial
  classes cannot promote a student by leaving the row alone.
- **A student with no grades on file is held, not promoted.** Promoting
  on no evidence would move a child up a year on the strength of a
  teacher not having entered anything.

The reason behind every recommendation is printed on the row — "General
average 88, every subject passed", "2 subjects below 75: Mathematics,
Science" — because a list where every line says the same thing is a list
nobody reads.

The rule is per subject, not on the average: a child with 95s and one 60
has a subject to make up, and the average would hide it.

Grades come through `computeQuarterlyGrade` — the same function the
report card prints from ([Module 32](32-grading.md)). Two ways of
computing a grade is how a school ends up with a child promoted on one
screen and retained on another.

## Where a student goes next

Grade levels here are free text, typed by the school: "Grade 10", "1st
Year", "Yr 7 (SPED)". So the next one is read out of what they typed —
the single number in it, incremented, with the ordinal suffix moved
along so "1st Year" becomes "2nd Year" and not "2st Year".

**When there is no single number to advance, it refuses.** A guess puts a
child in the wrong year and nobody finds out until June, so the row shows
a question instead: *"Which year 'Kinder' leads to is not something this
can work out. Type it in."*

The section is suggested the same way — "Grade 9 - Rizal" becomes
"Grade 10 - Rizal" — and left blank when the year does not appear in the
name.

Whether a Grade 6 or Grade 10 student graduates or moves up depends on
whether the school runs the division above, which is read off the roster
rather than from a setting somebody would have to keep current: a school
with no Senior High students has no Senior High, whatever a checkbox
says. Grade 12 always graduates, even at a school with a college — a
Senior High graduate applies to college, they are not rolled into it.

## Running it twice is safe by construction

Each student's promotion record is written at a document id built from
the school year and their id — `2026-2027_stu_001` — with `create`. A
student already rolled over cannot be created again, so the second
attempt **skips** them and says so rather than moving them twice. It is
the same mechanism the official receipt series uses, for the same
reason: the id *is* the uniqueness guarantee, and a query is not.

That makes the interrupted case work the way a registrar needs. A page
that fails leaves earlier pages applied and the rest untouched, and
running the whole thing again finishes the job. The screen reports "42
moved, 3 had already been done" rather than a green tick that hides the
difference.

The callable runs **one transaction per student** rather than one batch
per page. A batch would be fewer round trips and could not tell which
students it skipped — `create` on an existing document fails the whole
batch, so one already-rolled-over student would abort a page of two
hundred.

## What actually changes

| Outcome | The student record |
| --- | --- |
| Promoted | `gradeLevel` and `section` become the destination on the row |
| Graduated | `status` becomes `graduated` — the record stays, because they come back for a transcript years later |
| Retained | Nothing |
| Remedial required | Nothing — they have not finished the classes yet |
| No decision | Nothing, and no record either — see below |

Retained and remedial students still get a promotion record even though
nothing on their record changes. "We decided to retain this student in
2026-2027" is a fact the office has to be able to produce, and a decision
that left no trace is indistinguishable from a rollover that missed them.

**"No decision" is the exception: it is left out of the run entirely.**
The promotion record is what marks a student as done for the year and
what a re-run skips on, so writing one for somebody nobody has decided
about would lock them out of the rollover permanently. A registrar who
runs this before the last marks are in has to be able to come back for
those students once the marks arrive, and leaving them unwritten is what
makes that work. The screen leaves those rows out of the count on the
button and says so if they are all that is left.

The record keeps **both** what was recommended and what was decided, so
an override is visible afterwards rather than looking like what the marks
said all along.

## Rules

`promotions` and `schoolYears` deny client writes outright. A promotion
record written from a client would move a child up a year with nothing
checking; one deleted from a client would let the rollover run a second
time, since the record's existence is what prevents that. Both are
written only by `runYearEndRollover` through the Admin SDK.

Reads go to the registrar's office — Director, Admin, Principal,
Registrar — plus the student and their linked parents. "Was I promoted"
is a question a family is entitled to the answer to from the record,
rather than by queueing at the counter. Teachers are not on that list: a
promotion decision is not theirs.

## Where things are

| Thing | File |
| --- | --- |
| Outcomes, recommendation, next year | `registrar_portal/domain/entities/promotion.dart` |
| Building and running a plan | `registrar_portal/domain/usecases/rollover_usecases.dart` |
| The screen | `registrar_portal/presentation/screens/year_end_rollover_screen.dart` |
| Server validation | `functions/src/shared/academics/rollover.ts` |
| The callable | `functions/src/callable/academics/runYearEndRollover.ts` |
| Firestore | `schools/{id}/promotions/{year}_{studentId}`, `schools/{id}/schoolYears/{year}` |

A composite index on `grades` by `section` was added for the plan's one
read, and the go-live preflight ([Module 21](21-system-check.md)) probes
it — the rollover runs on one day of the year, which is exactly the kind
of query a missing index is discovered by on the day it matters.
