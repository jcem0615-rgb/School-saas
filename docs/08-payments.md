# Module 8: Payments (Core)

## Overview

Covers recording a payment (cash/GCash/bank transfer, with online gateway
integration deferred per your earlier answer), generating a sequential
receipt, tracking a student's running balance, and processing refunds.
Payment History and Refund History are the same underlying list (a refund
is just a row with `refundOf` set and a negative amount) rather than two
separate collections/screens.

## ⚠️ Security fix applied this module

While adding the Payments rule, I found and fixed a real bug introduced in
Module 6 and carried through Module 7: **the tenant catch-all rule granted
blanket read access to every collection**, because Firestore grants access
if *any* matching `match` block allows it (OR across all applicable
blocks, not "most specific wins"). The catch-all's
`allow read: if belongsToSchool(schoolId) && schoolIsAccessible(schoolId)`
independently satisfied that OR for *every* tenant collection — meaning
the role restrictions written into the `attendance` and `expenses` blocks
were silently non-functional; any signed-in tenant member could read any
student's attendance or the school's financial expense records regardless
of role.

**Fix:** the catch-all now denies both read and write by default
(`allow read, write: if false`). Every collection that needs client read
access must define its own explicit rule — which `users`, `announcements`,
`meetings`, `approvals`, `expenses`, `attendance`, and now `students` and
`payments` all already do. See `test-rules/payments.rules.test.ts`,
section "REGRESSION," for tests that specifically pin this down (e.g.
faculty can read a student record but not that same student's payment
record — proving the restriction is deliberate per-collection, not a
blanket outage from over-correcting).

A second, smaller fix landed alongside it: `markAttendance.ts` (Module 7)
now resolves a **students-collection ID** as `personId` for student scans
instead of the account ID, so that a Parent's `linkedStudentIds` means the
same thing when checked against attendance, payments, and (later) grades.
The attendance rule's self-read check was updated to match. See
`docs/07-qr-attendance.md`, "ID space" section, for the full rationale.

## Why balance is server-computed, never client-computed

`students.balance` is a denormalized running total, updated only inside
the same Firestore transaction that writes the payment/refund record
(`recordPayment.ts` / `recordRefund.ts`). The client only ever *reads* it
via `watchStudentBalance`. This matters for the same reason billing is
server-computed: a device showing "you owe ₱0" because of a client-side
calculation bug or tampering is a very different failure mode than a
Firestore read simply being stale for a second.

## Refunds require a different role than collecting payments

`recordPayment` allows Director/Admin/Registrar. `recordRefund` allows
**only** Director/Admin — Registrar is deliberately excluded. A cashier
who can both take money in and send money back out unilaterally is a
classic internal-control gap; requiring a more senior role to reverse a
transaction is a real safeguard, not a formality, and is exactly the kind
of thing a school's bookkeeper or auditor will ask about when evaluating
whether to trust this system with their money.

## Fee assessment: what the balance is actually for

A balance used to be one number. Payments reduced it and a registrar typed
the opening figure into `setStudentBalance` by hand, so a family asking
"why do we owe ₱17,000?" got the figure back and nothing else. Two
collections close that gap.

**`feeStructures`** is what the school charges — "Grade 10, SY 2026-2027:
tuition ₱15,000, books ₱2,000". A template, published once a year by
Director/Admin. A registrar assesses fees but does not decide what they
are, which is why the rule lists only those two roles for writes.

**`assessments`** is what one student was actually charged. The items are
**copied in**, not referenced: a fee structure is a template the school
edits between years, an assessment is a thing that happened to a family,
and it must read the same in five years as it did the day it was made. A
school that raises tuition in January must not silently reprice every
family who enrolled in June.

### Why both writes are callables

`assessStudentFees` and `voidAssessment` move the itemised record and
`balance` **in one transaction**, for the same reason `recordPayment`
does: `balance` is server-owned and `firestore.rules` refuses every
client write to `assessments`. A client that could write there directly
could charge a family money with no balance behind it, or move a balance
with no record of why.

### Voiding, never deleting

