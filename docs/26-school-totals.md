# Module 26: Enrolment and Collections

## Overview

How many students the school is teaching, how much of what it has charged
is still owed, and how much has come in this month -- on the dashboard of
everyone who runs the school.

The Owner has had these numbers since the platform's first day, because
billing runs on the active-student count. Inside the school the same
figures existed only in a report somebody had to go and ask for, which is
not the same as knowing. A Director could not answer "how many are we
teaching, and how much are we owed" without leaving the screen they start
their day on.

Director, Principal, Admin and Registrar.

## What each role sees

| Role | Active students | Outstanding | Collected this month |
|---|---|---|---|
| Director | Yes | Yes | Yes |
| Admin | Yes | Yes | Yes |
| Registrar | Yes | Yes | Yes |
| Principal | Yes | **No** | **No** |

The Principal's omission is the boundary `docs/16-principal-role.md`
already draws: division-level academic oversight, deliberately separated
from the school's money, the same way `expenses` are. The card says so in
a line rather than leaving a gap to wonder about, and the repository does
not hand a Principal the figures at all -- hiding them in the widget
would make it a presentation choice rather than a rule.

## Aggregation queries, not documents

`count()` and `sum()` are answered from the index without returning a
single document, so the card costs a handful of reads whether the school
has ninety students or nine thousand.

That is why this is not built on `studentsStreamProvider`. The unbounded
roster is the right tool for a faculty submission sheet and the wrong one
for a figure on a dashboard somebody opens twenty times a day -- its own
doc comment says as much.

Four queries, all filtered on `isDeleted == false`, because a
soft-deleted student is off the roll and counting them would inflate the
head count the school is billed on:

| Figure | Query |
|---|---|
| Active students | `status == 'enrolled'` |
| Outstanding | `balance > 0`, summed |
| Students owing | the same query, counted |
| Collected this month | `payments` where `createdAt >= 1st`, summed |

## Two arithmetic decisions worth stating

**Outstanding counts positive balances only.** A credit balance is money
the school is holding, not money it is owed. Summing the two together
would let one family's overpayment quietly cancel another family's
arrears and report the pair as settled -- the same reasoning the
collections report already applies.

**Collected sums every payment row, with no status filter.** A refund is
its own row with a negative amount and the payment it reverses keeps its
positive one, so the pair nets itself off. Filtering to `completed` would
report a month's take without the money handed back out of it.

The payments query is also deliberately the same two fields the existing
`isDeleted, createdAt` index already covers. A query needing an index
nobody deployed is one that works in the emulator and fails at the
counter.

## Division scoping

A Principal -- and a Registrar, Faculty member or Guidance counsellor --
can be scoped to one division. An unscoped aggregate from a scoped
account is refused by the rules, correctly, so every query carries the
division when the reader has one.

The client does not otherwise know its own division: `assignedDivision`
reaches `firestore.rules` as a custom claim, which the client never sees.
So the datasource reads it from the account's own user document -- one
read, of their own record, so there is no rule it could fall foul of.

When the figures cover one division, the card says which. A head count
that silently covered one division of four would read as the whole
school.

## Indexes added

```
students  educationLevel, status, isDeleted     -- a scoped head count
students  isDeleted, balance                    -- who owes something
students  educationLevel, isDeleted, balance    -- both, for a scoped registrar
```

## Refreshed on demand, not streamed

A `FutureProvider`, read once when a dashboard opens and again when
somebody presses refresh. A stream would re-run four aggregation queries
on every write anywhere in the school, to move a number nobody is
watching change.

## Testing

| Layer | File | Covers |
|---|---|---|
| Widget | `school_totals_test.dart` | the count is enrolled students rather than every record; outstanding never nets a credit; a Principal's card shows the head count and says where the money lives |
| Demo | `school_totals_test.dart` | the money half reaches the three roles that collect it, and is withheld from a Principal at the repository rather than the widget |

## Deferred

- **A trend.** "Down eleven since last month" is the figure that starts a
  conversation, and it needs a stored monthly snapshot rather than a
  live aggregate.
- **Tapping through to the collections report** with the period already
  set to this month.
