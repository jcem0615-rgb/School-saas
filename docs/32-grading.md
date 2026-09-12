# Module 32 — Grading and the report card

A quarterly grade is not an average of the marks in a subject. It is
three components — Written Work, Performance Tasks and Quarterly
Assessment — weighted per subject and added together, and the weights are
not the same for every subject. Until this module the app held raw scores
and showed a flat percentage, with a comment on the student's screen
saying so: *"Deliberately not called a final grade: weighting by term and
by assessment type is a school policy decision this module does not
model."*

That is the gap this closes. A school that cannot produce the number that
goes on a Form 138 keeps a parallel spreadsheet, and once the spreadsheet
exists it becomes the record and the app becomes decoration.

## The weights are data, and the school confirms them

DepEd Order 8, s. 2015 sets different weights for different subject
groups, and different ones again for Senior High tracks. Those numbers
are public record and they also change: an order is superseded, a track
is added, a private school runs its own approved scheme.

Hard-coding them would make this software assert a regulatory fact it
cannot keep current, and a school computing wrong quarterly grades
because the app was written in 2026 is a school issuing wrong Form 138s.

So the scheme is stored per school at `schools/{id}/settings/grading`,
seeded with the DepEd groupings as a **starting point**, and it carries
one more field than the numbers:

```
confirmedBySchool: false
```

False until a named person at the school opens **Grading Scheme** (Admin
or Registrar dashboard), checks the weights against the order that is
current for them, and presses confirm. Their name and the date are stored
with it. Grades still compute and show on screen while it is false —
teachers are not blocked from working — but **the report card refuses to
print**, and says why.

Editing the scheme revokes the confirmation. That is enforced in the data
source rather than left to the screen: a scheme somebody confirmed in
June and somebody else edited in October is not a confirmed scheme, and
the only way that stays true is if editing revokes it rather than relying
on whoever edited to remember.

The seeded groupings are Languages/AP/EsP at 30/50/20, Science and
Mathematics at 40/40/20, MAPEH and EPP/TLE at 20/60/20, and a catch-all
at 30/50/20 so a subject nobody grouped still gets a grade rather than an
error.

`SaveGradingSchemeUseCase` refuses a group whose three weights do not add
to 100. That is the one misconfiguration that does not announce itself:
30/50/30 produces grades that look entirely plausible and are wrong for
every child for a whole school year. It is refused in the use case rather
than only in the form, so an import or a script cannot get round it.

## The arithmetic, and the one judgement call in it

`computeQuarterlyGrade` sums the raw scores in each component, divides by
what those pieces were worth, weights the three percentages, and
transmutes. The steps are DepEd's and are not in dispute. What is a
decision:

**An ungraded component is not a zero.** It is rescaled out of the weight
entirely. In the second week of a quarter no quarterly assessment has
been given, and counting it as zero at 20 per cent caps every child in
the school at 80 until the exam. A teacher looking at that concludes the
system is broken, and they are right.

The components that are still empty are named — on the teacher's class
list, on the student's subject page, and in the note at the foot of the
report card — so nobody mistakes a grade computed from two of three
components for a final one.

**And the grade is marked INC until they are filled.** The rescale keeps
the working figure honest; it does not make that figure a final grade.
`QuarterlyGrade.isIncomplete` is true when work has been recorded but a
component that carries weight is still empty, and it is what separates
the two audiences:

| Where | What it shows | Why |
|---|---|---|
| Class record, grades list | The number, with INC beside it | A teacher mid-quarter needs to see where a child stands, *and* that this one will not print as a grade yet |
| Report card | `INC`, not the number | A final grade is a thing the school stands behind. Printing the number is how a child ends up carrying a grade nobody meant to issue |

Two consequences follow from that, both deliberate:

- **An incomplete subject is left out of the general average**, alongside
  the ungraded ones. An average cannot include a figure the document
  beside it does not print.