A reversal leaves both the charge and the reversal on the record, marked
with who voided it and why (the reason is required, refused blank). The
balance moved when the assessment was made; a record that could simply
disappear would leave a figure nobody could account for and an itemised
list that no longer adds up to it. `voidAssessment` re-reads `voidedAt`
**inside** the transaction, so two cashiers voiding at once cannot reverse
one charge twice.

### The duplicate guard

Charging the same schedule to the same student twice for the same year is
the mistake this feature makes easy: two clicks and a family silently owes
double. `assessStudentFees` refuses a second assessment matching
`studentId + sourceStructureId + schoolYear` with `voidedAt == null`. The
check runs *before* the transaction — it is a question about other
documents, and a transactional read would have to lock the whole
collection to answer it. That is also why the write stores `voidedAt:
null` explicitly rather than omitting the field: Firestore cannot match a
document that does not carry the field being queried.

### What families see

`BalanceBreakdown` sits above the payment history on the same screen the
student, the parent and the registrar all reach: total assessed, less
payments received, balance. Charged minus paid, itemised.

It states the arithmetic **even when it does not come out**. A school
partway through adopting this has students whose balance was set the old
way with no assessment behind it; showing only the assessments there would
imply the list is the whole story and understate what is owed. The
unexplained remainder is named instead — which also tells the office
exactly which records still need an assessment raising.

The "less payments received" line sums **every** payment row as it stands.
A refund is its own row with a negative amount and the payment it reverses
keeps its positive one (marked `refunded`), so the pair cancels out on its
own. Filtering either out produces a phantom remainder against a balance
that is perfectly correct.

### Screens

| Screen | Role | What it does |
|---|---|---|
| `FeeStructuresScreen` | Director / Admin | Publish and retire fee schedules |
| `AssessFeesScreen` | Registrar / Director / Admin | Charge a schedule to one student, with history and void |
| `BalanceBreakdown` | everyone on `PaymentHistoryScreen` | Why the balance is what it is |

The copied items stay editable on the assessment screen. Real enrolments
have exceptions — a scholar whose tuition is waived, a transferee who
joins after the field trip — and the alternative is the office abandoning
the schedule and typing everything by hand for the one student in ten who
differs.

## "The student paid but the balance is not deducting"

Reported from a counter, and it had three separate causes. All of them
produce the same thing a cashier sees: a receipt, and a balance that did
not move.

**A payment could be recorded against nobody.** Record Payment, opened
without a student already chosen, took a typed ID and sent it. In demo
mode the store's `update` silently matches nothing when the id is wrong,
so the payment was appended, the audit entry written, the receipt handed
over, and no student's balance touched. The natural mistake makes it
happen: a cashier types the **student number** off the ID card
(`2024-00051`) rather than the record id (`stu_001`).

Three changes, because one alone leaves the hole open somewhere:

- The screen resolves the ID against the roster before anything is sent,
  accepting either the record id **or** the printed student number, and
  shows the student's name, class and current balance. Record Payment
  stays disabled until it names somebody.
- The demo repository refuses an unknown student, the way the callable
  already did with `not-found`.
- The id sent is always the resolved record's id, never the typed text.

The balance on that banner is the second half of it: a cashier keying an
id had no confirmation they had reached the right record, and afterwards
no figure to check the deduction against.

**The balance was not rounded on the payment paths.** `applyPayment`
rounds server-side, and the demo's assessment path rounds, but its
payment, approval and refund paths did not. Three centavo-denominated
payments left a balance of `1462.9900000000002`, which prints as
`₱1,462.99` and fails every equality check made against it -- the worst
combination for a figure a school reconciles against.

**Two cashiers at once could lose one of the two payments.**
`recordPayment` and `recordRefund` read the student's balance *before*
opening their transaction, so two collections happening at the same
counter both started from the same figure and the second write landed on
top of the first. One payment banked, receipted, and absent from the
balance. Both now read inside the transaction, which is what makes
Firestore retry rather than overwrite -- `assessStudentFees`,
`voidAssessment` and `decidePaymentSubmission` already did.

`recordRefund` gained one more thing from that move: it re-reads the
original payment inside the transaction, so the already-refunded check
holds against a snapshot that could otherwise be stale by the time it
runs.

### What is not this bug

An online payment submitted by a family deliberately does **not** move
the balance. It moves when a cashier approves it, which is the whole
point of the review step, and the confirmation dialog says so.

