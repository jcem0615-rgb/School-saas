# Module 9b: Registrar/Cashier Portal

## Overview

Covers Student Registration, Student Records/History, and closes a gap
left open since the Payments module: the `students` collection could be
read but never created or edited from the client (`allow write: if false`
placeholder). Payment Collection, Receipts, and Balances are not
rebuilt here — Student Detail links directly into the Payments module's
existing `RecordPaymentScreen`/`PaymentHistoryScreen`, which already
accept a `studentId`.

## Student Registration: why it's a callable, not a client write

Same reasoning as receipt numbers in Payments: `studentNumber` is a
human-readable sequential identifier (`S-2026-000001`) generated via the
same atomic counter transaction pattern (`getNextSequence`), which a
client cannot safely replicate without risking collisions under
concurrent registrations. `registerStudent.ts` also initializes `balance:
0` and `status: 'enrolled'` in the same write, so a student record is
never observably in a half-initialized state.

## Editing an existing record: real client writes, real field boundary

Unlike creation, *editing* an existing student (name, grade, section,
status, guardian contacts) is a direct client Firestore write — same
pattern as Announcements/Meetings/Expenses. The `students` rule now
explicitly protects three fields from that direct-write path even though
Registrar/Admin/Director can edit everything else:

- **`balance`** — only `recordPayment`/`recordRefund` (Payments module)
  may change it, inside the same transaction that writes the payment record.
- **`studentNumber`** — permanent identifier once assigned.
- **`userId`** — only set by `provisionUser.ts`'s validated linking step
  (see below); a direct client write here could silently attach a
  student's academic record to the wrong portal account.

See `test-rules/registrar-portal.rules.test.ts` for tests pinning down
exactly this boundary — editable fields succeed, protected fields fail,
even for a Registrar who can otherwise edit the record.

## Student Portal account provisioning

`provisionUser.ts` (Module 4) is extended two ways this module:

1. **`registrar` added to `PROVISIONING_MATRIX`**, permitted to create
   `student` and `parent` role accounts (previously no caller role could
   create either).
2. **Optional linking fields**: `linkedStudentId` (role `student`) links
   the new account to an existing academic record by setting that
   record's `userId` — validated *before* the Auth account is minted (a
   student record that's already linked, or doesn't exist, fails cleanly
   rather than leaving an orphaned Auth account behind). `linkedStudentIds`
   (role `parent`) is deferred to the Parent Portal module to actually use,
   but the plumbing — validating every referenced student record exists —
   is already here.

A student record does **not** require a portal account to exist — this
is why Student Registration and account provisioning are two separate
actions in the UI (Student Detail shows a "Create Student Portal Account"
button only when `userId` is still null). Younger students or schools
that don't want to issue every student a login can register students
purely as academic/billing records.

## Firestore collections

No new collections — this module fills in `students` (already schema'd
since Module 3, read-gated since Payments) with real create/update rules,
and reuses `payments`/`attendance` via cross-links from Student Detail.

## Testing

| Layer | File | Covers |
|---|---|---|
| Domain | `registrar_usecases_test.dart` | registration field validation, account email validation |
| Functions | `studentNumber.test.ts` | sequential number formatting |
| Rules | `registrar-portal.rules.test.ts` | server-only creation, editable-vs-protected field boundary, faculty has no write access |

## Deferred to later modules

- **TOR, Form 137, printable Student IDs** — require PDF generation
  (Documents module). The *digital* Student ID (QR code) already works
  today via the existing `MyQrIdScreen` once a student has a portal account.
- **Student History** as a dedicated audit-style timeline view — the
  underlying data already exists (generic audit trigger logs every
  `students` doc change); a per-student filtered view of `AuditTrailScreen`
  is a small addition once the Audit Trail module gets its dedicated pass.
- **Reports** (enrollment reports, etc.) — Reports module.
- **Parent account linking UI** — the `linkedStudentIds` validation exists
  in `provisionUser.ts` now, but the Registrar-facing "create a Parent
  account and link these children" screen is built alongside Parent Portal.

## The student list is paged

The list used to read the whole `students` collection on open. That is
fine for the demo's nine records and indefensible for a school with
three thousand: the same three thousand reads every time anybody opens
the screen, on the largest collection in the tenant, from the screen the
registrar's office leaves open all day.

It now asks for twenty at a time, with **Load more** under the last row.

Two details in that are load-bearing:

**The division chips filter the query, not the page.** The `where` goes
to Firestore alongside `isDeleted` — the composite index for
`educationLevel + isDeleted + lastName` already existed. Filtering the
page after it arrived would quietly shrink it: ask for twenty, get the
four Senior High students who happened to fall inside those twenty.

**Search leaves paging behind on purpose.** Firestore cannot match a
substring, so `cruz` can only be found by looking at every record.
Typing switches the screen to the unbounded query and filters it here,
exactly as it did before. Browsing is paged; searching is a deliberate
full read, and it happens when someone asks for it rather than every
time the screen opens.

The alternative — a `startAfter` cursor — is the textbook answer and the
wrong one here. The list is live: a student registered at the next desk
appears without a refresh. A cursor chain means one stream per page,
each with its own lifetime, all needing to stay in sync. One widening
`limit` stays one stream. It costs re-reading page one when you ask for
page two; at twenty a page that is a far better trade than the three
thousand it replaced.

Export is deliberately *not* paged. `fetchAllStudents()` is a separate
one-shot read of the whole roster, because a CSV that silently stopped
at the twenty rows on screen is the exact failure paging invites — and
the kind only noticed after the file has gone to the division office.

Demo mode overrides the page size down to four (`studentPageSizeProvider`).
Nine seeded students would never reach a page of twenty, and paging that
never triggers is paging nobody can check.
