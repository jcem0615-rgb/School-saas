# Module 43: The general ledger

## What this is

Double-entry books. A chart of accounts, a journal, and a trial balance
that adds up.

Until now the finance side of LogicClass was a bursar's system: it knew
what each family owed, what they had paid, and what the school had spent.
That answers the registrar's questions and the cashier's. It does not
answer the accounting office's — *what is the school worth, what does it
owe, did it make a surplus this term* — and a college has an accounting
office that expects a ledger.

## The rule the whole module turns on

**The books are posted by the events that cause them, never typed up
afterwards.**

A school that hand-keys its tuition into a journal ends up with two
truths: the payments the cashier recorded, and the journal somebody wrote
up on Friday. Reconciling them is the week this product exists to give
back — it is the same "four places that never agree" problem the whole
system argues against, and a ledger bolted on the wrong way is the
fastest way to recreate it inside one app.

So every posting happens **inside the transaction that writes the thing
being accounted for**:

| Event | Entry | Posted from |
|---|---|---|
| Fees assessed | Dr Accounts Receivable, Cr Tuition Revenue | `assessStudentFees` |
| Payment collected | Dr Cash/E-Wallet/Bank, Cr Accounts Receivable | `recordPayment` |
| Refund | Dr Accounts Receivable, Cr Cash | `recordRefund` |
| Payroll run | Dr Salaries, Dr Benefits, Cr four payables, Cr Bank | `runPayroll` |

The entry and the receipt commit together or neither does. A ledger
posted afterwards — in a trigger, or a second write — is a ledger that
disagrees with the receipt every time that second write fails.

**Revenue is recognised at assessment, not at collection.** The school
has done the teaching and is owed the money, so the receivable and the
revenue are both raised when the fee is assessed; collecting it later
only moves an asset. Posting revenue in both places would count every
peso twice, and that is the most common way a ledger bolted onto a
billing system goes wrong.

Two entries do start with a person — opening balances and corrections —
and both go through callables.

## Nothing is ever edited

`allow update, delete: if false` on `journalEntries`, for everyone.

A mistake is corrected by posting the reverse of it: every debit becomes
a credit and back again, dated today. Both the mistake and the fix stay
in the journal, which is what an accounting office does with a paper
journal and for the same reason — a book you can go back and tidy is a
book nobody can rely on.

The reversal is dated **today**, never back-dated to the original. A
correction filed into a closed period is how last month's reported
figures quietly change.

A reversal cannot itself be reversed. That is how a journal turns into a
tangle nobody can read; if the reversal was wrong, post a fresh entry.

## Why the client cannot write to the journal

Security rules **cannot sum an array**. There is no way to express
"debits equal credits" in `firestore.rules`, which means any client
allowed to write could post books that do not balance.

So the journal is read-only to every client there is, and the two
hand-written entries go through `postManualEntry` and
`reverseJournalEntry`, which check the entry before anything is written.
The check also runs in the app, so an unbalanced entry is refused before
the button is enabled and the running difference is on screen while
somebody types.

The chart of accounts *is* an ordinary client write: it is a list of
names, and rules can check everything that matters about it — that the
code matches the document id, that a new account cannot declare itself a
system account, that a code and a type never move, and that nothing is
ever deleted.

## Money is counted in centavos

`0.1 + 0.2` is not `0.3` in binary floating point, and a trial balance is
exactly where that surfaces: twelve postings of ₱333.33 against one of
₱999.99 leaves a residue of a few billionths, and a strict equality check
then reports the books as out of balance for ever. Everything compares to
the nearest centavo (`sameMoney`), on both sides of the wire.

## The chart

Nineteen accounts, numbered by the convention every chart in the country
already follows — assets in the 1000s, liabilities in the 2000s, equity
3000s, revenue 4000s, expenses 5000s. A chart with two hundred accounts
is one nobody codes against correctly.

The sixteen the product posts to are **system accounts**: they can be
renamed — a school that calls 4010 "Other School Fees" should see that
everywhere — but never renumbered, never retyped, and never switched off,
because a payment next week has to find them by code.

