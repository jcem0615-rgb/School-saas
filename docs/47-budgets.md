# Module 47: Budgets

## What this is

What the school meant to spend, next to what it did.

A budget is a **plan**, and that is the whole of what makes this module
different from the three around it. The ledger, the payables ledger and
the collections are records of things that happened. A plan is allowed to
be wrong.

## A budget never refuses anything

The most important decision here, and the one most easily got wrong.

A school that cannot record the electricity bill because somebody
budgeted too little **does not thereby spend less**. It just has a
liability nobody can see — which is strictly worse than an overspend
somebody can. Blocking the entry doesn't stop the money; it stops the
record of the money.

So every breach is a **warning**, shown on the bill form where the money
is being committed, and never a block. The warning names the account and
says how far over it would go, in pesos. The bill records either way.

This is also why budgets are an ordinary client write while bills and
journal entries are callables. Nothing here has to balance and nothing
has to commit alongside anything else; rules can check everything that
matters.

## Actuals come from the books

The report reads its actuals out of the trial balance, not from a running
"spent so far" kept somewhere. A stored total is a second truth and it
drifts the first time something posts without updating it — and after
[Module 43](43-general-ledger.md) and [Module 46](46-accounts-payable.md),
plenty of things post: assessments, collections, payroll, bills, direct
expenses. The books already know, so the books are asked.

The consequence worth noticing: a bill recorded this morning moves the
budget report this morning, and nothing had to be told to do that.

## Two things the report must not do

**It must not hide spending on an account nobody budgeted.** That is
exactly what a budget report exists to find, and one that only listed
budgeted lines would balance and conceal it. An account with spend and no
budget appears with its own state, `Not budgeted`.

**It must not clamp an overspend at zero.** `remaining` goes negative, on
purpose, because the size of the overspend is the information. Only the
progress bar is clamped, and the figures underneath still say how far
over it went.

## The states

| State | When |
|---|---|
| Within budget | Under four fifths spent |
| Running low | Four fifths or more, but not over |
| Over budget | More than the allowance, by more than a centavo |
| Not budgeted | Money spent on an account with no allowance |

Four fifths, because that leaves roughly a term's notice on a year's
budget — early enough to do something, which is the only point at which a
warning is worth anything.

The centavo tolerance is the same one the ledger uses. A budget flipping
to "over" on a billionth of a peso is a warning nobody would believe
twice.

Spending **exactly** the allowance reads as `Running low`, not `Over`.

## What can be budgeted

Spending and income only. A school does not budget its bank balance, and
a report listing Cash on Hand next to Utilities is one nobody reads
twice. Setting a budget against an asset, liability or equity account is
refused, by name.

## Setting one to zero, rather than deleting it

`allow delete: if false`, like everything else here. Setting a line to
zero is how it comes off the plan — and it leaves the spending against it
visible as unbudgeted, which a deleted row would not.

The document id is `{schoolYear}_{accountCode}`, enforced in rules. One
budget per account per year by construction: a school with two has no way
to tell which one anybody meant, and setting one again replaces it rather
than leaving a pair.

## The year follows the ledger

`budgetYearProvider` reads the ledger's period, so the plan and the books
are never looking at different years. Changing the year on the budget
screen changes it on the ledger screen too — which is right, because
"budget for 2026-2027" and "trial balance for 2026-2027" are the same
question asked twice.

## Where it lives

```
app/lib/features/budgets/
  domain/entities/budget.dart        Budget, BudgetLine, BudgetState,
                                     BudgetReport, the refusal function
  data/budgets_repository_impl.dart  port, model and impl in one file:
                                     it is a plain read and a plain write
  presentation/controllers/          providers, and budgetWarningFor()
  presentation/screens/budget_screen.dart
```

Firestore: `schools/{schoolId}/budgets/{schoolYear}_{accountCode}`.

Reached from the Director's dashboard: **Budget**. The warning appears on
the Accounts Payable bill form.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `test/unit/features/budgets/budget_test.dart` | remaining stays negative on an overspend, four fifths is a warning, exactly-spent is not over, the centavo tolerance, unbudgeted spend surfaced, budgeted-but-unspent kept, quiet accounts dropped, balance sheet accounts never listed, attention ordering worst-first, the refusals |
| Store + screen | `test/smoke/budget_test.dart` | the seeded year is not comfortable, actuals come from the books, setting replaces rather than duplicates, zero leaves the spend visible, the warning before spending, the screen opens on what needs attention |
| Rules | `test-rules/budgets.rules.test.ts` | Director and Admin only, the id must be year-and-account, negative and non-numeric amounts refused, zero allowed, no delete, no cross-school read |

## What is not here yet

- **No periods within the year.** One allowance for the whole school
  year, so a line that is 90% spent in October is only obviously wrong to
  a person who knows the year is a third gone. Monthly or quarterly
  phasing is the next thing this needs.
- **No commitments.** An approved purchase that has not become a bill yet
  does not reduce what is available, so two people can each spend the
  last of a budget.
- **No carry-forward.** Nothing moves an underspend into next year.
- **No approval flow.** Whoever can see the budget can change it; there
  is no record of a budget being proposed and approved, only of what it
  currently says and who last set it.