- **One incomplete quarter leaves the subject's final column empty**
  rather than averaging the quarters that are done, which would report a
  year's grade off three quarters as though it were four.

A component the school weights at **zero** is not missing anything — it
cannot move the grade, so it is excluded from `missingComponents` and
never triggers INC. Naming it would send a teacher looking for work that
has nowhere to go.

INC is not the same state as ungraded. A subject with nothing at all in
it has no grade; a subject with two of three components has a grade that
is not finished. The first is left out of everything, the second is
marked and shown.

The smaller decisions, each with a test behind it:

- **Several pieces in one component are summed, not averaged.** A
  10-point quiz and a 90-point test are not equal halves of the
  component.
- **Work worth zero points does not enter the denominator.** That is a
  teacher recording attendance at an activity, not an assessment.
- **Bonus marks are kept, not clamped.** Schools give them; capping
  silently would erase a teacher's decision, and a component over 100 is
  visible and explicable.
- **A subject with nothing recorded has no grade**, not a zero, and is
  left out of the general average rather than dragging it down until the
  quarter closes.

## Transmutation

Stored as bands: an initial grade from `from` to `to` becomes
`transmuted`. **An empty table means the school does not transmute** —
a real configuration, not a missing one, and inventing a table for a
school that has not set one would silently change every grade it issues.

A value outside every band clamps to the nearest end rather than falling
through to zero. A table that does not reach 100 is a misconfiguration,
and turning a perfect paper into a zero is the worst possible way to
discover it.

The exact band boundaries are not shipped as a default. They are typed by
the school, for the same reason the weights are confirmed by it.

## What a teacher does

### The class record

One piece of work is one **column**; the class is the rows; the teacher
types down the column and saves once. That is the screen a teacher
actually keeps grades in, and it is new.

What was there before was a dialog per child, per mark, asking for the
student, the term, the component, the score and the total each time.
Nobody marks forty children that way. They keep a spreadsheet and type
the totals in at the end, which is the thing this module exists to
replace.

The class is always on the screen, whether or not anything has been given
out. That was a defect: a quarter with no pieces of work in it collapsed
the whole record to one sentence, and the roster went with it — a teacher
opening their own class saw nobody in it, which reads as a broken roster
rather than "you have not set a quiz yet". The columns are what is empty,
not the class. With nothing marked, every student is listed waiting on
their first mark.

An empty *roster* is a different problem and says so separately: it is
almost always a section name that does not match the one on the student
records, and a teacher staring at a blank list has no way to guess that.

Opening a student shows the whole grade for that subject, grouped the way
it is computed. Each component in turn: what it counts for, the pieces of
work inside it with this student's mark on each, the raw total over what
was possible, the percentage, the weight, and what that contributed. Then
the working in order, the initial grade, and the verdict.

**Including the components with nothing in them.** That was the gap. The
breakdown listed only the components that had work, so a teacher read two
correct lines and had no way to tell a third existed — and the empty one
is exactly what decides whether this is a grade or an INC. An empty
component now appears with the weight still to come against it, and the
pieces of work under it read *No piece of work added yet*.

A teacher asked why a child got 87 can point at the line. One that shows
only the answer sends them back to the spreadsheet.

### Adding, editing and removing a piece of work

All three go through a callable, because all three can change grades that
have already been recorded.

**Add** creates the column before anything is marked, so every mark
against it has the same total behind it. **Edit** renames it, moves it to
another component, or changes what it is out of — allowed deliberately,
because a teacher who set 20 and meant 25 has to be able to say so. It
rescales nothing: the marks stay as typed, and any that no longer fit the
new total are **named in the reply** rather than clamped. Either number
could be the right one and only the teacher knows which.

**Delete** takes the marks with it. That is the whole reason it is a
callable and not a client write:

- A column removed on its own would leave every mark against it still
  summing into the component total — the class still graded on a quiz
  that is no longer on any screen, with nothing anywhere to explain the
  figure. The two go in **one batch**: together, or not at all.
