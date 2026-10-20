# Module 46: Accounts payable

## What this is

What the school owes, to whom, and how late.

The difference between this and the `expenses` collection is the word
*yet*. An expense is money gone. A bill is money owed — a liability the
school is carrying — and that was the single thing the finance side could
not tell anybody. A bursar's system knows what came in. An accounting
office needs to know what is going out and when.

Built on [Module 43](43-general-ledger.md): every bill, payment and void
posts its own journal entry, inside the same transaction that writes the
bill. A payables list that disagrees with the ledger is exactly the gap
this closes.

## The accrual

**What was bought is an expense the moment it is delivered, not the day
it is paid for.** That is the whole of why accounts payable exists as
something separate from a cash book.

| Event | Entry |
|---|---|
| Bill recorded | Dr whatever was bought (one line each), Cr Accounts Payable (one line) |
| Bill paid | Dr Accounts Payable, Cr the cash account it came out of |
| Bill voided | Dr Accounts Payable, Cr back every expense line |

**A payment touches no expense account.** The expense was recognised when
the bill was recorded; touching it again at payment is the double-count
that makes a year's expenses read twice what the school actually spent.

One credit line on a bill, not one per expense line: the school owes the
vendor one amount and will pay it with one cheque. Splitting the
liability across four lines makes the payables ledger unreadable for no
gain.

## The duplicate check

Entering the same supplier invoice twice is the most common mistake in a
payables ledger, and it pays a supplier twice. `recordBill` refuses a
bill whose **vendor and invoice number** already exist and are not void,
and says which one.

The same number from a *different* supplier is fine — invoice numbering
is the supplier's, not the school's, and two of them will collide
eventually.

This is also why the supplier's own invoice number is required rather
than a number we generate. Without it there is no way to tell a supplier
which bill is being queried, and no way to notice the duplicate at all.

## Due dates fill themselves in

Terms live on the vendor — "Net 30", "Cash on delivery" — and a bill
computes its own due date from them. A date somebody has to work out by
hand is a date that gets typed as today, and then every ageing report is
wrong. It stays editable, because a supplier will sometimes give you
longer on one invoice.

## Ageing

The usual five buckets: not yet due, 1–30, 31–60, 61–90, over 90. A
school's report will be compared against one produced by somebody else's
software, so the boundaries are the ones everyone uses.

Computed from the bills rather than stored, so a bill paid this morning
is off the report this morning. A stored ageing total is one that drifts
the first time a payment forgets to update it.

**Paid and voided bills are off it entirely.** Both staying on is the
classic way a school believes it owes more than it does. A part-paid bill
appears at what is still outstanding, not its full value.

The status on screen is **worked out from the numbers**, not read from
the stored field. They agree, and when they do not it is the numbers that
are right — a status field that drifted is how a paid bill sits on an
ageing report for a year.

## Voiding, not deleting

`allow delete: if false`. A bill entered by mistake is voided, with a
reason, and the liability reversed by its own entry.

**Only a bill with nothing paid against it can be voided.** Once money
has gone out, the cash really did leave; pretending the bill never
existed would leave a payment pointing at nothing. A part-paid bill that
turns out to be wrong is settled or credited by the supplier, not
vanished.

## Overpaying is refused

A payment larger than what is outstanding is almost always a typo, and
letting it through turns one mistake into a wrong figure on every report
that sums what is owed. The refusal says what is left, in pesos.

The outstanding balance is read **inside** the payment transaction. Two
people paying the same bill at the same moment otherwise both read the
same figure and the second write lands on top of the first — a supplier
paid twice with the ledger showing one payment. Same reason
`recordPayment` reads a student's balance inside its own transaction.

## Writes are server-only

Bills are read-only to every client. `recordBill`, `payBill` and
`voidBill` are callables, for the same reason the journal is: the entry
each posts has to balance and has to commit with the bill, and security
rules can prove neither.

The attack this closes is small and obvious: mark a bill paid from a
client, no money moves, and the ledger still says the school owes it.

The **supplier list** is an ordinary client write — it is a list of
names, and rules can check everything that matters about it. A vendor is
deactivated, never deleted: one with bills against it cannot go without
those bills losing the name they were raised under.

## Direct expenses, and the one compromise

Money spent with no bill behind it — the sari-sari store, a tricycle fare
— still has to reach the books. That posting is a **trigger**
(`onExpenseRecorded`), not a transaction, and it is the only one in the
finance modules that is.

The reason is honest and worth writing down: the Director's expenses
screen writes its document straight to Firestore and has done since long
before there were books to post to. Routing it through a callable is the
tidier answer and is worth doing. Until then a trigger is the honest one.

What it gives up is atomicity. For a moment after the expense is written
the books do not know about it, and if the function fails every retry it
never will. What makes that survivable: the entry carries
`sourceId: expenseId` and the trigger skips the write if an entry already
cites it. Firestore delivers at least once, so without that check a
retried delivery would post the same expense twice — worse than posting
it late.

Two further honest limits on that path:

- The expenses screen does not ask which account the money came out of,
  so the trigger assumes **Cash in Bank**. A school reconciling its bank
  statement will correct it by recoding.
- The six categories map onto accounts, and **Transportation has no
  account of its own** in the standard chart, so it lands in Other
  Expenses. A school that spends enough on it to care adds 5400 and
  recodes — visible and wrong beats invisible and wrong.

## Where it lives

```
app/lib/features/payables/
  domain/entities/vendor.dart   terms, due-date arithmetic
  domain/entities/bill.dart     Bill, BillLine, BillPayment,
                                AgeingBucket, PayablesAgeing,
                                the two refusal functions
  domain/usecases/ ... data/ ... presentation/
functions/src/shared/ledger/billLines.ts     the four entry shapes
functions/src/callable/payables/             recordBill, payBill, voidBill
functions/src/triggers/payables/onExpenseRecorded.ts
```

Firestore: `schools/{schoolId}/vendors` and `schools/{schoolId}/bills`.

Reached from the Director's dashboard: **Accounts Payable**.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `test/unit/features/payables/bill_test.dart` | due dates from terms including a month-end crossing, outstanding to the centavo, no negative debt on an overpayment, status derived not trusted, the five buckets and their boundaries, paid and void off the ageing report, per-vendor grouping, every refusal |
| Server | `functions/test/shared/ledger/billLines.test.ts` | the bill entry balances with one payable line, line descriptions carried onto journal lines, a payment touching no expense account, void as the exact opposite of record, the expense-category map and its fallback |
| Store + screen | `test/smoke/payables_test.dart` | the seeded ledger spans buckets, recording raises the liability and keeps the trial balance square, duplicate invoice refused by name, same number from another supplier allowed, part payment, overpayment refused in pesos, void reverses and keeps the row, a part-paid bill cannot be voided |
| Rules | `test-rules/payables.rules.test.ts` | Director and Admin only, no client write to bills at all, a bill cannot be marked paid from a client, no delete, vendors need a name and can be deactivated but not deleted |

## What is not here yet

- **Purchase orders.** A bill is entered when it arrives; there is no
  commitment recorded before that.
- **Credit notes.** The refusal on voiding a part-paid bill tells a
  school to record a credit from the supplier, and there is nowhere to
  record one. That is the next thing this module needs.
- **Recurring bills.** Meralco arrives every month and is typed in every
  month.
- **No payment batching.** One payment, one bill. A single cheque
  covering three invoices is entered three times.
