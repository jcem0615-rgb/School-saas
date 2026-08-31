# Module 37 — The demo

The demo is not a mock-up. `demoOverrides()` swaps the repository layer
and nothing else: every use case, controller, route and widget above it
runs exactly as it does against Firebase. What somebody clicks through is
the real app with a different bottom layer, which is why it has been
worth keeping honest through thirty-six modules.

It is also, right now, the only thing that can be shown to a school —
real mode needs Blaze for Cloud Functions ([Module 3](03-going-live.md)).

## The problem it had

Twelve accounts, ten portals, and a switcher that listed logins. Every
module seeded data with a story in it — a family who has gone quiet since
February, a student below 75 in maths, a shelf that has run out, an
instalment nobody has paid — and **none of that is discoverable from a
grid of icons.** Somebody being shown the app taps three tiles, sees
tables of plausible data, and misses the point of all of it.

## One line per role

Each role in the switcher now carries the single thing worth opening,
phrased as what you would actually find there:

> **Registrar** — Admissions opens on the families nobody has rung in a
> week. Then Records & Forms, which prints a report card and logs that it
> left the office.
>
> **Staff** — Inventory. The bond paper is under its reorder level and a
> projector is out with a teacher.

Not a feature list; the tile is already on the screen. This is the reason
to tap it.

They live in `demo_tour.dart`, beside the seed rather than inside the
switcher widget, because the two have to agree.

## The copy is tested against the data

A promise the demo no longer keeps is worse than no promise: somebody is
shown the app, taps the thing they were told to look at, and finds
nothing there. Seeded data changes every time a module lands, so
`demo_tour_test.dart` asserts the **claims**, not the wording:

- the bond paper really is below its reorder level
- a projector really is out with somebody
- families really are overdue a phone call
- a Grade 10 - Rizal maths student really does come out below 75, run
  through the same `computeQuarterlyGrade` the report card uses
- every role with an account has a note, and no note exists for a role
  that has none

Change the seed so a claim stops being true and the suite says so.

## There is no reset button

The store lives in memory for the life of the tab, so **reloading the
page already is one**, and the switcher says so. A button that tore down
and rebuilt every stream mid-session would be a worse answer to a
question the browser already answers — and closing a `BehaviorSubject`
out from under live listeners is a real way to break a demo in front of
somebody.

## What the seed is meant to show

Not a tidy school. A school mid-term, with the specific problems each
module was built to surface:

| Where | What is wrong on purpose |
| --- | --- |
| Admissions | two families have not been rung in three weeks |
| Payments | an instalment plan with an overdue line |
| Grading | a quarter in progress, so no quarterly assessment exists yet |
| Faculty | one student in maths below the line |
| Inventory | bond paper below reorder, a projector out on issue |
| Payroll | three staff on three different bases, tables confirmed |
| Receipts | a part-used booklet, so the series has something to reconcile |

A demo where everything is green demonstrates nothing. The point of each
of these is that the app noticed.
