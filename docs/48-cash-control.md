# Module 48: Cash and collection control

## What this is

A cashier's drawer, from the moment it is opened to the moment it is
counted.

The school already knew what it had collected — [Module 08](08-payments.md)
has recorded every receipt since the beginning. What it could not say was
whether the money **in the drawer** matched, and "the cashier is
trustworthy" is not a control, it is a hope. A shift turns the end of the
day into one number somebody signs: counted, against expected, and the
difference recorded whichever way it falls.

## A shift is a window of time, not a tag

The obvious design is to stamp a shift id onto every receipt. This does
not do that.

A shift is a **window over one cashier's own collections**: every cash
payment that cashier took between opening and closing is in the reckoning
by construction. Nothing has to remember to tag a receipt, which means
nothing can forget to — and `recordPayment` did not have to change at
all.

A receipt written at 5:01pm after a 5:00pm close belongs to no drawer,
and that is correct rather than a gap: it belongs to the next one.

## The expected figure is worked out, never supplied

This is the control, and everything else is scaffolding around it.

`closeCashierShift` queries the payments that cashier took inside the
window and adds them to the float. It does **not** accept an expected
figure from the client. A count checked against a number the counter
supplied is not a control at all — and that is exactly the attack the
Firestore rules close too: the drawer collection is read-only to every
client, because a client that could write it could set `expectedAmount`
to whatever it had just counted and balance every drawer for ever.

There is a test for precisely this: a caller that passes a nonsense
counted amount still gets the real expected figure back and a real
variance.

The figure is then **stored on the shift**, so what the variance was
struck against cannot move afterwards. A refund backdated into the window
would otherwise silently rewrite last Tuesday's reckoning.

## Refunds come out of the same money

A refund is stored as a payment with a negative amount, so summing the
amounts in the window nets them off exactly as the drawer does. A
reckoning that ignored them would read short by exactly the refunds,
every time one happened.

## A difference always needs a reason

Closing a drawer that does not balance requires an explanation, and the
refusal says which way and by how much.

It does not have to be a *good* reason. "Two hundred short, no idea" is a
far better record than silence — the point is that the difference was
noticed, dated and attributed, not that it was solved. The screen says so
in as many words.

## Over is not good news

Short and over both land in **5910 Cash Short or Over**, a new system
account. Over is the same control failing in the other direction: money
in the drawer that no receipt accounts for is as much of a problem as
money missing, and a school that only looked at shortages would never
find a cashier under-ringing.

| | Entry |
|---|---|
| Short | Dr Cash Short or Over, Cr Cash on Hand |
| Over | Dr Cash on Hand, Cr Cash Short or Over |
| Balanced | Nothing. A pair of zero lines is an entry that says nothing, and an entry of nothing is refused anyway. |

## What the cashier sees while counting

The expected figure is on screen **while the drawer is running**, not
only at close. A figure that appears afterwards is one a cashier cannot
check themselves against.

But the count box is empty and the difference only appears once something
is typed. A box pre-filled with what it should be is a box that gets
accepted without counting.

## Who sees which drawers

A cashier sees their own. The Director and the Admin see everybody's,
because "who was short last month" is the question the module exists to
answer and it is not one a cashier asks about themselves. Enforced in
rules, independently of the screen.

A cashier closes their **own** drawer. An admin closing somebody else's
would put their name on a count they did not make.

## One change outside this module

`Payment` gained a `collectedBy` field — the collector's uid. The
Firestore document already carried it; the Dart entity only exposed
`collectedByName`.

Matching a drawer on the name would have worked until two members of
staff shared one, or until a name was corrected after the receipt was
written. The name is for reading; the uid is for matching.

## Where it lives

```
app/lib/features/cashiering/
  domain/entities/cashier_shift.dart   CashierShift, ShiftReckoning,
                                       the two refusal functions
  data/cashiering_repository_impl.dart
  presentation/controllers/ ... screens/cashier_drawer_screen.dart
functions/src/shared/ledger/shiftLines.ts     expected, and the variance entry
functions/src/callable/cashiering/            openCashierShift, closeCashierShift
```

Firestore: `schools/{schoolId}/cashierShifts`. Two composite indexes were
added — one for the close's query over a cashier's receipts, one for
finding a cashier's open drawer.

Reached from the Registrar's and the Admin's dashboards: **Cash Drawer**.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `test/unit/features/cashiering/cashier_shift_test.dart` | the reckoning including refunds, an open drawer has no variance, short/over/balanced to the centavo, the window's inclusive bounds, a second drawer refused by name, a difference needing a reason |
| Server | `functions/test/shared/ledger/shiftLines.test.ts` | expected rounds to centavos, a balanced drawer posts nothing, short and over both balance and both land in 5910 |
| Store + screen | `test/smoke/cashiering_test.dart` | opening, the reckoning excluding another cashier's cash, a balanced close posting nothing, short and over moving 5910 with the trial balance still square, the expected figure reckoned rather than taken from the caller, no second close |
| Rules | `test-rules/cashiering.rules.test.ts` | a cashier sees only their own, the office sees all, no client write at all — including the close-from-a-client attack — and no delete |

## What is not here yet

- **No deposit record.** The screen says what to bank; nothing records
  that it was banked, so a drawer can balance and the money still not
  reach the account.
- **No denomination breakdown.** One counted figure, not a count of
  hundreds and fifties, which is what most cashiers actually fill in.
- **Cash taken with no drawer open is not refused**, only left out of
  every reckoning. Requiring an open drawer would be the stronger
  control; it would also stop a school recording a payment on a day
  somebody forgot to open one, which is worse.
- **No handover.** A drawer passed between two people mid-day is two
  shifts or none; there is nothing in between.