## Paying by bank transfer

A family paying online can now choose **Bank Transfer**, and the school
publishes the accounts they may send it to.

Bank transfer used to be left off the family's list, on the reasoning
that it was "something a cashier attests to, not a family". That is true
of cash and it is not true of a transfer: a transfer carries a reference
number and a deposit slip, which is exactly the evidence an e-wallet
payment carries and exactly what the cashier checks. Nothing about the
verification step changes — the balance still moves only when a
registrar approves — so the only thing keeping transfers off the list
was the list.

**Accounts are a list, not a field.** `PaymentSettings` used to hold one
unlabelled account number beside the e-wallet QR. That is enough for a
school with one account and useless for one with three: the family typed
a reference number and the cashier had no idea which statement to look
in. Each account now carries a bank, an account name, a number and an
optional branch.

**Which account the family used is recorded on the submission**, as text
(`destinationLabel`, e.g. `BPI - Lipa City · 1234-5678-90`) rather than
as an account id. A cashier reading it months later has to know which
account was meant even if it has since been closed and taken off the
list, and an id that no longer resolves is worse than a label that does.

**An account is closed, never deleted.** Submissions point at it, and a
row that vanishes takes their meaning with it. A closed account stops
being offered and stays on file.

**A method is only offered when the school can receive it.**
`PaymentSettings.payableMethods` asks per method: bank transfer needs at
least one open account, e-wallet needs a QR or a number. Offering
"Bank Transfer" on a school that has published no bank account is an
option that leads to a screen saying it cannot be done.

**The destination card follows the method.** A family transferring to BDO
does not need the GCash QR on screen, and showing both is how money ends
up in the wrong account. Account numbers are selectable and set in
tabular figures, because the next thing that happens is somebody copying
one into a banking app.

Covered by `app/test/unit/features/payments/bank_accounts_test.dart` (what
a school offers, how an account reads, and per-row parsing that drops a
bank account with no number rather than offering it) and
`app/test/smoke/online_banking_test.dart` (the registrar adding and
closing accounts without disturbing the QR, and a family's transfer
recording its destination and crediting nothing until approved).

## Discounts and scholarships

Before this, a waiver was hint text. `assess_fees_screen.dart` suggested
typing *"Tuition waived under academic scholarship"* into the remarks
box, and that was the entire feature. A remark cannot be summed, so
**"how much did we give away in discounts this year"** -- a question a
private school's board asks every single year -- had no answer in the
system at all.

A `Discount` is now a line on the assessment: a kind from a closed list
(sibling, early payment, employee's child, alumni, academic scholarship,
financial assistance, other), a label in the school's own words, an
amount, optionally the rate that produced it, and who approved it.

### Gross, discount, net

`Assessment.total` **nets** the discounts, rather than a `netTotal`
sitting beside a gross `total`. Every existing caller -- the balance, the
breakdown, the collections report -- means *"what does this family owe
for this"*, and every one of them would have been wrong by the discount
had the netting been opt-in. `grossTotal` and `discountTotal` are there
for the reports that need to distinguish them.

### The amount is stored, not just the rate

A 10% discount stores 2,000 **and** 10. Storing only the rate would mean
recomputing it later against fee items that can be edited afterwards, so
a discount granted on tuition of 20,000 could quietly become a discount
on 24,000 -- and the printed assessment in a family's hand would stop
matching the record. The rate is kept beside the amount so the line still
reads "Sibling discount (10% of tuition)", which is what makes it
checkable.

### It defaults to tuition, not to everything

Most PH private schools discount tuition and not the miscellaneous
fees, because the miscellaneous bundle is largely money passed through to
third parties. `appliesTo` carries that, and the editor defaults to
tuition. A percentage that quietly included the laboratory fee is a
school giving away more than it decided to.

### What is refused

A school may waive up to the whole of what it is charging and not a
centavo more -- past that the charge goes negative and the school is
paying a family to enrol, which the balance arithmetic would carry
without complaint. Checked in the editor, the use case and
`validateDiscounts` server-side, and the entity clamps `total` at zero as
well so a hand-corrected document cannot produce one either.