A school adds its own, and the code has to sit in the block its type
owns. An expense filed under 1500 lands on the balance sheet as an asset
and is found months later.

The chart is seeded the first time anything posts, not when a school is
created — so a school that never opens the finance screens never grows a
chart it did not ask for. Seeding is idempotent and only writes codes
that are missing, so a renamed account keeps its name.

## Two copies of the chart, on purpose

`functions/src/shared/ledger/accounts.ts` and
`app/lib/features/ledger/domain/entities/ledger_account.dart` are the
same file in two languages. The posting happens server-side, inside a
transaction; the reading happens in the app; neither can import the
other.

`functions/test/shared/ledger/ledger.test.ts` reads the Dart file and
checks the codes have not drifted apart. That test is the only thing
keeping the two honest.

## Who sees it

The Director and the Admin, and nobody else — not the principal, not the
registrar. A principal runs a division, not a set of books, and a chart
of accounts tells you what the school spends on what.

## Where it lives

```
app/lib/features/ledger/
  domain/entities/ledger_account.dart    AccountType, the chart, posting maps
  domain/entities/journal_entry.dart     JournalLine, JournalEntry,
                                         the balance check, TrialBalance
  domain/usecases/ledger_usecases.dart
  data/ ... presentation/
functions/src/shared/ledger/
  accounts.ts          the chart, server side
  postJournalEntry.ts  the transaction-scoped posting helper
  payrollLines.ts      the payroll entry, pure and tested
functions/src/callable/ledger/
  postManualEntry.ts  reverseJournalEntry.ts
```

Firestore: `schools/{schoolId}/ledgerAccounts` (keyed by code) and
`schools/{schoolId}/journalEntries`.

Reached from the Director's dashboard: **General Ledger**.

## A note on the payroll entry

A payroll is four facts at once, and it is easy to post three: the school
owes its staff their gross pay, it owes four agencies what was withheld,
it owes those agencies **its own share as well**, and cash leaves for the
net. Miss the employer share and the entry still balances — it just
understates both the expense and the liability, and nobody notices until
a remittance comes up short.

Each agency gets one payable line carrying both halves, because that is
how it is remitted: one payment per agency, not one per half. To make
that possible, `PayslipLine` now carries the contribution `kind` and the
payslip carries the employer share split by agency. Matching on the
printed label instead would break the day somebody translates it.

An absence is not a deduction in the accounting sense — it never became
a liability to anybody. It is pay the school did not owe, so it reduces
what is charged to salaries rather than creating something owed.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `test/unit/features/ledger/journal_entry_test.dart` | a line is one side or the other, the balance check and the centavo tolerance, normal balances, the trial balance including an entry citing a code the chart has lost, reversal netting to nothing, every posting code seeded and in its block |
| Server | `functions/test/shared/ledger/ledger.test.ts` | the same balance checks, entry-number format, the chart parity test against the Dart file, and the payroll entry: employer share charged to benefits, both halves per agency, an absence not treated as withheld, a run with no deductions |
| Store + screen | `test/smoke/ledger_test.dart` | the seeded books balance and were all posted by events, manual entries refused for imbalance / no memo / future date / unknown account, reversal leaves both rows and nets to zero, no double reversal, chart block and system-account rules |
| Rules | `test-rules/ledger.rules.test.ts` | Director and Admin only, no client write to the journal at all, no edit and no delete by anyone, chart code must match the id, no self-declared system accounts, rename yes / renumber no |

## What is not here yet

- **Accounts payable, budgets and cash control** post to this ledger and
  are the next three modules.
- **No period close.** Nothing stops an entry being posted into a school
  year somebody has already reported on, beyond the reversal rule above.
- **Discounts and subsidies** reduce revenue rather than appearing as
  contra-revenue accounts of their own. Showing them separately needs a
  revenue account per fee item, which the fee structure does not carry.
- **No financial statements.** The trial balance is here; a formatted
  balance sheet and statement of operations are a reporting job on top of
  it, not more bookkeeping.