- Both are **soft** (`isDeleted`), which is what every read in this
  module already filters on. A hard delete of a child's recorded score is
  not something a teacher should be able to do from a phone, and the
  audit entry needs something to point at.
- The **count of marks removed comes back**, and the screen asks with it:
  *"Delete Quiz 1?"* is a question about a title; *"the 32 marks recorded
  against it will go too"* is a question about children's grades. A
  teacher who is not told finds out from a parent.

Delete is the teaching side's — Faculty and Admin, the same roles that
may mark — and refuses a piece of work that is already gone rather than
reporting a second success.

### A mark can be corrected

This is the defect the class record was built on top of, and it was
silent.

`submitGrade` wrote a **new document every time**. Scores inside a
component sum, and so do the maximums — so a teacher who typed 80 out of
10, noticed, and re-entered 8 out of 10 ended the quarter with 88 out of
20. Nothing errored. No screen said anything. The `allow update` rule
that would have permitted a correction existed, and a rules test asserted
it worked, and no code path in the app ever issued one: a rules test
proving a capability nothing exercises is the most comfortable kind of
wrong.

The import knew. Its own comment says *"a mark is posted, never
replaced"*, and it works around it by refusing a row identical to one
already on file — which catches a file run twice and does nothing
whatever about a correction, because a corrected mark is by definition
not identical.

Giving the work an identity fixes it by construction. A mark lives at
`{assessment}_{student}`, so entering it again replaces it. Both write
paths — the class record's whole-column save and the single-mark post the
import and the dialog use — land at the same id.

### A blank is not a zero

Left empty means the child did not sit it: the piece of work drops out of
both their score and the total it is over. Zero means they sat it and
scored nothing, and the total counts against them. Collapsing the two
marks an absent child as having failed.

### The percentages the teacher sets

The school's confirmed scheme is still the default and is what a class
with no override is graded on. What the class record adds is the case
that scheme cannot express: a subject marked on a split the department
agreed, which before this had to be done in a spreadsheet beside the app.

The override is per subject and section, carries the name of whoever set
it, and is refused unless the three add up to a hundred — the one
misconfiguration that does not announce itself, since 30/50/30 produces
grades that look entirely plausible and are wrong for every child in the
class, all quarter. The record names which weights produced the grade and
whose they are, so a split nobody agreed to is visible rather than
quietly in effect.

Changing them recomputes every grade in the class. Nothing is re-entered.

### Grade Submission, and the import

The older per-student path is kept for a single late mark and for the
spreadsheet import, and both now go through `postGradeMark`, which finds
or creates the piece of work the mark belongs to. So an import run twice
replaces rather than doubles.

The submit dialog and the import both carry a **Component**. It is a
dropdown, not free text: a score filed under nothing cannot be weighted,
and the whole quarterly grade rests on that one choice.

The import gained a Component column (blank means written work, which is
what every mark posted before this existed already counts as), and it
still refuses a row identical to one on file — less critical now that a
re-run replaces, but it is the thing that tells you the file was run
twice.

### One quarter at a time

The class list used to read every mark the class had ever been given and
label the result with whichever term came back first, so a teacher in Q2
was shown a number computed from Q1 and Q2 added together. The query is
scoped to a quarter now, and the screen picks one.

The same query's limit was 300 marks per class for the *year*. A busy
subject reaches that inside a quarter and the oldest marks fall out of
the window, which does not fail — it quietly moves the grade.

## What a student and a parent see

The subject page shows the real quarterly grade, its descriptor, and a
breakdown per quarter: each component, the raw total out of what was
possible, the percentage, and the weight applied. A grade a family cannot
trace is one they have to take on trust, and the weights are not the same
for every subject — which is exactly the thing people assume.

The number here and the number on the report card are the same number,
computed by the same function. There is deliberately not a second way to
compute a grade.