Two discounts that are each fine but together exceed the fees are the
case that slips through when only individual lines are checked; there is
a test for exactly that.

### The approver comes from the token

`approvedByName` is stamped from the caller's own ID token and never read
from the payload. A client that could name its own approver could grant a
scholarship in the director's name.

### Where it meets the payment plan

A discounted family's instalment plan must add up to the **net**, not to
the published fees. Validating against the gross would refuse every
discounted family a payment plan at all. `assessStudentFees` computes the
net first and passes that to `validateInstallments`.

### The report

**Discounts and Scholarships** groups by kind, with the number of
students behind each figure so a large total from three board grants is
not mistaken for a broad policy, and shows each as a share of the fees
assessed. Voided assessments are excluded -- they granted nothing in the
end.

## ESC grants and SHS vouchers

The one thing on this list that only exists for private schools. DepEd,
through PEAC, pays part of a qualified student's tuition: an **ESC**
grant in junior high, a **voucher** in senior high. The family is charged
less and the school bills the government for the difference.

### Why this is not a `DiscountKind`

Because they are opposites. A discount is money the school gave away and
will never see. A subsidy is money the school is **owed** and has to
produce a claim for. Folding them together makes both year-end figures
wrong at once: the discounts report overstates what the school absorbed
by the whole of its ESC intake, and the claim -- which needs a list --
has nowhere to come from.

So `Subsidy` is its own record on the assessment, with its own report,
and `Assessment` carries `grossTotal`, `discountTotal`, `subsidyTotal`
and `total` as four distinct figures.

### The certificate number is required

A grant with no certificate is a grant the school cannot bill for, so a
family charged less on the strength of one is a family the school has
quietly given money to -- the same mistake discounts guard against,
arrived at from the other side. The field label follows the programme
(`ESC certificate no.` / `QVR / voucher no.`) because a bursar is copying
from whichever form is in front of them.

One certificate is claimed once: a duplicate on the same assessment is
refused, case-insensitively. PEAC rejects the second claim, and by then
the family has been charged as though both were coming.

The same number under two *different* programmes is allowed — grantors
number independently and a collision is coincidence.

### The ceiling is what is left, not the gross

Grants are checked against what remains **after** discounts. A student
with a 2,000 sibling discount has 22,000 chargeable, not 24,000, and
checking the grant against the published fees would let a discount and a
grant together exceed them.

### The claims report is the deliverable

**ESC and Voucher Claims** lists every grant with its student, class,
certificate and amount, sorted by programme then by name -- the order a
billing form is filled in.

This is the report that replaces a spreadsheet. A private school running
ESC keeps a parallel ledger in Excel because the PEAC billing needs a
list and no school system produced one, and reconciling that spreadsheet
against actual enrolment is where money gets lost: a student who
transferred out in September is still on the claim, or a grantee enrolled
in July never made it on. Here the list *is* the enrolment -- every line
comes from an assessment that actually charged a student -- so it cannot
include somebody who was never assessed, nor omit somebody who was.

One row per grant, not per student: the school bills per certificate, and
a student holding both an ESC grant and a city scholarship is two claims
to two grantors.

## Billing in instalments

A private school does not charge once. It charges on enrolment and then
monthly or per quarter, each with a date, and the question its
administrator asks every morning is *who is behind* -- which a balance
cannot answer. A family on a four-payment plan who has paid the first
two is 22,000 short and perfectly current, and chasing them is how a
school loses a family it was never at risk of losing.

### The plan is a plan, not a second ledger

`FeeStructure` and `Assessment` each carry a list of `Installment`
(`{label, dueDate, amount}`), copied from the schedule to the assessment
the same way the fee items are and for the same reason: a school that
moves next year's due dates must not move the dates a family already
agreed to.

The tempting alternative -- a document per instalment with its own
`paid` field -- was rejected. Every payment would have to allocate
itself across several documents in one transaction, every refund
un-allocate, a voided assessment unwind the lot, and any of those
failing halfway would leave a family's plan disagreeing with their
balance. The ledger already exists and is already correct.

So nothing about who has paid what is stored. It is derived:

    overdue = (what the plan says was due by today) - (everything paid)

