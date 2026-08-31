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

The submit dialog and the spreadsheet import both carry a **Component**
now. It is a dropdown, not free text: a score filed under nothing cannot
be weighted, and the whole quarterly grade rests on that one choice.

The class list shows the computed grade for the term the last mark was
posted in, with the weight group that produced it and which components
are still empty, instead of the most recent raw score out of its own
total.

The import gained a Component column (blank means written work, which is
what every mark posted before this existed already counts as), and its
duplicate rule had to widen. It used to refuse a student who already had
a mark for the term. A student legitimately has many marks in a term now
— three components, several pieces inside each — so the rule is no longer
"already has a mark this term" but "already has this exact mark": same
component, same label, same score out of the same total. That is a file
being run twice, which would silently double a child's written work,
since scores inside a component sum. Two genuinely identical unlabelled
quizzes are the one case it refuses wrongly, and naming one of them in
Remarks is the way through.

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
| Weights, bands, defaults | `faculty_portal/domain/entities/grading_scheme.dart` |
| The arithmetic | `faculty_portal/domain/entities/quarterly_grade.dart` |
| Stored shape | `faculty_portal/data/models/grading_scheme_model.dart` |
| Settings screen | `faculty_portal/presentation/screens/grading_scheme_screen.dart` |
| The document | `faculty_portal/presentation/documents/report_card_pdf.dart` |
| Firestore | `schools/{id}/settings/grading` |

The scheme lives under `settings/`, which `firestore.rules` already makes
readable by everyone in the tenant and writable only by Director, Admin
and Registrar. A student reading their own grade needs the weights to be
told how it was arrived at, so tenant-wide read is right; the weights are
a school-wide decision somebody is answerable for, so the write list is
the one that already owns school-wide settings. No rules change was
needed.