## The report card

`ReportCardPdf` lays out subjects down the left, quarters across, the
final grade and Passed/Failed at the right, the general average boxed
below, and three signature blocks — Class Adviser, Principal, Parent /
Guardian. A quarter with no work in it prints **blank, not zero**.

A second page shows **how those grades were computed** for the most
recent quarter with work in it: per subject, each component's raw total
over what was possible, its percentage, the weight, and what it
contributed, then the initial grade and the final. One quarter rather
than four — the one the family is reading the card for, and four of these
is a document nobody opens. Page one is the record; this is the
arithmetic behind it, because "weighted per subject" tells a parent a
rule was applied without telling them what it did.

It is issued from **Records & Forms** in the Registrar's portal alongside
the TOR and Form 137, which means it goes through the same release log:
who collected it, when, why, and how many copies. A family that says they
never received one, or received a different one, is a dispute the office
has to be able to answer.

`ReportCardPdf.build` throws rather than producing a document when
`confirmedBySchool` is false, and the screen shows the domain's own
sentence. It is not a failure — it is the school being told to do the
step it has not done.

## Where things are

| Thing | File |
| --- | --- |
| **The class record** | `faculty_portal/presentation/screens/class_record_screen.dart` |
| A piece of work, a mark against it | `faculty_portal/domain/entities/class_assessment.dart` |
| Whose percentages, and where from | `faculty_portal/domain/entities/class_weights.dart` |
| Weights, bands, defaults | `faculty_portal/domain/entities/grading_scheme.dart` |
| The arithmetic | `faculty_portal/domain/entities/quarterly_grade.dart` |
| Assembling the record | `faculty_portal/presentation/controllers/faculty_controller.dart` |
| Settings screen | `faculty_portal/presentation/screens/grading_scheme_screen.dart` |
| The document | `faculty_portal/presentation/documents/report_card_pdf.dart` |
| **The write paths** | `functions/src/callable/grading/` — `saveClassAssessment`, `deleteClassAssessment`, `saveAssessmentScores`, `setClassWeights`, `postGradeMark` |
| Validation, keys, weights | `functions/src/shared/grading/` |
| Firestore | `schools/{id}/settings/grading`, `classAssessments/{id}`, `classWeights/{classKey}`, `grades/{assessment}_{student}` |
| **Tests** | `quarterly_grade_test.dart` (the arithmetic, INC, the average), `class_record_test.dart` (add, edit, delete against the demo), `gradingCallables.test.ts` (every write path against the emulator) |

### Rules

The scheme lives under `settings/`, which `firestore.rules` already makes
readable by everyone in the tenant and writable only by Director, Admin
and Registrar. A student reading their own grade needs the weights to be
told how it was arrived at, so tenant-wide read is right; the weights are
a school-wide decision somebody is answerable for.

**Marks are server-written.** `allow create, update, delete: if false` on
`grades`. Two reasons, and the first is not about security: it is the
only way one mark per student per piece of work can be guaranteed, which
is what makes a correction a correction. The second is that the old
update rule pinned `studentId` and nothing else, so `submittedByName` was
writable — and a grade is a record of what a named teacher marked. "Who
gave this grade" answered with whatever the client typed is not a record.
The `approvals` rule has always required a decision to be signed by the
account making it; this is the same requirement, arrived at late.

`classAssessments` and `classWeights` are readable by the whole school
and written by nobody. A total editable from a console is a total the
marks were never checked against, and how a grade was reached is not a
secret from the family it belongs to.

Tests: `functions/test/shared/grading/` (pure),
`functions/test/shared/grading-emulator/` (the four callables against a
real Firestore, including a mark entered twice being one mark),
`test-rules/faculty-portal.rules.test.ts`, and the Dart suites under
`app/test/unit/features/faculty_portal/` and
`app/test/smoke/class_record_test.dart`.