That is a pure function of two numbers and a date. It cannot drift from
the balance because it is computed from it, and it handles refunds,
voids and back-dated payments without any code that knows about them.
`BillingSchedule` in `installment.dart` is the whole of it;
`billingSchedule.ts` is the server's twin, used to validate.

### Money is not earmarked

Payments settle the earliest unpaid instalment first, and "overdue"
compares running totals rather than matching payments to lines. This is
the difference between a system that works and one that generates
angry phone calls: a family who paid 15,000 in June against a plan whose
first two instalments total 15,000 is **not** overdue in August, even
though the August instalment has no payment "against" it.

Paying ahead never produces a negative overdue figure either. A report
showing "-10,000 overdue" reads as a credit the school owes.

### The plan must add up to the charge

Enforced in three places -- the editor, the use case, and
`validateInstallments` server-side -- because a plan that does not match
either tells a family they have finished paying when they have not, or
chases them for money nobody charged them. A centavo of tolerance,
because thirds do not divide; more than that and the plan has drifted.

An empty plan is legal and means the whole amount fell due when it was
charged. That is the honest reading of an ad-hoc charge (a replacement
ID is not paid off over four months) and it is what every assessment
written before this feature means.

### Where it shows up

| Who | Where |
|---|---|
| A family | `PaymentPlanCard` on Payment History -- every instalment, what is paid, what is overdue and by how many days |
| A bursar | The same card, so the two cannot disagree about what was owed when |
| Whoever publishes fees | `InstallmentEditor` on the fee schedule, with a live "plan totals X -- matches the fees" check and a Split evenly helper |
| The office | **Overdue Accounts** in Reports: every family behind, banded 1-30 / 31-60 / 61-90 / over 90 days, sorted by how late rather than how much |

Sorted by age, not amount, deliberately: a small debt six months old is
a different conversation from a large one due last week, and it is the
old one that stops being collectable.

### What it cannot see

Students with no payment plan never appear in the Overdue report, and
the report says so in its own note. Their fees fell due when they were
charged, so they are either paid or simply outstanding -- there is no
schedule to be behind on. A collections list that looked complete and
was not would be trusted, and should not be.

Charges with no plan *are* counted when a student has one elsewhere:
`Assessment.combinedSchedule` gives them a single line falling due the
day they were made. Leaving them out would quietly excuse a November
make-up-exam fee from ever being late. The family-facing card asks the
narrower question -- did the school actually publish a plan -- so a
school billing in one lump is never shown a card containing an invented
row.

## Exam permits and clearance

The permit is the lever a private school actually uses to collect: the
cashier signs a slip and the proctor turns away anybody without one.
The workflow already existed in the school and not in the app -- the
promissory note in the demo fixture is titled *"Second Quarter exam
permit"*, which is the tell.

### Derived, never stored

A permit written down on Monday lies on Friday: the family pays on
Wednesday and the record still says they owe. `clearanceFor()` computes
it from the payment plan, the payments and the approved notes each time
it is asked, so a payment taken at the window clears the student before
they have walked back to the classroom.

Three outcomes: **cleared** (nothing overdue), **cleared by note** (an
approved promissory note covers the whole of what is overdue), and
**blocked**, which carries the shortfall.

### Partly covered is not covered

A note for 2,000 against 5,000 overdue leaves 3,000. Issuing a permit on
it would be the school agreeing to something nobody agreed to, so the
student is blocked -- but the note is still cited, because the cashier
needs to know one exists before having that conversation.

### Notes now expire

A promissory note is an `ApprovalRequest` of type `promissory_note`, and
it carried an amount and a reason but no date -- so an approved note
would have cleared a student for exams forever, which is not what anybody
approving one thought they were agreeing to. The request form now takes a
**settle-by** date, defaulting to a fortnight.

A note whose date has passed clears nobody. A note *on* its date still
clears -- a note to settle by the 30th covers the exam on the 30th, which
is the whole point of asking for it. A note with no date at all (every
note written before the field existed, and any whose date will not parse)
covers indefinitely: refusing to honour one would turn a student away
over a schema change.

Only **approved** notes count. Clearing somebody for having asked would
make the approval step decorative.

### Where it shows up

