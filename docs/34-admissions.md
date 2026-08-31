# Module 34 — Admissions

The pipeline from the first phone call to the day a child is on a class
list.

A private school's year is won or lost between January and June, and what
loses it is not a decision. It is a family who enquired in February, was
never rung back, and enrolled somewhere else in April — and nobody at the
school can say how many of those there were, because the enquiry was a
note in a logbook and the logbook has no column for what happened next.

So the first thing on this screen is not the list. It is the count of
families nobody has spoken to in a week.

## The stages, and the two endings

`inquiry → applied → exam scheduled → exam taken → offered → reserved →
enrolled`, plus **not accepted** and **withdrew**.

The two endings are separate on purpose. "We turned down forty" and
"forty families walked away" are different problems and only one of them
is the school's doing; a pipeline that cannot tell them apart reports
itself as busy while it is really just stuck.

**A stage cannot be set to whatever somebody expects.** From where a
family is, the only moves are: one step forward, one step back, or out to
either ending. A pipeline whose stages can be set freely stops meaning
anything within a term — somebody marks a family as offered because that
is the outcome they are expecting, and the funnel then reports offers the
school never made. The step *back* is not a nicety either: a family gets
marked offered by mistake, and a pipeline with no way to correct that is
one people work around by making a second record for the same child.

A family who was turned down or walked away and later comes back returns
to **the beginning**, not to wherever they had reached months ago.

## The step and its evidence are one act

A family is not at "exam taken" without a score, and not at "reserved"
without a payment. Advancing collects both together, and refuses without
them. Letting the stage be set first and the number filled in later
leaves half the pipeline as stages with nothing behind them — which is
the logbook this module replaces.

The entrance exam is stored as score **and** what the paper was out of,
and a score above the maximum is refused: that is almost always the two
fields the wrong way round, and it would rank a child above everybody who
sat the same paper. An unsat exam reads as **no percentage at all**, not
zero — a child who has not taken the test has not failed it, and a list
sorted by score would otherwise put them below everybody who did badly.

A reservation payment is **added** to what is already there, never
replacing it. A family paying it in two instalments is ordinary, and
overwriting would lose money the school has taken.

## Enrolment is not a stage anybody sets

It is the one stage with a record behind it, so it has its own callable.
An applicant marked "enrolled" with no student record is a child the
school believes is enrolled and the registrar cannot find — and the
family discovers it on the first day of classes.

`enrolApplicant` writes the applicant's `studentId` in the same
transaction that creates the student, and the transaction refuses when it
is already set. Two clicks on a slow connection, or a registrar coming
back to a screen they left open, produce one student and a clear message
the second time — not twins. The re-read inside the transaction is the
guarantee; the check before it exists only to give a better message.

**The reservation fee follows the family.** Whatever they paid to hold
the place is carried onto the student record as a negative balance, which
this system already treats as money the family is owed against fees not
yet charged. A reservation that stayed on the applicant record would be
money the school has taken and the cashier cannot see, and the family
would be asked for it twice.

The student number is drawn before the transaction, because
`getNextSequence` runs one of its own and they cannot nest. A transaction
that then fails leaves a gap in the student numbers — visible,
explicable, and far less costly than the alternative, which is two
children sharing one number.

## Who to ring this morning

An open applicant nobody has moved in **seven days** is on the follow-up
list, longest wait first. One number rather than one per stage: a
per-stage table is a thing nobody tunes and everybody argues about, and
the office's real question is simply "who have we not spoken to lately".

It counts days **in the stage**, not days since the enquiry, so a family
being actively worked through the pipeline does not show up as gone cold.
Closed applicants are never on it, however long ago they closed — a list
that says an enrolled family is waiting for a phone call is a list the
office stops reading.

## The funnel

Two numbers per stage, because a school needs both: how many are sitting
there **now**, and how many have **reached at least** that far. Forty
families are at the enquiry stage today; four hundred passed through it
this year, and a report giving only the first looks like a school with no
pipeline at all by June.

A stage nobody has reached has **no** conversion rate rather than 0% — a
report showing zeroes for a season that has not started reads as a
disaster when nothing has happened at all.

Also recorded, and recorded nowhere else in this system today: **how the
family heard about the school**. It is the single most useful field on
this record for a director deciding where next year's advertising goes.

## Rules

`applicants` is the one collection in a tenant holding personal data
about people with no relationship to the school at all — a family who
rang once and went elsewhere. Reads are the admissions office only
(Director, Admin, Registrar). Not faculty, not guidance, not the
principal, and not parents or students: a parent whose child later
enrols reads the student record, not the enquiry.

Client writes are denied outright. The stage rules, the exam check and
the enrol-exactly-once guarantee all live in the callables, and a client
that could write this document could set the stage to enrolled with
nothing behind it.

## Where things are

| Thing | File |
| --- | --- |
| Stages, funnel, follow-up | `admissions/domain/entities/applicant.dart` |
| Validation and transitions | `admissions/domain/usecases/admissions_usecases.dart` |
| The pipeline screen | `admissions/presentation/screens/admissions_screen.dart` |
| One family | `admissions/presentation/screens/applicant_detail_screen.dart` |
| Server rules | `functions/src/shared/admissions/applicant.ts` |
| Callables | `functions/src/callable/admissions/` |
| Firestore | `schools/{id}/applicants/{applicantId}` |

The legal-transition rule is written twice, once in Dart and once in
TypeScript. That is deliberate: the client's copy is what makes the
screen offer the right buttons, and the server's is what actually holds
when something else calls the callable.

`enrolApplicant` repeats a little of `registerStudent` — the program
lookup and the student document's shape. Extracting a shared builder
would be the tidier move and is not done here: `registerStudent` has no
server-side tests behind it, and refactoring the one path every student
record in the system goes through, to save a dozen lines, is not a trade
worth making.
