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

- Online payment gateway integration (e.g. PayMongo) — architecture leaves
  a clean seam (`PaymentMethod.online` already exists in the schema); wiring
  an actual gateway webhook is out of scope for this build per your
  earlier direction.
- Payment/refund reporting and PDF/Excel export — Reports & Documents modules.
- Statement of Account view for Parents — reuses `PaymentHistoryScreen`
  directly; wired up when the Parent Portal module is built.