| Who | Where |
|---|---|
| A family | `ExamPermitCard` on Payment History, without a print button -- a self-printed permit is worth nothing at the door, but knowing a week early that you are ₱3,400 short is worth a great deal |
| The cashier | **Exam Permits** in Reports: everybody, blocked first, then by how much, with the shortfall and what each clearance rests on |
| The proctor | `ExamPermitPdf` -- half a page, two to a sheet, verdict boxed in capitals in the top third because it is read at arm's length in a queue |

Students with no assessment never appear on the list. There is nothing
they can be behind on.

### The approvals read

`ExamPermits` is the only report that sets `needsApprovals`, and its
approvals query is deliberately **not** filtered by the report period:
a note approved in August still covers an examination in October, and a
note filtered out of the read is a student wrongly turned away.

## Official receipts

A private school is a business. It issues Official Receipts from booklets
printed under an Authority to Print, each with a serial range, and it has
to account for every number in that range -- issued, cancelled, or
unused. The end of that accounting is not the school's convenience; it is
what an examiner asks for.

### What this is not

**Not a BIR-accredited Computerised Accounting System.** It does not
print an OR and does not claim the number it holds was machine-generated.
The number recorded is the one pre-printed on the paper the family was
handed. Saying otherwise in the UI would put a school in front of an
examiner with software claiming to be something it has no permit to be,
so the settings screen says so in as many words.

What it does do is know which booklet is in use and what number should
come next, so a mis-keyed number is caught at the counter rather than in
October of the following year.

### Two numbers, on purpose

`Payment.receiptNumber` (`RC-2026-000042`) is the system's own sequential
id and is unchanged. `Payment.officialReceiptNo` is an integer: the
serial on the BIR paper. They are different things -- one a record id
this system generated, the other a serial printed under a government
permit -- and a school issuing no ORs leaves the second null with nothing
else changing.

### Uniqueness is a document id, not a query

`claimOfficialReceipt` runs **inside** the payment transaction and writes
a claim document whose id *is* the number. Two cashiers typing 0042 at
the same moment: the second `create` fails and that cashier is told,
rather than both payments filing against one receipt and the discrepancy
surfacing at month end. A query could not do this -- two concurrent
transactions would both pass it.

The claim and the payment commit together or neither does, so a failed
payment never burns a number.

### No booklet, no change

A school with no booklet registered records payments exactly as before.
Sending a number anyway is refused rather than dropped: it means the
cashier is recording something the school has not told the system about,
and silently discarding the one field they cared about is worse than
saying no. Two active booklets is also refused -- which series a receipt
belongs to would be a guess.

### The reconciliation

**Receipt Series** in Reports lists every number up to the highest one
used, with what became of it, and leads with the figure nobody has today:
**Unaccounted**.

Numbers above the highest used are blank paper in a drawer and are not
listed -- five hundred rows of "unaccounted" would drown the one that is
actually a question. A gap *inside* what has been used is the question:
a receipt written and not recorded, or one recorded against a different
booklet.

A refund does not consume a number: the school issues its own document
for those, and counting the refund against the original's number would
make the series say one receipt was used twice.

## Firestore collections touched

```
schools/{schoolId}/payments/{id}        -- see Module 3 schema; amount is negative for refund rows
schools/{schoolId}/students/{id}        -- balance field only, read-only from client
schools/{schoolId}/feeStructures/{id}   -- published fee schedules; Director/Admin write, tenant-readable, never deleted
schools/{schoolId}/assessments/{id}     -- what a student was charged; no client writes at all
```

Note: full Student Registration (creating/editing `students` records) is
Registrar Portal's job, not yet built. This module only needed enough of
that collection's shape (`balance`, `userId`) to make payments work, and
added the minimum viable read rule — `allow write: if false` on `students`
remains until Registrar Portal defines the real create/update rules.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `payment_usecases_test.dart` | amount/reference/reason validation |
| Functions | `balanceMath.test.ts` | payment/refund arithmetic, receipt number formatting |
| Functions | `getNextSequence.test.ts` | atomic counter (no duplicates under concurrency, per-school isolation) — **requires the Firestore emulator** |
| Rules | `payments.rules.test.ts` | self/staff/linked-parent access, refund role gate, and the catch-all regression |
| Domain | `fee_usecases_test.dart` | schedule/assessment validation, `appliesTo` matching, voided totals |
| Widget | `balance_breakdown_test.dart` | the arithmetic, including refunds and unexplained remainders |
| Demo | `fee_assessment_test.dart` | assess/void round-trip, double-void and duplicate-schedule guards |
| Rules | `fee-assessment.rules.test.ts` | no client writes to `assessments`, family reads, Director/Admin-only schedules |
| Domain | `billing_schedule_test.dart` | due-by arithmetic, oldest-first settlement, paying ahead, thirds that do not divide, combining plans across assessments |
| Functions | `billingSchedule.test.ts` | plan-must-match-charge, malformed plans, the centavo tolerance |
| Widget | `payment_plan_test.dart` | what the family is told, and the Overdue report's rows and caveat |
| Domain | `discount_test.dart` | percentage bases, netting, the full-waiver edge, what is refused, how the line reads |
| Functions | `discounts.test.ts` | over-granting (singly and in combination), the approver stamp, unknown kinds |
| Domain | `subsidy_test.dart` | netting apart from discounts, the required certificate, duplicate claims, and that neither report double-counts the other's money |
| Functions | `subsidies.test.ts` | the certificate requirement, case-insensitive duplicates, the post-discount ceiling |
| Domain | `receipt_series_test.dart` | gap detection, cancelled numbers closing a gap, refunds and foreign booklets excluded, duplicates counted once |
| Rules | `receipt-booklets.rules.test.ts` | Director/Admin register, registrar reads only, claims are server-written |
| Domain | `clearance_test.dart` | partial cover, expiry on and after the date, undated notes, and reading notes out of the approvals queue |

## Known gap flagged for QA

The Director Dashboard's aggregate queries (`.count()` / `.sum()` on
`attendance`/`payments`, built in Module 6) rely on Firestore evaluating
security rules per-matched-document for aggregation queries the same way
it does for list queries. This is Firestore's documented behavior, but
because the `attendance`/`payments` rules now mix a role-only condition
with a `resource.data`-dependent one in the same OR expression, this
should be explicitly verified against the Firestore emulator during QA
(Module: Testing) rather than assumed — aggregate-query rule evaluation is
a narrower, less-traveled path than ordinary list queries.

## Deferred to later modules

- **Reminders.** The plan knows what is due and the notification inbox
  exists; nothing yet sends "your October payment is due on Friday".
  A scheduled function reading `amountDueBy` is the shape of it.
- **Per-family arrangements.** A plan comes from the schedule. A family
  who negotiates their own dates has a promissory note, which is a
  separate record and does not move the plan.
- **Late fees.** Nothing charges interest or a penalty on an overdue
  instalment. That is a policy decision per school, not arithmetic.
- **Standing scholarships.** A discount is granted per assessment. A
  scholarship that renews each year, with conditions attached (a grade
  average to maintain, a review date), is a record of its own and is not
  built. The registrar re-grants it when they assess.
- **Whether a claim was actually paid.** The report is the claim, not
  the receipt. Tracking a billing run to PEAC and reconciling what came
  back is a batch of its own and is not built; the school still does
  that half in its own records.
- **Eligibility over time.** A grantee who loses ESC mid-year is handled
  by not recording the grant on the next assessment. Nothing tracks the
  entitlement itself, or warns that last year's grantee has no grant
  this year.
- **Recording a spoiled receipt.** `reconcileSeries` takes cancellations
  and the tests cover them, but there is no screen or callable to file
  one yet -- so today a torn receipt shows as a gap. That is the honest
  state and the next thing to build here.
- **An approval threshold.** Anybody who may assess fees may grant any
  discount up to the full amount. A school wanting "over 20% needs the
  director" would need a second decision step; today the control is that
  the approver is named and the audit trail records it.

- Online payment gateway integration (e.g. PayMongo) — architecture leaves
  a clean seam (`PaymentMethod.online` already exists in the schema); wiring
  an actual gateway webhook is out of scope for this build per your
  earlier direction.
- Payment/refund reporting and PDF/Excel export — Reports & Documents modules.
- Statement of Account view for Parents — reuses `PaymentHistoryScreen`
  directly; wired up when the Parent Portal module is built.
